# A07 · Strata

A four-landing shaft for categories **1D (ascent load)** and **3C (conductive / insulating transformation)**. A spring-loaded ascent rig carries one reversible core and one bank. In Copper the core is a rigid rack shoe: it bridges the traction contacts and completes the anchor's generator circuit. In Ceramic the same core folds inside a narrow stair profile and opens the contact. A Ceramic unload spends the harness spring on a mechanical damper; Copper works against the generator and recovers one unit of bank per four strain released. The press takes charge to change the core's form and leaves the harness preload in place. At the Crown the same bank pulls the hatch bolt through the Copper contact.

## Section and player decisions

| Rise (cm) | Copper hand: cm / strain per tick | Copper boost: cm / strain / bank drawn per tick | Ceramic stair: cm / strain per tick |
|---|---:|---:|---:|
| Sump → Switchback (0 → 420) | 5 / 5 | 10 / 2 / 2 | 4 / 3 |
| Switchback → Gallery (420 → 1000) | 5 / 10 | 10 / 3 / 6 | 4 / 3 |
| Gallery → Crown (1000 → 1620) | 5 / 9 | 10 / 3 / 5 | 4 / 4 |

Expose rack load and motor draw where the rail starts, and mark the deeper final stair risers. At every boundary the player can read height, bank, harness load, and the remaining time on any armed safety clock. Unloading requires an anchor: Copper bleeds 4 strain per tick into the bank (capacity 280); Ceramic dissipates 8. Hand and stair travel spend no charge. Waiting holds altitude and preload. Each ready decision covers 20 integer ticks, at 60 Hz; feet and motor stop exactly at a landing, so a partial final beat charges only for actual motor ticks. The spring's relief valve caps strain at 660. Continuous strain of 420 or more for 60 ticks trips the cradle, with a further 60 ticks of return warning. The first boundary after any warning onset preserves at least 41 ticks. See [INTERFACE.md](INTERFACE.md) for model calls and view bindings.

The lower rail is a place to bank charge: hand crank up; then bleed strain at the Switchback. Alternatively press Ceramic at the Sump, climb the first two stairs, and save the lower rail trip at the cost of a tighter bank. Use the middle stair to conserve charge, reset the spring at the Gallery, then change back. On the upper rail, hand work recovers electrical value through the strain it stores; motor bursts trade that advantage for time and strain headroom. Land with enough warning time left to get below the trip point. Copper unloading at the Crown pays the final deficit before the hatch can start. This makes the meter history matter at the next landing: a route can reach the same height with the same meters and a different unload deadline.

## Counterfactuals from public inputs

- At the Gallery, hand and boost from the same state give **+100 cm / +180 strain / 0 charge** versus **+200 cm / +60 strain / −100 charge** in a beat. In the banked run, reaching the Crown at 32 charge falls short of the 130 hatch cost. Four unload beats get to 112; the fifth gets to 132. The trace continues to a full bleed to show the spring stops at zero.
- On the middle rail, `boost, climb, climb, boost` and `climb, climb, boost, boost` both arrive at 1,000 cm with 514 strain and 52 charge, but with **36** versus **27** ticks left to trip. Clearing that load takes **24** ticks in Copper. An idle beat in the first case spends 20 ticks without releasing any load, so the delayed unload fails.
- The top stair reaches the Crown, but even from a cold harness it takes 155 movement ticks; the warning starts after 105. After the boundary at 160 ticks only **5 ticks** remain, while bleeding 620 below 420 needs **26** Ceramic ticks. On the viable upper rail, dropping only two rather than three ceramic unload beats at the Gallery starts the same motor plan with 115 additional strain and trips before the Crown unload clears it.
- Starting a conversion breaks the contacts now; it changes the routing only after the visible press countdown. Ceramic unloading cools the harness without filling the bank. Waiting on an armed harness releases neither load nor time pressure; the fallback is a timely unload or a signaled return and clean retry.

## Reproduce

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --script res://tools/strata/verify.gd
```

`golden.json` records two normal-input replays with semantic checkpoints and SHA-256 of the per-tick snapshot tape (Godot's default sorted JSON). The Crown commits at tick **901** on the banked lower-rail route (31 charge remains) and **841** on the insulated start (4 remains). The verifier also explores the restricted public-input graphs omitting `transform` and `boost`, separately; both can reach Crown height, and neither reaches a decision boundary at the Crown with Copper and strain below 420. It collapses absolute time to active cue ages, skips passive idle in `ready` where it can only age an armed clock, and skips returns because the cradle restores the initial meters and position. This is headless model evidence; the Forward+ view and Game MCP capture remain with main.
