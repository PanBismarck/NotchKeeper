# Notch — zasady dla Claude

Apka **macOS-only** (bez iPhone'a, Windows, Linux): mała wyspa w notchu MacBooka,
która pokazuje sesje Claude Code na żywo i pozwala zatwierdzać uprawnienia jednym kliknięciem.
Inspiracja: Coucou (MIT) — kod do podglądu w `reference-coucou/` (tylko do czytania, nie kopiujemy assetów/nazwy/postaci Mochi).

## Subagenty
Jeśli opłaca się delegować (mechaniczne zadania, przeszukiwanie `reference-coucou/`), używaj agentów z `model: haiku`. Proste rzeczy rób sam — spawn agenta też kosztuje.

## Start każdej sesji
1. Przeczytaj `HANDOFF.md` (stan, ostatnie decyzje, następny krok).
2. Przeczytaj tylko bieżącą fazę w `TODO.md` — nie całe repo.
3. Pracuj tylko nad tą fazą. Coś spoza fazy → dopisz do sekcji „Później” w `TODO.md`.

## Oszczędzanie kontekstu (limit!)
- Nie czytaj całych dużych plików. Najpierw `grep -n`, potem `sed -n 'od,dop'`.
- `reference-coucou/` przeszukuj grepem, nigdy nie czytaj w całości (HookServer.swift ma 3700 linii).
- Pliki Swift trzymaj < ~400 linii — dziel na mniejsze.
- Build: wyciągaj tylko błędy: `xcodebuild ... 2>&1 | grep -E "error:|warning: unre|BUILD"`.
- Nie wklejaj długich logów do czatu.

## Koniec fazy / po dużej zmianie → HANDOFF
1. Zbuduj i sprawdź, że działa.
2. Odhacz punkty w `TODO.md`.
3. Nadpisz `HANDOFF.md` (wzór w pliku): co zrobione, kluczowe pliki, decyzje, znane problemy, DOKŁADNY następny krok.
4. `git commit`.
5. Powiedz userowi: „Handoff gotowy, zrób /clear i napisz: lecimy dalej”.

## Stack i reguły techniczne
- Swift 6 (strict concurrency), SwiftUI + AppKit, macOS 15+. Zero zależności zewnętrznych.
- Projekt generowany XcodeGen (`project.yml`) — nie edytuj `.xcodeproj` ręcznie.
- Build: `~/.local/bin/xcodegen && xcodebuild -scheme NotchKeeper -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`
- Run: `pkill -x NotchKeeper; open build/Build/Products/Debug/NotchKeeper.app`
- XcodeGen 2.46.0 zbudowany ze źródeł w `~/.local/bin` (brak Homebrew).
- Apka bez ikony w Docku (`LSUIElement`) i bez ikony w pasku menu — menu pod prawym klikiem na notch (`NotchMenu`).
- **Nigdy nie blokuj Claude Code**: hook kończy się natychmiast, jeśli apka nie odpowiada.
- **Nigdy nie nadpisuj `~/.claude/settings.json`** bez: kopii z datą, merge, pokazania diffa, potwierdzenia usera.
- Nigdy nie zatwierdzaj uprawnienia bez kliknięcia usera.
- Sekrety (jeśli kiedyś będą) tylko w Keychain. Zero telemetrii.

## Bateria (MacBook — priorytet!)
Apka działa cały czas, więc w spoczynku ma być praktycznie niewidoczna w „Energy Impact”.
- Event-driven, nie polling: żadnych `Timer`ów co sekundę, żadnego odpytywania plików/procesów w pętli.
- Gdy wyspa schowana: 0% CPU — `TimelineView(.animation(paused:))`, brak Canvas redraw, brak śledzenia myszy w pętli.
- Śledzenie myszy tylko przez `NSTrackingArea` / monitor eventów, nie timerem; globalny monitor ruchu myszy tylko gdy wyspa otwarta.
- Animacje maskotki: ograniczony framerate, pauza, gdy nic się nie dzieje (idle → statyczna klatka + rzadkie mrugnięcie).
- Socket: blokujący `accept` / `DispatchSource` — zero aktywnego czekania.
- Timery (auto-zwijanie) z `tolerance` ≥ 10% i tylko gdy potrzebne; anulować przy zmianie stanu.
- Nie wybudzać GPU bez potrzeby: brak ciągłych blurów/materiałów pod animacją przy schowanej wyspie.
- Każda faza kończy się szybkim pomiarem: Activity Monitor → Energy (wyspa schowana: ~0 CPU, brak „Preventing Sleep”).
