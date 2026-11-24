# A08 · The Tempered Span

**Deliverable: working referee and replayable mechanism prototype. Difficulty gate: failed by a reproducible fast reduction.** No renderer, scene registration or independent red-team claim in this handoff.

## The machine

A narrow bridge needs a taut carrier cable and a guide shoe seated between two witness lines under the same moving load. The **Cable Jack** and **Forming Kiln** sit on parallel service paths from the **Splice Bench** to the **Proof Yoke**. Beyond the yoke, another pair of paths goes past the **Dashpot Brake** or **Counterweight** to the same **Test Span**, then the **Far Landing**. The two rail approaches put opposite side loads on the same copper seat as the trolley rolls across. There are eight named objects; the gauges and latch belong to these objects.

Two pieces stay outside the splice: the jack's ratchet holds cable **preload** and the copper seat keeps its **permanent bend**. The bench restores its selected local clock, keeper pin, heat, ballast and brake. To heat the seat, the service punch drops the keeper pin into a catchbox; the kiln shutter opens, and the proof load path is now interrupted. Restoring an intact mark reconnects the old load path around the already bent insert. A cold seat can be reheated under a different pull to increase or flatten its bend. The same rewind can be repeated, Home always remains available, and a Bench stamp can be replaced. No echo or previous input tape is played back.

At the yoke, the proof cam locks adjustments during a 240-tick draw. Its lobe drives through a dashpot and a minor eccentric on the exterior clock. On a rising draw, one approach's moving side load can counteract the shoe's increasing displacement; on the falling draw the opposite approach can. The weight shifts the neutral seat and also takes tension out of the cable. A deep bend lengthens the lever arm and can make a seemingly well-centered unloaded shoe bind on the rails under a rider. The separate gauges show a good seat with a slack cable and a taut cable with a displaced shoe.

### Labels and the public rulers

Suggested player-facing placards: **“Cut keeper to open kiln”**, **“Gold teeth stay / Copper bend stays”**, **“Compare Home and Bench”**, **“Cable: 73 minimum under rider”**, **“Shoe: ±7 under rider”**, **“Pull cancel for the safety trolley.”**

All scales are indexed in divisions, and all clocks in real 60 Hz ticks. These are fixture ratios, with truncating integer division as in GDScript:

- `P` cable teeth (0–64), `B` counterweight (0–36), `K` brake (0–18) adjust by one division per held tick. Kiln heat gains two per held tick and cools one per released tick (0–100). At 50 or hotter with the pin out, the permanent bend `M` moves one division per tick toward `clamp(P - B/2 - 18, 0, 40)`.
- At proof age `a`, the cam lift is `max(0,44 - (a-120)^2/180)`. When this lobe is positive the eccentric adds `((60 - abs(60 - (exterior_tick % 120)))/15) - 2`, then lift is clamped below at zero. The piston uses sixteenths: `piston += (16*lift - piston)/(4+K)`, starting parked. The cam/brake/piston form a continuous-in-time sampled draw, not an action lookup table.
- `force = P + piston/16 - K`; `tension = force - B/3 - rider_load`; `shoe = force - 2*B - M + side_load`. The trolley's 48 samples use `rider_load = 8 + min(i,47-i)/5`, `side_load = (2*i-47)*(4+M*M/120)/47` via Brake, with the sign reversed via Weight. Entry is certified only if `tension >= 73` and `abs(shoe) <= 7` at all 48 samples. With no rider, both loads are zero.

The punch, splice and proof start each have 48 ticks of continuous warning. Proof end is posted from arm to expiry (288 ticks if left running). The queued release is posted at least 48 ticks ahead. A bad trial keeps the latch shut and reports the first failing sample. Manual entry asks the same interlock, with no forced boarding. A rider can withdraw to the departure rail using the safety trolley; proof can be rearmed and settings changed. There is no injury or forced reset.

## Mechanism demonstrations

| Replay | Manufacturing and memory | Old-world crossing |
|---|---|---|
| `staged_jack_rising_weight` | Rack to 43 before heating an unweighted seat. Splice Home at 233 with `P=43, M=25`; finish jacking cold and move the ballast to 36. | Only the Weight entry opens (460–464) on this draw. Queue releases at 460; Far Landing at **508**. |
| `loaded_bench_falling_brake` | Pull to 64 and use a 34-division ballast while forming, so copper sets to 29. Mark ballast and brake (4) before punching; splice Bench at 411 retaining `P=64, M=29`. | Weight gives an earlier window (564–568). This run uses the falling Brake window (609–613), enters at 609 and reaches Far Landing at **657**. |

The verifier also swaps the early and late `haul` holds on the **same itinerary** with the same kiln hold. It restores the same local state and 43 cable teeth in both histories; the cold late haul leaves bend 0, and identical old-world inputs now fail. In a separate trace, Home and Bench were stamped at the same exterior phase and are chosen at the same real tick, with identical retained cable and copper; their ballast/brake restores are 0/0 and 34/4 and immediately move both needles. Further checks pay out just the cable, keep the pin out, reject a mistimed entry, withdraw/retry a splice, cancel/requeue a rider, retreat and win on a second draw, test an exact warm mark, and compare the two needles at the same tick on opposite approaches.

## Difficulty diagnosis

- A shortest walk ignores the seated pin and encounters a locked span. An action tape or a beat match cannot reproduce a physically different hot/cold history. Merely saturating the jack and forming at zero ballast gave `P=64, M=40`; adding ballast 36 afterwards did not produce a win in the saturation control.
- **Actual shortcut:** use the *same* ballast for forming and proof, keep the dashpot brake at zero, fully haul first, and save the ballast at the Bench. Estimate force near a usable entry as 99 divisions. The centered shoe gives `99 ≈ 2B + (64 - B/2 - 18)`, hence `B ≈ 35`. Torch fully, restore Bench, go by Weight and queue. `diagnose.gd` uses only public input and never reads the golden fixture. Its first candidate `B=35` with no phase wait won at **tick 537 (8.95 seconds at 60 Hz)**. The search plus negative control took about 65 ms of model runtime (excluding Godot startup and writing the probe). Holding the recipe fixed and shifting the arm tick across a whole turn won at **120/120** exterior phases; the first solution did not depend on lucky timing.
- Structurally, a solver can condense every past action to a small set of sufficient statistics: preload, bend, selected local ballast/brake, seated pin and real phase. During proof the settings are locked; the two loaded approaches are projections of one precomputable piston trajectory. This leaves a small settings/window search, and the measured recipe collapses it still further. This ruleset remains vulnerable to a white-box quick solve. A future iteration would need a second *necessary* in-draw commitment that changes the same trajectory after a first reunion, with opposing evidence at the later reunion. Narrower windows or a larger map leave this shortcut intact.

## Run from the repository root

```powershell
$g = '.\.runtime\godot\4.7.2\Godot_v4.7.2-stable_mono_win64_console.exe'
& $g --headless --path . --script res://tools/counterfactual/verify.gd
& $g --headless --path . --script res://tools/counterfactual/diagnose.gd -- --robustness
& $g --headless --path . --script res://tools/counterfactual/play.gd -- --pace --route=staged_jack_rising_weight
& $g --headless --path . --script res://tools/counterfactual/play.gd -- --pace --route=loaded_bench_falling_brake
```

`play.gd` accepts `--file=` for a standalone receipt (including the JSON printed by the diagnosis) and `--trace` for per-tick input/state output. `--pace` uses actual Godot physics callbacks; omit it for fast deterministic headless simulation. Use [the interface](INTERFACE.md) to wire a player view. This verification covers the referee and paced headless input, with no Forward+ or player-comprehension gate claimed.
