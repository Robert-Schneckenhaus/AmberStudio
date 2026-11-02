# Anleitung: ein eigenes Spiel mit Amber Studio und der Engine

Stand 2026-09-21. Diese Anleitung fasst zusammen, wie aus dem Framework ein Spiel wird: von den Inhalten (Karten, Texte, Regeln, Fenster) über Tests und Pack bis zur eigenen Spielschleife. Genaue Formate stehen in der [Spec](spec/Spec-00-AmberScript-und-Pack-v0.md), die Bedienung der einzelnen Werkzeuge in [src/README.md](src/README.md) und [game/README.md](game/README.md).

## 1. Das Bild im Kopf

Ein Spiel besteht aus **Daten** und einer **Hülle**:

```
Daten (was das Spiel ist)                       Hülle (wie es läuft)
--------------------------------------------    ------------------------------------
tables.yaml    Texte, Gegenstände, Wörter ...   Host (CShift): Grafik, Eingabe, Ton,
maps/*.tmx     Karten (Tiled)                   Party, Kampf, Weltdarstellung
scripts/*.ams  Regeln, NPCs, Screen-Verhalten   implementiert IGameHost
screens/*.yaml Fenster (Layout)                 ------------------------------------
characters.yaml Aussehen der Figuren            Interpreter (Amber.Runtime, CShift
                                                oder c/ in C99): führt die Regeln aus
```

Der **Interpreter** kennt weder Grafik noch Party. Er führt Regeln aus und ruft für alles, was Spielwissen braucht, den **Host** (`IGameHost.Execute` für Aktionen, `Evaluate` für Bedingungen). Deshalb lassen sich Inhalte ohne Programmcode schreiben, solange der Host die verwendeten Aktionen kennt, und deshalb kann dieselbe Regelmaschine später auf dem Amiga laufen.

Zwei Wege:

| Weg | Wann | Aufwand |
|---|---|---|
| **A: Inhalte für `amberplayer`** (`game/`) | Du willst ein Spiel im Stil des Beispiels bauen: Tiled-Karten, Konversationen, Quests, Truhen, Zeitablauf | Nur Daten; CShift nur für neue Natives oder Widgets |
| **B: eigener Host** auf `Amber.Runtime` oder `c/` | Du willst eine andere Spielart (Kampf, Weltkarte, anderes Rendering) oder eine andere Plattform (Amiga) | Host selbst schreiben, Inhalte bleiben gleich |

Der Spieler `amberplayer` (Weg A) ist die Vorlage für Weg B: `PrototypeHost`, `ScreenHost` und `GameSession` zeigen, wie ein Host aufgebaut ist.

## 2. Voraussetzungen und Werkzeuge

- Der CShift-Compiler `cshiftc` ([Releases](https://github.com/Robert-Schneckenhaus/CShift/releases)); Windows oder Linux (das Fenster des Spielers kommt von GLFW, unter Linux das Paket `libglfw3-dev`).
- [Amber Studio](game/Amber.Studio/README.md) zum Bearbeiten von Karten, Datenbank und Gesprächen und zum Spielen ab einer Stelle (auch im Browser).
- Optional: [Tiled](https://www.mapeditor.org/) für Karten (oder der eingebaute Editor `scripts\edit.cmd`), VS Code mit der Erweiterung aus `tools/vscode-amberscript` (`scripts\install-vscode-extension.cmd`).
- Grafik: Das Beispiel bringt ein kleines eigenes Tileset mit (`scripts/make-example-maps.py`). Für ein eigenes Spiel eigene Tilesets und Figuren einsetzen; Tilesets und Figurenpakete, die nicht mit ins Repository sollen, liegen unter `assets/` (nicht eingecheckt). Ohne Figurenpaket zeichnet der Spieler einfache Figuren.

Die wichtigsten Kommandos:

| Kommando | Zweck |
|---|---|
| `scripts\start.cmd` | `amberplayer` bauen und das Beispiel spielen (Linux: `scripts/start.sh`, ebenso bei den anderen Skripten) |
| `scripts\test.cmd [unit\|content\|playthrough\|pack\|studio]` | Alle Tests oder einen Teil |
| `scripts\edit.cmd [karte]` | Kartenbearbeiter |
| `scripts\start.cmd --check-content` | Tabellen, Skripte, Screens kompilieren und prüfen |
| `scripts\start.cmd --headless --script tests\playthrough.txt` | Spiel per Eingabeskript durchspielen (ohne `--headless` im Fenster) |
| `scripts\start.cmd --build-pack datei.pack` | Inhalte in ein Pack kochen |
| `src/Amber.Script.Cli/bin/amberc <befehl>` (nach `cshiftc build src/Amber.Script.Cli`) | `compile`, `stats`, `pack`, `dump`, `trace`, `layout-diff`, `gen-c` |

## 3. Weg A: Inhalte für `amberplayer`

Alle Inhalte liegen in `game/content/`. Die Reihenfolge, in der man ein Spiel baut:

### 3.1 Tabellen anlegen (`tables.yaml`)

Jedes Symbol, das ein Skript benutzt (`T.x`, `I.x`, `K.x` ...), muss hier stehen. **Unbekannte Symbole sind Fehler E001** (strenger Modus). IDs werden fortlaufend in der Reihenfolge des Auftretens vergeben; **die Reihenfolge nie umsortieren**, wenn es schon Spielstände gibt (siehe 6).

| Abschnitt | Symbol | Inhalt |
|---|---|---|
| `maps:` | `M.name` | Kartenname → Anzeigename |
| `screens:` | `S.name` | Namen der Screens (YAML in `screens/`) |
| `natives:` | `N.name` | Funktionen und Datenquellen des Hosts |
| `chests:` | `CH.name` | Truhen mit Gold und Gegenständen |
| `hero:`, `monsters:`, `groups:` | `G.name` | Held (TP, Angriff, Abwehr), Monster und Monstergruppen für `battle(G.name, 0)` |
| `keywords:` | `K.name` | Wörter für Konversationen (Anzeigetext) |
| `items:` | `I.name` | Gegenstände (Name, Beschreibung, `icon:` Zelle im Icon-Blatt `icon_sheet:`, `price:` für Händler, `heal:`, `attack:`/`defense:` Boni beim Tragen) |
| `tiles:` | `TILE.name` | Tiled-Tile-IDs, die Skripte setzen |
| `deltas:` | `DELTA.name` | Tile-Änderungssätze (z. B. „Brücke erscheint") |
| `texts:` | `T.name` | Texte, optional mit `speaker:` |

### 3.2 Karten (`maps/name.tmx`)

- Vier Bildebenen mit festen Namen: `ground`, `decor`, `objects`, `over` (Krone, wird über Figuren gezeichnet), dazu die Ebene `collision` (blockierte Felder) und eine Objektebene `waypoints` mit benannten Punkten (`mira_stone` ...) für NPC-Routinen.
- Erstellen und bearbeiten: entweder in Tiled oder mit `scripts\edit.cmd name` (Terrain-Pinsel, Kollision, Rückgängig; Ctrl+S schreibt die TMX) oder in Amber Studio. Die Beispielkarten macht `scripts/make-example-maps.py`; **nach Handbearbeitung nicht mehr ausführen** (überschreibt).
- Neue Karte anmelden: unter `maps:` in `tables.yaml` eintragen, TMX ablegen, im Skript einen `map name { ... }`-Block anlegen. Die Kartengröße muss zur TMX passen.

### 3.3 Regeln (`scripts/*.ams`)

Kleine, vollständige Karte in AmberScript:

```
flag quest_done;                       // globales Flag (gilt für alle Karten)

map village {                          // Regeln dieser Karte
  flag notice_read;                    // Flags nur dieser Karte
  flag quest_started;
  flag berries_picked;
  flag treasure_taken;

  on map_enter -> arrival;             // Trigger -> Gruppe
  group arrival { once do { say(T.arrival); learn_word(K.village); } }

  // Untersuchen (Leertaste) in einem Rechteck (x, y, Breite, Höhe)
  on examine in (17, 26, 1, 1) -> notice;
  group notice { do { say(T.notice); set_flag(notice_read); } }

  // Gruppe mit "first": die erste passende Regel gewinnt
  on examine in (30, 18, 1, 1) -> bush;
  group bush first {
    when flag(berries_picked)         do { say(T.bush_empty); }
    when flag(quest_started)          do { give_item(I.berries, 3); set_flag(berries_picked); say(T.bush_pick); }
    else                              do { say(T.bush_seen); }
  }

  // Screen mit Rückgabewert: "then" läuft, wenn der Block fertig ist
  on examine in (33, 19, 1, 1) -> log;
  group log first {
    when not flag(treasure_taken) do { push_screen(S.chest, 0, 1, CH.log_treasure); } then log_done;
    else                          do { say(T.log_empty); }
  }
  group log_done { when result == 1 do { set_flag(treasure_taken); } }

  // Ja/Nein-Frage: confirm wartet, "then" wertet result aus (1 = Ja)
  on custom(quest_offer) -> quest_offer;
  group quest_offer { do { say(T.mira_bridge_ask); confirm(T.mira_confirm); } then quest_answer; }
  group quest_answer first {
    when result == 1 do { set_flag(quest_started); say(T.mira_accept); }
    else             do { say(T.mira_decline); }
  }

  // NPC: Anrede, Stichwörter (auch mit Bedingung), Gegenstand geben, Tagesroutine, Bark
  npc mira at (14, 20) {
    greet T.mira_greet;

    topic "Name"   do { say(T.mira_name); }
    topic "Bridge" when flag(quest_started) do { say(T.mira_bridge_waiting); }
    topic "Bridge" do { raise(quest_offer, 0); }        // löst on custom(quest_offer) aus
    topic "*"      do { say(T.mira_default); }          // alles andere

    on give_item(I.berries) when flag(quest_started) do { take_item(I.berries, 3); give_gold(25); set_flag(quest_done); }
    on give_item(I.berries) do { say(T.mira_default); }

    routine day { 06:00 walk_to mira_stone; stay 1h;  07:00 walk_to mira_bench; }
    bark T.mira_noon when near(4) every 15s;
  }
}
```

Wichtige Bausteine (vollständig in Spec Abschnitt 7):

- **Trigger** (`on ...`): `map_enter`, `map_exit`, `enter_tile`, `leave_tile`, `examine`, `interact`, `speak`, `use_item`, `give_item`, `show_item`, `keyword`, `hour`, `day_change`, `flag_changed`, `var_changed`, `custom`, `screen_open`/`screen_close`, `click`, `battle_end` u. a. Ortsbezogene Trigger nehmen `at (x,y)` oder `in (x,y,w,h)`.
- **Bedingungen:** `flag(x)`, `var == n`, `has_item(I.x, n)`, `gold >= n`, `hour_in(a, b)` (auch über Mitternacht), `word_known(K.x)`, `near(n)`, `chance(n)`, `result == 1`, `arg == n`, verknüpft mit `and`/`or`/`not` (Konjunktive Normalform, kein Kontrollfluss in Aktionen).
- **Aktionen:** `say`, `confirm`, `give_item`/`take_item`, `give_gold`/`take_gold`, `set_flag`/`clear_flag`, `set_var`/`add_var`, `learn_word`, `teleport(M.map, x, y, dir, n)`, `set_tile(layer, x, y, TILE.x)`, `apply_delta(DELTA.x)`, `push_screen`/`pop_screen`, `raise(custom, v)` (löst `on custom(...)` aus), `wait(n)`, `set_routine`, `native(N.x, ...)`.
- **Regelketten:** `when ... do {...}`, `else do {...}`, `once`, `then gruppe;` (setzt fort, wenn der Block fertig ist, z. B. nach `confirm` oder `push_screen`). `first` (erste passende Regel) oder `all` (alle passenden) steuert, was in einer Gruppe läuft.
- **Presets/`use`** für wiederkehrende Muster, Thread-Variablen `t0..t7` für lokalen Zustand.

Prüfen: `--check-content` (oder `amberc compile game/content/scripts --lenient`). Der Compiler meldet Fehler E001–E021 und Warnungen (z. B. Flag nie gesetzt: W002/W003; `autosave` an unsicherer Stelle: W004). Die VS-Code-Erweiterung färbt `.ams` ein.

### 3.4 Fenster (Screens)

Layout ist YAML, Verhalten AmberScript, Daten und Sonderfunktionen kommen vom Host:

1. `content/screens/mein_screen.yaml` anlegen (Knoten `window`, `label`, `button`, `textview`, `list`, `input`, `itemgrid`; Größen, Hotkeys, Datenquellen wie `party.items`, `on_click: gruppenname`). Vorlage: `chest.yaml`, `inventory.yaml`. Das Schema `spec/schemas/screen.schema.json` prüft beim Laden und nennt Datei und Pfad.
2. In `tables.yaml` unter `screens:` eintragen.
3. In `scripts/screens.ams` einen `screen mein_screen { ... }`-Block mit den Gruppen schreiben, auf die das YAML verweist. Der Screen beendet sich mit `pop_screen(wert)`, der Aufrufer sieht den Wert als `result`.
4. Öffnen mit `push_screen(S.mein_screen, flags, argc, args...)`; der aufrufende Thread wartet (Flag Bit 0 = nicht warten). Die Argumente sind Variablen 0..n-1 des Screens.

Braucht ein Screen Daten oder Funktionen, die es noch nicht gibt: Natives in `Game/ScreenHost.csh` ergänzen (Quelle unter einem Namen wie `party.words` anbieten oder eine Funktion für `native(N.x, ...)`), den Namen in `tables.yaml` unter `natives:` eintragen. Fehlt ein Native im Host, schlägt die Ladeprüfung fehl (Fehler der Art `MissingNative`, im Pack-Test sichtbar).

### 3.5 Figuren, Truhen, Wörter

- Aussehen: `characters.yaml` (`ebene/teil/variante`, Paper-Doll-Ebenen). NPC-Name im Skript = Name im YAML.
- Truhen: `chests:` in `tables.yaml`, öffnen mit `push_screen(S.chest, 0, 1, CH.name)`.
- Kampf: `battle(G.wolves, 0)` wartet und liefert `result` (0 gewonnen, 1 geflohen, 2 verloren) für die folgende Gruppe per `then`; Vorbild sind die Ratten in `cellar.ams`. Hinweis: `hp n` im Eingabeskript setzt die Trefferpunkte, damit sich Sieg und Niederlage sicher testen lassen.
- Icons und Balken: Gegenstände zeigen ihr Icon in den Rastern (`itemgrid`), wenn `tables.yaml` ein `icon_sheet:` nennt und der Gegenstand ein `icon:` hat (Zellennummer im Blatt); ohne Blatt erscheinen drei Buchstaben. Ein `bar`-Knoten (`kind: hp`, `slot: 1`) zeigt die Trefferpunkte als Balken, `label` mit `bind: "items.name"` den Namen der gewählten Zeile eines Rasters.
- Oberfläche aus Sprites/Farben: `content/ui.yaml` (optional) definiert Looks aus Sprites und/oder Farbflächen für Fenster, Knöpfe usw. (`border` für einen Rahmen aus acht wiederkehrenden Kantenstücken, `tile`, `rect`, `frame`, `image`) und legt fest, welcher Look eine Knotenart standardmäßig benutzt (`defaults:`) oder ein einzelner Knoten per `look: name`. Details und Grenzen in `game/README.md` „Oberfläche aus Sprites und Farben"; ohne `ui.yaml` (wie im Beispiel) zeichnet der Spieler schlichte Flächen.
- Dungeon: eine Karte wie jede andere, die Wege und Räume bauen sich aus Bodenfarben (`scripts/make-example-maps.py` zeigt, wie man Karten per Skript erzeugt). Truhen, Schalter und Tore sind Objekte der Objektebene mit einer `examine`-Regel; ein Tor öffnet `apply_delta` (`tile: empty` löscht das Objekt, `unblock:` gibt die Felder frei), nach dem Laden stellt eine `map_enter`-Regel den Zustand über das Flag wieder her.
- Händler: eine Truhe als Vorrat plus `push_screen(S.shop, 0, 1, CH.name)`; Preise stehen an den Gegenständen. Öffnungszeiten sind eine Bedingung am Thema (`topic "Trade" when hour_in(8, 18) do { ... }`).
- Wörter: `keywords:` und `learn_word(K.x)`; der Spieler wählt sie oder tippt sie (Taste T) in der Konversation.

### 3.6 Was der Host nicht kann, erweitert man in CShift

`PrototypeHost.Execute` behandelt die Aktionen, die Spielwissen brauchen (Gegenstände, Teleport, Tile-Änderung, NPC-Routine, Screens). Nicht unterstützte Aktionen meldet er auf der Konsole (`music`, `sfx`, `battle`, `spawn` mit Effekten ... sind nur Platzhalter oder fehlen). Neue Aktion einbauen: ein Zweig `if (op == ActionOp.X)` in `Execute` (`Game/Host.csh`), ggf. eine neue Bedingung in `Evaluate`. Der Compiler kennt alle Opcodes aus den Tabellen der Spec bereits.

## 4. Testen in drei Stufen

1. **Statisch:** `scripts\test.cmd content` (Tabellen, Skripte, Screens, Pack-Ladeprüfung).
2. **Regelmaschine ohne Spiel:** Szenarien und Golden Traces. Eine `.scenario`-Datei beschreibt Ereignisse und Erwartungen, `amberc trace` erzeugt daraus eine Spur (Reihenfolge der Trigger, Regeln, Aktionen, Zustands-Hash), die als „Golden File" eingecheckt wird:
   ```
   seed 1234
   script mein_spiel.ams
   load map village

   at 0   fire map_enter
   at 5   expect waiting say 1          # der Text wartet auf Bestätigung
   at 10  answer say
   at 20  fire examine x=17 y=26
   at 25  answer say
   at 26  expect flag notice_read 1
   at 30  hash
   end 50
   ```
   `amberc trace x.scenario --update x.golden` (neu erzeugen), `--check x.golden` (vergleichen), `--via-pack` (aus dem Pack laden, Spur muss gleich sein). Beispiele in `examples/scenarios/`. Die CShift- und die C-Laufzeit (und die C#-Referenz) müssen dieselbe Spur liefern, das ist der Vertrag für die Amiga-Portierung.
3. **Ganzes Spiel:** Ein Eingabeskript (`game/tests/playthrough.txt`) drückt Tasten, wartet, macht Screenshots und prüft (`expect gold 25`, `expect flag quest_done 1`, `expect map glade`, `expect modals 0` ...). Falsche Erwartung = Exit-Code 1. Speichern (F2) und Laden (F3) prüft das Ende von `playthrough.txt`; `scripts\test.cmd pack` spielt dasselbe aus einem gekochten Pack.

Faustregel: jede Quest bekommt zuerst ein Szenario (schnell, deterministisch) und eine Strecke im Playthrough (findet Host-, Screen- und Ablaufprobleme).

## 5. Pack: das ausgelieferte Format

`--build-pack datei.pack` (`amberplayer`) oder `amberc pack <skripte> --out x.pack [--screens dir] [--profile amiga] [--no-symbols]` kocht Skripte, Screens, Tabellen, Texte und Karten-Chunks (mit gebackenen Routinen) in einen Container (Big-Endian, CRC, Deflate; Profil `amiga` ohne Deflate). `amberc dump x.pack` zeigt den Inhalt. Beim Laden prüft der Leser Version, Layout-Hash und ob alle Natives vorhanden sind.

`amberplayer` kocht die losen Dateien beim Start im Speicher oder läuft mit `--pack datei.pack` aus einem Pack; der Pack ist auch der Weg für andere Hosts und den Amiga. Der Pack-Test in `--check-content` stellt sicher, dass beides zusammenpasst.

## 6. Spielstände und Versionen

- Speichern F2, Laden F3 (`SaveSystem`); das Savegame ist ein `SaveData` (Spec 10.2) mit Skriptzustand, Zufallszustand, Uhr, Kartenänderungen, NPC-Zuständen und Party. Die Party steht mit **Namen** statt IDs darin.
- Das Savegame merkt sich das **Layout** (welche Flags/Vars gibt es, in welcher Reihenfolge, je Karte). Ändert sich das Layout zwischen Fassungen, lehnt `amberplayer` den Spielstand ab; die Bibliothek (`SaveMigration`) kann nach Namen migrieren.
- Vor jedem Release: Layout-Datei der Fassung aufheben und bei der nächsten mit `amberc layout-diff alt.layout neu.layout` vergleichen. **Flags nur hinten anhängen oder umbenennen mit Migration, nie mittendrin einfügen** (Namen bleiben stabil, Reihenfolge ist egal, solange migriert wird).

## 7. Weg B: eigener Host

Minimales Einbetten (aus [src/README.md](src/README.md)):

```csharp
var result = ScriptCompiler.Compile(files, CompileOptions { LenientSymbols = true });
var global = result.Global;

var interpreter = Interpreter.Create(global.ToChunk(), StateSizes.Of(global.FlagCount.Get(), global.VarCount.Get(), global.Var32Count.Get()),
	RuntimeLimits.Default());

interpreter.LoadMap(mapId, map.ToChunk(), StateSizes.Of(map.FlagCount.Get(), map.VarCount.Get(), map.Var32Count.Get()));

interpreter.Trigger(ref host, TriggerContext { Type = TriggerType.Interact, MapId = mapId, X = 12, Y = 6 });
interpreter.Resume(ref host, threadId, 1);   // wenn ein wartender Thread (say, confirm, push_screen) fertig ist
interpreter.Tick(ref host);                  // 50 Hz
```

Was der Host liefert:

- `IGameHost.Execute(op, operands, context)`: führt Aktionen aus, die der Interpreter nicht selbst behandelt, und meldet `Done` oder `Blocked` (Thread wartet auf `Resume`).
- `IGameHost.Evaluate(op, operands, context)`: beantwortet Bedingungen, die Spieldaten brauchen (`has_item`, `gold`, `near`, `tile_is` ...).
- Auslöser: der Host meldet Ereignisse mit `Trigger(...)` (Schritt, Untersuchen, Uhrzeit ...).
- Optional: `Interpreter.CreateTraced(..., trace)` für Spuren (jeder Schritt landet in einer `List<string>`), `LoadScreen/UnloadScreen` für Screens (Screens als Chunk aus `Amber.Screens`).
- Der Host ist ein eigener Struct, der `IGameHost` implementiert; er wird per `ref` übergeben (CShift hat keine Interface-Werte, die Methoden des Interpreters sind generisch).
- Zustand: `Interpreter` und der Host halten den Spielzustand; `SaveData` (Amber.Pack) sammelt ihn.

Wer `amberplayer` als Vorbild nimmt: `GameSession` (Zustand, Kartenwechsel mit `map_exit`), `PrototypeHost` (Aktionen/Bedingungen), `ScreenHost` (Screens öffnen, Daten und Natives), `NpcBrain` (Routinen), `SaveSystem`.

**Amiga oder andere Plattformen:** `c/` enthält die C99-Laufzeit (Pack-Leser, Interpreter mit Screens, Szenario-Läufer). `amberc gen-c c/include` erzeugt `amber_tables.h`. Baue mit `c\build.cmd` und vergleiche die Spur (`CRuntimeTests`). Auf echter Amiga-Hardware ist das noch nicht erprobt.

## 8. Empfohlener Ablauf für ein neues Spiel

1. **Ordner anlegen**: eigene `content/`-Struktur (Kopie von `game/content/`), `amberplayer --content pfad` oder Amber Studio darauf zeigen lassen.
2. **Tabellen** für die erste Quest schreiben (Texte, Gegenstände, Wörter).
3. **Karte** bauen (Editor/Tiled), Kollision und Wegpunkte setzen.
4. **Regeln** schreiben, `--check-content` grün bekommen.
5. **Szenario + Golden Trace** für die Quest.
6. **Screens** anlegen oder anpassen, Natives ergänzen.
7. **Playthrough-Skript**: jede Änderung mit `scripts\test.cmd` prüfen.
8. **Pack** kochen, mit `amberc dump` ansehen, Layout-Datei für Spielstände aufheben.
9. Erst danach: Host-Erweiterungen (Kampf ausbauen, Musik, Weltkarte).

## 9. Grenzen und offene Punkte

| Fehlt | Stand |
|---|---|
| Musik, Sound | Aktionen `music`, `sfx` sind Platzhalter |
| Erfahrung und Stufen | Kampf in Echtzeit auf der Karte mit Held und bis zu 4 Gefährten (Heiler, Magier, Ranger), aber ohne Erfahrung und Stufen |
| Präsentations-Packs (Grafik/Ton im Pack) | offen; Grafik kommt aus TMX und Tileset-Dateien |
| Screen-Knoten `image`, `portrait`, `viewport` | fehlen (`bar` und die Icons der Gegenstände gibt es) |
| m68k-Toolchain und Amiga-Emulator (6.1, 6.6) | offen |
| Migration alter Savegames | Bibliothek vorhanden, `amberplayer` nutzt sie nicht |
| Nur Tastatur/Maus, keine Einstellungen | offen |

## 10. Wo steht was

| Frage | Datei |
|---|---|
| Wie ist die Sprache genau definiert? | [Spec Abschnitt 7 (Grammatik), 5–6 (Trigger/Bedingungen/Aktionen)](spec/Spec-00-AmberScript-und-Pack-v0.md) |
| Screen-Format? | Spec 8, [spec/schemas/screen.schema.json](spec/schemas/screen.schema.json) |
| Pack und Savegame? | Spec 9 und 10 |
| Beispiele zu Konversation, Screens, Presets, Welt? | [examples/](examples/README.md) |
| Bedienung der Werkzeuge? | [src/README.md](src/README.md), [game/README.md](game/README.md), [c/README.md](c/README.md) |
