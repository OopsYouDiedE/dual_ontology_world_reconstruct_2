# A03 · The Palimpsest Switchyard

[Scene-facing contract](INTERFACE.md) · [Machine replay fixtures (spoilers)](golden.json)

## Player rules

1. **Ink.** Choose socket I, II, or III. The cart takes that rail, stamps the same value into the bay's lift gate, and records it on the tape. Each bay can be stamped once. Leave every bay inked before going through the Turn.
2. **Rewind.** The lift reads that tape last stroke first. Its mirror swaps I and III; II stays II. The pin under the lift rotates that mirrored setting by zero, one, or two sockets. The lift takes the resulting rail and cures the bay it just left.
3. **Exit.** Cure each bay once. A capped rail, revisit, or early terminal stops the attempt. Take the Exit after the last cure.

**Controls for presentation:** `1` / `2` / `3` selects a rail and projects its ghost; `E` commits. At the Turn, project the rewind ghost and use `E` to start it. `R` replaces the model at a quiet boundary for a fresh attempt. Keep the full two-deck rail survey available during planning. The ghost shows 40 simulated ticks: one outbound travel and a dwell, or two consecutive lift strokes. Draw source/destination and rail in-world; a red ghost marks a predicted failure. `step_tick()` takes one 60 Hz simulation tick, and every stroke resolves exactly at tick 20 of its travel.

## Why the two routes constrain each other

A proposed ink edge fixes both a **local setting** and a **time-indexed pulse**. Let `p[i]` be the socket taken at ink step `i`. If rewind stroke `k` happens to be at the bay inked in step `j`, its lift socket is `(2 − p[71 − k] + p[j]) mod 3`. A changed ink detour alters the gates on those bays *and* the timestamps of the pulses that reach other bays. The lift route must satisfy both effects while preserving its own ability to visit every bay. There is no lift steering, pass action, tape edit, or repeatable stroke.

The rail maps and every gate setting are inspectable. For example, a pin at III plus a pulse of II takes lift socket I: `(2 − 1 + 2) mod 3 = 0`. When the reversed pulse comes from the very bay the lift is leaving, the settings cancel to socket III. This holds for the first and last lift strokes on any winning route. Each unused bay also needs a remaining way in and out on its deck. Those are useful pencil-and-paper checks when a local branch would cut off a pocket. The Turn and Exit are unique directed rails; using a shortened route to either triggers its coverage interlock.

## Verification

From the project root:

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/palimpsest/Verify.gd
```

- `golden.json` lists public actions and exact bay visits for the winning replay. It reaches the Exit at tick **2880** (72 ink strokes, 72 lift strokes). The only input after recording is `rewind`.
- Two recorded detours both ink all 72 bays and pass the 40-tick ghost. Their lift routes jam on strokes **8** and **57**. The test also compares projected and live transitions tick-for-tick, checks early Turn/Exit and capped-socket guards, and checks that reading forward, dropping the pins, or dropping the mirror each breaks the golden return.
- The **20-hour independent legal-solve gate is pending**. Give the independent tester the model and inspectable rules; keep the replay and witness-derived cases with QA.
