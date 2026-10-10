# HANDOFF

> Nadpisywany na końcu każdej fazy / po dużej zmianie. Krótko — max ~40 linii.

**Data:** 2026-10-10
**Faza:** 11 (v0.3.1: audyt + publiczny GitHub) — wszystko gotowe lokalnie. Został tylko publiczny release (po zgodzie usera).

## Zrobione w tej sesji
- `LICENSE` (MIT, © 2026 PanBismarck).
- `README.md` po angielsku (główny) + `README.pl.md`; linki EN ⇄ PL, sekcja Acknowledgements (Coucou, Louis-CFM, MIT),
  Gatekeeper: prawy klik → Otwórz / „Open Anyway” / `xattr -dr com.apple.quarantine`. Opisane funkcje v0.3
  (pełny ekran, Liquid Glass). README EN zaznacza, że UI jest na razie tylko po polsku (nazwy menu z tłumaczeniem).
- GIF: w README jest komentarz-placeholder `docs/demo.gif` — do nagrania przez usera (prawy klik → Tryb demo).
- `project.yml`: `MARKETING_VERSION` 0.3.1, `CURRENT_PROJECT_VERSION` 3.
- `scripts/release.sh` ✔ → `dist/NotchKeeper-0.3.1.dmg` (1,2 MB) + `.zip` (1,1 MB); w bundle wersja 0.3.1 i `notchkeeper-hook`.

## Do zrobienia przez usera
- (opcjonalnie) nagrać `docs/demo.gif` i odkomentować w obu README.
- `gh auth login` (gh w `~/.local/bin/gh`), jeśli jeszcze nie.
- Dalej aktualne z poprzedniej sesji: „Hooki Claude Code…” → „Zaktualizuj”; usunąć stare `/Applications/Notch.app`.

## Znane
- UI tylko po polsku — lokalizacja EN to kandydat do ROADMAP (ważne dla publicznego repo).
- Q1 ostrzeżenie `nonisolated(unsafe)` SystemGlass.swift:33 (odpuszczone).

## Następny krok (TYLKO po wyraźnej zgodzie usera)
Publiczne repo `PanBismarck/NotchKeeper` z historią od zera: nowy katalog/orphan branch, jeden commit z obecnym
stanem (bez `reference-coucou/`, `build/`, `dist/`), `gh repo create --public`, push, tag `v0.3.1`,
`gh release create v0.3.1 dist/NotchKeeper-0.3.1.dmg dist/NotchKeeper-0.3.1.zip` z notatką (EN).
Przed pushem: ponowny grep pod sekrety/ścieżki/maile w plikach do publikacji.
