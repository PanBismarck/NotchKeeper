# NotchKeeper — Roadmapa

> Stan: **v0.1.0** wydana lokalnie (fazy 0–9), **v0.3** zrobiona (faza 10). Następna: **v0.3.1** = audyt + publiczny GitHub. Każda wersja = osobna faza w `TODO.md` + handoff.
> Bateria i „nigdy nie blokuj Claude” obowiązują zawsze. Tylko Claude Code, tylko macOS.
>
> **Odrzucone przez usera:** skok do terminala, personalizacja maskotki, inne CLI, pozostałe funkcje „dla Claude Code”
> z researchu 2026-10-09 (AskUserQuestion, skróty Allow/Deny, diff, Markdown, reguły, push na telefon…).
> Research: Isle, Pushary Isle, CodeIsland, claude-island, NotchNook, Alcove.

## v0.1.x — Stabilizacja
- Uwagi z codziennego używania, pomiar baterii po dniu pracy, start po restarcie.
- Wykrywanie starego `notch-hook` → podpowiedź „Zaktualizuj”.

## v0.3 — Ukrywanie wyspy ✅ (faza 10)
- Chowanie wyspy, gdy aktywna apka jest w pełnym ekranie (opcja; wyjątek: czekające uprawnienie).
- ~~Wyspa niewidoczna na zrzutach~~ — pominięte na życzenie usera.
- Opcja „schowana w notchu” na pełnym ekranie: najechanie → skrzydełka, klik → duża wyspa.
- **Liquid Glass design**: rozwinięta wyspa, karty i okno Ustawień w stylu Liquid Glass (`glassEffect`, macOS 26+,
  fallback na `.ultraThinMaterial` dla macOS 15). Notch/„uszy” zostają czarne (muszą zlewać się z prawdziwym notchem).

## v0.3.1 — Audyt + pierwsze publiczne wydanie na GitHubie (faza 11)
- **Audyt przed upublicznieniem** (cały kod, ~3,3 tys. linii Swift + `notch-hook`):
  - Bezpieczeństwo: socket hooków (uprawnienia pliku, kto może się połączyć, limity rozmiaru wiadomości, zły JSON),
    `notch-hook` (zawsze szybkie wyjście, timeouty — nigdy nie blokuje Claude), zapis `~/.claude/settings.json`
    (kopia, merge), decyzja o uprawnieniu tylko z kliknięcia, prywatne API (`dlopen`), entitlements / hardened runtime.
  - Prywatność: zero sieci i telemetrii, brak danych osobistych / ścieżek / sekretów w repo i w historii gita.
  - Optymalizacja: Energy w spoczynku, przy pracy sesji i po rozwinięciu (sprawa 4% / 11%), wybudzenia, pamięć,
    zbędne przerysowania SwiftUI.
  - Jakość: force-unwrapy i ścieżki crashy, ostrzeżenia Swift 6, martwy kod, pliki > 400 linii, pokrycie testami.
- **Przygotowanie repo**: LICENSE (MIT), historia od zera (jeden commit), autor = noreply GitHuba, README (EN + PL) z GIF-em, podziękowanie dla Coucou (inspiracja, MIT),
  `.gitignore`, wersja 0.3.1, notka o Gatekeeperze (apka bez notaryzacji → pierwszy start przez prawy klik → Otwórz).
- **Wydanie**: publiczne repo na GitHubie, tag `v0.3.1`, GitHub Release z `.dmg` i `.zip` (`scripts/release.sh`).
  Każdy krok wychodzący na zewnątrz (utworzenie repo, push, release) — dopiero po potwierdzeniu usera.

## v0.3.2 — Interfejs po angielsku
- Wszystkie napisy UI (wyspa, karta uprawnień, menu pod prawym klikiem, Ustawienia, okno hooków) w String Catalog
  (`Localizable.xcstrings`), język bazowy EN + tłumaczenie PL; wybór wg języka systemu.
- Liczby mnogie („+3 więcej”, czasy) przez warianty pluralizacji w katalogu, nie ręcznie.
- README: usunąć notkę „UI tylko po polsku” i polskie nazwy menu z wersji EN.

## v0.4 — Półka na pliki + AirDrop
- Przeciągnięcie pliku na notch → wyspa się otwiera i pokazuje półkę.
- Półka trzyma pliki tymczasowo (odnośniki, nie kopie), przeciąganie z powrotem do Findera/apek.
- Upuszczenie na strefę AirDrop → `NSSharingService(named: .sendViaAirDrop)`.
- Zawartość półki przetrwa restart apki (opcja), czyszczenie ręczne.
- Bateria: nasłuch drag tylko przez `NSDraggingDestination` panelu — zero pollingu.
- Niebieski ludek: osobny stan maskotki, gdy sesja czeka na zadanie w tle (`run_in_background`, Monitor, subagent w tle).

## v0.5 — Odtwarzacz muzyki
- Tytuł, wykonawca, okładka, play/pause/następny/poprzedni; w „uszach” mini-okładka gdy gra.
- Spotify + Apple Music. Do zbadania na starcie fazy: od macOS 15.4 prywatny MediaRemote jest ograniczony
  → plan B: AppleScript / `ScriptingBridge` per apka (wymaga zgody Automation) albo
  powiadomienia `com.spotify.client.PlaybackStateChanged` / `com.apple.Music.playerInfo` (event-driven, 0 kosztu).
- Pasek postępu utworu tylko gdy wyspa otwarta (bateria).
- Priorytet sesji Claude: czekające uprawnienie zawsze wygrywa z muzyką.

## v1.0 — Wydanie „pełne”
- Apple Developer ID → podpis + notaryzacja, auto-aktualizacje (Sparkle).
- README EN + zrzuty/GIF, licencja, GitHub Releases, UI PL + EN.

## v1.1 — Limity planu i kontekst (odłożone 2026-10-10)
- **Limit planu**: okno 5 h + tygodniowe (% i czas do resetu) — w „uszach” i w rozwiniętej wyspie.
- **Kontekst sesji**: % zajętego okna kontekstu przy każdej sesji, ostrzeżenie blisko auto-compactu.
- Wnioski z próby (v0.2, cofnięta — kod w historii git, commit `eb346ff`):
  - JSON statusline Claude Code ma `rate_limits` i `context_window`, ale **Claude Desktop nie uruchamia `statusLine`** —
    a user nie używa terminala. Lokalnie (JSONL, `~/.claude/cache`) brak danych o limitach.
  - Limity: jedyne źródło to nieoficjalny endpoint użycia Anthropic z tokenem OAuth z Keychain (sieć) — user odrzucił.
  - Kontekst: z `transcript_path` (ostatnie `usage`: input + cache_creation + cache_read), ale rozmiar okna modelu
    nieznany lokalnie (`model-catalog` go nie podaje) — trzeba rozwiązać.

