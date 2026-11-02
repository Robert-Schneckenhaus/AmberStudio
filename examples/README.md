# Beispiele

Alle Dateien folgen der [Spec v0](../spec/Spec-00-AmberScript-und-Pack-v0.md). Es gibt noch **keinen Compiler**; die Beispiele dienen als Testeingaben für M1 (Parser, Cook) und als Ausdrucks-Test für die Sprache. Namen, Koordinaten und IDs sind Platzhalter.

| Pfad | Zweck | Meilenstein |
|---|---|---|
| `rosetta/amberstar-events.ams` | Alle 23 Event-Typen aus Amberstar (`EventType`) in AmberScript | M1 |
| `conversation/shandra.ams` | Keyword-Dialog mit `topic`, `show_item`, `give_item` | M1 |
| `screens/*.yaml` | Screens `confirmation`, `textbox`, `input_word`, `chest` plus Prefab `window_modal` | M2 |
| `screens/screens.ams` | Handler-Gruppen dieser Screens (`screen`-Blöcke) | M2 |
| `world/lebendige-welt.ams` | Tagesroutinen, Barks, reaktive Regeln, Weltzustands-Variante, Party-Kommentar | M5 |
| `presets/presets.ams` | Wiederverwendung: Schalter-Muster, relatives Tile, Fragmente, Einmal-Geschenk, geteilte Gruppe mit `here` | M1 (1.15–1.17) |

Die YAML-Dateien lassen sich in VS Code gegen `../spec/schemas/screen.schema.json` prüfen (Zuordnung in den Workspace-Einstellungen unter `yaml.schemas`, erfordert die Erweiterung „YAML" von Red Hat).
