# Notch — TODO

Jedna faza ≈ jedna sesja Claude. Po każdej fazie: HANDOFF → commit → `/clear`.
Gdzie podejrzeć w Coucou: ścieżki względem `reference-coucou/NotchBuddy/Sources/App/`.

---

## Faza 0 — Setup (bez Xcode się nie da)
- [x] Xcode zainstalowany, `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (user, wymaga hasła)
- [x] `xcodebuild -version` działa, licencja zaakceptowana
- [x] XcodeGen 2.46.0 zbudowany ze źródeł → `~/.local/bin` (brak brew)
- [x] Nazwa robocza „Notch”, bundle ID `pl.bismarck.Notch` (do ew. zmiany przed fazą 4)
- [x] `git init`, `.gitignore` (build/, *.xcodeproj, DerivedData, `reference-coucou/`)
- [x] `project.yml`: target `Notch` (macOS 15, Swift 6, `-strict-concurrency=complete`, Debug bez podpisu)
- [x] Pusta apka: `LSUIElement = YES`, ikona w pasku menu (`MenuBarExtra`) z „Quit”
- [x] Build + uruchomienie z CLI działa
- **Done gdy:** ikona w pasku menu, Quit zamyka apkę. → HANDOFF

## Faza 1 — Okno w notchu
Ref: `IslandWindowController.swift` (grep: `NSPanel`, `safeAreaInsets`, `auxiliaryTop`, `IslandPanel`)
- [x] `NSPanel` borderless + `.nonactivatingPanel`, przezroczyste tło, bez cienia
- [x] Poziom nad paskiem menu (`mainMenuWindow + 3`), `collectionBehavior`: wszystkie Spaces, fullscreen, ignoresCycle
- [x] Wyliczanie rozmiaru/pozycji notcha z `safeAreaInsets.top` + `auxiliaryTopLeftArea/RightArea`
- [x] Ekran bez notcha (monitor zewnętrzny) → udawana „pigułka” na górze na środku
- [x] Wybór ekranu: domyślnie ten z notchem; reakcja na podłączenie/odłączenie monitora (`didChangeScreenParametersNotification`)
- [x] Czarny kształt notcha w SwiftUI (zaokrąglone dolne rogi, płynnie łączy się z prawdziwym notchem)
- [x] Przepuszczanie kliknięć: panel ma rozmiar wyspy (bez `ignoresMouseEvents`), hover przez `NSTrackingArea` — zero pollingu
- **Done gdy:** czarna wyspa idealnie pokrywa notch, nie zabiera fokusu, nie blokuje klikania w pasek menu. → HANDOFF

## Faza 2 — Stany i animacje wyspy
Ref: `IslandStateMachine.swift` (cały plik jest mały — można przeczytać)
- [x] Maszyna stanów (czysta, testowalna): `hidden` → `compact` (notch + „uszy”) → `expanded`
- [x] Hover → `compact`/`expanded`, opuszczenie myszy → timer zwijania
- [x] Kliknięcie → `expanded`; Esc / klik poza → zwiń
- [x] Animacje spring przy zmianie rozmiaru (panel rośnie w dół, wyśrodkowany)
- [x] „Trzymaj otwarte”, gdy czeka zatwierdzenie (hook do fazy 5)
- [x] Unit testy maszyny stanów
- [x] Sprawdzić CPU w Activity Monitor przy `hidden` ≈ 0%
- **Done gdy:** wyspa płynnie rośnie/zwija się, testy zielone. → HANDOFF

## Faza 3 — Odbiór eventów z Claude Code (HookServer)
Ref: `HookServer.swift` (grep: `socket(AF_UNIX`, `maxPayload`, `processEvent`, `case "PreToolUse"`)
- [x] Socket Unix w `~/Library/Application Support/Notch/notch.sock`, katalog 0700, socket 0600
- [x] Wątek w tle: accept → czytaj JSON (limit 1 MB, timeout 5 s, max 32 połączeń) → `@MainActor` stan
- [x] Usuwanie starego socketu przy starcie, sprzątanie przy wyjściu
- [x] **Helper hooka** — mały CLI w Swifcie (`notch-hook`, osobny target, wbudowany w `.app`):
      czyta stdin, wysyła do socketu, przy braku apki/timeout → wyjście 0 bez outputu (fail-open)
      (Coucou używa sh+python3 — my bez Pythona)
- [x] Test ręczny: `echo '{...}' | notch-hook PreToolUse` → event widać w logu apki
- **Done gdy:** event wysłany z terminala dociera do apki; apka wyłączona → hook kończy się natychmiast. → HANDOFF

## Faza 4 — Instalacja hooków w Claude Code
Ref: `ClaudeSettingsFile.swift`, `ClaudeHookDetection.swift`
- [x] Wykrywanie, czy hooki są już zainstalowane
- [x] Merge do `~/.claude/settings.json` dla: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`, `PermissionRequest`
- [x] Kopia z datą → pokazanie diffa w oknie → zapis dopiero po „Zainstaluj”
- [x] Nie ruszać cudzych hooków; odinstalowanie usuwa tylko nasze wpisy
- [x] Ścieżka do `notch-hook` w cudzysłowie (spacje w „Application Support”)
- **Done gdy:** prawdziwa sesja Claude Code wysyła eventy do apki. → HANDOFF

## Faza 5 — Sesje na żywo
- [x] Model `Session`: id, projekt (z `cwd`), status (working / waiting / idle / done / error), bieżące narzędzie + plik, czas startu
- [x] Mapowanie eventów → status (PreToolUse = working + „Edit main.swift”, Stop = done, Notification = waiting…)
- [x] Widok compact: kropka statusu + nazwa narzędzia w „uszach”
- [x] Widok expanded: lista sesji, ostatnie kroki, czas trwania
- [x] Kilka równoległych sesji; usuwanie martwych (SessionEnd / brak eventów X min)
- [ ] Skok do terminala sesji (Ref: `TerminalTarget.swift`) — opcjonalnie
- **Done gdy:** 2 równoległe sesje Claude Code widać poprawnie. → HANDOFF

## Faza 6 — Zatwierdzanie uprawnień
Ref: `HookServer.swift` (grep: `pendingApprovalFD`, `processPermissionRequest`, `"ask"`), `AskQuestion.swift`
- [x] `PermissionRequest`: helper trzyma połączenie i czeka na decyzję
- [x] Karta w wyspie: narzędzie + komenda/plik, przyciski **Allow / Deny / Always**, „Odpowiedz w terminalu”
- [x] Wyspa sama się otwiera i zostaje otwarta do decyzji
- [x] Zwrot JSON-a decyzji w formacie Claude Code; timeout/zamknięcie → „ask” (Claude pyta w terminalu)
- [x] Kolejka, gdy kilka próśb naraz
- [ ] (opcja, pominięte → Później) `AskUserQuestion` — wybór odpowiedzi z wyspy
- **Done gdy:** realne „Allow” z notcha przepuszcza komendę w Claude Code. → HANDOFF

## Faza 7 — Maskotka
Ref: `BotEngine.swift`, `BotCanvasView.swift` (tylko technika — postać własna!)
- [x] Własna postać rysowana w `Canvas` + `TimelineView` (pauza przy hidden)
- [x] Stany: idle, working, waiting (potrzebuje Cię), done (radość), error
- [x] Oczy śledzą kursor; mruganie
- [x] Kolor zależny od statusu
- **Done gdy:** maskotka reaguje na stan sesji, CPU przy hidden ≈ 0%. → HANDOFF

## Faza 8 — Ustawienia i dopieszczenie
- [x] Okno Settings: hooki (instaluj/odinstaluj), ekran, czas auto-zwijania, dźwięki on/off
- [x] Uruchamianie przy logowaniu (`SMAppService.mainApp`)
- [x] Dźwięki (własne / systemowe) na „waiting” i „done”
- [x] Skrót klawiszowy otwierający wyspę
- [x] Tryb demo (udawana sesja) — ułatwia testy UI
- **Done gdy:** da się używać na co dzień. → HANDOFF

## Faza 9 — Wydanie (opcjonalnie)
- [x] Ikona apki (`scripts/make-icon.swift` → `Resources/Assets.xcassets`)
- [x] Build Release, zip / DMG (`scripts/release.sh` → `dist/`)
- [x] Bez Apple Developer: instrukcja „prawy klik → Otwórz”; z Developer ID (99 USD): podpis + notaryzacja
- [x] README

## Faza 10 — v0.3: pełny ekran + Liquid Glass
- [x] `FullScreenWatcher`: brak paska menu + okno aktywnej apki na cały ekran; tylko eventy Space/aktywacji apki
- [x] Wyspa chowa się nad apką w pełnym ekranie; czekające uprawnienie ją pokazuje (opcja w Ustawieniach)
- [x] Liquid Glass za rozwiniętą wyspą (`glassEffect` 26+, `.ultraThinMaterial` na 15), pas notcha czarny (opcja)
- [x] Okno Ustawień przezroczyste (`containerBackground`)
- [x] Suwak przezroczystości szkła (`.regular` → `.clear`) + opcja „jak w systemie” (`NSGlassTintAmount`, Reduce transparency)
- [x] Szkło aktywne także po najechaniu (prywatne `_hasActiveAppearance` w `NotchPanel`)
- [x] Antenka maskotki nieucinana (headroom w `MascotView`), treść wyspy niżej
- [x] Test usera: wygląd szkła, suwak, synchronizacja z systemem
- [x] Pełny ekran wykrywany przez typ Space (`CGSCopyManagedDisplaySpaces`) — na notchu pasek menu nie znika
- [x] Bez mrugania: chowanie od razu, pokazywanie po 0,5 s; zanikanie 0,2 s
- [x] Opcja „schowana w notchu”: najechanie → skrzydełka, klik → duża wyspa
- [x] Test usera: chowanie na pełnym ekranie
- [ ] Energy: ~4% gdy sesja pracuje, 11% po rozwinięciu — zmierzyć prawdziwy spoczynek (do Fazy 11)
- (zrzuty ekranu / `sharingType` — pominięte na życzenie usera)
- **Done gdy:** user zatwierdzi wygląd i chowanie. → HANDOFF

---

## Faza 11 — v0.3.1: audyt + publiczne wydanie na GitHubie
Decyzje (2026-10-10): licencja MIT; historia od zera (repo publiczne startuje jednym commitem, lokalna historia zostaje
tylko u usera); autor = PanBismarck (noreply, ustawione w `git config` repo); nazwa: **NotchKeeper** (sprawdzone 2026-10-10: wolna na GitHubie i w sieci; rename apki, bundle id, README).
`gh` 2.102.0 w `~/.local/bin/gh` (user loguje się sam: `gh auth login`).
- [x] Audyt bezpieczeństwa: `HookServer` + `NotchSocket` (uprawnienia socketu, peer, limity, parsowanie),
      `Sources/Helper/main.swift` (timeouty, szybkie wyjście), instalator hooków / `settings.json`, uprawnienia tylko z kliku
- [x] Audyt prywatności: brak sieci/telemetrii, `grep` repo + historii gita pod sekrety, ścieżki, maile
- [x] Audyt baterii: pomiar spoczynek / sesja pracuje / wyspa rozwinięta (`top -stats idlew,power`, `sample`) → poprawki
- [x] Audyt jakości: force-unwrapy, ostrzeżenia, martwy kod, pliki > 400 linii, brakujące testy
- Wyniki audytu (2026-10-10):
  - S1 (średnie) karta uprawnień ukrywa część komendy: cięcie do 400 znaków + `lineLimit(3)` ze skrótem w środku,
    a „Pozwól” zatwierdza całość. Też znaki niewidoczne/bidi.
  - S2 „Zawsze” nie pokazuje dodawanej reguły. S3 kopie `settings.json.notch-backup-*` bez limitu.
  - P1 ścieżka socketu (nazwa konta) w logu jako `.public`. Poza tym: zero sieci/telemetrii/sekretów.
  - Bateria (Release): spoczynek 0% / 0,1 wybudzeń/s; sesja pracuje 0,37% / 2,4/s; rozwinięta 0,8% / 3,4/s
    (power ≤ 1). Debug rozwinięta ~0,6% — więc 4%/11% to nie Debug; w stanie ustalonym nie odtworzone
    (pewnie piki przy animacjach). WindowServer ~30% z apką i bez. B1: 2 warstwy Liquid Glass naraz.
  - Q1 ostrzeżenie `nonisolated(unsafe)` SystemGlass.swift:33. Q2 brak testów `HookInstaller.apply`.
    Force-unwrapów, martwego kodu i plików > 400 linii brak; 82 testy ✔.
- [x] Raport z audytu → user wybrał S1 + Q2 (reszta odpuszczona) → zrobione: karta pokazuje całą komendę
      (przewijanie + „przewiń ↓”, znaki niewidoczne jako ⟨U+XXXX⟩, MCP = wszystkie parametry, > 5000 znaków →
      tylko „W terminalu”); `HookInstaller` → Core + 6 testów (wyszedł błąd: 2 kopie w tej samej sekundzie). 92 testy ✔
- [x] Rename na NotchKeeper (2026-10-10): bundle `io.github.panbismarck.NotchKeeper`, `NotchKeeper.app`, helper
      `notchkeeper-hook`, `Application Support/NotchKeeper`, scheme/targety, kopie `settings.json.notchkeeper-backup-*`.
      Migracja: stare wpisy `notch-hook` dalej „nasze” (status „nieaktualne” → podmiana), ustawienia kopiowane raz
      z `pl.bismarck.Notch`, stary katalog sprzątany po udanym „Zastosuj”. 94 testy ✔
- [x] LICENSE, README EN (README.md) + PL (README.pl.md), podziękowanie Coucou, Gatekeeper + xattr. GIF: TODO usera → docs/demo.gif
- [x] Wersja 0.3.1 (build 3) w `project.yml`, `scripts/release.sh` → `dist/NotchKeeper-0.3.1.dmg` + `.zip`
- [ ] (po zgodzie usera) publiczne repo, push, tag `v0.3.1`, GitHub Release
- **Done gdy:** audyt zamknięty, release publiczny. → HANDOFF

## Później (pomysły spoza zakresu) — zastąpione przez ROADMAP.md (aktualna)
- `AskUserQuestion` — wybór odpowiedzi z wyspy (opcja z Fazy 6)
- Inne agenty (Codex, Gemini CLI)
- Podgląd diffów edytowanych plików
- → v0.4: Niebieski ludek (osobny stan maskotki), gdy sesja czeka na zadanie w tle (`run_in_background`, Monitor, subagent w tle) — zamiast „pracuje”/„idle”
- Upuszczanie pliku na notch → pytanie do Claude
- Wskaźnik zużycia planu Claude
