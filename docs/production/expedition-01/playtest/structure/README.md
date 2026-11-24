# First expedition: paired A/B structure playtest

**Question:** How does an offset portal in the A1 Immersion Arcade affect approach and traversal under the existing Human Sol policies?

- **A — stock arcade.** The harness instantiates the current `Expedition.tscn` and leaves the scene geometry alone.
- **B — offset portal.** The same scene receives three opaque, colliding mesh boxes at world `x = 4.50 m`. Jambs span `z = −2.22…0.65 m` and `1.85…2.22 m`; the lintel leaves a `1.20 m` wide and `2.20 m` tall opening centered at `z = +1.25 m`. The stock spawn at `x = 1, z = 0`, looking toward `+x`, now faces a jamb. The shared floor, exits, mechanics, labels and Human Sol controller stay in place. This treatment changes both visibility and walkable clearance; it estimates their combined effect.

At tick 8 both arms test the same two horizontal rays at `y = 1.57 m`. The center ray must be clear in A and blocked in B; the offset ray must be clear in both. The existing camera-based depth proxy must detect the portal face only in B. These checks are recorded outside policy input. The B mesh owns a static collider in the form already recognized by the depth proxy.

## Reproduce

From the repository root, with the project-local Godot 4.7.2 .NET and existing imports ready:

```powershell
$env:DOTNET_ROOT = 'C:/Program Files/dotnet'
python -B docs/production/expedition-01/playtest/structure/run.py --seeds 31 113 --ticks 7200
```

The runner stages a copy of the existing SceneTree test driver under a new ignored `.runtime/structure-*` directory. It adds only geometry installation, the diagnostic sample and report fields; policy, sensor, trace and lightweight-fixture helpers load from their existing paths. Each case runs serially, in its own Godot process and user-data directory at fixed 60 Hz, headless. Layout order alternates AB/BA across the matrix. Within each profile/seed pair, the runner checks equality of the sampled policy settings. Seeds control Human Sol's reaction and movement parameters and seed the scene RNG; the investigation uses the fixed first-expedition route. `--godot` and `--timeout` override the launcher and per-case wall limit. The ordinary Godot project and active campaign are left in place; no import or project build command is run.

`pairs.json` lists both arms, deltas and input hashes. Each case records its command, geometry check, decision trace, player and Hale paths, in-game events, and logs. The runner exits nonzero on an invalid pair, an engine error, a failed geometry check, or a detected change in the recorded input files. `tick_budget` and game-level `failed` are separately reported outcomes. The hash manifest identifies the launcher and local expedition scripts/scene/project inputs; replay also depends on the repository's transitive assets and installed engine.

## Executed results — November 24, 2026

Run directory: `.runtime/structure-565b9cfbef/`. All **12 cases / six pairs** passed the geometry, policy-parameter and process checks. Recorded input hashes stayed unchanged. All cases advanced past the test plane and reached the 7,200-tick budget without an ending card.

| Profile | Seed | First sample beyond portal, A → B (tick) | First different decision (tick) | Δ path (m) | Δ longest dwell (ticks) | Max x, A → B (m) |
|---|---:|---:|---:|---:|---:|---:|
| cautious | 31 | 612 → 636 | 323 | −1.88 | −43 | 35.61 → 35.61 |
| cautious | 113 | 600 → 612 | 321 | +0.88 | −265 | 35.61 → 35.61 |
| curious | 31 | 408 → 408 | — | 0.00 | 0 | 33.67 → 33.67 |
| curious | 113 | 396 → 396 | — | 0.00 | 0 | 35.61 → 35.61 |
| direct | 31 | 516 → 516 | 337 | −73.53 | −232 | 35.61 → 34.05 |
| direct | 113 | 504 → 504 | 335 | −2.62 | −1 | 35.61 → 35.61 |

Deltas are B minus A. First-sample passage means the walker center reaches `x ≥ 4.80 m` in the observer trace (12-tick cadence, 0.2 s); this is a sampled threshold. First different decision compares ordered `decision_trace` records; a dash means both traces matched. Path length uses per-tick displacement over the entire run. Longest dwell is the existing Human Sol measure of time without more than 0.65 m of net progress from its current anchor. Maximum x is a position diagnostic rather than an objective milestone.

**What moved:** Both cautious runs shifted their approach toward the opening and reached the threshold one or two samples later. Both curious traces followed the same approach and subsequent actions in A and B. Direct crossed on the same sampled ticks in both layouts, but seed 31 produced a different later sequence: A logged the gate prompt and accumulated 138.57 m of travel; B logged Hale's lock confirmation and accumulated 65.04 m. Keep that seed-specific downstream change separate from the local portal crossing metric.

**Design use:** This is evidence about simulated sightline response, route progress, and policy sensitivity. The next useful comparison would isolate visibility from clearance and use human observation to assess whether players notice and understand the opening. This run measured no player enjoyment, perceived legibility, or rendered visual quality.

### Offline design-review page

Starting with a completed structure matrix, the exported scene collision footprint file and the local render dependencies, run the following from the repository root. The page reads no remote resources. Its default film uses the **live** input captures; the expandable second film uses a fixed-heading path replay. The two candidate whole-map plans are graph proposals and their video is an animated topology diagram.

```powershell
$p = 'docs/production/expedition-01/playtest'
$o = '.runtime/design-review'
python -B "$p/structure/film_live.py"
python -B "$p/structure/film.py"
python -B "$p/structure/join_films.py" "$o/live-A.mp4" "$o/live-B.mp4" "$o/live-paired.mp4"
python -B "$p/structure/join_films.py" "$o/A.mp4" "$o/B.mp4" "$o/paired.mp4"
python -B "$p/complexity/review_plans.py"
python -B "$p/complexity/review_video.py"
python -B "$p/clutter/design_review.py"
python -B "$p/structure/review.py" .runtime/structure-565b9cfbef .runtime/collision_fixture_geometry.json $o
```

On this run, both live recordings reproduced every sampled player position and decision in the first 720 ticks of their corresponding historical trace. Route maps show player and companion positions sampled every 12 ticks; the event list preserves the event's own tick and world X/Z. The overview contains six independently selectable pairs. The 12-second video is available for cautious seed 31.
