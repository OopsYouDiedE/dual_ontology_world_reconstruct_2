# A05 view contract — The Afterimage Carriage

`preload("res://scenes/physics_lab/afterimage/AfterimageRules.gd").new()` is the sole authority. Call `reset()` on restart, `step_tick()` once per fixed 60 Hz physics tick, and `observe()` after stepping. `layout()` returns stable public geometry and labels; coordinates below are schematic, so the view can choose scale. Queue with `queue_action(verb, target = "") -> bool`; the first queued input is consumed on the next multiple of 20 ticks. A true return means queued, not applied; the outcome is in `last_action`. Idle implies `wait`. The rewind reel is **eight** beats (160 ticks), giving both swings and the prism throw room on the same replay.

| Site ID | Schematic (x,z) | Fixture/input |
|---|---|---|
| `hub` | (-2, 0) | `prism`: request clear/silver throw |
| `lamp` | (-3, -2) | `pulse`: flash a fixed, wired lamp |
| `bell` | (-3, 2) | `pulse`: ring a fixed, wired bell |
| `carriage` | (0, 0) | `pulse`: ring the carriage bell; `prism`: same shared throw |
| `exit` | (2, 0) | Winning landing |

`move` takes a site ID; `wait`, `prism`, `pulse`, `rewind`, and `escape` take no target. `escape` takes a permanent one-way service ladder from Carriage to Hub; draw it separately from the gangways (`layout().escape`). Static paths: Hub–Lamp, Hub–Bell. Dynamic paths: Hub–Carriage only while `west` + `clear`; Carriage–Exit only while `east` + `silver`. The player can ride the carriage through any swing. The model uses whole-pad moves at decision ticks; animate approved moves in strictly less than 20 ticks. Do not expose a continuous-physics shortcut or infer traversability from animation.

### `observe()` (dictionary; detached from model)

- `tick`, `next_decision_tick`, `player`, `form` (`clear`/`silver`), `alignment` (`neutral`/`west`/`east`), `won`, `walkable` (array of pairs of site IDs), `queued` (action dictionary or empty), `last_action` (`tick`, `verb`, `target`, `ok`, `reason`, `from`, `to`).
- `optics` = `{"receiver": "west" or "east", "revealed_gangway": [site, site]}`. In clear, show the West pickup and outline the West gangway; in silver, show the East pickup and outline the East gangway. The previous pickup loses its reflection; a revealed gangway outline only becomes a floor if it is also in `walkable`. Both pickups and both prism paths can be labeled on a fixed wiring plate.
- `signals` contains the current 20-tick pulses: `{channel: "light"/"sound", source: site, origin: "live"/"echo", start_tick, end_tick}`. The wired lamp reflects through the **present** prism, including when replayed. Show ringing and flashing independently; draw the echo at a fixture only for its surviving pulse. Put a visible wire on each fixed fixture; the carriage bell is live-only.
- `pair` is `{}` or `{tick, receiver, accepted, reason}` for the current beat. Illuminate both legs independently and show receiver confirmation for an accepted pair.
- `cues` contains `{kind, from, to, start_tick, due_tick}`. Kinds: `prism`, `swing`, `spring`, `rewind`. For `rewind` the endpoints are site IDs and the cue additionally gives `restore_form` and `restore_alignment` (projection at the rewind deadline; the exterior escapement keeps moving). Use continuous light/audio plus a filling physical meter for each cue. Existing paths stay valid up to their due tick; deadlines resolve before commands at that boundary. Telegraph motion with the drive, spring or a ghost target during the cue; keep the currently usable floor visually aligned until commit. A pendulum/spring scale can use `spring_due_tick` (`-1` when idle) to show the whole West lease.
- `reel` = `{capacity, recorded, tape, cursor, anchor, rewinding, replaying, can_rewind}`. `recorded` is how many beats are buffered. `tape` is an array of eight visible fixture IDs or `""` for blank when full (partial earlier); no pawn on blank beats. `cursor` is the number of beats already played on the echo reel; `0` on rewind commit. Section marks can use exactly eight segments. During playback the recording head is disengaged. `can_rewind` reports legal rewind *now* (requires full reel, an anchor on Hub/Lamp/Bell, no swing/prism cue, no echo, no already-active rewind; a spring return may coexist).

### Visual read

Use one room, five labeled footprints, and a single ferry plate that visibly swings from a neutral position. Pair two fixtures on the same beat: the lamp chooses the receiver via the prism; either bell gives the pressure/sound leg. Draw the same-beat receiver confirmation where both visible traces converge. Clear and silver need distinct silhouettes (transmitting vs. reflecting), in addition to color. Crossing, cooldown and past pulses are model state, so keep text, bridge collision and highlight synchronized with `observe()`. Exact equations and counterfactuals are in the separate model notes/test, not required by the scene.
