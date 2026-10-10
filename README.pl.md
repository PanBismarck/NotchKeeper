# NotchKeeper

Mała wyspa w notchu MacBooka, która pokazuje sesje **Claude Code** na żywo
i pozwala zatwierdzać uprawnienia jednym kliknięciem — bez przełączania się do terminala.

[English](README.md) · **Polski**

<img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@1x.png" width="128" alt="Ikona NotchKeeper">

<!-- GIF z demo: docs/demo.gif (prawy klik na notch → Tryb demo) -->

- **Sesje na żywo** — status (pracuje / czeka na Ciebie / gotowe / błąd), bieżące narzędzie i plik, czas trwania; kilka sesji naraz.
- **Uprawnienia z wyspy** — karta z pełną komendą lub plikiem i przyciskami *Pozwól / Odrzuć / Zawsze*.
  Brak kliknięcia = Claude pyta jak zwykle w terminalu.
- **Maskotka** — zmienia minę i kolor zależnie od stanu, śledzi kursor.
- **Oszczędna dla baterii** — wszystko na eventach, schowana wyspa ≈ 0% CPU.
- **Pełny ekran** — wyspa chowa się nad apką na pełnym ekranie; czekające uprawnienie i tak ją pokaże.
- **Liquid Glass** na macOS 26 (materiał na macOS 15), regulowana przezroczystość.
- Skrót ⌥⌘N, opcjonalne dźwięki, start przy logowaniu, monitor bez notcha → „pigułka” na górze ekranu.

Wymaga macOS 15 lub nowszego. Bez telemetrii, bez połączeń sieciowych.

## Instalacja

1. Pobierz `NotchKeeper-<wersja>.dmg` (lub `.zip`) z [Releases](../../releases) i przeciągnij **NotchKeeper.app** do **Applications**.
2. Pierwsze uruchomienie: apka nie jest notaryzowana przez Apple, więc macOS ją zablokuje.
   **Prawy klik na NotchKeeper.app → Otwórz → Otwórz.**
   Jeśli tego przycisku nie ma (nowsze macOS): *Ustawienia systemowe → Prywatność i ochrona → „NotchKeeper” został zablokowany → Otwórz mimo to*.
   Albo w terminalu:
   ```bash
   xattr -dr com.apple.quarantine /Applications/NotchKeeper.app
   ```
3. **Prawy klik na notch** → **Hooki Claude Code…** → przejrzyj zmiany → **Zainstaluj**.
4. Uruchom nową sesję `claude` — wyspa ożyje.

### Co robi instalacja hooków

- Kopiuje mały program `notchkeeper-hook` do `~/Library/Application Support/NotchKeeper/bin/`.
- Dopisuje wpisy do `~/.claude/settings.json` (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
  Notification, Stop, SessionEnd, PermissionRequest). Przed zapisem pokazuje diff i robi kopię pliku z datą.
- Cudzych hooków nie rusza. **Odinstaluj** w tym samym oknie usuwa tylko wpisy NotchKeeper.

Hook nigdy nie blokuje Claude Code: jeśli apka nie działa, kończy się od razu.
Komunikacja idzie wyłącznie przez lokalny socket Unix (`~/Library/Application Support/NotchKeeper/notch.sock`, uprawnienia 0600).

## Użycie

| Akcja | Jak |
|---|---|
| Otwórz / zamknij wyspę | najedź na notch, kliknij albo ⌥⌘N |
| Zwiń | Esc lub klik poza wyspą |
| Odpowiedz na uprawnienie | *Pozwól* (raz), *Zawsze* (zapamiętaj regułę), *Odrzuć*, *W terminalu* |
| Menu (Ustawienia, Hooki, Tryb demo, Zakończ) | **prawy klik na notch** |

## Odinstalowanie

1. Prawy klik na notch → **Hooki Claude Code…** → **Odinstaluj**.
2. Zamknij apkę i usuń `NotchKeeper.app` oraz `~/Library/Application Support/NotchKeeper/`.

## Budowanie ze źródeł

Potrzebne: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen && xcodebuild -scheme NotchKeeper -configuration Debug -derivedDataPath build build
```

```bash
./scripts/release.sh
```

`release.sh` buduje wersję Release i tworzy `dist/NotchKeeper-<wersja>.zip` i `.dmg` (podpis ad-hoc).
Ikona generowana jest skryptem `swift scripts/make-icon.swift`.

Bez konta Apple Developer apka jest podpisana ad-hoc, stąd krok „prawy klik → Otwórz”.
Z Developer ID można ją podpisać i notaryzować — wtedy otwiera się normalnie.

## Podziękowania

Pomysł zainspirowany projektem [Coucou](https://github.com/Louis-CFM/coucou) autorstwa Louis-CFM (MIT) — dzięki!
Kod, maskotka i grafika NotchKeeper są własne.

## Licencja

[MIT](LICENSE) © 2026 PanBismarck
