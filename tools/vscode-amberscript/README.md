# AmberScript for VS Code

Syntax highlighting, snippets and editor settings for `.ams` files, the event language of Amberworlds (see `spec/Spec-00-AmberScript-und-Pack-v0.md`, section 7).

## What is highlighted

| Kind | Examples |
|---|---|
| Declarations | `map village`, `npc mira`, `group notice`, `flag done`, `var counter` |
| Keywords | `on`, `when`, `else`, `do`, `then`, `once`, `first`, `at`, `in`, `topic`, `greet`, `bark`, `every`, `routine`, `walk_to`, `stay`, `and`, `or`, `not`, `here` |
| Triggers after `on` | `on examine`, `on enter_tile`, `on hour(12)` |
| Actions and conditions | `say(T.text)`, `teleport(M.glade, 15, 26, up, 1)`, `has_item(I.berries, 3)`, `hour_in(20, 5)` |
| Table symbols | `T.text`, `I.item`, `K.word`, `M.map`, `TILE.bridge`, `DELTA.bridge` |
| Numbers | `12`, `0x1F`, `+1`, times `06:00`, durations `30s`, `2min`, `1h`, `50t` |
| Constants | `active`, `party`, `up`, `down`, `set`, `cleared` |
| Group targets | `-> notice` |
| Strings, comments | `"Name"`, `// ...`, `/* ... */` |

Snippets: `map`, `group`, `groupfirst`, `when`, `onexamine`, `onenter`, `teleport`, `npc`, `topic`, `routine`, `bark`, `confirmthen`, `once`.

## Install

```
powershell -ExecutionPolicy Bypass -File tools/vscode-amberscript/build.ps1 -Install
```

or `scripts\install-vscode-extension.cmd`. This builds `out/amberscript-<version>.vsix` (no npm needed) and installs it with `code --install-extension`. Reload the VS Code window afterwards.

## Keeping the grammar in sync

The lists of actions, conditions, triggers and table prefixes in `syntaxes/amberscript.tmLanguage.json` come from the opcode tables in `src/Amber.Script.Common` (`TriggerTable.csh`, `ConditionTable.csh`, `ActionTable.csh`). The unit test `GrammarTests` fails if a name of the tables is missing in the grammar; add it there (and in the lists in the `triggers` and `calls` rules) when you add an opcode.
