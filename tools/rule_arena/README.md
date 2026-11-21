# Night Watch: ten-room rules arena (referee guide)

The entrant is an author. Sol gets 40 minutes to write a JavaScript policy. After the deadline the organizer runs the frozen file, without author intervention, paired against the reference on the same held-out draw and under the same ABI/watchdog. The tournament has not been played against Sol.

## Run from repository root

```sh
npm ci --prefix tools/rule_arena
node --test tools/rule_arena/arena.test.mjs
node tools/rule_arena/arena.mjs run --seed 42 --out .runtime/rule-arena/run.json
node tools/rule_arena/arena.mjs replay --in .runtime/rule-arena/run.json
```

Use Node 24 (tested on 24.14.1). Omit `--seed` for a fresh draw, or add `--bot path/to/submission.js`. In Godot 4.7.2 .NET, run `scenes/rubber_whitebox/rule_arena/RuleArena.tscn` with F6. It launches the same Node referee and plays the adjudicated tape. Use `-- --arena-replay=ABSOLUTE_RECORD_PATH` as Godot user arguments to inspect an existing game. Space pauses, X changes playback rate, N advances a room, Tab changes framing, V displays the captain’s last actual 3×9 scan. A dot is a miss or an unlit nearest surface. Spectator controls never reach the bot. For a real Forward+ smoke test including screenshots, run `.runtime/python/Scripts/python.exe tools/testing/rule_arena_capture.py` in the configured project environment.

## What is being solved?

Each room has a control booth followed by an existing Night Watch blockout. The captain stays at the controls until release. The generator collapses room slots subject to wing and uniqueness constraints; it varies the booth geometry, instrument positions, sockets, seals, windings, timing and loading limits. The original room plans provide the traversal geometry. The three booklets are different executable predicate trees. Each alone accepts only compatible lifts with extra dwell time. In a party, those individually safe choices can put two figures on the same winding. Later rooms add clearance and contact constraints. Observing a compatible carriage both extended and retracted earns evidence for changing one companion’s rule; forcing an order risks panic, disobedience and loss of sanity. The game currently varies one family of load-and-phase puzzles across ten stages. Passage after a successful release is automatic.

`physics.mjs` specifies ray intersections, light gating and phase/AST primitives. `game.mjs` owns all encounters, random draws, observations and verdicts. The Godot view reconstructs the simulation; renderer lighting is illustrative, the scored light model is per-surface. If the reviewed blockout changes, regenerate `blockouts.json` with project Godot `--headless --path . --script res://scenes/rubber_whitebox/rule_arena/ExportPlans.gd` and rerun both test suites.

### Why a generated run always has a route from spawn

1. Choose distinct windings and one compatible lift per active role first. The captain’s lift carries a native seal. Set the lift phases so that all selected lifts have enough support at a shared anchor beat.
2. Center the torque band and set the contact plate from that assignment. Gear bias vanishes at the anchor. `certificate()` checks the assignment against actual load and release predicates on every game creation; no reroll or brute-force timeout.
3. The booths place instruments on separated bearings. Three headings cover the circle; dwelling for 13 beats at each observes each required carriage lit in both positions. The captain can issue proofs/bookings from the console while calm, then wait at most one 120-beat superperiod for the anchor. `witness.mjs` exercises this with the real observation/command path, including all receipts.
4. Per-room conservative budget: 42 beats to scan/turn, 2 for orders, 120 for the window, 10 for transit. Ten rooms × 174 beats × 20 steps = **34,800 steps** out of 36,000. This is an existence guarantee from spawn; an unsafe command can still kill a party. The independent reference never reads the construction witness.

### Replay and budgets

The adjudicator runs the entrant in a QuickJS WASM interpreter in a worker; only a serialized observation goes in and an integer comes out. One call per simulated step; 27 rays every twentieth step. The referee measures wall time including handoff. A deadline violation discards that action, terminates the worker and waits out the remaining cycle; guest memory is then reset. Use an idle, fixed machine for paired matches. A fixed seed **and accepted action tape** reproduce the verdict; a machine under CPU contention can interrupt a live policy at a different step.

Only version, seed, source digest, final tick/result and non-zero `(tick,action)` pairs are recorded as compact JSON. Replay regenerates state from those pairs. Use the matching referee revision. Keep the richer `--view` output private and temporary. In the seed-42 sample JSON occupied 1,063 bytes; the same object as PyYAML default block YAML occupied 1,638 bytes. Parsing 500 times locally took about 8 ms with Python `json` versus 408 ms with PyYAML `CSafeLoader`.

## Conduct an actual blind match

```sh
node tools/rule_arena/match.mjs prepare .runtime/rule-arena/match-01
node tools/rule_arena/match.mjs clock   .runtime/rule-arena/match-01
node tools/rule_arena/match.mjs score   .runtime/rule-arena/match-01
```

Run these as separate organizer steps. `prepare` needs a **new directory** with an existing parent. Preserve the published commitment before handing out the packet. Give Sol an isolated author workspace containing **only** `author/`; do not expose the repository, `referee/`, reference policy or organizer guide. Use separate OS permissions or a separate machine and a submission drop to mirror atomic `submission.js` saves into the watched directory. Start `clock` when the author receives the packet; it snapshots the last complete file observed before the deadline (100 ms polling). Keep the clock process alive. `score` checks hashes, runs 32 paired games sequentially and saves both action tapes and `referee/score.json`. Archive Node version, machine/load, commitment, frozen hash, score and referee revision. Do not treat a broken submission, a setup fault, or host scheduling noise as evidence of puzzle difficulty. Review loss causes and the last scans and orders before attributing failure.

## Regression evidence

- 1,024 generation seeds for the certificate and native-booklet invariant; 32 optical-policy replays; 8 end-to-end construction witnesses including unsigned seed boundaries. Tests also cover shadows, panic, deadlines and interpreter interruption.
- Separate official-budget runs on **public regression seeds 0–31**: 32/32 reached Main Camp Hall; 6,400–9,840 steps, average 7,564.375. These are development seeds, not Sol's blind match.
- On RTX 3070, 1280×720 Forward+, the seed-42 MCP traversal reached camp at tick 9,060. In a sample of 888 rendered intervals across rooms, median 16.666 ms, p95 19.154 ms. This sample reaches the 60 FPS median target, with frame-time excursions above it.
