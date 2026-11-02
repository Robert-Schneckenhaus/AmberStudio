# Quellcode (M1)

**CShift** (Compiler `cshiftc` 0.39 von [Robert-Schneckenhaus/CShift](https://github.com/Robert-Schneckenhaus/CShift)), portiert aus einer früheren C#-Fassung (daher Stil und Namen: Tabs, Allman, Klassenstruktur wie in C#). Basis: [Spec 00](../spec/Spec-00-AmberScript-und-Pack-v0.md).

## Ordner

Jeder Ordner unter `src/` entspricht einem C#-Projekt; CShift kennt keine Bibliotheken, ein Programm nennt die Ordner, die es übersetzt, in seiner `cshift.json`.

| Ordner | Inhalt |
|---|---|
| `Amber.Base` | Neu: was .NET mitbrachte und die Standardbibliothek von CShift nicht hat. Fehlerarten (`ErrorKind`, statt der Ausnahmetypen), Big-Endian-Puffer (`ByteWriter`, `ByteReader`), Latin-1, Deflate (Packen und Entpacken, RFC 1951), YAML- und JSON-Leser, stabiles Sortieren, Text-Helfer, `Cell<T>` (ein von Kopien geteilter Wert), Dateibereiche lesen |
| `Amber.Script.Common` | Format: Enums (Trigger, Bedingungen, Aktionen), Opcode-Tabellen mit Operandenbeschreibung (`ActionTable`, `ConditionTable`, `TriggerTable`; einzige Quelle für Parser, Encoder, Dump), `Wire`-Helfer, `ScriptChunk` (Leser), `ScriptDumper`, `Crc32` |
| `Amber.Script` | Compiler: `Syntax/` (Lexer, Parser, AST), `Compilation/` (Pass A Deklarationen und Zucker, Pass B Regeln, Analyse E015/E006/W001, Deduplizierung, Musterstatistik), `Binary/` (Encoder), `ScriptCompiler` |
| `Amber.Runtime` | Regel-Interpreter (`Interpreter`), `StateStore`, Host-Schnittstelle `IGameHost`, `TriggerContext`. Bewusst „C-freundlich" (feste Thread-Tabelle, wortweiser Zugriff, keine Ausnahmen im Ablauf) |
| `Amber.Screens` | Screens als Daten (Spec Abschnitt 8): `ScreenLibrary` (YAML lesen, `extends`/Prefabs auflösen, jede Datei gegen `screen.schema.json` prüfen), `ScreenSchema`, `ScreenChunk` (Binärformat 8.2/8.3 schreiben und lesen), `ScreenKeys`, `UiTheme` und `LookLayout` (Oberfläche aus Sprites und Farben) |
| `Amber.Pack` | Pack-Container (Spec 9) und Savegame (10.2): `PackWriter`, Leser aus dem Speicher und aus der Datei, Kompression (none, RLE0, Deflate), Tabellen, `PackContent` (Lader mit Ladeprüfung der Natives), `PackDumper`, `SaveData`, `SaveMigration`, `LayoutDiff` |
| `Amber.Cook` | Der Cook: `PackBuilder` macht aus Compiler-Ergebnis, Screens und Tabellen ein Pack; `CTables` schreibt die Tabellen der C-Laufzeit |
| `Amber.Conformance` | Golden Traces (Spec 12.3): `Scenario` (Szenario-Datei), `ScenarioRunner` (führt sie mit einem festen Host aus, aus Quelltext oder aus einem Pack, und erzeugt den Trace), `TraceComparer` |
| `Amber.Graphics` | Neu, Grafik: RGBA-Bilder (`Image`, `Color`), PNG lesen und schreiben (auch Palettenbilder: `DecodePngPicture` liefert die Indizes, `EncodeIndexedPng`), Paletten (`Palette`: Eintrag 0 transparent, die letzten 8 für die Oberfläche; GIMP-Paletten `.gpl` lesen und schreiben), Paletten aus Bildern bauen (`ColorHistogram`, `BuildPalette`: exakt oder Median Cut, `--base`-Einträge bleiben an ihrem Platz, 4 Bit je Kanal für die alten Amigas), Bilder auf Palettenindizes abbilden (`IndexImage`), Paletten mischen und Effekte (`BlendPalettes`, `TintPalette`, `NightOf`; die 8 UI-Einträge bleiben immer unverändert) |
| `Amber.Palette.Cli` | `amberpal`: `extract` (Palette aus PNGs), `index` (PNGs als Palettenbilder), `apply` (eine andere Palette für ein Palettenbild, z. B. Nacht), `swatch` (Palette als Bild) |
| `Amber.Script.Cli` | `amberc`: `compile`, `stats`, `pack` (`--profile amiga`), `dump` (auch Packs), `trace`, `layout-diff`, `gen-c` (Tabellen für die C-Laufzeit); Programm mit eigener `cshift.json` |
| `c/` | C-Laufzeit für den Amiga-Spike (M6), siehe [c/README.md](../c/README.md); `CRuntimeTests` vergleicht ihre Spur mit der des Interpreters |
| `game/Amber.Player` | Der Spieler (`amberplayer`): spielt einen Inhaltsordner, mit Kartenbearbeiter und Entwicklerwerkzeugen, siehe [game/README.md](../game/README.md) |
| `tools/vscode-amberscript` | VS Code-Erweiterung für `.ams` (Grammatik, Snippets); `GrammarTests` prüfen, dass sie zu den Opcode-Tabellen passt |
| `tests/Amber.Tests` | Die Tests (aus der xUnit-Fassung der C#-Zeit portiert) als CShift-Programm mit eigenem kleinen Testrahmen (`Harness/`: `Assert`, Fakten und Theorien, Filter): Lexer/Parser, Compiler (Spec-Hex-Beispiele, Fehlercodes, Beispieldateien), Interpreter, Wiederverwendung, Screen-Schema und Screen-Chunk, Theme, Golden Traces, Pack und Cook, Savegame und Migration, Grammatik, C-Laufzeit; dazu neu die Paletten (`PaletteTests`). 236 Tests, alle grün |

## Benutzen

`cshiftc` von den [Releases](https://github.com/Robert-Schneckenhaus/CShift/releases) holen (Windows: zip entpacken, Linux: `tar -xf`) und in den `PATH` legen; die Skripte nehmen sonst den, den die Umgebungsvariable `CSHIFTC` nennt. `cshiftc build <ordner>` übersetzt das Programm der `cshift.json` im Ordner nach `<ordner>/bin`.

```
cshiftc build src/Amber.Script.Cli            # amberc
cshiftc build tests/Amber.Tests               # Testprogramm
tests/Amber.Tests/bin/amber-tests             # alle Tests (aus dem Repository heraus)
tests/Amber.Tests/bin/amber-tests Pack Save   # nur Tests, deren Name eines der Wörter enthält; --list, --verbose

# alle Beispiele übersetzen (nachsichtige Symbol-IDs, Screen-Signaturen aus den YAMLs)
src/Amber.Script.Cli/bin/amberc compile examples --lenient --screens examples/screens --dump

# Musterstatistik
src/Amber.Script.Cli/bin/amberc stats examples --lenient --screens examples/screens --out stats.md

# Golden Trace: Szenario ausführen, Trace ausgeben oder gegen die Golden-Datei prüfen (--update schreibt sie neu)
src/Amber.Script.Cli/bin/amberc trace examples/scenarios/schrein.scenario --check examples/scenarios/schrein.golden

# Pack kochen und ansehen; dasselbe Szenario aus dem Pack ausführen (die Spur muss gleich sein)
src/Amber.Script.Cli/bin/amberc pack examples/scenarios/schrein.ams --lenient --out schrein.pack
src/Amber.Script.Cli/bin/amberc dump schrein.pack
src/Amber.Script.Cli/bin/amberc trace examples/scenarios/schrein.scenario --via-pack --check examples/scenarios/schrein.golden

# Unterschied zweier Layouts (Release gegen Release)
src/Amber.Script.Cli/bin/amberc layout-diff alt/layout.txt neu/layout.txt

# Chunks schreiben und ansehen
src/Amber.Script.Cli/bin/amberc compile examples/presets --lenient --out out
src/Amber.Script.Cli/bin/amberc dump out/map.presets_demo.groups.bin out/map.presets_demo.bindings.bin
```

Paletten und Palettenbilder (Ziele Z4; die Karte als Ganzes macht der Prototyp mit `--map-palette`, siehe [game/README.md](../game/README.md)):

```
cshiftc build src/Amber.Palette.Cli
src/Amber.Palette.Cli/bin/amberpal --help

# Palette aus Bildern: 256 Einträge, die 8 Farben der Oberfläche aus ui.gpl am Ende, dazu ein Bild der Palette
src/Amber.Palette.Cli/bin/amberpal extract tiles/*.png --out dorf.gpl --ui ui.gpl --swatch dorf.png

# neue Bilder dazu, ohne dass sich die vorhandenen Einträge verschieben
src/Amber.Palette.Cli/bin/amberpal extract neu/*.png --base dorf.gpl --out dorf.gpl

# Bilder als Palettenbilder (8-Bit-PNG mit der Palette); die Ausgabe nennt die Pixel, die nicht genau passten
src/Amber.Palette.Cli/bin/amberpal index tiles/*.png --palette dorf.gpl --out tiles_idx

# dieselben Indizes mit der Nachtpalette ansehen
src/Amber.Palette.Cli/bin/amberpal apply tiles_idx/gras.png --palette dorf_nacht.gpl --out gras_nacht.png

# 32 Farben mit 12-Bit-Farben für die alten Amigas
src/Amber.Palette.Cli/bin/amberpal extract tiles/*.png --size 32 --bits 4 --ui ui.gpl --out dorf32.gpl
```

Unter Windows heißen die Programme `amberc.exe`, `amberpal.exe` und `amber-tests.exe`. `scripts/test.sh` (Linux) und `scripts\test.cmd` (Windows) bauen alles und führen alle Tests aus. Die Tests der C-Laufzeit brauchen einen C-Compiler (`AMBER_CC`, sonst `clang`, `gcc` oder `cc` aus dem `PATH`; das `clang` der CShift-Toolchain unter `toolchain/bin` geht auch) und werden ohne ihn übersprungen.

Die Ausgaben sind dieselben wie die der C#-Fassung: Chunks, Dumps, Statistiken und Traces wurden beim Portieren Byte für Byte verglichen. Einzige Ausnahme sind die mit Deflate gepackten Chunks eines Packs: `Amber.Base/Deflate.csh` ist ein eigener Kompressor und packt ein paar Byte anders als .NET (gleiche Chunks, gleicher entpackter Inhalt; jede Fassung liest und zeigt die Packs der anderen gleich).

## Interpreter einbetten (Skizze)

```csharp
var result = ScriptCompiler.Compile(files, CompileOptions { LenientSymbols = true });
var global = result.Global;
var interpreter = Interpreter.Create(global.ToChunk(), StateSizes.Of(global.FlagCount.Get(), global.VarCount.Get(), global.Var32Count.Get()), RuntimeLimits.Default());

interpreter.LoadMap(mapId, map.ToChunk(), StateSizes.Of(map.FlagCount.Get(), map.VarCount.Get(), map.Var32Count.Get()));
interpreter.Trigger(ref host, TriggerContext { Type = TriggerType.Interact, MapId = mapId, X = 12, Y = 6 });
interpreter.Resume(ref host, threadId, 1);   // nach einer blockierenden Aktion (Screen, Kampf ...)
interpreter.Tick(ref host);                  // reaktive Ereignisse, map_tick, wait
```

`host` ist ein eigener Struct, der `IGameHost` implementiert: `Execute` bekommt alle Aktionen, die der Interpreter nicht selbst behandelt (Teleport, Text, Kampf, Screens …), `Evaluate` alle Bedingungen, die Spieldaten brauchen (Gruppe, Uhrzeit, Karte …). CShift hat keine Interface-Werte, deshalb sind die Methoden des Interpreters generisch (`Trigger<THost>(ref THost host, ...) where THost : IGameHost`) und der Host wird per `ref` übergeben.

## Bekannte Lücken

- Keine Tabellen-Loader: unbekannte Symbole nur im nachsichtigen Modus.
- `attr(...) >= n` ist noch nicht schreibbar (siehe Spec, Änderungsvermerke).
- Routinen werden geparst, aber nicht gebacken; kein Adapter zu `Amberstar.Game` (1.11).
- Tests gibt es, obwohl das Amber-Projekt sonst keine hat: jede Aufgabe gilt erst mit grünem Test als fertig.
