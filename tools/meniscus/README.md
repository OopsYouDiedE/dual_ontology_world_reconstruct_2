# A09 · The Meniscus Court — headless interface tests

From the repository root, run the project-local Godot 4.7.2 .NET console build:

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/meniscus/verify.gd
```

The runner uses only `layout`, `apply` and `snapshot`. It checks each golden twice: batched waits and single external ticks must produce identical states and timestamped events. `golden.json` contains all inputs and critical readouts. A failed assertion exits with code 1.

| Replay | Seal ticks | Exit tick | Simulated time | Measured CPU-side replay wall time (both modes) |
|---|---:|---:|---:|---:|
| North first; refill before recast | 228, 402 | 426 | 7.10 s | 11.428 ms |
| South first; cancelled trial and screened witness | 257, 429 | 453 | 7.55 s | 12.345 ms |

Recorded on the project-local Windows Godot `4.7.2.stable.mono.official.ed1daf0bf`: **439 checks, zero failures, exit 0**; runner 31.098 ms, console launch-to-exit 466.369 ms (PowerShell stopwatch). Simulated seconds measure model ticks; launch/replay numbers measure host wall time. No room, rendering or player input latency is measured here.

## Dynamic counterexamples

- **Hydraulic opportunity cost:** Two runs take the same inputs from the same initial state except for the North stamp at tick 228. Both immediately recast to South and take the gallery route. At tick 378 they have the same span, true South receiver, docked shuttle and 96 coolant from North. The earlier stamp leaves **26** South head; skipping it leaves **62**. Only the latter can stamp South at that moment (its North seal is still unset). The spent run recovers without a reset: recast North to refill, then South to stamp at tick 530 and exit at 554, keeping its original North seal.
- **Phase history:** Scheduling the same South change one tick later gives the same South walk and flow paths and the same folded glyph at tick 57. Vane phase 84 sends the early run to the dump; phase 83 lights the late run's real receiver. The bronze shuttle also lands at a different phase (18 vs 20). The outer clock is 57 ticks in both.
- **Folded mark and split causes:** At North Pier tick 180, a live receiver alone fails with `shuttle_out_of_dock`. At tick 192, the shuttle docks and the painted mark persists, but the receiver goes dark and `stamp` fails with `receiver_dark`. The shutter removes the mark without moving the vane or changing the direct path. At tick 228 the genuine receiver still works with the shutter closed.
- **Retiring span:** Support stays up throughout the 48-tick warning. Both standing on the span and starting a walk onto it before the deadline hold commitment until clear. A held thaw can be cancelled and tried again, with final commitment only after the actor reaches the pier.

## Likely fast red-team route

The map is a two-branch witness circuit with permanent seals. Common casting lines let the player recast from either pier, and the Far Gallery bypasses a second walk across a span. A white-box solver can prime one cistern with the opposite cast, cross, advance one tick at a time until `stamp_checks.available`, stamp, then wait for the wet gauge to reach at least **48** before ordering a recast: the 48-tick warning finishes filling it to **96**. It can take the gallery during that warning and read the next joint window from the public phase table or from `stamp_checks`. The comparison shutter is optional for a solver that already reads the real receiver contact. The small graph, serial seals and explicit readouts make this a likely quick solve; the headless runs establish the causal mechanics and coverage.
