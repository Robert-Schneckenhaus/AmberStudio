# Amber Studio

Der Editor für Spiele der Amber-Engine, geschrieben in CShift mit **System.Ui**. Er läuft als Fenster unter Windows und Linux und als Webseite im Browser (wasm). Bisher: Karten, Spielen ab hier, Datenbank und Gespräche; geplant sind ein Ereignis-Editor, Screens, Grafik und Paletten und ein Einblick ins laufende Spiel.

Das Studio hat **kein eigenes Dateiformat**. Es liest und schreibt die Dateien des Spiels:

- `tables.yaml`
- `maps/*.tmx`
- `scripts/*.ams`
- `screens/*.yaml`

Git, VS Code, Tiled und die Testskripte funktionieren deshalb weiter. Geändert wird immer nur die betroffene Zeile. Kommentare und Layout bleiben stehen.

## Bauen und starten

Das Studio braucht Baum, Trenner, Reiter und gehaltene Tasten aus System.Ui. Die sind seit CShift-PR #141 in `master` und kommen mit dem nächsten Release (nach 0.41). Bis dahin nimmt man die Standardbibliothek eines CShift-Checkouts von `master`:

```
cshiftc build game/Amber.Studio --stdlib <CShift>/stdlib
game/Amber.Studio/bin/amberstudio                      # öffnet das Repository um den aktuellen Ordner
game/Amber.Studio/bin/amberstudio --project <ordner>   # oder einen anderen Spielordner
```

Ein Projekt ist ein Spielordner: der Ordner mit `tables.yaml`, ein Ordner mit `content/tables.yaml` oder das Repository mit `game/content`. Bilder, die nicht im Spielordner liegen (`assets/`, etwa lizenzierte Pakete), sucht das Studio im Ordner darüber. Fehlen sie, zeigt es wie das Spiel Platzhalter.

**Im Browser:**

```
cshiftc publish game/Amber.Studio --stdlib <CShift>/stdlib -o amberstudio.html
```

Die HTML-Datei enthält alles und läuft auch direkt von der Platte. „Projekt öffnen…“ öffnet die Ordnerauswahl des Browsers; der gewählte Ordner wird in die Seite kopiert. Es reicht der Inhaltsordner (`game/content`); wer Bilder aus `assets/` braucht, wählt den Ordner darüber.

**Zum Ausprobieren ohne Compiler:** Der Workflow `.github/workflows/pages.yml` baut das Studio mit [scripts/studio-page.sh](../../scripts/studio-page.sh) als Seite auf GitHub Pages, bei jedem Push auf `main`, der das Spiel oder die Bibliotheken ändert. Die Seite öffnet beim Start das Beispielspiel (`game/content`).

Gespeicherte Dateien bietet der Browser als **Download** an, denn eine Webseite kann den Ordner des Benutzers nicht beschreiben. Die Seite enthält nur das `cshift.js` des Compilers, mit dem sie gebaut wurde. Bis zum nächsten CShift-Release meldet der Browser keine gehaltenen Tasten. Das Spiel behandelt eine Taste dann als gehalten, solange sie sich wiederholt.

## Aufbau des Fensters

- **Oben:** die Menüleiste (Projekt, Bearbeiten, Spiel, Ansicht).
- **Links:** der Projektbaum mit Karten, Datenbank (die Abschnitte von `tables.yaml`), Gesprächen (jede Figur mit `npc`-Block), Skripten, Screens und `tables.yaml`.
- **Mitte:** Reiter für Karte, Spiel, Datenbank, Gespräche und Text. Darunter stehen die **Meldungen**: die Prüfung wie `--check-content` (Tabellen, Skripte, Screens, gekochtes Pack) und die Funde von „Wo benutzt?“. Ein Klick auf eine Meldung mit Datei und Zeile öffnet die Stelle.
- **Rechts:** die Eigenschaften dessen, was gewählt ist.

Die Grenzen zwischen den Bereichen lassen sich mit der Maus verschieben.

| Reiter | Was man dort tut |
|---|---|
| **Karte** | Mit den Werkzeugen des Prototyp-Kartenbearbeiters (`Editor/MapDocument`) malen: Malen, Radieren, Pipette (auch die rechte Maustaste) und Gelände aus dem Wang-Set. Dazu Ebenen zeigen und wählen, die Kollisionsebene, ein Raster, Zoom (Regler oder Strg+Mausrad) und die Kacheln des Tilesets. Rückgängig gilt pro Strich. Gespeichert wird als TMX, die alte Datei bleibt als `.bak` erhalten. |
| **Spiel** | **F5 spielt ab hier:** Das Spiel kocht den Inhalt wie beim Start, setzt die Party auf die offene Karte an die Stelle unter der Maus und läuft mit 50 Ticks pro Sekunde mitten im Studio. Escape in der Welt beendet das Spiel (wie im Spiel selbst), Umschalt+F5 auch. Danach geht es zurück zur Karte. |
| **Datenbank** | Jeder Abschnitt von `tables.yaml` ist eine Tabelle mit einer Zeile pro Eintrag und einer Spalte pro Feld, dazu eine Suche über Schlüssel und Werte. Rechts lassen sich die Felder des gewählten Eintrags ändern (Enter oder die Box verlassen) und neue Felder hinzufügen. Man kann Einträge kopieren und entfernen. „Wo benutzt?“ sucht das Symbol (`I.herb`, `T.x`, …) in den Skripten. |
| **Gespräche** | Eine Figur mit Begrüßung und Themen. Ein Thema ist ein Wort mit Bedingung; die erste passende Antwort zählt, `*` antwortet auf jedes andere Wort. Dazu kommen Zeigen und Geben. Die Texte stehen ausgeschrieben da und sind änderbar (sie stehen in `texts` von `tables.yaml`). Wort und Bedingung eines Themas lassen sich ändern. Ein neues Thema bekommt seinen Text in `texts` (mit dem Sprecher der Begrüßung) und sein Wort in `keywords`. |
| **Text** | Skripte, Screens und `tables.yaml` zum Lesen, mit Zeilennummern. Die Meldungen springen hierher. Bearbeitet werden diese Dateien weiter in VS Code. |

**Tasten:**

| Taste | Wirkung |
|---|---|
| Strg+S | alles speichern und neu prüfen |
| F7 | prüfen |
| Strg+Z / Strg+Y | rückgängig / wiederholen (Karte, Datenbank, Gespräche) |
| F5 | spielen ab hier |
| Umschalt+F5 | Spiel beenden |
| Strg+O | Projekt öffnen |

## Code

| Datei | Inhalt |
|---|---|
| `Studio/Main.csh` | Fenster und Hauptschleife, `--project`, `--test` |
| `Studio/App.csh` | Aufteilung, Menüs, Baum, Reiter, Meldungen, Tasten, Speichern |
| `Studio/MapView.csh` | Kartenbereich und Werkzeugleiste (nutzt `MapDocument`, `TileImages`, den Renderer des Spiels) |
| `Studio/GameView.csh` | das Spiel als dritte Plattform neben Fenster und Testlauf: Eingabe von System.Ui, Ticks nach der Uhr, Bild skaliert |
| `Studio/TableView.csh` | Datenbank |
| `Studio/TalkView.csh` | Gespräche |
| `Studio/YamlEdit.csh` | einzelne YAML-Werte in einer Zeile ersetzen |
| `Studio/TextDoc.csh` | Textdateien mit Rückgängig |
| `Studio/Messages.csh` | Prüfung und Meldungen |
| `Studio/Bridge.csh` | Bilder und Tasten zwischen Engine und System.Ui (beide haben `Image`, `Color`, `Key`) |
| `Studio/StudioTest.csh` | der Testlauf ohne Fenster |

Das Studio übersetzt die Quellen des Prototyps mit (ohne `Program.csh` und das GLFW-Fenster) und dazu die Bibliotheken unter `src/`.

## Test

`scripts/test.sh studio` (bzw. `test.cmd studio`) baut das Studio und lässt [game/tests/studio.txt](../tests/studio.txt) ohne Fenster laufen, auf einer Kopie des Inhalts in `game/out/studio`. Der Test malt und radiert, spielt ab einer Stelle und beendet das Spiel. Er ändert Felder, legt Einträge an und entfernt sie, sucht ein Symbol, ändert einen Gesprächstext und legt ein neues Thema an. Nach dem Speichern prüft er, dass der Inhalt fehlerfrei kompiliert, und er sieht einen absichtlichen Fehler in den Meldungen. Bildschirmfotos landen in `game/out/studio_*.png`.

Ohne einen Compiler mit dem neuen System.Ui überspringt `test.sh` das Studio. Mit `CSHIFT_STDLIB=<CShift>/stdlib` läuft es mit.
