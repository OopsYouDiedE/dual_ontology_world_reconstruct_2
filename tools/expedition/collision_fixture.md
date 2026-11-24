# Expedition collision fixture

Opt in per production scene instance, including each fresh scene in WalkTest or the human runner:

```gdscript
const Fixture = preload("res://tools/expedition/collision_fixture.gd")
# ...
level = preload("res://scenes/expedition_01/Sortie.tscn").instantiate()
root.add_child(level)
if lightweight:
    Fixture.apply_lightweight(level)
```

Apply after `_ready()` (normally when `add_child` returns), before the first rendered frame. The helper is idempotent and returns the environment paths and passes it turned off. It duplicates the environment per scene and disables SDFGI, SSAO, SSIL and SSR when enabled. The production lights, shadows, meshes, materials, animation, emission/bloom, fog, camera, HUD, audio, collision, and all processing and simulation clocks stay in place. Indirect lighting and contact shading can read differently; use full mode for reference captures and pixel comparisons. Physics-only headless runs already avoid GPU rendering costs; this mode targets rendered runs.

## Geometry API

```gdscript
# Sample after physics has settled; wait at least two ticks after scene startup.
var geometry := Fixture.capture(level)
var signature := Fixture.fingerprint(geometry) # SHA-256 of canonical JSON
var status := Fixture.write_json("res://.runtime/expedition_geometry.json", geometry)
```

A capture is a snapshot of the actual shape owners and current world transforms, plus baked collision for collision-enabled root CSGs. Coordinates are world X/Z with Y vertical. Each row has a structural ID, role, body and shape type, collision layer/mask, owner-disabled flag, shape parameters, transform and margin, XZ footprints, and Y extents. Disabled shapes and layer-zero plates remain in the export with their current metadata. Apply the query's layer mask when using this as an obstacle map, and filter by Y for stacked floors.

Boxes and convex solids export convex hulls of projected vertices. Concave/CSG rows export projected triangles, including degenerate edge-on triangles. For curved shapes the transform and radius/segment give the exact smooth projection; the 32-point display outline is sampled. Extents describe shape geometry before solver margin. Unsupported or empty shapes appear in `errors`, and `write_json` rejects incomplete geometry. Capturing and serializing geometry is separate from lightweight mode; keep exports outside measured traversal loops.

## Full/light parity check and export

```powershell
$godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
& $godot --headless --path . --fixed-fps 60 --script res://tools/expedition/collision_fixture_test.gd -- --geometry=.runtime/collision_fixture_geometry.json
```

Omit `--geometry` to only verify. The test drives separate full and light instances through seven equivalent snapshots and compares the complete fingerprints. Physics rays verify the moving counterweight lift, the plate's gaze-driven blackout and recovery, and the return gate's tween. The boot JSON is exported only after parity passes. Headless verification checks rule and collision parity, not GPU speed or visual fidelity.
