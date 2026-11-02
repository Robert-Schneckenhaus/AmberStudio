# Spec 00 – AmberScript und Amber Pack v0 (Entwurf)

Status: **Entwurf zur Durchsicht** (2026-09-19).
Alle Nummern (Opcodes, IDs) sind **vorläufig** und werden in M1 gegen die Implementierung bestätigt. Danach gilt: Formatversion 0 ist eingefroren; Änderungen erhöhen die Version.

Entscheidungen, die hier gelten: Kein Kontrollfluss in Aktionen (Verzweigung über Bedingungen und Regelketten). Amiga-Ziel A1200. C# als Referenzimplementierung. YAML für Screens/Tabellen, `.ams` für Regeln. Ticks zu 50 Hz. Latin-1 im Pack. Big-Endian.

Schlüsselwörter: **MUSS** = verbindlich für jede Implementierung, **SOLL** = Empfehlung, **KANN** = optional.

---

## 1. Grundlagen

### 1.1 Zahlen und Ausrichtung

| Typ | Größe | Bemerkung |
|---|---|---|
| `u8`, `i8` | 1 Byte | |
| `u16`, `i16` (Wort) | 2 Byte, **Big-Endian** | Grundeinheit; jedes Wort MUSS auf gerader Adresse liegen |
| `u32`, `i32` (Langwort) | 2 Wörter, **hi dann lo** | in Befehlsströmen als zwei Wörter, nie mit 4-Byte-Ausrichtung gerechnet |
| ID | `u16` | `0xFFFF` = NONE, sofern nicht anders angegeben |
| Koordinaten | `u16` (0-basiert) | Importer wandeln Amberstars 1-basierte Werte um |

Der Runtime-Kern rechnet ganzzahlig. **Keine Fließkommazahlen**, keine Laufzeit-Strings (nur Text-IDs). Festkomma nur, wo eine Aktion es ausdrücklich verlangt.

### 1.2 Slots und Namensräume

Zustand liegt in vier Namensräumen. Ein **Slot16** adressiert einen Eintrag: `[ns:2][index:14]`.

| ns | Name | Lebensdauer | Größe/Layout |
|---|---|---|---|
| 0 | `global` | Savegame | Flags (Bits), Vars (`i16`), Vars32 (`i32`), Größen im Pack-Header |
| 1 | `map` | Savegame, je Karte | Größen im Map-Chunk; Zustand nur für besuchte Karten |
| 2 | `screen` | Lebensdauer der Screen-Instanz | Argumente = Vars 0..argc-1, danach lokale Vars |
| 3 | `thread` | Lebensdauer des Ablaufs | 8 Vars `t0..t7` (`i16`) |

- Flag-Befehle indizieren das **Flag-Array** des Namensraums, Var-Befehle das **Var-Array**, Var32-Befehle das **Var32-Array**. Die drei Indexräume sind getrennt.
- Der `map`-Namensraum gehört immer der **Besitzer-Karte** der Regel (Karte, in der die Bindung deklariert ist). Ein `map`-Slot in einer globalen Bindung oder Gruppe ist ein Cook-Fehler (E007).
- Zwei Sonderwerte gehören nicht zu den Namensräumen: `result` (`i16`, Ergebnis der letzten blockierenden Aktion im Ablauf) und `trigger_arg` (`i32`, vom Trigger mitgegeben).

### 1.3 Referenztypen in Operanden

| Typ | Kodierung | Bedeutung |
|---|---|---|
| Slot16 | `[ns:2][index:14]` | siehe 1.2 |
| GroupRef16 | bit15 = 0: **globale** Gruppe (Index in SCRIPTS-Chunk); bit15 = 1: **lokale** Gruppe (Index im Chunk, der die Referenz enthält: Map, Screen) | `0xFFFF` = NONE |
| EntityRef16 | `0xFFFF` = Party; sonst Entity-ID der aktuellen Karte | |
| Target8 (in einem Wort, obere Hälfte 0) | 0 aktives Mitglied, 1 irgendein Mitglied, 2 alle, 3 Anführer, 4..9 = Party-Slot 1..6 | |
| Cmp | 0 `==`, 1 `!=`, 2 `<`, 3 `<=`, 4 `>`, 5 `>=` | |
| Dir | 0 hoch, 1 rechts, 2 runter, 3 links, `0xFF` = behalten/zufällig (je nach Aktion) | |
| Pos (Paar x, y) | zwei Wörter; **`0xFFFF, 0xFFFF` = „hier"** (Auslöseort, siehe 1.4) | im Quelltext `(x, y)`, `x, y` oder `here` |
| TileRef16 | bit15 = 0: absolute Tile-ID (0..0x7FFF); bit15 = 1: **relativ**, untere 15 Bit = vorzeichenbehaftete Differenz zum aktuellen Tile an der Position (nur `set_tile`) | im Quelltext `TILE.x`/Zahl bzw. `+1`, `-2` |

### 1.4 Auslöseort („hier")

Beim Auslösen einer Bindung merkt sich der Ablauf `trigger_x` und `trigger_y`. Das ist der **Ort des Ereignisses**: bei `enter_tile`, `leave_tile`, `step` das betretene Tile; bei `examine`, `speak`, `listen`, `interact`, `use_item`, `cast_spell` das Ziel-Tile; bei Entity-Scope die aktuelle Position des Entity. Bei Scope global/Karte/Screen/Node und bei `map_*`/`hour`/reaktiven Triggern gibt es **keinen** Auslöseort; `here` ist dort ein Cook-Fehler (E015).

`here` ist nur für Positionsoperanden erlaubt, die als „Pos" gekennzeichnet sind: `set_tile`, `tile_is`, `spawn`, `move_entity`. Es bezieht sich immer auf die **Besitzer-Karte**. Der Auslöseort bleibt über `then`-Ketten erhalten. Dadurch kann **eine** Gruppe für beliebig viele Bindungen (auch auf anderen Positionen und Karten, sofern sie keine `map`-Slots nutzt) wiederverwendet werden.

Alle übrigen IDs (Items, Texte, Zauber, Gruppen …) stammen aus den Tabellen (siehe 7.3, Symbolpräfixe).

---

## 2. Ausführungsmodell

### 2.1 Begriffe

- **Regel** = Bedingungsstrom + Aktionsstrom + `next` (`GroupRef16` oder NONE).
- **Gruppe** = geordnete Regelliste mit Modus `first` oder `all`.
- **Bindung** = `Trigger + Geltungsbereich + Parameter -> Gruppe`.
- **Ablauf (Thread)** = laufende Abarbeitung einer Bindungsauslösung: aktuelle Gruppe/Regel/Aktion, `result`, `trigger_arg`, Auslöseort (`trigger_x`, `trigger_y`, siehe 1.4), Besitzer-Karte, Schrittzähler. Kein Stack, keine lokalen Frames.

### 2.2 Semantik

```
fire(binding, arg, owner):
    if binding hat schon einen aktiven Ablauf für (binding, owner): verwerfen        // R-2, keine Reentranz
    if kein freier Thread-Slot: verwerfen + Trace-Warnung                              // R-3
    t = neuer Ablauf(owner, trigger_arg = arg, result = 0, steps = 0)
    enter(t, binding.group)

enter(t, g):                                    // g nach GroupRef16 aufgelöst
    t.steps += 1
    if t.steps > maxChainSteps: abbrechen + Trace-Fehler
    for rule in g.rules (in Reihenfolge):
        if eval_conditions(rule, t):
            run_actions(t, rule)                 // kann blockieren, Fortsetzung siehe 2.3
            if rule.next != NONE: enter(t, rule.next)      // nur Modus first
            if g.mode == first: return
    return                                       // keine Regel passte: Kette endet leise
```

- `eval_conditions` und `run_actions` sind in 4 und 5 definiert. Eine Regel ohne Bedingungen trifft immer zu.
- Modus `all` erlaubt **kein** `then` (Cook-Fehler E005), damit die Reihenfolge nicht mehrdeutig wird.
- Bedingungen werden **beim Betreten der Regel** ausgewertet (Zustand zu diesem Zeitpunkt). Nach blockierenden Aktionen einer früheren Regel im selben Ablauf gilt bereits der neue Zustand (`all`-Modus).

### 2.3 Blockieren und Fortsetzen

Eine blockierende Aktion (in der Tabelle mit **B** markiert) beendet die Abarbeitung des Ablaufs **vorläufig**. Er wird fortgesetzt, wenn das Ereignis eintritt, auf das er wartet (Screen geschlossen, Kampf beendet, Zeit abgelaufen). Der Host meldet das Ergebnis, der Interpreter setzt `result` und läuft mit der **nächsten Aktion** weiter (oder mit `next`, falls die Regel zu Ende ist).

- Nicht blockierende Aktionen liefern kein Ergebnis und ändern `result` nicht.
- `result` gilt **pro Ablauf**. Es bleibt über `then`-Ketten erhalten und wird bei jeder blockierenden Aktion überschrieben.
- Während ein Ablauf wartet, laufen andere Abläufe, Animationen, Uhr und Screens normal weiter. Für Modalität sorgt der Screen-Stack (siehe 8).

### 2.4 Regeln (R-Nummern)

| # | Regel |
|---|---|
| R-1 | Ein Ablauf hat genau einen Besitzer (Bindung + Besitzer-Karte). Der `map`-Namensraum bleibt auch nach einer Teleportation der ursprünglichen Besitzer-Karte zugeordnet. |
| R-2 | Pro `(Bindung, Besitzer)` läuft höchstens ein Ablauf gleichzeitig. Auslösungen währenddessen werden verworfen. |
| R-3 | Ohne freien Thread-Slot wird die Auslösung verworfen und im Trace vermerkt. `maxThreads` steht im Pack-Header. |
| R-4 | Reaktive Trigger (`flag_changed`, `var_changed`, `custom`) werden **nicht sofort**, sondern in eine FIFO-Warteschlange gestellt (`maxPendingEvents`) und zu Beginn des nächsten Ticks abgearbeitet. Läuft die Warteschlange über, wird das Ereignis verworfen und im Trace vermerkt. |
| R-5 | `flag_changed` feuert nur bei tatsächlicher Wertänderung. |
| R-6 | Nach einem Kartenwechsel werden Abläufe anderer Besitzer-Karten beendet. Der Ablauf, der `teleport` ausgeführt hat, läuft weiter. |
| R-7 | Abläufe werden pro Tick in aufsteigender Thread-ID abgearbeitet. |
| R-8 | Eine Auslösung ohne passende Regel ist kein Fehler. |

### 2.5 Grenzen (im Pack-Header, Standardwerte)

`maxThreads` 16, `maxChainSteps` 64, `maxScreenDepth` 8, `maxPendingEvents` 32. Der Amiga-Kern alloziert statisch entsprechend.

---

## 3. Trigger

Bindungstabelle je Eintrag **8 Wörter** (16 Byte):

```
w0: [trigger:8][scope:8]
w1: group        (GroupRef16)
w2: p1           (Triggerparameter 1)
w3: p2           (Triggerparameter 2)
w4: sx           (Geltungsbereich: x, Entity-ID, Node-ID oder Screen-ID)
w5: sy
w6: sw           (nur scope area)
w7: sh
```

**Geltungsbereich (`scope`):** 0 global, 1 Karte (jede Position), 2 Tile (`sx,sy`), 3 Area (`sx,sy,sw,sh`), 4 Entity (`sx` = Entity-ID), 5 Screen (`sx` = Screen-ID), 6 Node (`sx` = Node-ID im aktuellen Screen).

| ID | Trigger | Scope | p1 / p2 | `trigger_arg` | Anmerkung |
|---|---|---|---|---|---|
| 0x01 | `enter_tile` | 2,3,4 | – | – | Party betritt Tile/Area |
| 0x02 | `leave_tile` | 2,3,4 | – | – | |
| 0x03 | `step` | 2,3 | – | – | jeder Schritt in der Area |
| 0x04 | `examine` | 2,3,4 | – | – | Auge |
| 0x05 | `speak` | 2,3,4 | – | – | Mund |
| 0x06 | `listen` | 2,3,4 | – | – | Ohr |
| 0x07 | `use_item` | 2,3,4 | p1 = Item (`0xFFFF` beliebig) | Item-ID | |
| 0x08 | `cast_spell` | 2,3,4 | p1 = Zauber (`0xFFFF` beliebig) | Zauber-ID | |
| 0x09 | `map_enter` | 1 | – | – | nach dem Laden der Karte |
| 0x0A | `map_exit` | 1 | – | – | |
| 0x0B | `map_tick` | 1 | p1 = Intervall in Ticks | – | Umgebungsleben |
| 0x0C | `keyword` | 4 | – | Wort-ID | Konversation |
| 0x0D | `show_item` | 4 | – | Item-ID | |
| 0x0E | `give_item` | 4 | – | Item-ID | |
| 0x0F | `give_gold` | 4 | – | Betrag | |
| 0x10 | `give_food` | 4 | – | Menge | |
| 0x11 | `see_party` | 4 | p1 = Reichweite | – | |
| 0x12 | `entity_died` | 4 | – | – | |
| 0x13 | `join_request` | 4 | – | – | Party fragt NPC nach Beitritt |
| 0x14 | `interact` | 2,3,4 | – | – | **Hand** (Betätigen/Benutzen: Schalter, Türen, Hebel). Ambermoon kennt die Hand als vierten Cursor neben Auge, Mund, Ohr |
| 0x20 | `hour` | 0,1 | p1 = Stunde (`0xFFFF` jede) | Stunde | |
| 0x21 | `day_change` | 0 | – | Tag | |
| 0x22 | `travel_step` | 0,1 | – | – | |
| 0x23 | `weather_change` | 0 | p1 = Wetter (`0xFFFF` beliebig) | Wetter | |
| 0x30 | `flag_changed` | 0,1 | p1 = Slot16, p2: 0 beliebig, 1 gesetzt, 2 gelöscht | neuer Wert | reaktiv (R-4) |
| 0x31 | `var_changed` | 0,1 | p1 = Slot16 | neuer Wert | reaktiv (R-4) |
| 0x32 | `custom` | 0,1 | p1 = Custom-ID | Wert der `raise`-Aktion | Signal, siehe Aktion `raise` |
| 0x40 | `screen_open` | 5 | – | – | nach dem Öffnen |
| 0x41 | `screen_close` | 5 | – | – | vor dem Schließen |
| 0x42 | `screen_resume` | 5 | – | – | Screen darüber wurde geschlossen |
| 0x43 | `click` | 6 | p1 = Maus-Tastenmaske (1 links, 2 rechts) | Tastenmaske | Node |
| 0x44 | `hover` | 6 | – | – | |
| 0x45 | `key` | 0,5 | p1 = Tastencode | Tastencode | |
| 0x46 | `region_click` | 3 (in Screen) | p1 = Tastenmaske | Tastenmaske | Fläche im Screen |
| 0x50 | `battle_end` | 0 | p1 = Gruppen-ID (`0xFFFF` beliebig) | Ausgang (0 gewonnen, 1 geflohen, 2 verloren) | |
| 0x51 | `item_gained` | 0 | p1 = Item (`0xFFFF` beliebig) | Item-ID | |
| 0x52 | `member_joined` | 0 | p1 = Charakter (`0xFFFF` beliebig) | Charakter | |
| 0x53 | `member_left` | 0 | p1 = Charakter | Charakter | |
| 0x54 | `level_up` | 0 | – | neue Stufe | |

Bei Area-Scope (`in (x, y, w, h)`) feuern `enter_tile` und `leave_tile` nur beim **Überschreiten der Grenze** (nicht bei jedem Schritt innerhalb), `step` dagegen bei jedem Schritt in der Area.

Neue Trigger erweitern diese Tabelle ohne Formatänderung (neue ID). Der Interpreter kennt Trigger nicht; **Hosts** lösen sie aus.

---

## 4. Bedingungen

Befehlswort (für Bedingungen und Aktionen gleich): `w0 = (op << 8) | (len << 2) | (or_next << 1) | neg`, danach `len` Operandenwörter (`len` 0..63). Bedingungs- und Aktionsströme haben **getrennte Opcode-Räume**.

- `neg` negiert das Ergebnis dieser Bedingung.
- `or_next = 1` verknüpft diese Bedingung mit der **folgenden** per ODER (gleiche Klausel). Klauseln (Ketten von ODER) werden per UND verknüpft.

```
eval_conditions(rule):
    clauseTrue = false
    for cond in rule.conditions:
        v = eval(cond) xor cond.neg
        clauseTrue = clauseTrue or v
        if cond.or_next == 0:
            if not clauseTrue: return false
            clauseTrue = false
    return true                                   // leere Liste = true
```

Eine letzte Bedingung mit `or_next = 1` ist ein Cook-Fehler.

| Op | Name | Operanden | Wahr, wenn |
|---|---|---|---|
| 0x01 | `flag` | Slot16 | Flag gesetzt |
| 0x02 | `var` | Slot16, Cmp, i16 | Var `cmp` Wert |
| 0x03 | `var32` | Slot16, Cmp, hi, lo | Var32 `cmp` Wert |
| 0x04 | `varvar` | Slot16 A, Cmp, Slot16 B | Var A `cmp` Var B |
| 0x05 | `result` | Cmp, i16 | `result` `cmp` Wert |
| 0x06 | `arg` | Cmp, hi, lo | `trigger_arg` `cmp` Wert |
| 0x07 | `chance` | Prozent (0..100) | `rand16` liegt unter der Schwelle (12.1) |
| 0x08 | `word_known` | Wort-ID | Wort im Wörterbuch der Party (KnownWords) |
| 0x09 | `has_item` | Item, Anzahl (0 = 1) | Party besitzt mindestens Anzahl |
| 0x0A | `has_member` | Charakter-ID | Charakter ist in der Party |
| 0x0B | `party_class` | Klasse | mindestens ein Mitglied dieser Klasse |
| 0x0C | `party_race` | Rasse | dito |
| 0x0D | `party_lang` | Sprache | mindestens ein Mitglied spricht sie |
| 0x0E | `party_size` | Cmp, i16 | Partygröße `cmp` Wert |
| 0x0F | `gold` | Cmp, hi, lo | Gruppengold `cmp` Wert |
| 0x10 | `attr` | Target8, Attribut, Cmp, i16 | Wert des Mitglieds `cmp` |
| 0x11 | `probe` | Target8, Attribut/Fertigkeit | Wurf gegen den Wert gelingt (12.1) |
| 0x12 | `hour_in` | von, bis | Stunde in `[von, bis)`; bei `von > bis` über Mitternacht |
| 0x13 | `day_in` | von, bis | Tag in `[von, bis]` |
| 0x14 | `season` | Jahreszeit | aktuelle Jahreszeit |
| 0x15 | `in_map` | Map-ID | Party ist in dieser Karte |
| 0x16 | `transport` | Transport-ID | Party nutzt dieses Transportmittel |
| 0x17 | `world` | Welt-ID | aktive Welt/Variante (für „Worlds") |
| 0x18 | `spell_active` | Zauber-ID | temporärer Zauber aktiv |
| 0x19 | `tile_is` | Layer, Pos (x, y), Tile | Tile an dieser Stelle (Besitzer-Karte); Pos darf „hier" sein; Tile nur absolut |
| 0x1A | `screen_open` | Screen-ID | Screen liegt im Stack |
| 0x1B | `member_condition` | Target8, Zustand | Mitglied hat den Statuszustand |
| 0x1C | `near` | EntityRef16, Reichweite | Party ist innerhalb der Reichweite |
| 0x1D | `facing` | Dir | Party blickt in Richtung |
| 0x1E | `input_matches` | Slot16 (Var mit Wortlisten-ID) | Text des `input`-Knotens im obersten Screen entspricht einem Eintrag der Wortliste (ohne Beachtung der Groß-/Kleinschreibung) |

Opcodes `0xE0..0xFF` sind für Erweiterungen reserviert.

---

## 5. Aktionen

Notation: `(op) name(operanden)`, **B** = blockiert.

### 5.1 Zustand

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x01 | `set_flag` | Slot16 | | löst ggf. `flag_changed` aus |
| 0x02 | `clear_flag` | Slot16 | | |
| 0x03 | `toggle_flag` | Slot16 | | |
| 0x04 | `set_var` | Slot16, i16 | | |
| 0x05 | `add_var` | Slot16, i16 | | Sättigung bei Überlauf |
| 0x06 | `set_var32` | Slot16, hi, lo | | |
| 0x07 | `add_var32` | Slot16, hi, lo | | vorzeichenbehaftet |
| 0x08 | `copy_var` | Slot16 dst, Slot16 src | | |
| 0x09 | `learn_word` | Wort-ID | | KnownWords |

### 5.2 Welt

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x10 | `teleport` | Map, x, y, Dir (`0xFF` behalten), fade (0/1) | **B** | fortgesetzt nach Übergang, `result` = 0 |
| 0x11 | `set_tile` | Layer, Pos (x, y), TileRef16 | | Besitzer-Karte; als Tile-Änderung gespeichert. Pos darf „hier" sein, Tile darf **relativ** sein (`+1`): nötig für wiederverwendbare Schalter-Gruppen |
| 0x12 | `set_tile_on` | Map, Layer, x, y, Tile | | andere Karte |
| 0x13 | `spawn` | EntityRef16, Pos (x, y) | | Pos darf „hier" sein |
| 0x14 | `despawn` | EntityRef16 | | |
| 0x15 | `move_entity` | EntityRef16, Pos (x, y), Tempo | | nicht blockierend; Pos darf „hier" sein |
| 0x16 | `set_dir` | EntityRef16, Dir (`0xFF` zufällig) | | Party oder Entity (Spinner) |
| 0x17 | `set_light` | Modus, Radius | | |
| 0x18 | `set_weather` | Wetter | | |
| 0x19 | `set_world` | Welt-ID | | wechselt Weltvariante |
| 0x1A | `set_routine` | EntityRef16, Routine-ID | | |
| 0x1B | `set_modifier` | Modifier, Wert (0/1) | | Konstanten `antimagic` (0), `no_rest` (1), `no_map_spell` (2); gilt bis zur nächsten Änderung oder zum Verlassen der Karte |
| 0x1C | `apply_delta` | Delta-ID | | wendet einen **Tile-Änderungssatz** (Tabelle `DELTA`) auf die Besitzer-Karte an; als Tile-Änderungen gespeichert (Weltzustands-Varianten, Konzept W2) |

### 5.3 Party

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x20 | `give_item` | Item, Anzahl | | `result` unverändert; bei vollem Inventar Aktion ohne Wirkung und Trace-Hinweis |
| 0x21 | `take_item` | Item, Anzahl | | |
| 0x22 | `give_gold` | hi, lo | | |
| 0x23 | `take_gold` | hi, lo | | |
| 0x24 | `give_food` | Menge | | |
| 0x25 | `take_food` | Menge | | |
| 0x26 | `give_xp` | Target8, hi, lo | | |
| 0x27 | `add_member` | Charakter-ID | | Party voll: keine Wirkung |
| 0x28 | `remove_member` | Charakter-ID | | |
| 0x29 | `heal` | Target8, HP, SP | | `0x7FFF` = voll |
| 0x2A | `damage` | Target8, Betrag, Art | | Art aus Tabelle (physisch, Feuer …) |
| 0x2B | `add_condition` | Target8, Zustand | | |
| 0x2C | `remove_condition` | Target8, Zustand | | |
| 0x2D | `change_attr` | Target8, Attribut, Delta | | |
| 0x2E | `teach_spell` | Target8, Zauber | | |
| 0x2F | `move_all` | Quelle, Ziel-Target8 | | Quelle = Truhe aus `screen`-Var 0: `chest_all` (1: Items, Gold, Rationen), `chest_gold` (2), `chest_items` (3), `chest_food` (4) |

### 5.4 Kampf und Magie

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x30 | `battle` | Monstergruppe, Flags | **B** | `result`: 0 gewonnen, 1 geflohen, 2 verloren (bei „Party tot" kehrt der Kampf nicht zurück; Spielende) |
| 0x31 | `trap` | Fallentyp, Schaden | **B** | Wurf gegen Glück, Meldung, Wirkung (nativer Mechanismus) |
| 0x32 | `cast_effect` | Effekt, Target8 | | Zaubereffekt aus Tabelle |

### 5.5 Dialog

`say`, `say_picture`, `ask_word`, `ask_choice` und `confirm` sind **semantisch gleichwertig** zu `push_screen` auf einen Standard-Screen (`S.textbox`, `S.picture_text`, `S.input_word`, `S.choice`, `S.confirmation`, Beispiele in `examples/screens/`). Sie haben eigene Opcodes nur, weil sie sehr häufig vorkommen (2 statt 5 Wörter). Die Referenzimplementierung KANN sie intern als `push_screen` ausführen.

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x40 | `say` | Text | **B** | wartet auf Klick |
| 0x41 | `say_picture` | Bild, Text | **B** | |
| 0x42 | `ask_word` | Wortliste | **B** | `result`: 1 richtig, 0 falsch/abgebrochen. Wortliste = zulässige Antworten (Tabelle `WORDS`), Groß-/Kleinschreibung egal |
| 0x43 | `ask_choice` | Text, Auswahlliste | **B** | `result` = Index (0-basiert), `0xFFFF` abgebrochen |
| 0x44 | `confirm` | Text | **B** | `result`: 1 ja, 0 nein |
| 0x45 | `bark` | EntityRef16, Text | | Sprechblase, nicht blockierend |

### 5.6 UI und Screens

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x50 | `push_screen` | Screen, Flags, argc, arg0.. | **B**, außer Flag bit0 `nowait` | Argumente werden Screen-Vars 0..argc-1. `result` = Wert des `pop_screen` |
| 0x51 | `pop_screen` | Wert (`i16`) | | schließt den obersten Screen, meldet den Wert dem wartenden Ablauf |
| 0x52 | `replace_screen` | Screen, Flags, argc, arg0.. | | Pop + Push |
| 0x53 | `set_node` | Node, Eigenschaft, Wert | | Eigenschaften: 0 visible, 1 enabled, 2 Text-ID, 3 Icon, 4 Wert |
| 0x54 | `show_node` | Node | | |
| 0x55 | `hide_node` | Node | | |
| 0x56 | `enable_node` | Node | | |
| 0x57 | `disable_node` | Node | | |
| 0x58 | `set_text` | Node, Text | | |

### 5.7 Medien und Zeit

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x60 | `music` | Musik-ID | | |
| 0x61 | `sfx` | Sound-ID | | |
| 0x62 | `fade` | 0 aus / 1 ein, Ticks | **B** | |
| 0x63 | `shake` | Ticks | | |
| 0x64 | `flash` | Farbe, Ticks | | Paletteneffekt (Z4): die Kunst-Einträge der Palette gehen zur Farbe und zurück; die 8 UI-Einträge bleiben |
| 0x65 | `play_outro` | – | **B** | |
| 0x66 | `set_palette` | Palette (`PAL.x`, `0xFFFF` = freigeben) | | setzt die Palette der Besitzer-Karte sofort (nur Kunst-Einträge). Eine gesetzte Palette hat Vorrang vor Tag und Nacht, bis `set_palette(0xFFFF)` sie freigibt. Neu 2026-10-23, siehe 16 |
| 0x67 | `fade_palette` | Palette (`PAL.x`, `0xFFFF` = freigeben), Ticks, Flags (bit0 `nowait`) | **B**, außer `nowait` | blendet in Ticks zur Palette über; sonst wie `set_palette` |
| 0x70 | `advance_time` | Minuten | | |
| 0x71 | `wait` | Ticks | **B** | 50 Hz |

### 5.8 System

| Op | Aktion | Operanden | B | Anmerkung |
|---|---|---|---|---|
| 0x78 | `raise` | Custom-ID, Wert (`i16`) | | Signal; Trigger `custom` (R-4). **Ersatz für Unterprogramme** |
| 0x79 | `autosave` | – | | speichert **am Ende der Kette** (nicht sofort). Erlaubt nur als letzte Aktion einer Regel ohne `then` (Warnung W004) |
| 0x7F | `native` | Native-ID, argc, arg0.. | laut Native-Tabelle | Erweiterungspunkt (9.4) |

Opcodes `0xE0..0xFF` sind reserviert.

---

## 6. Encoding

### 6.1 Regel, Gruppe, Gruppentabelle

```
RuleRecord (Wörter):
  w0  condWords      Anzahl Wörter des Bedingungsstroms
  w1  actionWords    Anzahl Wörter des Aktionsstroms
  w2  next           GroupRef16 oder 0xFFFF
  w3  reserved (0)   (v1: Regel-Flags)
  ... Bedingungsstrom ...
  ... Aktionsstrom ...

GroupRecord:
  w0  [mode:8][ruleCount:8]     mode 0 = first, 1 = all
  w1  totalWords                Gesamtlänge des Records in Wörtern (inkl. Header)
  ... RuleRecord x ruleCount ...

Gruppentabelle (Chunk SCRIPTS, auch lokal in MAP/SCREEN):
  u16 groupCount, u16 reserved
  u32 offset[groupCount]        Byte-Offsets ab Chunkanfang, gerade
  ... GroupRecords ...
```

### 6.2 Beispiel (Bit für Bit)

Quelle:

```
group schrein first {
  when not flag(schrein_benutzt) and hour_in(20, 6)
  do { say(T.geist); set_flag(schrein_benutzt); battle(G.geist, 0); }
}
```
Angenommen `schrein_benutzt` = globales Flag 137 (`Slot16 = 0x0089`), `T.geist` = 42 (`0x002A`), `G.geist` = 7.

```
Bedingung 1: flag, neg=1, len=1     0x0105  0x0089
Bedingung 2: hour_in, len=2         0x1208  0x0014  0x0006
Aktion 1: say, len=1                0x4004  0x002A
Aktion 2: set_flag, len=1           0x0104  0x0089
Aktion 3: battle, len=2             0x3008  0x0007  0x0000

RuleRecord:  0005 0007 FFFF 0000  | 0105 0089 1208 0014 0006 | 4004 002A 0104 0089 3008 0007 0000
GroupRecord: 0001 0012            | (RuleRecord, 16 Wörter)
```
Prüfung: `0x0105` = op `0x01`, `len` 1 (`1<<2 = 4`), `or_next` 0, `neg` 1 ⇒ `0x01<<8 | 4 | 0 | 1 = 0x0105`. `totalWords` = 2 (Kopf) + 16 (Regel) = 18 = `0x0012`. Der Interpreter bearbeitet Wort für Wort, ein `0x0105`-Zugriff liegt auf gerader Adresse und kommt ohne Byte-Zugriffe aus.

### 6.3 Bindung

`on step at (3, 4) -> schrein;` (Tile-Scope, Gruppe lokal 0):

```
w0 0x0302   step, scope Tile
w1 0x8000   lokale Gruppe 0
w2 0x0000   p1
w3 0x0000   p2
w4 0x0003   x
w5 0x0004   y
w6 0x0000
w7 0x0000
```

### 6.4 Interpreter auf 68k (Hinweis, kein Teil der Spec)

Zwei 256er-Sprungtabellen (Bedingungen, Aktionen), eine Schleife über `w0`, Operanden per Wortzugriff. 32-Bit-Werte werden aus zwei Wörtern gebildet, damit keine 4-Byte-Ausrichtung nötig ist.

---

## 7. Quellsprache `.ams` (v0)

### 7.1 Lexik

- Kommentare: `// bis Zeilenende`, `/* … */`.
- Bezeichner: `[A-Za-z_][A-Za-z0-9_]*` (ASCII). Zahlen: dezimal, `0x…`, negativ mit `-`. Zeiten: `HH:MM`. Zeichenketten: `"…"`, UTF-8.
- Anweisungen enden mit `;`, Blöcke mit `{ }`.

### 7.2 Grammatik (EBNF)

```
program     = { top } ;
top         = decl | map | screenBlock | binding | group | conversation | npc | entity | preset | use ;

screenBlock = "screen" ident "{" { decl | binding | group } "}" ;   (* sieht die args des YAML-Screens; Gruppen sind screen-lokal *)

decl        = ( "flag" | "var" | "var32" ) ident [ "=" int ] ";" ;

map         = "map" ident "{" { mapItem } "}" ;
mapItem     = "template" ident ";" | decl | binding | group | conversation | npc | entity | preset | use ;

entity      = "entity" ident "at" pos "{" { binding | bark | routine } "}" ;
npc         = "npc"    ident "at" pos "{" { binding | bark | routine | conversationBody } "}" ;
pos         = "(" int "," int ")" ;
rect        = "(" int "," int "," int "," int ")" ;

binding     = "on" trigger [ "at" pos | "in" rect ] "->" ident ";" ;
trigger     = ident [ "(" [ arg { "," arg } ] ")" ] ;

group       = "group" ident [ "first" | "all" ] "{" rule { rule } "}" ;
rule        = [ "once" ] ( "when" cond | "else" ) "do" block [ "then" ident ";" ]
            | [ "once" ] "do" block [ "then" ident ";" ] ;
block       = "{" { action ";" } "}" ;

cond        = clause { "and" clause } ;
clause      = literal | "(" literal { "or" literal } ")" ;
literal     = [ "not" ] atom ;
atom        = call                         (* flag(x), hour_in(a, b), has_item(I.x, 2), chance(30) … *)
            | operand cmp operand ;        (* result == 1, gold >= 500, reputation < 3, arg == K.foo *)
cmp         = "==" | "!=" | "<" | "<=" | ">" | ">=" ;

action      = ident "(" [ arg { "," arg } ] ")" ;
arg         = int | rel | ident | sym | pos | "here" ;
rel         = ( "+" | "-" ) int ;          (* relativer Tile-Wert, nur bei set_tile *)
sym         = prefix "." ident ;           (* T.text, I.item, G.monsters … *)

conversation = "conversation" ident "{" conversationBody "}" ;
conversationBody = { "greet" sym ";" | topic | onItem } ;
topic       = "topic" string [ "when" cond ] "do" block ;
onItem      = "on" ( "show_item" | "give_item" | "give_gold" ) "(" arg ")" [ "when" cond ] "do" block ;

routine     = "routine" ident "{" { routineEntry } "}" ;
routineEntry = time routineStep ";" { routineStep ";" } ;         (* ein Zeitpunkt, danach beliebig viele Schritte *)
routineStep = "walk_to" ident | "stay" duration | "sleep" ;
bark        = "bark" sym [ "when" cond ] "every" duration ";" ;

preset      = "preset" ( presetFragment | presetPattern ) ;
presetFragment = ( "cond" | "action" ) ident params "=" fragmentBody ";" ;
fragmentBody = cond                                   (* bei "preset cond" *)
             | action ";" { action ";" } ;            (* bei "preset action" *)
presetPattern  = ident params "on" trigger [ "first" | "all" ]
                 "{" { decl } rule { rule } "}" ;
params      = "(" [ param { "," param } ] ")" ;
param       = ident [ ":" kind ] [ "=" arg ] ;
kind        = "int" | "text" | "item" | "tile" | "flag" | "var" | "word" | "pos" | "group" | "sym" ;
use         = "use" ident "(" [ arg { "," arg } ] ")" [ "at" pos | "in" rect ] ";" ;
```

- `or` **MUSS** in Klammern stehen, sobald es mit `and` kombiniert wird (E008). Grund: kein Rätselraten über Vorrang.
- `else` ist nur als **letzte** Regel einer `first`-Gruppe erlaubt (E011) und ist gleichbedeutend mit „keine Bedingung".
- Aktionen und Bedingungen verwenden **nur** die Namen aus den Tabellen in 4 und 5; die Operanden sind positionsgebunden.

**Zahlen als Operanden:** 32-Bit-Operanden (`give_gold`, `give_xp`, `gold`, `arg`, `set_var32` …) werden im Quelltext als **eine** Zahl geschrieben (`give_gold(250)`); der Compiler zerlegt sie in `hi`/`lo`.

### 7.3 Symbolpräfixe und Konstanten

Symbole stammen aus den Tabellen (`tables/*.yaml`). Der Cook vergibt IDs und meldet Unbekanntes (E001).

| Präfix | Bedeutung | Präfix | Bedeutung |
|---|---|---|---|
| `T.` | Text | `I.` | Item |
| `K.` | Keyword/Wort | `W.` | Antwortliste (`ask_word`) |
| `G.` | Monstergruppe | `M.` | Karte |
| `C.` | Charakter/Party-Mitglied | `S.` | Screen |
| `SP.` | Zauber | `E.` | Entity (in der Karte) |
| `CL.` | Klasse | `RC.` | Rasse |
| `LG.` | Sprache | `AT.` | Attribut/Fertigkeit |
| `PIC.` | Bild | `MUS.` | Musik |
| `SND.` | Sound | `TILE.` | Tile |
| `TR.` | Transportmittel | `TRAP.` | Fallentyp |
| `PLACE.` | Ortsart (Gilde, Händler …) | `FX.` | Zaubereffekt |
| `DELTA.` | Tile-Änderungssatz (`apply_delta`) | `CH.` | Truhe (Inhalt für den Truhen-Screen) |
| `N.` | Host-Funktion oder Datenquelle (`native`) | | |

**Schlüsselwort-Konstanten** (ohne Präfix): Target8 `active`, `any`, `all`, `leader`, `slot1`..`slot6`; Entity `party`; Richtungen `up`, `right`, `down`, `left`, `keep`, `random`; `flag_changed`-Modus `any`, `set`, `cleared`; Modifier `antimagic`, `no_rest`, `no_map_spell`; `move_all`-Quellen `chest_all`, `chest_gold`, `chest_items`, `chest_food`.

### 7.4 Zucker (der Compiler erzeugt daraus nur Gruppen und Bindungen)

- **`once`** vor einer Regel: reserviert ein Flag im passenden Namensraum (Karte oder global), fügt die Bedingung `not flag(x)` und als erste Aktion `set_flag(x)` hinzu. Ersetzt Amberstars „SaveEvent".
- **`conversation`/`topic`**: Bindungen für `keyword`, `show_item`, `give_item`, `give_gold` am NPC. Jede `topic` wird eine Regel mit Bedingung `arg == K.<wort>` in einer `first`-Gruppe. `topic "*"` ist die letzte Regel (Vorgabe).
- **`greet`** (aus der Umsetzung ergänzt): Bindung `speak` am NPC auf eine Gruppe `<npc>$greet` mit `say(<Begrüßung>)` und `push_screen(S.conversation, 0, 1, <Entity-ID>)`. Der native Konversations-Screen übernimmt dann die Stichwörter. Ohne `greet` entfällt nur das `say`.
- **Stichwörter**: Wörter aus `topic "Wort"` werden kleingeschrieben als Symbol `K.<wort>` registriert (`topic "Amberstar"` ⇔ `K.amberstar`).
- **`routine`**: wird zu einer Tabelle aus Zeit, Ziel, Verhalten. Beim Cook per Pfadsuche in Wegpunkte gebacken (Chunk MAP). Der Interpreter sieht davon nichts; der Host führt Routinen aus (`set_routine` wählt).
- **`bark`**: wird zu einer Bindung `map_tick` mit den Bedingungen und einer Aktion `bark`. Innerhalb von `npc`/`entity` steht `near(r)` als Kurzform für `near(<dieses Entity>, r)`.
- **Entity- und Routinennamen** dürfen innerhalb ihrer Karte ohne Präfix verwendet werden (`set_routine(baeckerin, feier)`). Da Entities karten-lokal sind, dürfen Gruppen, die sie referenzieren, nur **in der Karte** stehen (globale Gruppe mit Entity-Verweis ist Fehler E003). Reaktive Bindungen mit Scope 1 (Karte) wirken nur, solange die Karte geladen ist. Für Änderungen, die passieren, während die Party woanders ist, gehört deshalb zusätzlich ein `map_enter`-Abgleich in die Karte (Beispiel: `examples/world/lebendige-welt.ams`).

### 7.5 Zeitangaben

`duration`: `30t` (Ticks), `2s`, `2min` (Spielzeit-Minuten), `6h`. Der Cook wandelt in Ticks bzw. Spielminuten. Die Umrechnung von Sekunden ist fest 50 Ticks/s.

### 7.6 Wiederverwendung: Gruppen teilen, Presets, Deduplizierung

Häufige Muster (Schalter, Türen, Einmal-Geschenke, „braucht Schlüssel") sollen nicht jedes Mal neu geschrieben werden. Vier Stufen, aufsteigend nach Aufwand. **Stufe 1–3 gehören zu v0**, Stufe 4 ist reserviert (Abschnitt 14).

| Stufe | Mechanismus | Wirkung | Kosten |
|---|---|---|---|
| 1 | **Gruppen teilen** + `here` und relatives Tile (1.3, 1.4) | Beliebig viele Bindungen zeigen auf **eine** Gruppe (`on interact at (x,y) -> hebel`) | keine, Format unverändert |
| 2 | **Presets** (Compile-Zeit-Ersetzung) | Benannte, typisierte Vorlagen für Bedingungen, Aktionen oder ganze Muster | keine Laufzeitkosten, Format unverändert |
| 3 | **Deduplizierung** im Cook | Bytegleiche Gruppen nach Expansion werden zu einer zusammengefasst | unsichtbar, abschaltbar (`--no-dedup`) |
| 4 | Laufzeit-Templates mit Parametern | Datenersparnis bei sehr vielen Instanzen | erst nach Messung (siehe 14) |

#### Preset-Arten

- **Fragment `cond`**: eine Bedingung (oder Klausel), aufrufbar wie jede Bedingung. `preset cond has_key(k: item) = has_item(k, 1);`
- **Fragment `action`**: eine Folge von Aktionen, aufrufbar wie eine Aktion. `preset action open_at(x: int, y: int, t: tile) = set_tile(1, x, y, t); sfx(SND.mechanism);`
- **Muster (`pattern`)**: Trigger plus Regeln (eine ganze Gruppe). Wird mit `use name(args) at (x, y);` (oder `in (x, y, w, h)`, oder innerhalb eines `entity`/`npc`-Blocks ohne Ort) instanziiert. Erzeugt Bindung **und** Gruppe.

```
preset lever(tile_off: tile, tile_on: tile, click: sym = SND.click) on interact {
  when tile_is(1, here, tile_off) do { set_tile(1, here, tile_on);  sfx(click); }
  when tile_is(1, here, tile_on)  do { set_tile(1, here, tile_off); sfx(click); }
}
use lever(TILE.lever_up, TILE.lever_down) at (12, 6);
```

#### Regeln

1. **Typisiert**: Jeder Parameter hat eine Art (`int`, `text`, `item`, `tile`, `flag`, `var`, `word`, `pos`, `group`, `sym`; ohne Angabe `sym`). Der Cook prüft beim Ersetzen (E017). Ersetzt wird auf Token-Ebene nach der Prüfung, nie per Zeichenketten-Verkettung.
2. **Keine Rekursion**, Verschachtelung höchstens 4 Ebenen. Fragmente dürfen andere Fragmente aufrufen. Muster dürfen Fragmente aufrufen, aber **kein `use`** eines anderen Musters (E016).
3. **Keine Bedingungen im Preset selbst**: Ein Preset ist eine Vorlage, keine Logik. Verzweigt wird weiterhin nur durch Regeln (Prinzip „kein Kontrollfluss").
4. **Zustand je Instanz**: `flag`, `var`, `var32` **innerhalb eines Musters** erzeugen für jede Verwendung einen neuen Slot (im Namensraum des Verwendungsortes: Karte oder global). So funktioniert „einmaliges Geschenk" ohne Namenskollisionen. Gruppen mit Instanzzustand werden nicht dedupliziert (sie sind nicht bytegleich).
5. **Sichtbarkeit**: Presets auf Datei-/Top-Ebene gelten global (Konvention: `std/presets.ams` für die mitgelieferte Bibliothek, `presets/*.ams` für eigene). Presets in einem `map`-Block gelten nur dort und verdecken globale gleichen Namens (W007). Preset-Namen dürfen nicht den Namen eingebauter Bedingungen/Aktionen entsprechen (E019).
6. **`here`** in einem Preset bezieht sich auf den **Verwendungsort**. Ob dort ein Auslöseort existiert, prüft der Cook nach der Expansion (E015).
7. **Herkunft bleibt sichtbar**: Der SYMBOLS-Chunk (und der Trace) nennt Preset-Name und Verwendungsstelle (`lever @ spannenberg.ams:14`), auch nach der Deduplizierung.

#### Beispiel

Siehe [examples/presets/](../examples/presets/) (Schalter, relativer Schalter, Fragmente, Einmal-Geschenk).

#### Stufe 3: Deduplizierung

Zwei Gruppen mit **bytegleichem** GroupRecord (nach Expansion und Slot-Vergabe) werden zu einer zusammengefasst. Bindungen und `then`-Verweise zeigen auf die gemeinsame Gruppe, die kleinste ursprüngliche Gruppen-ID gewinnt. Die Semantik ändert sich nicht (nur Zustand außerhalb der Gruppe, kein Instanzzustand). Chunk-Kompression (9.3) fängt zusätzlich Wiederholungen auf Platte ab.

---

## 8. Screens

Definition als YAML nach [schemas/screen.schema.json](schemas/screen.schema.json). Beispiele: [../examples/screens/](../examples/screens/).

### 8.1 Stack-Semantik

`push_screen(S, flags, argc, args…)`:
1. Screen darunter einfrieren (bei nicht transparent verstecken; bei `modal` Eingabe sperren).
2. Instanz erzeugen: Knoten aus dem Pool, Prefabs expandieren; `screen`-Namensraum initialisieren (Args in Vars 0..argc-1).
3. Cursor und Mausbereiche (Hit-Regionen) auf den Stack legen.
4. Trigger `screen_open` auslösen.

`pop_screen(v)`: Trigger `screen_close`, Knoten freigeben, Zustand darunter wiederherstellen, den **wartenden Ablauf** (der `push_screen` ohne `nowait` ausgeführt hat) mit `result = v` fortsetzen, danach Trigger `screen_resume` für den Screen darunter. Wurde der Screen von außen geschlossen (Escape, Rechtsklick), ist `v = 0`.

**Eingabe-Routing:** oberster Screen zuerst. `passthrough`-Regionen reichen Eingaben an den Screen darunter weiter (z. B. Party-Leiste). Ein Screen `modal` fängt alle übrigen Eingaben ab. *Umsetzung im Prototyp:* Ein Mausklick (links oder rechts) in einer `passthrough`-Region eines **transparenten** Screens geht an den Screen darunter; Tastatur und alles außerhalb der Regionen bleiben beim obersten Screen. Bei nicht transparenten Screens ist das Feld wirkungslos (der Screen darunter ist versteckt).

### 8.2 Screen-Header (in M2 umgesetzt und geprüft)

Alle Wörter big endian, wie die Skript-Chunks (`ScreenChunk` in `src/Amber.Screens`). Der Chunk besteht aus dem Header (16 Wörter), den Passthrough-Rechtecken (je 4 Wörter: x, y, w, h), der Knotentabelle und der Tabelle der Literaltexte.

```
w0  screenId
w1  flags       bit0 modal, bit1 transparent, bit2-3 fade (0 none 1 in 2 out 3 both),
                bit4 close_on_escape, bit5 close_on_right_click, bit6 close_on_space,
                bit7 allow_character_select, bit8 allow_inventory
w2  regionX  w3 regionY  w4 regionW  w5 regionH   (i16, wie alle Koordinaten)
w6  argc     w7 nodeCount   w8 literalCount   w9 passthroughCount
w10 onOpen (GroupRef16, 0xFFFF = keiner)  w11 onClose  w12 onResume  w13 cursorId (0 = keiner)
w14 nodeTableOffset (Wörter ab Chunkanfang)  w15 literalTableOffset
```

**Abweichung vom Entwurf:** `w8` war `localGroupCount`, `w15` `groupTableOffset`. Die lokalen Gruppen eines Screens stehen im Skript-Chunk des `screen`-Blocks (Abschnitt 6), eine zweite Tabelle im Screen-Chunk wäre doppelt. Stattdessen trägt `w8`/`w15` die **Literaltexte**: Texte, die im YAML als Klartext stehen (nur zu Entwicklungszwecken, siehe Schema `dynamicText`), kommen in eine Tabelle am Chunk-Ende (Länge in Bytes als Wort, Latin-1-Bytes, auf ganze Wörter aufgefüllt). Handler-Gruppen (`onOpen` …) sind `GroupRef16` in den Skript-Chunk des Screens oder in die globalen Gruppen.

### 8.3 Knotenrecord (in M2 umgesetzt und geprüft)

```
NodeRecord = 16 Wörter, die Knotentabelle steht in Tiefensuche-Reihenfolge; die Position ist der Knotenindex
  w0  [type:8][flags:8]     type: 0 container 1 image 2 label 3 button 4 input 5 list
                            6 itemgrid 7 portrait 8 bar 9 window 10 textview 11 viewport 12 picture
                            flags: bit0 visible, bit1 enabled, bit2 bound (w9 ist eine Datenquelle)
  w1  id                    der Knotenindex, wenn der Knoten einen Namen hat (per Skript ansprechbar), sonst 0xFFFF
  w2  parent (Knotenindex oder 0xFFFF)
  w3  x  w4 y  w5 w  w6 h   (logische Pixel, i16, relativ zum Parent)
  w7  layer
  w8  gfx / icon            (Grafik-ID der UI-Tabelle, 0 = keine)
  w9  Text                  Tabellentext-ID (1..0x7FFF), 0x8000|n Literaltext n, 0xC000|n Screen-Argument n
                            (dessen Wert ist die Text-ID); bei flags.bound: ID der nativen Datenquelle, oder 0x8000|n =
                            Detailtext der gewählten Zeile des Listenknotens n dieses Screens (`<liste>.detail`); für `itemgrid` ebenso, `<knoten>.name` ist der Text der gewählten Zeile
  w10 bind-Argument         Index in eckigen Klammern (party[2].hp), sonst 0xFFFF
  w11 onClick (GroupRef16)  w12 onHover (GroupRef16)   (0xFFFF = keiner)
  w13..w15 je nach Typ:
      window    w13 = (Kacheln x << 8) | Kacheln y     w14 = dark
      label     w13 = align (0 links, 1 mitte, 2 rechts)  w14 = color   w15 = blink
      button    w13 = Hotkey (Tastencode, siehe unten)
      input     w13 = max_length   w14 = onSubmit
      list      w13 = (columns << 8) | rows   w14 = onSelect
      itemgrid  w13 = (cols << 8) | rows      w14 = onSelect   w15 = onDrop
      portrait  w13 = slot
      bar       w13 = kind (0 hp, 1 sp)  w14 = slot
      textview  w13 = paged
      viewport  w13 = kind (0 map2d, 1 map3d, 2 battle)
      image/picture  w13 = opaque
```

**Knotenindex:** Er zählt **alle** Knoten in Tiefensuche-Reihenfolge, auch die ohne Namen (die Namen der Liste `NodeIds` sind dann leer). `set_node` & Co. und die Knotentabelle des Chunks benutzen denselben Index. **Prefabs** (`use`) sind schon vor dem Schreiben aufgelöst; die Knoten des Prefabs stehen unter einem unbenannten Container. **Hotkey-Codes:** Buchstaben und Ziffern als ASCII (Großbuchstaben), `esc` 27, `enter` 13, `tab` 9, `space` 32, `num0..num9` 0x100+n, `f1..f12` 0x110+n, Pfeile 0x120 (hoch), 0x121 (runter), 0x122 (links), 0x123 (rechts).

**Cook:** `ScreenChunk.Write(screen, symbols)` bekommt die Tabellen über `IScreenSymbols` (Screen, Text, Grafik, Datenquelle, Gruppe, Cursor). Ein Round-Trip-Test (`ScreenChunkTests`) schreibt und liest alle Beispiel- und Prototyp-Screens; beschädigte Chunks (abgeschnitten, falscher Typ, falscher Offset) lösen `InvalidChunkException` aus. Die echten Nativ-Tabellen füllt erst der Pack-Cook (M3).

### 8.4 Bindungen an Datenquellen

`bind` und `source` verweisen auf **native Datenquellen** (Name→ID in der NATIVES-Tabelle), z. B. `chest.gold`, `chest.items`, `party[2].hp`. Beim Schreiben der Quelle wird der Knoten als „dirty" markiert und im nächsten Tick neu gezeichnet. *Umsetzung im Prototyp:* Jede Quelle hat einen **Versionszähler** (Party, Truhe, Screen-Meldung; die Auswahl einer `list` für `<liste>.detail`). Ein Widget merkt sich die Version, mit der es zuletzt gezeichnet hat, und zeichnet nur neu, wenn sich die Version, sein Fokus, sein Hover oder sein eigener Zustand (`visible`, `enabled`, Text per `set_text`, Auswahl, Eingabe) geändert hat. Ein Screen ohne Änderung kostet keine Zeichenaufrufe (Test: `expect redraws 0`).

**Bindungen und Widgets im Detail:**
- **`input`** liest getippte Zeichen (nur druckbare ASCII-Zeichen, bis `max_length`), Rücktaste löscht; `Enter` startet `on_submit`. Den Text liest die Host-Funktion des Handlers (Prototyp: `native(N.lookup_word, 0)`). Solange ein `input` den Fokus hat, sind Buchstaben-Hotkeys der Knöpfe und die Leertaste aus (es ist Text); `Esc` und `Enter` bleiben.
- **`itemgrid`** zeigt die Zeilen einer Quelle in `cols` × `rows` Plätzen. Klick oder `Enter` startet `on_select` (Wert der Zeile als `trigger_arg`). Zieht man einen Gegenstand auf ein **anderes** Raster, läuft dessen `on_drop`-Gruppe (Wert als `trigger_arg`). Der Prototyp zeigt Text statt Symbole, da er keine Gegenstandsgrafiken hat.

---

## 9. Pack-Format

### 9.1 Kopf (40 Byte)

```
0   u8[4]  magic "AMBP"
4   u16    formatVersion (= 0)
6   u16    profileId (0 desktop, 1 amiga_a1200)
8   u16    flags (bit0: SYMBOLS vorhanden)
10  u16    tocCount
12  u32    tocOffset          (durch 4 teilbar)
16  u32    layoutHash         (CRC32 der LAYOUT-Beschreibung, siehe 10.1)
20  u16    maxThreads
22  u16    maxChainSteps
24  u16    maxScreenDepth
26  u16    maxPendingEvents
28  u16    globalFlagBits
30  u16    globalVars
32  u16    globalVars32
34  u16    nativeCount
36  u32    reserved
```

### 9.2 TOC-Eintrag (20 Byte)

```
0  u16 type        4  u32 offset (durch 4 teilbar)
2  u16 id          8  u32 packedSize   12 u32 unpackedSize
16 u16 compression 18 u16 crc16 (CRC-16/CCITT über die gepackten Bytes)
```

| Typ | Name | `id` | Inhalt |
|---|---|---|---|
| 0x0001 | SCRIPTS | 0 | globale Gruppentabelle |
| 0x0002 | BINDINGS | 0 | globale Bindungen |
| 0x0003 | SCREEN | Screen-ID | Header, Knoten, lokale Gruppen, lokale Bindungen |
| 0x0004 | MAP | Map-ID | Karte, Entities, lokale Gruppen/Bindungen, Routinen, Map-Namensraum-Größen |
| 0x0005 | TILESET_LOGIC | Tileset-ID | Tile-Flags (begehbar, blockiert, animiert …) |
| 0x0006 | TABLE | Tabellentyp | Items, Monster, Zauber, Klassen, Orte … (Records fester Größe) |
| 0x0007 | TEXT | Sprach-ID | Zeichenkettentabelle (11) |
| 0x0008 | NATIVES | 0 | erwartete native Funktionen und Datenquellen |
| 0x0009 | SYMBOLS | 0 | Debugnamen (nur wenn Flag gesetzt) |
| 0x000A | LAYOUT | 0 | Slot-Zuordnung (Namens-Hash → Index) |
| 0x000B | WORDS | 0 | Wörter/Antwortlisten |

Präsentationsdaten liegen **getrennt** in `gfx_<profil>.pack` und `snd_<profil>.pack` im selben Container (Typen ab `0x0100`: TILESET_GFX, ATLAS, PALETTE, FONT, CURSOR, PICTURE, ab `0x0200`: MUSIC, SFX).

### 9.3 Kompression

| ID | Name | Bemerkung |
|---|---|---|
| 0 | none | |
| 1 | RLE0 | in `Amber.GameData.Pyrdacor` vorhanden (ID abgleichen) |
| 2 | Deflate | Desktop; auf Amiga nur für Ladezeit-unkritische Chunks |
| 3 | reserviert | leichtgewichtiger LZ-Variant für Amiga, Entscheidung in M6 |

### 9.4 Native Tabelle (Erweiterungspunkt)

Eintrag: `u16 id`, `u16 flags` (bit0 blockierend, bit1 Datenquelle), `u8 argc`, `u8 nameLen`, Name (ASCII, auf gerade Länge aufgefüllt). Die Runtime prüft beim Laden, dass jede geforderte native ID implementiert ist; sonst Ladefehler. Der Cook meldet unbekannte Namen (E013).

### 9.5 Lader

```
IPackReader.Get(type, id) -> ReadOnlySpan<byte>     // dekomprimiert
IPackReader.Contains(type, id) -> bool
```
Implementierungen: `FilePackReader` (Desktop, lose Dateien im Dev-Modus), `MemoryPackReader`, später `AmigaDiskPackReader` (C). Die bestehenden `I*Loader` (`IMapLoader` …) setzen auf `IPackReader` auf.

### 9.6 Chunk-Inhalte (in M3 umgesetzt: `src/Amber.Pack`, `src/Amber.Cook`)

Alle Zahlen des Containers und der Chunks sind **big endian**, Chunk-Anfänge liegen auf durch 4 teilbaren Offsets, das TOC steht am Dateiende und ist nach (Typ, ID) sortiert. **CRC-16** ist CRC-16/CCITT-FALSE (Polynom 0x1021, Startwert 0xFFFF, ohne Spiegelung und ohne Endwert-XOR; Prüfwert für „123456789“: 0x29B1) über die **gepackten** Bytes. Kompression 1 (RLE0) und 2 (Deflate, roher Deflate-Strom) sind dieselben Verfahren wie in `Amber.GameData.Pyrdacor`; nur die Kennungen unterscheiden sich (dort 0xC001 und 0xDEF0, im Pack 1 und 2). RLE0: Ein Nullbyte wird von der Anzahl der weiteren Nullen gefolgt, längere Läufe stehen in Blöcken zu 256.

| Typ | ID | Inhalt |
|---|---|---|
| SCRIPTS, BINDINGS | 0 | die Gruppen- und Bindungstabelle des globalen Skripts (Abschnitt 6) |
| MAP | Map-ID | `u16 nameLen, flags, vars, vars32, entityCount, reserved`, Name (auf gerade Länge aufgefüllt), Entities (`u16 id, x, y, u8 kind, u8 nameLen`, Name), dann `u32 len` mit den Gruppen und `u32 len` mit den Bindungen, jeweils auf 4 aufgefüllt. nach den Gruppen und Bindungen die **Routinen** (siehe unten) |
| SCREEN | Screen-ID | `u32 defLen, u16 flags, vars, vars32, reserved`, die Screen-Definition (8.2/8.3), aufgefüllt, dann Gruppen und Bindungen des `screen`-Blocks wie bei MAP |
| NATIVES | 0 | Tabelle nach 9.4. Die Funktionen sind die `N.`-Symbole (Bit 1 „Datenquelle“ nicht gesetzt), die Datenquellen der Screens (`bind`, `source`) trägt der Cook mit den nächsten freien IDs nach (Bit 1 gesetzt). IDs unter 0x8000, ab 0x8000 stehen lokale Quellen (`<knoten>.detail`, `<knoten>.name`, siehe 8.3) |
| LAYOUT | 0 | Text der Slot-Zuordnung wie `layout.txt` des Compilers, eine Zeile je Slot: `<Art> <Bereich> <Namensraum>.<Slotart>[<Index>] <Name>`; abweichend vom Entwurf **kein** Namens-Hash, damit sich Savegames nach Namen migrieren lassen. `layoutHash` im Kopf ist der CRC-32 dieses Textes |
| SYMBOLS | 0 | `u16 count`, dann `u8 kind, u8 0, u16 id, u16 nameLen`, Name (aufgefüllt): alle Tabellensymbole (nur bei Flag bit0 des Kopfes) |
| TEXT | Sprach-ID | Zeichenkettentabelle nach Abschnitt 11: `u16 count, u16 0, u32 offset[count]`, Latin-1-Zeichenketten mit 0 abgeschlossen; Offset 0 = die ID hat keinen Text |
| TABLE | 1, 2 | Namenstabellen (Aufbau wie SYMBOLS): 1 = UI-Grafiken (`gfx`, `icon`), 2 = Cursor; die IDs sind die Positionen ab 1 |
| TABLE | ab 0x0100 | Zeichenkettentabellen des Spiels (Aufbau wie TEXT), z. B. im Prototyp Sprecher, Stichworte, Gegenstandsnamen und -beschreibungen |

**Lader:** `IPackReader` (`Header`, `Entries`, `Contains`, `Get` mit CRC-Prüfung und Entpacken) mit `MemoryPackReader` und `FilePackReader` (nur Kopf und TOC beim Öffnen, Chunks auf Anforderung); `PackContent` liest daraus Skripte, Karten, Screens, Natives, Layout, Symbole, Texte und Tabellen und legt den `Interpreter` mit den Grenzen und den globalen Größen des Kopfes an (der Layout-Hash der Datei muss zum Kopf passen). **Ladeprüfung (9.4):** `PackContent.RequireNatives(...)` wirft `MissingNativeException` mit den fehlenden Namen. **Fehler** eines kaputten Packs sind `InvalidPackException` (Magic, Version, Offsets, doppelte Einträge, Ausrichtung), `PackChecksumException` und `PackChunkNotFoundException`. **Cook:** `PackBuilder` macht aus dem Ergebnis des Compilers, den Screen-Definitionen und den Tabellen des Spiels ein Pack; `amberc pack <skripte> --out x.pack [--screens ordner] [--lenient] [--no-symbols]`, `amberc dump x.pack` zeigt alle Abschnitte.

---

## 10. Zustand und Savegame

### 10.1 Layout aus Namen

Der Cook vergibt Slot-Indizes in Deklarationsreihenfolge je Namensraum und schreibt zwei Artefakte:
- **LAYOUT-Chunk** im Pack und `layout/<release>.layout` im Repo (Text: `ns kind name -> index`).
- `layoutHash` = CRC32 über die sortierte Zuordnung.

### 10.2 Savegame (in M3 umgesetzt: `SaveData`, `SaveMigration` in `src/Amber.Pack`)

```
"AMSV" | u16 version | u16 reserved | u32 layoutHash | u32 rngState | u16 Tag | u16 Minute | u16 Tick
Snapshot Global | u16 mapCount | je besuchter Karte: u16 mapId, u16 nameLen, Name, Snapshot, tileChanges[], entityStates[]
u32 partyLen | PARTY (Bytes, vom Spiel geschrieben: Charaktere, Inventare, Gold, Rationen) | u32 crc32 über alles davor

Snapshot     = u16 flags, u16 vars, u16 vars32, Flag-Bytes (auf gerade Länge aufgefüllt), Vars (i16), Vars32 (i32)
tileChange   = u8 layer, u8 0, u16 x, u16 y, u32 tile          (u32 Anzahl davor)
entityState  = u16 id, u16 x, u16 y, u8 facing, u8 0, u16 routine   (u16 Anzahl davor)
```

Alle Zahlen big endian. Gegenüber dem Entwurf neu: der **CRC-32** am Ende (beschädigte Dateien werden als `InvalidSaveException` abgewiesen), der **Kartenname** neben der ID (die Migration ordnet Karten nach Namen zu) und die Größen im Snapshot (damit man ohne das Pack migrieren kann). `SaveData.CanSave(interpreter)` ist wahr, wenn kein Ablauf läuft oder wartet.

- **Kein Ablauf-Zustand wird gespeichert.** Speichern ist nur möglich, wenn keine Abläufe warten (Leerlauf) oder per `autosave` am Kettenende. Konsequenz: Zwischensequenzen sind nicht mitten drin speicherbar. Das vermeidet die Serialisierung von Ablaufzuständen und ist für v0 ausreichend.
- **Migration:** Beim Laden mit anderem `layoutHash` wird das Savegame anhand der alten Layout-Datei (`layout/<release>.layout`) auf das neue Layout **nach Namen** umgeschrieben. Der Cook erzeugt beim Release eine Migrationsdatei aus dem Vergleich zweier Layouts. Gelöschte Namen werden verworfen, neue mit Standardwerten initialisiert. *Umsetzung:* `SaveMigration.Migrate(alt, altesLayout, neuesLayout, neueKarten)` prüft, dass das alte Layout zum Hash des Savegames passt, übernimmt die Werte je (Bereich, Slotart, Name), setzt neue Namen auf 0 und wirft Karten weg, die es im neuen Pack nicht mehr gibt (Zuordnung nach Kartenname); das Ergebnis meldet die verworfenen und neuen Slots und Karten. Tile-Änderungen, Entities, Zufallszustand, Uhr und Party bleiben unverändert. `LayoutDiff` und `amberc layout-diff alt.layout neu.layout` zeigen den Unterschied (`-` entfernt, `+` neu, `>` anderer Index).

---

## 11. Texte

- Chunk TEXT je Sprache: `u16 count, u16 reserved, u32 offset[count]`, danach nullterminierte **Latin-1**-Zeichenketten. Text-IDs sind stabile Schlüssel (`T.name`), Sprachpacks können teilweise fehlen (Rückfall auf Sprache 0 mit Trace-Hinweis).
- Quelle: UTF-8; nicht darstellbare Zeichen sind ein Cook-Fehler (E012).
- **Markup** (Escape-Byte `0x1B` + Code):

| Sequenz | Bedeutung |
|---|---|
| `\n` (0x0A) | Zeilenumbruch |
| `0x0C` | Seitenumbruch (Warten auf Klick) |
| `0x1B 0x01 <Slot16>` | Wert einer Var einfügen (`{v:reputation}`) |
| `0x1B 0x02 <Target8>` | Name eines Mitglieds (`{name:active}`) |
| `0x1B 0x03 <n>` | Farbe wechseln |
| `0x1B 0x04` / `0x1B 0x05` | Schlüsselwort hervorheben (Anfang/Ende), wie in Amber-Dialogen |

---

## 12. Determinismus und Konformitätstests

### 12.1 Zufall

- **xorshift32** (Verschiebungen 13, 17, 5), 32-Bit-Zustand im Savegame. `rand16()` = obere 16 Bit des neuen Zustands.
- `chance(p)`: wahr, wenn `(rand16() * 100) >> 16 < p` (ganzzahlig, 32-Bit-Rechnung).
- `probe(target, attr)`: `rand16() % 100 < wert` (Wert in Prozentpunkten, auf 0..100 begrenzt).
- Jeder Aufruf verbraucht genau einen Zufallswert, auch wenn das Ergebnis feststeht, damit Zustände reproduzierbar bleiben.

### 12.2 Zeit

Logische Ticks zu **50 Hz**. Der Desktop-Host ordnet die Fensterzeit den Ticks zu (feste Schrittweite, keine variable). Spielzeit läuft in Minuten (Umrechnung im Host, dokumentiert im Pack-Header, Standard: 1 Spielminute = 100 Ticks).

### 12.3 Golden Traces

Eine **Szenario-Datei** beschreibt Auslösungen und Host-Antworten; jede Implementierung erzeugt ein **Trace-Log**. Zwei Implementierungen sind konform, wenn die Logs Zeile für Zeile identisch sind.

```
# scenario
seed 12345
load map M.spannenberg_keller
at 0   fire enter_tile x=3 y=4
at 10  answer say
at 30  battle_result 0
at 40  expect flag schrein_benutzt

# trace
tick=0  fire  step@map=3 (3,4)     -> group=L0 rule=0
tick=0  act   say text=42          -> blocked(say)
tick=10 resume result=0
tick=10 act   set_flag slot=0x0089
tick=10 act   battle group=7       -> blocked(battle)
tick=30 resume result=0
tick=30 hash  crc32=0x8C1A44E2
```

Zustands-Hash: CRC32 über Global-Flags, Global-Vars (BE), Global-Vars32 (BE), Map-Namensraum der aktuellen Karte, `rngState`, Party-Gold in dieser Reihenfolge. Details in M1 festgelegt.

---

## 13. Cook-Diagnosen

| Code | Art | Bedeutung |
|---|---|---|
| E001 | Fehler | Unbekanntes Symbol |
| E002 | Fehler | Doppelte Deklaration |
| E003 | Fehler | Typfehler (z. B. Flag als Var benutzt, falsche Operandenzahl) |
| E004 | Fehler | Gruppe existiert nicht |
| E005 | Fehler | `then` in Gruppe mit Modus `all` |
| E006 | Fehler | `then`-Zyklus, dessen Regeln alle unbedingt sind (Endlosschleife) |
| E007 | Fehler | `map`-Slot in globalem Kontext |
| E008 | Fehler | `or` ohne Klammern neben `and` |
| E010 | Fehler | Slot-Limit überschritten (Pack-Header) |
| E011 | Fehler | `else` nicht als letzte Regel |
| E012 | Fehler | Zeichen nicht in Latin-1 darstellbar |
| E013 | Fehler | Unbekannte native Funktion |
| E014 | Fehler | `push_screen` mit falscher Argumentzahl |
| E015 | Fehler | `here` in einem Kontext ohne Auslöseort (globale/Karten-/Screen-Bindung, `map_*`, `hour`, reaktive Trigger) |
| E016 | Fehler | Preset-Rekursion, Verschachtelung tiefer als 4 oder `use` eines Musters in einem Muster |
| E017 | Fehler | Preset: falsche Argumentzahl oder Argumentart |
| E018 | Fehler | Unbekanntes Preset |
| E019 | Fehler | Preset-Name kollidiert mit einem eingebauten Namen |
| E020 | Fehler | Trigger in diesem Geltungsbereich nicht erlaubt (fehlendes `at`/`in`, falscher Block) |
| E021 | Fehler | Bedingungs-Fragment mit mehreren Klauseln in `or` oder mit `not` verwendet |
| E100 | Fehler | Syntaxfehler |
| W001 | Warnung | Gruppe wird von keiner Bindung oder `then` erreicht |
| W002 | Warnung | Flag wird gesetzt, aber nie gelesen |
| W003 | Warnung | Flag wird gelesen, aber nie gesetzt |
| W004 | Warnung | `autosave` nicht am Ketten-Ende |
| W005 | Warnung | Regel nach einer unbedingten Regel in `first` (unerreichbar) |
| W006 | Warnung | `then`-Zyklus mit bedingten Regeln (mögliche Endlosschleife, begrenzt durch `maxChainSteps`) |
| W007 | Warnung | Lokales Preset verdeckt ein globales gleichen Namens |
| W008 | Warnung | Preset wird nirgends benutzt |
| W009 | Warnung | NPC hat mehr als eine Begrüßung (`greet`); die erste gilt |
| W100 | Warnung | Für einen Screen ist keine Signatur bekannt; ein unbekannter Name wurde als Screen-Variable angelegt (nur im nachsichtigen Modus) |

---

## 14. Reserviert für v1 (nicht Teil von v0)

Wird erst ergänzt, wenn ein konkreter Fall es verlangt:

- Aktion `goto(gruppe)` (dynamisch, ersetzt statisches `then`), `repeat`.
- Zähler-basierte Wiederholungen, `call`/`return`.
- Ausdrücke in Operanden (`add_var(x, y)` mit Var-Operand, Arithmetik).
- Rule-Flags (`w3` im RuleRecord).
- **Stufe 4 der Wiederverwendung: Laufzeit-Templates** mit Parametern (Bindung trägt Template-ID und Parameter, der Interpreter setzt sie in Operanden ein). Erfordert eine Kennzeichnung „Operand ist Parameter i", z. B. über die für Aktionen freien Bits `neg`/`or_next` im Befehlswort. Nur sinnvoll, wenn die Musterstatistik (M1.14/M4.5) zeigt, dass Stufe 1–3 nicht genügen.
- **Trigger `group_done(gruppe)`** („Regel/Gruppe X beendet"), als **Benachrichtigung** (neuer Ablauf, `result` als `trigger_arg`), nur für Gruppen mit Markierung `notify`. Nachrüstbar ohne Formatbruch (neue Trigger-ID, Hook im Ketten-Ende). Entscheidung nach der Musterstatistik.
- **`then` in `all`-Gruppen** mit sequentieller Semantik („die Kette der Regel läuft zu Ende, bevor die nächste Regel geprüft wird").
- Serialisierung von Ablaufzuständen (Speichern mitten in einer Sequenz).
- Opcode-Bereiche `0xE0..0xFF` (Bedingungen und Aktionen).

---

## 15. Offene Punkte für die Durchsicht

Durchgesehen am 2026-10-23 (Ergebnisse auch im Änderungsvermerk 2026-10-23). **Entschieden:**

2. **Namensraum `thread` (t0..t7):** bleibt (umgesetzt in Compiler, Interpreter und C-Laufzeit; Zwischenspeicher innerhalb einer Kette).
3. **Speichern nur im Leerlauf:** ja für v0 (so im Prototyp); `autosave` am Kettenende deckt Sequenzen ab, Speichern mitten in einer Sequenz bleibt v1 (Abschnitt 14).
4. **`once` für Truhen:** genügt; der Inhalt einer Truhe ist nativer Zustand und wird gespeichert, `once` braucht es nur für Einmal-Texte und -Ereignisse.
5. **Gruppen-Modus `all` ohne `then`:** genügt für v0; erneut prüfen zusammen mit Punkt 7.
6. **Opcode-Nummern:** reichen. Die Familien (0x10 Welt, 0x20 Party …) sind eine Ordnung, keine Grenze: ist eine Familie voll (0x20–0x2F ist es), kommen neue Befehle in einen freien Bereich (0x80–0xDF). Einzige Quelle bleiben die Opcode-Tabellen in `Amber.Script.Common`.

**Warten auf die Ambermoon-Daten** (für das eigene Spiel blockiert keiner davon):

1. **Trigger-, Bedingungs- und Aktionskatalog** gegen die Ambermoon-Event-Typen prüfen (z. B. `Decision`, `Award`, `ChangeBuffs`, `Create`).
7. **`then` oder zusätzlich `group_done`**, Entscheidung D11 anhand der Musterstatistik (M1.14/M4.5).
8. **Relatives Tile** (`TileRef16`): entspricht es Ambermoons „Tile im selben Tileset ändern“?
9. **Weitere Cursorarten oder Auslöser** in Ambermoon neben Auge, Mund, Ohr, Hand.
10. **Standard-Presets** (`std/presets.ams`) aus der Musterstatistik.

---

## 16. Änderungsvermerke

### 2026-09-19 – Umsetzung M1 (Compiler, Interpreter, Dump, Statistik)

Abweichungen und Ergänzungen, die sich aus der ersten Implementierung ergeben haben. Der Quelltext liegt unter `src/`, die Tests unter `tests/`.

- **Dump und Lader:** `ScriptChunk` (Common) liest Gruppen- und Bindungstabelle nach Abschnitt 6 mit Bereichsprüfung. `ScriptDumper` erzeugt daraus lesbaren Text; die Beispiele 6.2 und 6.3 werden **bit-genau** erzeugt (Test).
- **Nur infix ausdrückbare Bedingungen:** Bedingungen mit Vergleichsoperand (`var`, `var32`, `varvar`, `result`, `arg`, `gold`, `party_size`) werden in Quelltext infix geschrieben (`gold >= 500`, `reputation < 3`). **Offen:** `attr(target, AT.x) >= n` hat noch keine Quellsyntax; Vorschlag `attr(active, AT.STR) >= 20`, das der Compiler in `[target, attr, cmp, value]` zerlegt.
- **`ThreadContext`:** Der Host bekommt bei jeder Aktion/Bedingung `ThreadId`, `OwnerMap`, `TriggerX/Y`, `TriggerArg` und `Result` (Abschnitt 2.1 und 1.4). Blockierende Aktionen setzt der Host über `Interpreter.Resume(threadId, result)` fort. Der Interpreter behandelt `set_flag`…`copy_var`, `raise`, `wait`, `autosave` und die Bedingungen `flag`, `var`, `var32`, `varvar`, `result`, `arg`, `chance` selbst; alles andere geht an den Host.
- **`push_screen`/`replace_screen`:** Das Flag `nowait` (bit0 von `flags`) wertet der Interpreter selbst aus (blockiert nie).
- **Area-Trigger:** `TriggerContext` hat `X/Y` und `OtherX/OtherY`. `enter_tile`/`leave_tile` feuern bei Area-Scope, wenn `X/Y` in der Area und `Other` außerhalb liegt.
- **`map_tick`** wird vom Interpreter gezählt (`Tick()`); `flag_changed`, `var_changed` und `custom` laufen über die Warteschlange (R-4), die `Tick()` zu Beginn abarbeitet.
- **Cook:** Symbole (`T.x`, `I.x` …) bekommen im nachsichtigen Modus (`--lenient`) fortlaufende IDs ab 1; im strengen Modus sind unbekannte Symbole E001 (Tabellen-Loader folgt). Screen-Argumente und Knotennamen liest der Cook aus den Screen-YAMLs (`args`, `nodes[*].id` in Tiefensuche); ohne Signatur greift W100.
- **Deduplizierung (Stufe 3)** ist implementiert (`CompileOptions.Deduplicate`, `amberc --no-dedup`). Der Cook liefert `GroupRefs` (Gruppenname → endgültiger `GroupRef16`), damit YAML-Handler auch nach dem Zusammenlegen auflösbar bleiben.
- **Layout:** `CompilationResult.LayoutText` und `LayoutHash` (CRC-32 über den Text, Abschnitt 10.1). `amberc compile --out` schreibt `layout.txt`.
- **Musterstatistik:** `amberc stats` (Aufgabe M1.14) gibt Markdown mit Trigger-Verteilung, häufigsten Regelformen (Nutzungen / verschiedene Operandensätze), Kettenlängen, Fan-in, Duplikaten und Preset-Kandidaten aus.
- **Neu bei den Präfixen:** `DELTA.` (Tile-Änderungssatz). **Neu bei den Diagnosen:** E020, E021, E100, W009, W100.
- **Noch nicht umgesetzt:** Routinen werden geparst und pro Karte gemerkt (`CompiledScope.Routines`), aber noch nicht zu Wegpunkten gebacken. `W002`/`W003` (Flags nie gelesen/gesetzt) und `E012` (Latin-1) fehlen, ebenso der Tabellen-Loader für strenge Symbole und der Pack-Container (M3).

### 2026-09-19 – Prototyp (game/)

- **Area-Scope für Interaktions-Trigger:** `examine`, `speak`, `listen`, `use_item`, `cast_spell` und `interact` erlauben jetzt Scope 3 (Area), nicht nur Tile und Entity. Grund: Objekte, die mehr als ein Tile belegen (32×32-Steine, 48×32-Baumstämme), sollen von jedem ihrer Tiles aus untersuchbar sein (`on examine in (14, 18, 2, 1) -> stein;`). Das Bindungsformat ändert sich nicht (Scope 3 gab es schon), der Interpreter prüft `X/Y` gegen die Area wie bei `step`.
- **Kartenwechsel:** Kartengebundene Bindungen laufen nur, solange die Karte geladen ist (`map_tick`, Barks, Routinen der Karte). Beim `teleport` auf eine andere Karte entlädt der Host die alte (`UnloadMap(id, teleportThread)`), hält deren `StateStore` fest und lädt die neue mit `LoadMap(id, chunk, state)`; der Zustand einer besuchten Karte bleibt so erhalten. Der Thread, der teleportiert hat, läuft weiter und behält die alte Karte als Besitzer. `map_enter` feuert der Host nach dem Laden in der Regel im nächsten Tick, nicht innerhalb der Aktion (der Interpreter teilt sich einen Operandenpuffer, verschachtelte Trigger aus einer Aktion heraus sind unsicher). Globale Flags (`flag x;` auf oberster Ebene) sind in allen Karten sichtbar.

### 2026-09-20 – Screens als Daten (M2, Prototyp)

- **`native(N.name, argc, args...)`:** Neue Aktion für Host-Funktionen, die keine eigene Opcode-Zeile verdienen (Datenquellen, Spezialaufrufe eines Screens). Neues Symbolpräfix `N.`, die Namen stammen aus `natives:` in `tables.yaml`; der Interpreter reicht die Aktion unverändert an den Host. Nicht blockierend.
- **`Interpreter.RunGroup(chunk, group, arg, ownerMap)`:** Führt eine Regelgruppe direkt aus, ohne Bindung. Damit starten YAML-Handler (`on_click`, `on_select`, `on_open` …) ihre Gruppen. `arg` kommt als `trigger_arg` (`pop_arg`-Muster: der Wert einer gewählten Listenzeile). Screen-lokale Gruppen werden über `CompiledScope.GroupRefs`, globale über `Global.GroupRefs` aufgelöst.
- **`ThreadContext.ScreenKey`:** Der Host sieht bei jeder Aktion, zu welchem geladenen Screen der Thread gehört (`set_node`, `set_text`, `show_node` … wirken auf diesen Screen). Bei Threads ohne Screen ist der Wert `-1`. `LoadedChunk.Key` ist öffentlich.
- **`list`-Knoten:** neues Feld `columns` (Standard 1); `rows` zählt die Zeilen je Spalte, die Einträge füllen Spalte für Spalte. `on_select` startet die Gruppe mit dem Wert der Zeile als `trigger_arg`.
- **`transparent`:** Ein Screen ohne `transparent: true` verdeckt die darunterliegenden Screens (sie werden bis zum Zurückkehren ausgeblendet, `on_resume` läuft beim Wiederaufdecken). Alle Prototyp-Screens sind undurchsichtig.
- **Schema-Test:** `ScreenSchemaTests` validiert `examples/screens/*.yaml` und `game/content/screens/*.yaml` gegen `spec/schemas/screen.schema.json` und weist kaputte Dateien ab.
- **Prototyp-Natives:** `pop_arg` (schließt den obersten Screen mit `trigger_arg`), `conversation_ask`, `conversation_give`, `conversation_show`. Datenquellen für `bind`/`source`: `party.gold`, `party.words`, `party.items`, `conversation.title`, `party.words.hint`, `screen.<arg>`.
- **Noch offen (Stand 2026-09-20, siehe den Vermerk vom 2026-09-21):** Knoten `input` und `itemgrid`, Screen-Chunk-Format, „dirty"-Markierung.

### 2026-09-21 – Screens als Daten, Rest von M2

- **Neues Projekt `src/Amber.Screens`:** `ScreenLibrary` (YAML lesen, `extends`/Prefabs auflösen), `ScreenDefinition`/`NodeDefinition`, `ScreenSchema` (Schema als eingebettete Ressource) und `ScreenChunk` (Abschnitt 8.2/8.3). Prototyp, `amberc` und die Tests benutzen dieselbe Bibliothek; die zweite YAML-Leseroutine im CLI und die zweite Liste erlaubter Schlüssel sind weg.
- **Schema im Cook:** `ScreenLibrary.Load` prüft **jede** Datei gegen `screen.schema.json` und bricht mit Dateiname und Pfad des Fehlers ab (Aufgabe 2.1).
- **Screen-Chunk:** Abschnitte 8.2 und 8.3 sind geprüft und angepasst (Literaltabelle statt Gruppentabelle, Bit `bound`, Feldbelegung je Typ, Hotkey-Codes). Round-Trip-Test über alle Beispiel- und Prototyp-Screens (Aufgabe 2.3).
- **Knotenindex zählt alle Knoten:** `NodeIds` enthält auch leere Namen. Vorher ließ die Bibliothek unbenannte Knoten aus, das CLI zählte sie mit; beides ist jetzt gleich und entspricht der Knotentabelle.
- **`itemgrid`:** neues Feld `on_select` (Klick/Enter), `on_drop` für gezogene Gegenstände. **`input`** und **`itemgrid`** sind im Prototyp umgesetzt.
- **Symbol `CH.`** (Truhe, `SymbolKind.Chest`): Inhalt aus `chests:` in `tables.yaml`; der Truhen-Screen bekommt die Truhe als Argument (`push_screen(S.chest, 0, 1, CH.name)`) und schließt mit `1`, wenn sie leer ist.
- **„dirty":** Versionszähler je Datenquelle, siehe 8.4. **Passthrough:** Mausklicks in den Regionen eines transparenten Screens gehen an den Screen darunter, siehe 8.1.
- **Prototyp-Natives (neu):** `lookup_word`, `conversation_ask_result`, `chest_take`, `chest_put`, `chest_take_all`, `chest_take_gold`, `chest_close`. Datenquellen: `chest.items`, `chest.gold`, `input.message`.
- **Noch offen:** `passthrough` hat im Prototyp keinen Screen, der es benutzt (nur die Rechteck-Prüfung ist getestet, nicht das Weiterreichen selbst); `portrait`, `bar`, `image`, `viewport` fehlen im Prototyp; der Cook schreibt die Screen-Chunks noch nicht in ein Pack (M3).

### 2026-09-21 – Diagnosen und Golden-Trace-Harness (M1 abgeschlossen)

- **Diagnosen:** E007 (Slot einer Karte in einem globalen Skript; vorher meldete der Compiler nur „unbekannt", E001), E013 (unbekannte native Funktion `N.name` im strengen Modus, statt E001), W002 (Flag gesetzt, nie gelesen), W003 (gelesen, nie gesetzt), W004 (`autosave` nicht als letzte Aktion einer Regel ohne `then`). W002/W003 melden nur **selbst deklarierte** Flags (`flag x;`); die erzeugten Flags von `once` und Presets sind immer gesetzt und gelesen. `toggle_flag` zählt als Lesen und Schreiben, `flag_changed` als Lesen. **E012** (Zeichen nicht in Latin-1) prüft der Tabellen-Loader des Prototyps für Texte (`GameContent`) und `ScreenChunk.Write` für Literaltexte; der Compiler sieht keine Texte.
- **Golden Traces (12.3), Projekt `src/Amber.Conformance`:** `Scenario` liest die Szenario-Datei, `ScenarioRunner` führt sie gegen den Interpreter mit einem festen Host aus, `TraceComparer` vergleicht Zeile für Zeile. `amberc trace <szenario> [--out datei] [--check golden] [--update golden]` (Exit-Code 1 bei Abweichung oder fehlgeschlagener Erwartung). Beispiel: `examples/scenarios/schrein.scenario` mit `schrein.golden`.
- **Szenario-Datei:** Kopfzeilen `seed N`, `script pfad` (Datei oder Ordner, relativ zur Szenario-Datei, mehrfach), `load map NAME`, `end T` (letzter Tick, sonst der des letzten Schritts); Schritte `at T <befehl>`: `fire <trigger> [x= y= ox= oy= entity= param= arg= screen= node=]` (Werte Zahl, Symbol wie `I.key` oder bei `entity` der Name), `answer <aktion> [ergebnis]` (setzt den Ablauf mit der kleinsten Nummer fort, der auf diese Aktion wartet; ohne Wartenden ein Fehler des Szenarios), `battle_result N` (= `answer battle N`), `expect flag|var|var32|gold|item|word|threads|waiting …`, `hash`. Kommentare mit `#`. Vor jedem Tick laufen die Schritte dieses Ticks, dann `Tick()`.
- **Trace-Zeilen** (`tick=<Tick des Interpreters> <Text>`): `fire <trigger> <parameter>` und `fired <trigger> threads=n` vom Szenario, `start <trigger> chunk=<Art>:<id> binding=<n> thread=<n>`, `act <aktion>` / `act <aktion> blocked`, `resume thread=<n> result=<n>`, `end thread=<n>` vom Interpreter (Namen wie im Quelltext), `answer <aktion> <ergebnis> thread=<n>`, `expect … ok` / `expect … FAILED (expected a, actual b)`, `hash crc32=0x… gold=<n>` (nach dem letzten Tick immer eine Hash-Zeile). Der Hash ist der CRC32 des Zustands (Globals, Karte, Zufallszustand); das Gold des Hosts steht daneben statt im CRC. Der Host des Harness kennt Gold, Gegenstände und Wörter; die Uhr läuft mit den Ticks (Start 09:00, 6000 Ticks je Stunde); blockierende Aktionen warten auf ein `answer`.
- **Abweichung vom Entwurf in 12.3:** Die Beispielzeilen dort zeigen `group=`/`rule=` je Auslösung; der Interpreter schreibt derzeit `binding=` und nicht die gewählte Regel. Eine zweite Implementierung muss das Format oben Zeile für Zeile erzeugen.

### 2026-09-21 – Pack, Lader, Savegame (M3)

- **Neue Projekte:** `src/Amber.Pack` (Format, Schreiber, Leser, Tabellen, Lader, Savegame, Dump) und `src/Amber.Cook` (`PackBuilder`: Compiler-Ergebnis, Screens und Tabellen zu einem Pack). Der Chunk-Inhalt steht in Abschnitt 9.6, das Savegame in 10.2.
- **Entwurf angepasst:** LAYOUT als Text statt Namens-Hash; Datenquellen der Screens stehen in der NATIVES-Tabelle (Bit 1), lokale Quellen (`<liste>.detail`); für `itemgrid` ebenso, `<knoten>.name` ist der Text der gewählten Zeile als 0x8000|Knotenindex im Knotenrecord; RLE0 und Deflate wie in `Amber.GameData.Pyrdacor` (Kennungen 1 und 2 im Pack); Savegame mit CRC-32, Kartenname und Snapshot-Größen.
- **Konformanz:** `ScenarioRunner` läuft auch aus einem Pack (`pack datei.pack` im Szenario oder `amberc trace … --via-pack`); die Spuren aus Quelltext und Pack sind Zeile für Zeile gleich (Test `CookTests`). Dafür braucht das Pack den SYMBOLS-Chunk, damit Szenarien Symbole wie `I.amulett` auflösen können.
- **Prototyp:** `--build-pack datei.pack` kocht die Inhalte (Skripte, Screens, Texte, Stichworte, Gegenstände) und prüft sie; `--check-content` macht dieselbe Prüfung im Speicher, inklusive Ladeprüfung der Natives gegen `ScreenHost.Implements`. Der Prototyp läuft noch aus den losen Inhalten (Karten sind Tiled-Dateien, die Routinen der NPCs sind noch nicht gebacken).
- **Nicht umgesetzt:** Aufgabe 3.4 (die Loader des Amberstar-Ports auf `IPackReader` umstellen, „Amberstar-Start aus dem Pack“) liegt im Amber-Repo und braucht die Loader im Klon; die Präsentations-Packs (`gfx_<profil>.pack`, Typen ab 0x0100) und das Backen der Routinen fehlen.

### 2026-09-21 – Routinen im Pack, Speichern im Prototyp

- **Routinen gebacken (Abschnitt 7.4):** `RoutineBaker` macht aus den `routine`-Blöcken einer Karte Zeitpläne im MAP-Chunk: nach Gruppen und Bindungen `u16 Anzahl Wegpunktnamen` (`u16 len`, Name, aufgefüllt), `u16 Anzahl Routinen`, je Routine `u16 id, u16 entity, u16 nameLen`, Name, `u16 Einträge`; je Eintrag `u16 Minute, u16 Schritte`; je Schritt `u8 Art (0 walk_to, 1 stay, 2 sleep), u8 0, u16 Wegpunkt (0xFFFF keiner), u32 Ticks`. Die Einträge sind nach Uhrzeit sortiert, Dauern in Ticks, die ID ist die Nummer, die `set_routine` benutzt (je Karte ab 0). **Abweichung von 7.4:** Die Wegsuche macht **nicht** der Cook, sondern der Host zur Laufzeit; die Wegpunkte bleiben Namen, weil der Skript-Cook die Kacheln der Karte nicht kennt. Der Prototyp führt seine NPCs nur noch aus diesen gebackenen Zeitplänen aus (kein AST mehr), `--check-content` vergleicht sie mit dem Pack. Dabei ist ein Fehler verschwunden: `set_routine` suchte die Routine in allen Karten statt in der der Regel.
- **Savegame im Prototyp (F2 speichern, F3 laden, `--save datei`):** `SaveSystem` schreibt ein `SaveData` (Abschnitt 10.2): Global- und Kartenzustand der Skripte, Zufallszustand, Uhr, die Änderungen an den Karten (`set_tile`, `apply_delta`; Kollisionsänderungen als Ebene 255 mit Wert 1 = blockiert, 0 = frei), die NPCs (Position, Blickrichtung, Bit 7 = unsichtbar, Routine) und als Party-Blob Gold, Gegenstände, Wörter, geöffnete Truhen sowie Karte, Position und Richtung der Party, alles mit **Namen** statt IDs. Gespeichert und geladen wird nur im Leerlauf (kein Fenster, kein Kartenwechsel, kein wartender Ablauf, `SaveData.CanSave`). Beim Laden wird zuerst alles geprüft (Layout-Hash, Größen, Namen); erst dann ändert sich das Spiel, und es feuert kein `map_enter`. Eine Migration eines Savegames einer anderen Fassung fehlt im Prototyp (die Bibliothek `SaveMigration` gibt es, der Prototyp bewahrt aber keine alten Layouts auf).

### 2026-09-21 – C-Laufzeit (M6-Spike auf dem PC)

- **Ordner `c/`:** Pack-Leser und Regel-Interpreter in portablem C99 ohne Allokation (`amber_pack.c`, `amber_rt.c`), ein Szenario-Läufer (`tools/amber_trace.c`) und die von `amberc gen-c` erzeugte Tabelle `include/amber_tables.h` (Konstanten und Namen von Triggern, Bedingungen, Aktionen und Symbolarten aus den Opcode-Tabellen). Der C-Läufer erzeugt für alle Szenarien in `examples/scenarios/` **dieselbe Spur** wie der C#-Läufer (Test `CRuntimeTests`); der Pack dafür ist vom Amiga-Profil (`amberc pack --profile amiga`, Profil-ID 1): kein Deflate, nur none und RLE0.
- **Kompiler:** Die Thread-Variablen `t0`..`t7` (Abschnitt 1.2, Namensraum 3) sind jetzt im Quelltext benutzbar; vorher meldete der Compiler „unbekannte Variable“.
- **Screens in C (nachgezogen):** Screen-Instanzen (Laden, Entladen, `run_group`, Screen-Trigger, Screen-Zustand) laufen jetzt auch in C; Szenarien bekommen dafür die Befehle `open`, `close` und `run` (siehe Abschnitt 12.3). Native-Aktionen laufen wie im C# über den Host. Der Cook schreibt für einen `screen`-Block ohne YAML-Datei einen SCREEN-Chunk mit leerer Definition. Die Ausführung auf einem echten m68k (Toolchain, Emulator, Speicher- und Zeitmessung) steht aus.
- **Szenario-Befehle für Screens:** `at T open NAME [werte…]` lädt den Screen mit seinem Zustand (die Werte sind die Screen-Variablen 0.., also die Argumente von `push_screen`) und löst `screen_open` aus, `at T close NAME` löst `screen_close` aus und entlädt ihn, `at T run NAME INDEX [wert]` startet die lokale Gruppe INDEX des offenen Screens direkt (`RunGroup`) mit dem Wert als `trigger_arg`. `expect flag|var|var32 NAME.slot …` liest einen Slot eines offenen Screens. Spurzeilen: `open screen NAME werte`, `opened screen NAME threads=n`, `close screen NAME`, `closed screen NAME threads=n`, `run screen NAME group INDEX arg=n`, `ran screen NAME started=0|1`. Screen-Bindungen sind nur mit den Screen-Triggern möglich (`flag_changed`, `var_changed`, `custom` sind nur global oder in einer Karte erlaubt); die Zustellung reaktiver Ereignisse an Screen-Instanzen ist im Interpreter (C# und C) vorhanden, aber ohne ein Skript, das sie auslöst, nicht durch ein Szenario abgedeckt.

### 2026-09-21 – `map_exit` im Prototyp

- **Kartenwechsel mit Abschied:** `GameSession.SwitchMap` löst zuerst `map_exit` der alten Karte aus. Starten dessen Regeln Abläufe, die warten (`say`, `wait`, …), bleibt die Party auf der alten Karte (die Welt steht), und der Wechsel geschieht erst, wenn diese Abläufe beendet sind (`UpdateLeaving`, jeden Tick). Sonst wechselt sie sofort. Abgewartet werden nur die von `map_exit` gestarteten Abläufe, nicht der `teleport`-Ablauf selbst und nicht, was vorher lief. Der `teleport`-Ablauf läuft wie bisher weiter, sobald die Aktion zurückkehrt; seine restlichen Aktionen laufen also **vor** dem eigentlichen Wechsel. Beim Laden eines Savegames feuert `map_exit` nicht. Gespeichert wird währenddessen nicht (`SaveSystem.CanSave`). Neu im Interpreter: `ActiveThreadsOf(ownerMap)` und `IsThreadActive(id)`.

### 2026-09-21 – Kampf, Händler, Dungeon, Icons und `bar` im Prototyp

- **`battle` im Prototyp:** die Aktion öffnet den Screen `battle` und liefert das Ergebnis (0 gewonnen, 1 geflohen, 2 verloren). Abweichung von Tabelle 7.x: bei Niederlage kehrt der Prototyp mit 2 zurück, damit das Skript reagieren kann (Spielende bleibt der Sollzustand der Spec).
- **`bar`:** `kind` (hp, sp) und `slot` (1..6) laut Schema; die Werte liefert der Host (`IScreenHost.Bar`), das Widget zeichnet neu, wenn sich `party.<kind>` ändert.
- **Lokale Quellen:** neben `<knoten>.detail` gibt es `<knoten>.name` (Text der gewählten Zeile), für `list` und `itemgrid`; im Knotenrecord `0xC000 | Knotenindex` (Bit 14 = `LocalName`), der Index hat 14 Bit.
- **`itemgrid`:** Zellen zu 20 Pixeln mit Icon (Icon-Blatt des Hosts) und Stückzahl statt Textzeilen. Spec-Änderung nur im Host: `rows` und `cols` zählen Zellen.

### 2026-09-23 – Theme (Sprites/Farben für Fenster und Knöpfe) im Prototyp

- **`UiTheme`** (`src/Amber.Screens/UiTheme.csh`) und **`LookLayout`** (derselbe Ordner): spec-unabhängige Bibliothek, liest eine Theme-Datei (Sprites, Farben, Looks aus `rect`/`frame`/`tile`/`border`/`image`-Teilen, Zustände, Standard-Look je Knotenart) und berechnet daraus die zu zeichnenden Elemente (Farbflächen, Sprite-Positionen) für ein Rechteck. Reine Geometrie, kein Renderer-Bezug; `UiThemeTests` (in `tests/Amber.Tests`, mit den Fällen der früheren `LookLayoutTests`) decken Parser und Layout ab.
- **Prototyp:** `content/ui.yaml` (optional; ohne Datei bleibt alles beim eingebauten Aussehen), `LoadUiSprites` lädt die Sprite-Dateien, `UiKit.LookBox` (beides `Game/Ui.csh`) zeichnet Looks für `WindowWidget`, `ButtonWidget`, `BarWidget`, `ItemGridWidget` (mit Fallback auf das alte schlichte Aussehen, wenn kein Look passt oder Sprites fehlen). Ein Rahmen aus Sprites zieht seine Dicke als Innenabstand für einen `inset: border`-Teil derselben Look ab.
- **ClientArea (2026-09-23, Nachbesserung):** `at`/`size` eines `window`-Knotens sind die Innenfläche; `UiKit.BorderThickness(kind, look)` liefert die Randdicke vorab, `WindowWidget` zeichnet damit ein entsprechend größeres Rechteck (Rand liegt außen, nicht innen). Andere Knoten (Knöpfe, Listen, Text) rechnen weiter mit den unveränderten Bildschirmmaßen; sie mussten für das Theme nicht angepasst werden. Randsprites müssen dort transparent sein, wo kein Muster sein soll (Sprites liegen immer über Farbflächen) — `assets/ambermoon-ui/002–009.png` hatten ursprünglich reines Schwarz statt Transparenz an den Ecken, korrigiert (Alpha 0 für reines Schwarz).
- **Grenze:** ein `image`-Teil, dessen Sprite größer als seine native Größe gezeichnet werden soll (`stretch: true`), stellt die Textur mit dem aktuellen `Amber.Renderer.OpenGL` falsch dar (ungetesteter Fall: `ISprite.Size` und `ISprite.TextureSize` unterschiedlich). `border` und `tile` (native Größe, ggf. wiederholt) sind davon nicht betroffen.

### 2026-10-23 – Durchsicht Abschnitt 15, Paletten (Ziele Z4)

- **Abschnitt 15:** Punkte 2–6 entschieden (siehe dort), Punkte 1 und 7–10 warten auf die Ambermoon-Daten.
- **Paletten** (Konzept: Palettengrafik): Bilder sind Palettenindizes; Eintrag 0 transparent, die letzten 8 Einträge gehören der Oberfläche und ändern sich nie mit der Karte, der Tageszeit oder einem Effekt. Neues Symbolpräfix `PAL.` (Paletten-Tabelle, `.gpl`-Dateien).
- **Tag und Nacht macht der Host:** Jede Karte nennt in ihrer Tabelle eine Tagespalette und eine Nachtpalette (optional Dämmerung); der Host blendet nach der Uhr zwischen ihnen (nur die Kunst-Einträge). Eine Karte kann das abschalten (`daylight: off`), z. B. ein Dungeon mit eigenem Licht: dann gilt ihre feste Palette, Licht im Dungeon über `set_light`. Format der Karten-Tabelle (Vorschlag): `village: { name: Birkenfeld, palette: PAL.village, night: PAL.village_night }`, `hollow: { name: The Sunken Hollow, palette: PAL.hollow, daylight: off }`.
- **Neue Aktionen** `set_palette` (0x66) und `fade_palette` (0x67) für Ereignisse (der Schrein erwacht, eine Höhle mit Fackel): eine gesetzte Palette hat Vorrang vor Tag und Nacht, bis sie mit `0xFFFF` freigegeben wird; sie gilt für die Besitzer-Karte und wird beim Verlassen der Karte freigegeben. **`flash`** wirkt jetzt über die Palette.
- **Umgesetzt (2026-10-23):** Opcodes in `ActionTable` (Symbolart `Palette`, Präfix `PAL`), Compiler, VS Code-Grammatik, `amber_tables.h`; im Prototyp Host, Renderer und Pack (Paletten und Karten-Looks als Tabellen des Spiels). Freigeben mit `0xFFFF` (im Quelltext `0xFFFF` oder `65535`). **`flash`:** die Farbe ist eine 12-Bit-Farbe `0xRGB` (4 Bit je Kanal, wie beim Amiga). Tag und Nacht: Morgendämmerung 5–7 Uhr, Abenddämmerung 19–21 Uhr (Host).
