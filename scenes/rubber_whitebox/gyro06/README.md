# 06 — Gyroscope Well

A walkable kinetic sculpture around one fixed tip. `Gyro06.tscn` is a standalone art scene; it does not change the campaign entry point.

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --path . --rendering-method forward_plus res://scenes/rubber_whitebox/gyro06/Gyro06.tscn -- --run-seed=6
```

**WASD** walks; **click** captures the mouse and **Esc** releases it. **1–4** select the four frozen plates, **Enter** returns to live walking from the entrance, **Space** toggles motion, **H** hides/restores the gyroscope. All plates are shown in the [review set](../../../docs/design/media/gyro06/).

## Well and motion

- The clear well is 24 m across and 16 m high. Deep outer bays reach beyond the clear diameter to accommodate the 40-tread perimeter stair. The gallery is at y = 7 m; two independently exposed, trussed tongues extend from the gallery. Ring access and the stair remain open as the tongues retract. The first-person test capsule is 1.75 m tall, 0.35 m in radius, with a 1.65 m eye height.
- The 19.84 m outer rim and 24° tilt give an 82.7% diameter ratio. The projected enclosing disc is about 62.4% of the well area before subtracting apertures. Seed 6 measures 0.723 m and 9.455 m across the low/high extrema of the rim. The fixed support cup is centered at `(0, 0.24, 0)`; the shaft point stays there throughout both rotations.
- `build_06_art(seed)` builds the architecture, mesh, collision, two bridge headings and lighting. Seed changes include bay count and placement, stair rotation, lamp tilt/heading, the number of through-apertures (2–4), and both directions and initial phases. `set_step(tick)` samples the mechanism without accumulation; the live scene advances a single step per 60 Hz physics tick. The precession period is 1,200 ticks and spin is 488 ticks. A and D use the same 45° camera at steps 0 and 600.
- Procedural rotor stock is beveled, closed triangle geometry. The visible surfaces cast the hard oculus shadow and supply the native collision faces directly via `create_trimesh_shape()`. `top_light_reaches(point, normal)` samples direct key visibility from those native faces in a physics frame. Decorative washes and fog stay outside that visibility result. The stair uses a continuous curved tread collider and separate physical rails. Cutaway plates trim architecture visibility only.
- The upper tongues extend toward the low side and slide out of the high-side swept volume. Their guard rails follow the exposed length. `hide_gyro(true)` removes all rotating visuals and collision faces together, removes the rotating shadow, and holds both tongues extended. The steel bearing cup stays in place.

## External sculpture option

Set `gyro_model_path`, `gyro_model_source`, and `gyro_model_license` on the scene, or pass `--gyro-model=<path> --gyro-source=<record> --gyro-license=<terms>`. Supply a static opaque mesh in metres, pointing along local +Y, with the downward tip at the local origin and true cutouts. Keep the crown radius in [9, 9.92] m, all points in y = 0–8.55 m, and material beyond r = 3 m within y = 4.83–5.735 m. The loader applies the well's bronze and bakes the imported mesh transforms into matching collision triangles. The supplied source and license are recorded on the rotor. Missing/invalid assets use the procedural assembly. Source, reuse rights and cutout count are properties of the provided asset; the envelope check governs fit.

## Verify and capture

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --fixed-fps 60 -s res://tools/testing/gyro06_verify.gd
& .runtime/python/Scripts/python.exe tools/testing/gyro06_capture.py --seed 6
```

The headless test checks generated geometry and half-cycle kinematics across seeds 1–12. On seed 6 it probes native collisions and light visibility, walks a real capsule up the stair and onto the tongue, and imports a temporary GLB fixture. The capture tool uses the project game MCP to export four native 1600×1000 Forward+ PNGs to `.runtime/gyro06/plates/`. It also checks playback and pause, bridge reversal, and the floor lighting with the rotor hidden. The review set in `docs/design/media/gyro06/` is the seed 6 delivery.
