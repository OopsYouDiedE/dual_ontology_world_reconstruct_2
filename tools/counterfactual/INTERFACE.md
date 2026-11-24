# A08 · The Tempered Span — minimum view contract

`res://scenes/physics_lab/counterfactual/Model.gd` is a standalone `RefCounted` referee. Instantiate it once per attempt. The view reads snapshots and forwards sampled input; physics, timing, forecasts and verdicts belong here.

```gdscript
var machine = preload("res://scenes/physics_lab/counterfactual/Model.gd").new()
# At the next 60 Hz physics callback (same input encoding for live and replay):
machine.step({"press": "move", "target": "jack", "hold": ""})
var frame: Dictionary = machine.observe()
```

### Real time, input and replay

- `step(input = {})` advances **one** exterior tick, including waits. Send one optional `press` edge and/or one optional `hold` level. Missing fields mean idle/released. Never send a held key as a fresh edge every tick unless that is the input to record. Polling `observe()` or `sample_proof()` takes no ticks. `reset()` starts a new attempt; victory freezes its last tick.
- On resulting tick `t`: increment both clocks, commit due mechanisms, apply the edge, apply the level if available, cool/heat and form, then stamp any new mark. At a successful splice, the captured local state is restored exactly and its thermal update resumes the next tick. Presses that coincide with a deadline act after the commit. Transit is 12 ticks; the destination is available on the arrival tick.
- Edges: `move` + `target`; `cut_pin` at Kiln; `mark`, `rewind_home`, `rewind_bench` at Start; `arm` at Yoke; `queue_cross` at a usable approach; `cancel`. `move span` requests immediate entry; `queue_cross` asks the entry latch to pick a certified future tick with ≥48 ticks of notice. A queued rider can withdraw, and a boarded rider can pull the independent safety trolley back.
- Levels: `haul`/`pay_out` at Jack; `heat` at Kiln with pin out; `raise`/`lower` at Weight; `tighten`/`loosen` at Brake. `active_hold` names the working control; holds are released while walking, working through a splice/pin deadline, or with a proof active.
- Receipt: `{ "inputs": [{"tick": 1, "press": "move", "target": "jack"}, {"tick": 13, "hold": "haul", "for": 43}] }`. 1-based exterior ticks, idle in gaps. `for` repeats a level; a `press` in that row still fires once. `Replay.gd` rejects overlapping edges or multiple competing levels. `play.gd -- --pace` feeds these same inputs on the real 60 Hz `physics_frame` signal.

### Minimum rendering fields

| Frame fields | Use in the view |
|---|---|
| `tick`, `local_tick`, `drum_phase` | Engraved independent counters. The exterior eccentric is 120 ticks per turn. |
| `place`, `travel`, `objects`, `links`, `crossing`, `won` | Eight named stations, two service paths on each side of the shared yoke, walking and trolley animation. `links` is geometry; the entry latch checks `proof`. `crossing` records `from`, `start_tick`, `due_tick` until completion/retreat. |
| `retained.preload`, `retained.bend` | Cable teeth and copper bend, both measurable and outside the splice. |
| `local.pin_intact`, `local.heat`, `local.ballast`, `local.brake` | Keeper pin, kiln heat, ballast slide, brake setting. `marks.home` and optional `marks.bench` are detached witness cards with local values, `saved_at_tick`, `saved_drum_phase`, and `local_tick`. Give both marks separate columns even at the same exterior drum phase. |
| `readings` | Current tension and signed shoe offset, separate thresholds (`min_tension`, `shoe_limit`), current load, signed side shift, and piston position (`draw_q16`, sixteenths of a division). With no rider these are unloaded readings. `forming_target`, `forming_heat`, `seat_leverage` are the observable hot-forming gauges. |
| `proof` | `stage` is `parked`, `arming`, or `live`. An active proof has `armed_tick`, `start_tick`, `end_tick`, and its locked settings. `windows[approach]` groups *entry* ticks into inclusive ranges; `next_entry[approach]` is the first available tick after the current frame or `-1`. `forecast[approach]` tests the next input tick; `best_trial[approach]` shows the strongest available full-cycle trial, including both worst margins and the first failed sample. `queued` carries the release flag when set. Two trials with the same extent and different approach can have different side loads. |
| `cues`, `event` | Draw cue banners/flags continuously over `[start_tick, due_tick)`. List entries carry English `text`. `event` is the most recent emitted event, including its tick; it persists on idle ticks. |

`sample_proof(approach, entry_tick, rider_offset)` reads one predicted rider sample with the same fields as current tension/seat. It works while armed, for offsets `0..47` and any entry for which all 48 samples are on that draw. It returns `{}` outside that domain. Show loaded cable tension and shoe seat side by side; never derive entry permission from an unloaded needle, a mesh, or the outside phase alone. Object names, cues and denial text are already English.
