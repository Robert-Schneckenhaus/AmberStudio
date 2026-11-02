# C-Laufzeit (M6-Spike)

Der Pack-Leser und der Regel-Interpreter in **portablem C99**, ohne Allokation, mit festen Tabellen (Konstanten `AMB_MAX_*` in `include/amber_rt.h`). Sie sind das Gegenstück zu `Amber.Pack` und `Amber.Runtime` und beweisen, dass die Architektur auf den Amiga passt: derselbe Pack, derselbe Ablauf, **dieselbe Spur**. Der Interpreter ist bewusst „C-freundlich“ geschrieben (feste Thread-Tabelle, wortweiser Zugriff auf big endian Chunks, keine Ausnahmen); die Umsetzung folgt dem Interpreter (`src/Amber.Runtime/Interpreter.csh`, ursprünglich `Interpreter.cs` der C#-Fassung) Zeile für Zeile.

| Datei | Inhalt |
|---|---|
| `include/amber_pack.h`, `src/amber_pack.c` | Pack lesen (Kopf, TOC mit Binärsuche, CRC-16, RLE0; **kein** Deflate, das Amiga-Profil des Cooks schreibt keins), CRC-32 für den Zustands-Hash |
| `include/amber_rt.h`, `src/amber_rt.c` | Interpreter: Threads, Bindungen und Trigger, Gruppen und Regeln (`first`/`all`, `then`, `or`/`not`), Zustand (global, Karte, Thread-Variablen), Ereigniswarteschlange (`flag_changed`, `var_changed`, `custom`), `wait`, `map_tick`, PRNG xorshift32 mit `chance`, Kettenlimit, Zustands-Hash, Spur. Screen-Instanzen (`amb_load_screen`, `amb_run_group`, Screen-Trigger und Screen-Zustand) |
| `include/amber_tables.h` | **Erzeugt** von `amberc gen-c c/include` aus den Opcode-Tabellen des Compilers (Konstanten und Namen von Triggern, Bedingungen und Aktionen, Symbolarten). Nicht von Hand ändern; ein Test prüft, dass die Datei aktuell ist |
| `tools/amber_trace.c` | Konsolen-Host und Szenario-Läufer (Aufgabe 6.4): liest ein Szenario (Spec 12.3) und einen Pack, führt es aus und schreibt die Spur. Host wie in `Amber.Conformance` (Gold, Gegenstände, Wörter, blockierende Aktionen warten auf `answer`) |

## Bauen und benutzen

```
c\build.cmd                                   # clang aus MSYS2 (oder AMBER_CC), c\build\amber_trace.exe
src\Amber.Script.Cli\bin\amberc.exe pack examples\scenarios\mix.ams --lenient --profile amiga --out mix.pack
c\build\amber_trace.exe szenario.scenario     # das Szenario nennt seinen Pack mit "pack mix.pack"
```

Der Läufer gibt die Spur auf der Standardausgabe aus und meldet fehlgeschlagene Erwartungen auf der Fehlerausgabe (Exit-Code 1); ein kaputtes Szenario oder ein beschädigter Pack gibt Exit-Code 2.

## Prüfung gegen den Interpreter

`CRuntimeTests` (in `tests/Amber.Tests`, früher `tests/Amber.Script.Tests` der C#-Fassung) baut die C-Laufzeit mit `-Wall -Wextra -pedantic -Werror`, kocht jedes Szenario aus `examples/scenarios/` in einen Pack des Amiga-Profils und vergleicht die Spur des C-Läufers Zeile für Zeile mit der Golden-Datei des Szenario-Läufers (`amberc trace`; CShift und die C#-Referenz liefern dieselben Golden-Dateien). Die Szenarien decken Fragen mit `then`, `all`-Gruppen, `or`/`not`, Ereignisse (auch mit negativen Werten und einer vollen Warteschlange), `wait`, `map_tick`, Bereiche (`enter_tile`/`leave_tile`), Zufall mit festem Seed, das Kettenlimit, `autosave`, Gespräche, 16-Bit- und 32-Bit-Variablen (mit Sättigung), Thread-Variablen, `push_screen` mit und ohne `nowait` sowie Screen-Instanzen (Öffnen, Schließen, Handler-Gruppen, Zustand des Screens) ab. Ohne C-Compiler (Umgebungsvariable `AMBER_CC`, `PATH`, MSYS2) tun diese Tests nichts.

## Was für den Amiga noch fehlt (M6)

- Toolchain für den A1200 (VBCC/GCC für m68k, Emulator), Bauen mit `-m68020`: 6.1
- Speicherbedarf und Zeit je Tick im Emulator messen: 6.6. Das Struct `amb_interp` ist auf dem Desktop (64 Bit) 9744 Byte groß (`amb_chunk` 832, `amb_thread` 104 Byte); die Zustands-Tabellen je Karte (`amb_state`) bestimmen das, die `AMB_MAX_*` lassen sich verkleinern.
- Der Läufer benutzt `stdio` und `malloc`; die Bibliothek selbst (`amber_pack.c`, `amber_rt.c`) nutzt nur `snprintf` für die Spur (abschaltbar, wenn `host.trace` NULL ist).
