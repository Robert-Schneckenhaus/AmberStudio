# Spieler, Studio und Beispiel (game/)

| Ordner | Inhalt |
|---|---|
| `Amber.Player/` | **amberplayer**: spielt einen Inhaltsordner (Tiled-Karten, AmberScript, Tabellen, Screens), dazu Kartenbearbeiter und Entwicklerwerkzeuge. Geschrieben in CShift; Fenster und Eingabe über **GLFW**, gezeichnet wird mit einem eigenen **Software-Renderer** in ein 320×200-Bild |
| `Amber.Studio/` | **Amber Studio**, der Editor mit Karten, Datenbank, Gesprächen und „Spielen ab hier“, auch im Browser: [README](Amber.Studio/README.md) |
| `content/` | Das **Beispielspiel**: eine Wiese mit Haus, Teich und Ina, ein Keller mit Ratten und einer Kiste |
| `tests/` | Eingabeskripte: das Beispiel durchspielen (`playthrough.txt`), das Studio bedienen (`studio.txt`) |

## Starten

```
scripts/start.sh                  # amberplayer bauen und das Beispiel spielen (weitere Argumente gehen durch, z. B. --scale 3)
scripts/test.sh                   # alles: Build, Unit-Tests, Inhalt prüfen, Durchspielen, aus dem Pack, Studio
scripts/test.sh unit|content|playthrough|pack|studio
```

Unter Windows `scripts\start.cmd`, `scripts\test.cmd`, `scripts\edit.cmd`. Gebaut wird mit `cshiftc` (siehe [src/README.md](../src/README.md)); von Hand, aus `game/`:

```
cshiftc build Amber.Player
Amber.Player/bin/amberplayer                       # Windows: amberplayer.exe
Amber.Player/bin/amberplayer --content pfad        # einen anderen Inhaltsordner spielen
```

**GLFW:** Unter Windows holt `Amber.Player/get-glfw.ps1` die offizielle statische Bibliothek nach `Amber.Player/lib` (die Skripte machen das beim ersten Bauen), unter Linux kommt sie aus dem Paket (`sudo apt install libglfw3-dev`). Der Header liegt unter `Amber.Player/include/GLFW` (zlib-Lizenz, `include/LICENSE-GLFW.md`).

Das Programm sucht den Ordner mit `game/content/tables.yaml` vom aktuellen Ordner aus nach oben (`--root ordner` gibt ihn vor, `--content ordner` den Inhaltsordner). Bilder, die nicht ins Repository gehören (lizenzierte Tilesets, Figurenpakete, Icons), sucht es unter `<root>/assets`.

| Taste | Wirkung |
|---|---|
| Pfeile / WASD | Gehen (mit Shift: Rennen), auch schräg |
| Leertaste / Enter | Ansprechen (Figur vor dir) oder Untersuchen (Feld vor dir); Text weiter |
| I / P | Gegenstände / Gefährten (Ausrüstung, Zauber) |
| In der Konversation: Pfeile, Enter, G, H, T, Esc | Wort wählen und fragen, Gegenstand geben (G) oder zeigen (H), ein Wort tippen (T), verlassen |
| In der Truhe: Pfeile, Enter, Maus, A, G, Esc | Gegenstand auf die andere Seite (auch per Ziehen), alles nehmen (A), Gold nehmen (G), schließen |
| Im Kampf: Mausklick, T, H | Klick auf einen Gegner oder **T** (der nächste) macht ihn zum Ziel; **H** heilt mit einem Gegenstand. Fliehen: weit genug weggehen |
| F2 / F3 | Speichern / Laden (`game/saves/quick.amsv` oder `--save datei`) |
| F5 / F6 | Debug: Spielzeit +1 Stunde / +10 Minuten |
| Esc | Beenden (außerhalb von Fenstern) |

## Das Beispielspiel

Bewusst klein; es zeigt alle Teile einmal, und die Tests spielen es durch.

- **Karten:** `content/maps/meadow.tmx` (24×16) und `cellar.tmx` (14×10), Ebenen `ground`, `decor`, `objects`, `over`, `collision`. Das Tileset `example tiles.png` ist selbst gezeichnet (MIT wie das Repository); `scripts/make-example-maps.py` erzeugt Tileset und Karten neu (danach in Tiled oder im Studio bearbeiten, nicht mehr neu erzeugen).
- **Skripte:** `meadow.ams` (Ankunft, Schild, Ina mit Gespräch und Geben, Treppe in den Keller), `cellar.ams` (Ratten als Kampf, Kiste als Truhe, Treppe hinauf), `screens.ams` (das Verhalten der Screens).
- **Tabellen:** `content/tables.yaml` mit Start (`start: { map: meadow, x: 12, y: 12 }`), Karten, Held, einer Gefährtin (Ina, Heilerin), einem Zauber, Monstern und Gruppen, Truhen, Wörtern, Gegenständen und Texten.
- **Ablauf:** das Schild lesen (Wort „Cellar“) → Ina nach dem Keller fragen → die Treppe hinunter → die Ratten besiegen → die Kiste leeren → Ina erneut fragen: sie schließt sich an.

Ohne `characters.yaml` (Figurenpaket) zeichnet der Spieler einfache Figuren, ohne `ui.yaml` schlichte Fenster, ohne `icon_sheet` drei Buchstaben statt Icons.

## Aus dem Pack

Das Spiel läuft **immer aus einem Pack** (Spec Abschnitt 9): Ohne Option kocht es beim Start den Inhaltsordner im Speicher (`Content/ContentSource.csh` liest, `Content/PackCook.csh` kocht) und läuft daraus (`Content/GameContent.csh`). Mit `--pack datei.pack` nimmt es ein fertig gekochtes Pack (`--build-pack`); dann braucht es keinen Compiler und keine Quelltexte. Im Pack: die Skripte (global, Karten mit Figuren und gebackenen Routinen, Screens), Layout, Symbolnamen, Natives, Texte, Stichworte und die Tabellen des Spiels (`Content/GameTables.csh`). **Noch nicht im Pack:** die Tiled-Karten und die Grafik.

## Paletten, Tag und Nacht

Karte und Figuren sind **Palettenbilder** (`Game/MapLook.csh`): Jede Karte bekommt beim Start eine Palette, die Kacheln und Figuren werden auf deren Einträge abgebildet, und der Renderer holt die Farben erst beim Zeichnen aus der aktuellen Palette. Tag, Nacht und Effekte ändern nur die Palette.

- **Palette der Karte:** aus `tables.yaml` (`maps: name: { name: ..., palette: <name> }`, `palettes: <name>: datei.gpl`), sonst aus den Kacheln der Karte und den Figuren gebaut.
- **Nacht:** `night: <name>` in der Karte, sonst aus der Tagespalette gemacht. Der Host blendet nach der Uhr (5–7 Uhr Morgendämmerung, 7–19 Tag, 19–21 Abenddämmerung, dann Nacht). `daylight: off` hält die Palette fest (der Keller des Beispiels).
- **Skripte:** `set_palette(PAL.x)`, `fade_palette(PAL.x, ticks, flags)`, `0xFFFF` gibt die Palette an Tag und Nacht zurück; `flash(0xRGB, ticks)` färbt die Karte kurz ein.
- **Unverändert:** Eintrag 0 (transparent) und die letzten 8 (Oberfläche).

## Screens, Kampf, Gefährten

- **Screens** (Textbox, Bestätigung, Konversation, Worteingabe, Gegenstandswahl, Inventar, Truhe, Shop, Gefährten) sind Daten: Layout in `content/screens/*.yaml` (geprüft gegen `spec/schemas/screen.schema.json`), Verhalten in `screen name { ... }`-Blöcken (`screens.ams`), native Widgets und Datenquellen in `Screens/Widgets.csh` und `Game/ScreenHost.csh`. `say`, `confirm` und `push_screen` öffnen Screens; `push_screen` wartet auf `pop_screen(wert)`, der Wert steht danach in `result`.
- **Kampf in Echtzeit** (`Game/Combat.csh`): `battle(G.gruppe, 0)` stellt die Monster neben den Helden auf die Karte; das Skript wartet, bis der Kampf vorbei ist (Ergebnis 0 gewonnen, 1 geflohen, 2 verloren). Der Held schlägt das Ziel im Takt der Angriffsgeschwindigkeit seiner Waffe (`speed:`), die Monster laufen zum Helden. Die Würfel sind die des Interpreters, ein Lauf mit Eingabeskript ist also immer gleich.
- **Gefährten** (`Game/Companions.csh`, `tables.yaml` `companions:`): bis zu 4, kommen mit `add_member(C.name)`, folgen über Kartenwechsel und kämpfen selbst: Heiler heilen und schützen, Ranger schießen auf das schwächste Monster, Magier auf Gruppen. Ausrüstung (`slot: weapon|armor`) und Zauber (`spells:`, Schriftrollen mit `teaches:`) im Screen `party` (Taste P).

## Kartenbearbeiter

Ein Editor für die Kartengrafik im selben Fenster und mit demselben Renderer wie das Spiel (640×400 virtuell): `scripts/edit.sh [karte]` (ohne Argument die erste Karte). Malen, Radieren, Pipette, Terrain-Pinsel (braucht ein Tileset mit Wang-Set), Ebenen, Kollision, Rückgängig; Ctrl+S schreibt die TMX (die alte bleibt als `.tmx.bak`). Bequemer geht das in [Amber Studio](Amber.Studio/README.md).

## Prüfen ohne Tastatur

Ein Eingabeskript treibt das Spiel Tick für Tick, macht Screenshots und prüft Erwartungen; mit `--headless` ohne Fenster:

```
cd game
Amber.Player/bin/amberplayer --headless --script tests/playthrough.txt --save out/test.amsv
```

Befehle: `wait N`, `press Key`, `hold Key N` (16 Ticks = ein Feld), `repeat Key n interval`, `down Key` / `up Key`, `shot pfad.png`, `warp x y`, `map name x y`, `time hh:mm`, `hp n`, `member add|remove name`, `type Text`, `mouse x y` / `mousedown` / `mouseup` / `click`, `expect gold|hp|item|word|flag|at|blocked|map|modals|member|redraws ...`, `quit`. Eine falsche Erwartung beendet den Lauf mit Exit-Code 1.

## Entwicklerwerkzeuge

| Aufruf | Zweck |
|---|---|
| `--check-content` | Tabellen und Skripte kompilieren, ein Pack im Speicher kochen und so zurücklesen, wie das Spiel es liest |
| `--build-pack datei.pack` | Die Inhalte in ein Pack kochen und prüfen; ansehen mit `amberc dump datei.pack`, starten mit `--pack datei.pack` |
| `--preview-map karte.tmx out.png 2 collision grid` | Karte ohne Fenster als PNG rendern |
| `--map-palette karte.tmx ... --out palette.gpl` | Palette einer oder mehrerer Karten aus den Farben ihrer Kacheln (Optionen wie `amberpal extract`) |
| `--contact sheet.png tileW tileH out.png ...` | Kontaktbogen mit Kachelnummern eines Tilesets |
| `--char-preview out.png "ebene/teil/variante,..." ...` | Figurenvorschau für ein Paper-Doll-Figurenpaket |

## Aufbau von Amber.Player

| Ordner | Inhalt |
|---|---|
| `Platform/` | Plattformschicht: `IPlatform` (Anzeige, Eingabe, Uhr) und die eine Spielschleife `RunGame`, `GlfwPlatform` (Fenster), `HeadlessPlatform` (ohne Fenster), Eingabe und Eingabeskript, Startoptionen, Pfade. Amber Studio ist eine dritte Plattform |
| `Graphics/` | Software-Renderer (Zeichenliste mit Ebenen, Alpha, Text), Pixelschrift, Kachelbilder mit Platzhaltern, Figuren (Paper Doll oder einfache Figuren) |
| `Tiled/` | TMX/TSX-Leser und -Schreiber (Wang-Sets, Flip-Flags, Animationen, CSV und Base64/zlib), ein kleiner XML-Leser |
| `Content/` | Tabellen laden, Skripte kompilieren, Pack kochen und prüfen |
| `Game/` | Welt, Akteure, NPC-Routinen, Uhr, Party, Kampf, Gefährten, Skript-Host (`PrototypeHost : IGameHost`), `ScreenHost`, `WorldView`, `Ui` (HUD, Sprechblasen, Theme), Spielstände |
| `Screens/` | Datengetriebene Screens: `Widgets`, `ScreenModal` |
| `Tools/` | Palette einer Karte, Kartenvorschau, Kontaktbogen, Figurenvorschau, Hilfen zum Erzeugen von Karten |
| `Editor/` | Kartenbearbeiter: Dokument mit Rückgängig und Terrain, Kachelvorrat, Bedienfläche |

## Oberfläche aus Sprites und Farben (Theme)

`content/ui.yaml` (optional, gelesen von `src/Amber.Screens/UiTheme.csh`) setzt Fenster und Knöpfe aus Sprites und Farbflächen zusammen: `sprite_folder` (relativ zu `assets/`), `sprites:`, `colors:`, `looks:` mit `parts:` (`rect`, `frame`, `tile`, `border` aus acht Randstücken, `image`) und `states:` für Hover und Fokus, `defaults:` je Knotenart; ein Knoten wählt einzeln mit `look: name`. Fehlt `ui.yaml` oder ein Sprite, fällt der Look auf schlichte Farbflächen zurück.

## Bekannte Lücken

- Musik und Sound fehlen. NPCs einer Karte, auf der man nicht ist, bewegen sich nicht. Der Host meldet nicht unterstützte Aktionen auf der Konsole.
- Karten und Grafik liegen noch nicht im Pack; eine Migration älterer Spielstände nutzt der Spieler nicht.
- Screens: `image`, `portrait` und `viewport` fehlen; der Spieler liest die Screens aus dem YAML im Pack, nicht aus dem Binär-Chunk.
