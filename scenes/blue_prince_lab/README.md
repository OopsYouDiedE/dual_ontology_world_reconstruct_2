# Grand Stair Hall — architectural reference lab

An optional, original study of the *Blue Prince* Grand Hall entrance image: a centered view down a cool blue-gray barrel vault, repeated pale pilasters and arch ribs, pools of warm light, a muted gold runner, and a door at the far end. The stair, mechanical bay, academy crest and freestanding helm belong to this prototype. Reference: [official game gallery](https://store.steampowered.com/app/1569580/Blue_Prince/) and [Grand Hall frame](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1569580/ss_7f4511e2454604568f545436f36674451fed6353.600x338.jpg). Game assets are generated in the project.

## Open the hall

From the repository root:

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --architecture-lab
```

- `1` entrance, `2` cabinet and gears, `3` landing, `4` banner and lamp. Click an in-frame mechanism to operate it.
- `F` to walk at eye level; WASD, mouse look, `E` to use an object within reach. `Esc` returns to the entrance view. The seeded expedition and its existing camera remain the default when the lab flag is absent.
- `G` turns the shared draft on or off. `H` toggles the HUD. The `SDFGI` button compares lighting in the same camera and scene state. `--lab-gi` chooses SDFGI on launch.

| Assembly | Physics / runtime source |
| --- | --- |
| Vault and walls | `HallShell.gd`: stone sections, rib wedges, pilasters, real window apertures and wall/floor collision. `HallFinish.gdshader` generates stone and woven runner detail. Exterior directional light enters through the east apertures; the sconces and oil lamp are separate interior sources. |
| Banner | Pinned cloth, gravity, drag and constraints. |
| Oil lamp | Damped, wind-driven pendulum with a warm shadow-casting light on the moving body. |
| Gear train | Extruded tooth profiles; 30:22 counter-rotation and locked tooth phase. |
| Room door and cabinet | Animated hinge bodies carry their own collision and trim. |
| Stair | 10 treads at 0.38 m run × 0.165 m rise. The tread mesh is stepped; the walk collider uses a continuous grade and the landing has its own floor and guards. |
| Helm | Original three-dimensional 1.30 m wide eight-spoke assembly: profiled turned grips, twin rim, bronze hub and fasteners. Cross-sections and radii are the source data in `Helm.gd`; no third-party helm mesh is required. Its axle turns 45° per operation. |

## Regenerate editable geometry in Blender 4.2

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 15 -- --architecture-lab --hall-recipe=.runtime/hall-recipe.json --lab-components=.runtime/hall-components.json
blender --background --factory-startup --python-exit-code 1 --python tools/blue_prince_lab/build_geometry_nodes.py -- .runtime/hall-recipe.json .runtime/hall-components.json .runtime/academy-hall.blend
```

The Blender asset uses **Cube → Instance on Points** with per-point dimensions for masonry and **Extrude Mesh** with per-face depth for arch stones. Its component collections assemble the generated Godot mesh sources as editable Geometry Nodes objects. The Blender file captures the assembled rest pose; the component generators, wind, hinges, materials and physics run in Godot. The `.blend` and intermediate receipts stay under `.runtime/`.

## Verification

```powershell
$Godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
foreach ($test in 'banner_test','gear_check','lamp_check','door_test','stairs_check') {
    & $Godot --headless --path . -s "res://tools/blue_prince_lab/$test.gd"
}
& .runtime/python/Scripts/python.exe tools/blue_prince_lab/hall_e2e.py
```

The last command uses the live game MCP bridge and its real Forward+ viewport. It operates the helm, gears, door and cabinet, checks cloth and pendulum deflection from the same gust, walks up the stairs and through the opened doorway, and outputs PNGs and a report under `.runtime/rogue-mcp/`. On the local RTX 3070 at 1280×720 both comparison frames reported 60 FPS against the MCP's 60 FPS cap. SDFGI is probe-based indirect lighting, not a hardware RT path; it is optional in this lab because it noticeably darkens the cool stone in the reference composition. The sampled value is a local comparison, not a minimum-GPU benchmark.
