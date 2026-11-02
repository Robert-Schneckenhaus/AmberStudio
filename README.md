# Amber Studio

Eine Engine und ein Editor für kachelbasierte 2D-Rollenspiele und Abenteuer von oben: Tiled-Karten, Ereignisse in der Skriptsprache **AmberScript**, Gespräche über Stichwörter, Truhen, Händler, Kampf in Echtzeit mit Gefährten, Tag und Nacht über Paletten, Spielstände. Alles in [CShift](https://github.com/Robert-Schneckenhaus/CShift) geschrieben; es läuft unter Windows und Linux, der Editor auch im Browser, und die Regelmaschine ist auf den Amiga ausgelegt.

**Im Browser ausprobieren:** die Seite dieses Repositorys auf GitHub Pages (Amber Studio mit dem Beispielspiel).

## Was drin ist

| Teil | Ordner |
|---|---|
| **AmberScript**: Compiler (Fehlercodes, Zucker für Gespräche, Routinen, Presets), Regel-Interpreter, Pack-Format, Savegames, Screens als Daten, Paletten | [src/](src/README.md), Spezifikation in [spec/](spec/Spec-00-AmberScript-und-Pack-v0.md) |
| **amberplayer**: spielt einen Inhaltsordner (Karten, Skripte, Tabellen, Screens), mit Kartenbearbeiter und Entwicklerwerkzeugen | [game/Amber.Player](game/README.md) |
| **Amber Studio**: Editor mit Projektbaum, Karten, Datenbank, Gesprächen, Prüfung und „Spielen ab hier“ | [game/Amber.Studio](game/Amber.Studio/README.md) |
| **Beispielspiel**: eine Wiese, ein Keller, eine Figur mit Gespräch, Ratten, eine Kiste, eine Gefährtin | [game/content](game/README.md#das-beispielspiel) |
| **amberc** (Kommandozeile: `compile`, `pack`, `dump`, `trace`, `gen-c` …), **amberpal** (Paletten) | `src/Amber.Script.Cli`, `src/Amber.Palette.Cli` |
| C-Laufzeit für den Amiga, Golden Traces, VS-Code-Erweiterung, Beispiele der Sprache | `c/`, `examples/`, `tools/vscode-amberscript` |

Wie man ein eigenes Spiel baut: [Anleitung-Eigenes-Spiel.md](Anleitung-Eigenes-Spiel.md).

## Schnellstart

Den CShift-Compiler `cshiftc` von den [Releases](https://github.com/Robert-Schneckenhaus/CShift/releases) holen und in den `PATH` legen (unter Linux dazu `sudo apt install libglfw3-dev`).

```
scripts/start.sh            # das Beispielspiel spielen
scripts/test.sh             # alle Tests
```

Amber Studio braucht Teile von System.Ui, die erst nach CShift 0.41 erscheinen; bis dahin mit der Standardbibliothek eines CShift-Checkouts von `master`:

```
cshiftc build game/Amber.Studio --stdlib <CShift>/stdlib
game/Amber.Studio/bin/amberstudio
CSHIFT_STDLIB=<CShift>/stdlib scripts/test.sh studio
```

Unter Windows dasselbe mit `scripts\start.cmd` und `scripts\test.cmd`.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Das gilt auch für das Tileset des Beispiels. GLFW-Header: zlib-Lizenz (`game/Amber.Player/include/LICENSE-GLFW.md`).
