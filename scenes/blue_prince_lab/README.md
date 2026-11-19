# Grand Stair Hall — architectural reference lab

An optional, original study of the *Blue Prince* Grand Hall entrance image: a centered view down a cool blue-gray barrel vault, tapered circular columns and stepped arch ribs, pools of warm light, a muted gold runner, and a door at the far end. The stair, mechanical bay, academy crest and freestanding three-axis tourbillons belong to this prototype. Reference: [official game gallery](https://store.steampowered.com/app/1569580/Blue_Prince/) and [Grand Hall frame](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1569580/ss_7f4511e2454604568f545436f36674451fed6353.600x338.jpg). Game assets are generated in the project.

## Open the hall

From the repository root:

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --architecture-lab
```

- `1` entrance, `2` cabinet and gears, `3` landing, `4` banner and lamp, `5` tourbillon in the workroom behind the hall door, `6` the independently operated center-hall exhibit. Click an in-frame mechanism to operate it.
- `F` to walk at eye level; WASD, mouse look, `E` to use an object within reach. `Esc` returns to the entrance view. The seeded expedition and its existing camera remain the default when the lab flag is absent.
- `G` turns the shared draft on or off. `H` toggles the HUD. `Toon`, `Ink`, `Glow`, and `SDFGI` toggle independent layers at the same camera and scene state. `--lab-gi` chooses SDFGI on launch.

| Assembly | Physics / runtime source |
| --- | --- |
| Vault and walls | `HallShell.gd`: stone sections, rib wedges, smooth radial column profiles, curved full-height drapery, real window apertures and wall/floor collision. `HallFinish.gdshader` generates stone and woven runner detail. Exterior directional light enters through the east apertures; the pendants and oil lamp are separate interior sources. |
| Banner | Pinned cloth, gravity, drag and constraints. |
| Oil lamp | Damped, wind-driven pendulum with a warm shadow-casting light on the moving body. |
| Gear train | Extruded tooth profiles; 30:22 counter-rotation and locked tooth phase. |
| Room door and cabinet | Animated hinge bodies carry their own collision and trim. |
| Stair | 10 treads at 0.38 m run × 0.165 m rise. The tread mesh is stepped; the walk collider uses a continuous grade and the landing has its own floor and guards. |
| Spherical three-axis tourbillon | `Tourbillon.gd` builds nested cages, bearings, balance wheel, spiral hairspring, and a stepping escape wheel from original dimensioned 3D geometry. The local X/Y/Z periods are 22/13/7 s. Click either exhibit to run or stop it independently. The smaller hall exhibit uses the hall Toon material and sits 0.84 m off the runner center to leave the main sightline and walk route clear. This is a kinematic exhibit, without manufacturer CAD or a force-driven escapement. |

## Look development

The entrance camera is at 1.07 m with a 14° upward pitch and a 68° vertical field of view. At 1280×720 the threshold lands at normalized y≈0.736, the far-left runner edge at x≈0.470, and the nearest left pendant at x≈0.302. The rise line is 5.10 m. Column shafts have 32 circular sides with radial smooth normals and geometric ring mouldings; the transverse ribs still use six hard-surface radial courses with axial depths of 0.88–1.30 m. The end portals retain the stepped jambs. Broad cool fill and a low-frequency pale wash on the inner stone replace the concentrated spotlight. The curtain mesh is a draped grid with phase-shifted folds and smooth normals.

`HallToon.gdshaderinc` bands the per-light normal response with softened transitions and leaves distance and shadow attenuation continuous. The pale stone floor also gets a weak broad specular lobe. `HallFinish.gdshader` adds low-frequency mineral mottling and runner wear. `HallInk.gdshader` uses distance-dependent coverage and stricter depth and normal cutoffs in the distance; it samples the pre-ink HDR scene to weaken contours around bright lantern glass. Additive Glow is enabled in this lab. Mortar, ribs and panel separations remain present in geometry or materials. Optional SDFGI is probe-based indirect lighting; the lab uses deliberate interior keys and fill by default.

## Regenerate editable geometry in Blender 4.2

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 15 -- --architecture-lab --hall-recipe=.runtime/hall-recipe.json --lab-components=.runtime/hall-components.json
blender --background --factory-startup --python-exit-code 1 --python tools/blue_prince_lab/build_geometry_nodes.py -- .runtime/hall-recipe.json .runtime/hall-components.json .runtime/academy-hall.blend
```

The Blender asset uses **Cube → Instance on Points** with per-point dimensions for masonry, **Extrude Mesh** for arched segments, radial profile courses for the circular columns, and curved grid surfaces for the pleats. Its component collections assemble the generated Godot mesh sources as editable Geometry Nodes objects. The Blender file captures the assembled rest pose; the component generators, wind, hinges, materials and physics run in Godot. The `.blend` and intermediate receipts stay under `.runtime/`.

## Verification

```powershell
$Godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
foreach ($test in 'banner_test','gear_check','lamp_check','door_test','stairs_check') {
    & $Godot --headless --path . -s "res://tools/blue_prince_lab/$test.gd"
}
& .runtime/python/Scripts/python.exe tools/blue_prince_lab/hall_e2e.py
```

The last command uses the live game MCP bridge and its real Forward+ viewport. It checks the entrance projections, compares Toon-only, Toon + Ink, Glow off, continuous diffuse, and SDFGI, independently operates both tourbillons, gears, door and cabinet, checks cloth and pendulum deflection from the same gust, and walks through the opened doorway and up the stairs. PNGs and an `architecture-report.json` are written under `.runtime/rogue-mcp/`.
