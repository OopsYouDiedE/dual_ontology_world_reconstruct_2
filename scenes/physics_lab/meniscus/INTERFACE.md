# A09 · The Meniscus Court — public interface v1

`res://scenes/physics_lab/meniscus/Model.gd` extends `RefCounted`. `Model.new()` starts a fresh run. The headless runner and any future room use the same three methods:

| Method | Contract |
|---|---|
| `Model.layout() -> Dictionary` | Static room/port IDs, English labels, integer plan coordinates (`x`, `z`; 100 units = 1 m), fixed walk edges, cast guide IDs, phase and hydraulic rules. |
| `model.snapshot() -> Dictionary` | Detached, JSON-compatible state at the current external tick: player/travel, casting/warning, walk graph, flow/head, both bubble phases, optical paths and endpoints, stamp checks, seals, outcome. |
| `model.apply(command: Dictionary) -> Dictionary` | `{ok, reason, events, state}`. `reason` is a stable English identifier (empty on success); events have `tick`, `id` and payload. State is the resulting snapshot. Rejected input is atomic. |

| Command | Meaning |
|---|---|
| `{action: "wait", ticks: 1}` | Advance 1–600 external ticks at 60 Hz. A real-time host can call this with one tick per physics step. |
| `{action: "move", target: "north_sill"}` | Start a 12-tick walk along a currently published `walk_edges` edge. `player.room` stays at the origin until arrival; `player.travel` gives `from`, `to`, `arrive_tick`. |
| `{action: "cast", target: "north"}` | Pull the common casting line from any standing room. `north`, `south`, `liquid` are legal targets. Schedules a change for tick +48; one request at a time. |
| `{action: "cancel"}` | Pull the common cancel line; the old form and all elapsed phase/head changes remain. |
| `{action: "screen"}` | Toggle the comparison shutter; repeatable, leaves the working beam and hydraulics alone. |
| `{action: "stamp"}` | At the active pier, use the directly lit receiver with a docked shuttle and sufficient head on both sides. The two permanent seals unlock the exit edge; walking into `exit` wins. |

Actions other than `wait` take place at the current tick and require standing. Terminal runs accept only `wait`, which holds the terminal tick. At each elapsed tick: advance the two bubble entities and hydraulics under the old form, finish due travel, then attempt any due cast. A cast applies its new conductance, support, optical path and rate table together; the first phase/head increment under that form follows one tick later.

## Room binding and cues

- `form`, `support.{guide, span}`, `walk_edges`, and `pending.{target, due_tick, interlocked, retiring_span}` are authoritative. Treat IDs from `layout().guides` as the same casting entity across floor support, fluid, light, and phase cues. Support remains live for the full 48-tick warning (0.80 seconds); an occupied retiring span or a walk touching it holds the change. `cast_warning`, `cast_held`, `cast_committed`, and `cast_cancelled` carry tick-stamped transitions. ArchBuilder can supply fixed bays/piers from the plan; bind collision and the pending cast overlay to the published walk graph. Use HallFinish for opaque stone/metal; draw glass, beam segments, and the projected mark as distinct overlays. No view or project changes are required by the model.
- `flow.paths` lists arrays of named ports and `flow.head` publishes both gauges. Liquid drains to the return; casting a lane supports that span, diverts water to the opposite cistern, and leaves the cast-side cistern to drain. The wet lane gains one unit each external tick (cap 96); other gauges lose one every third external tick. A stamp draws 48 units from its own cistern (minimum working head 54) and 72 from the opposite cistern. The opposite gauge is the next branch's reserve.
- `bubble.shuttle` and `bubble.vane` expose `phase`, `notch`, `rate`, `turns`. There are 12 integer units per notch, 8 notches per turn. Casting changes the units advanced per external tick and preserves accumulated phase. The shuttle's indexed position and the ceramic vane's ray direction are independently readable. External travel, countdown and head continue at 60 Hz.
- `optics.direct` and `optics.folded` list ordered port IDs for integer-plan ray polylines. `receiver` names a live electrical/optical contact (`""` for none); `mark` names an identical-looking painted registration glyph formed by the folded leg (`""` for none). The comparison shutter clips only that leg. `stamp_checks` gives each pier's `receiver_lit`, `shuttle_docked`, `head_ready`, `coolant_ready`, and `available` so the projected glyph can be tested against the actual contact. The exit edge is permanent once enabled. Labels in `layout()` and runtime `notice.text` are English.
