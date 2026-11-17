# Terra batch — 2026-11-17

Commit: `5571db5e0b6af1a87bb605c743fb05e0ec2a9fe3`  
Session: `b6148b29db7c0ec6`  
Runtime receipt: `.runtime/mainline-runs/2026-11-17T15-47-47-12700`

This independent English-language run began at the production title screen and used **New Game**. The route reached the bedroom, corridor, and B Wing kitchen. It collected two of seven kitchen clues through the live in-room sampling flow.

## Observed route

- **wake** — The detective woke in R05, stood up, inspected the bed through an in-room camera move, and opened the bedroom door. Visible spoken lines included “Where am I? I remember my name, but nothing since I arrived.” and “Someone's in the corridor.”
- **corridor** — The detective joined Huo Duo, Shen Ding, and Su Ling. Each was selectable by an in-world marker. The route communicated a wet sleeve, hand scratches, a broken string, a requested crank pin, and a locked room; the Kitchen marker then transferred the party.
- **kitchen_evidence** — The B Wing kitchen displayed seven-clue progress, physical boot/heel trace decals, and a `Drag to sample` macro interaction. Both sampled clues completed and raised the counter from `0/7` to `2/7`.

## Findings from visible frames

- The corridor and kitchen room boundaries rendered as large white voids beyond the architectural shell. The corridor has visibly saturated yellow/red interaction diamonds.
- The kitchen evidence close-up clearly showed boot/heel trace decals and a wet/fiber-like floor trace. On the heel-mark macro still, the detective mesh intruded into the lower-left of the evidence frame.
- All inspected dialogue and prompts were English. The observed spoken lines stayed within the stated 12-word limit; prompts were concise.
- The final audio postprocess failed on graceful session close. `audio-live.json` is retained as live telemetry only; no final audio score is reported.

## Measurements

- **wake:** steady `P95 9.507 ms`, `P99 13.319 ms`, `steady_spikes_over_33_3_ms 0`.
- **corridor:** steady `P95 7.088 ms`, `P99 7.409 ms`, `steady_spikes_over_33_3_ms 2` after live interaction.
- **kitchen_evidence:** steady `P95 7.140 ms`, `P99 10.040 ms`, `steady_spikes_over_33_3_ms 3` after live interaction.

No Astra reference image or canonical plot outline was used in this run. Those two comparisons remain unmeasured.
