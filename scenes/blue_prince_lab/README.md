# Grand Stair Hall — architectural reference lab

An optional, original study of the *Blue Prince* Grand Hall entrance image: a centered view down a cool blue-gray barrel vault, repeated octagonal columns and stepped arch ribs, pools of warm light, a muted gold runner, and a door at the far end. The stair, mechanical bay, academy crest and freestanding three-axis tourbillon belong to this prototype. Reference: [official game gallery](https://store.steampowered.com/app/1569580/Blue_Prince/) and [Grand Hall frame](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1569580/ss_7f4511e2454604568f545436f36674451fed6353.600x338.jpg). Game assets are generated in the project.

## Open the hall

From the repository root:

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64.exe --path . -- --architecture-lab
```

- `1` entrance, `2` cabinet and gears, `3` landing, `4` banner and lamp, `5` tourbillon in the workroom behind the hall door. Click an in-frame mechanism to operate it.
- `F` to walk at eye level; WASD, mouse look, `E` to use an object within reach. `Esc` returns to the entrance view. The seeded expedition and its existing camera remain the default when the lab flag is absent.
- `G` turns the shared draft on or off. `H` toggles the HUD. `Toon`, `Ink`, and `SDFGI` toggle independent layers at the same camera and scene state. `--lab-gi` chooses SDFGI on launch.

| Assembly | Physics / runtime source |
| --- | --- |
| Vault and walls | `HallShell.gd`: stone sections, rib wedges, octagonal column profiles, pleated curtains, real window apertures and wall/floor collision. `HallFinish.gdshader` generates stone and woven runner detail. Exterior directional light enters through the east apertures; the pendants and oil lamp are separate interior sources. |
| Banner | Pinned cloth, gravity, drag and constraints. |
| Oil lamp | Damped, wind-driven pendulum with a warm shadow-casting light on the moving body. |
| Gear train | Extruded tooth profiles; 30:22 counter-rotation and locked tooth phase. |
| Room door and cabinet | Animated hinge bodies carry their own collision and trim. |
| Stair | 10 treads at 0.38 m run × 0.165 m rise. The tread mesh is stepped; the walk collider uses a continuous grade and the landing has its own floor and guards. |
| Spherical three-axis tourbillon | `Tourbillon.gd` builds nested cages, bearings, balance wheel, spiral hairspring, and a stepping escape wheel from original dimensioned 3D geometry. The local X/Y/Z periods are 22/13/7 s. Click to run or stop. This is a kinematic exhibit, without manufacturer CAD or a force-driven escapement. |

## Look development

The entrance uses a 1.34 m camera, about 10° upward pitch, and a 64° vertical field of view. The three reference landmarks measured in normalized image coordinates are the threshold near y=0.714, far-left runner edge near x=0.469, and nearest left pendant near x=0.293. The transverse ribs use six radial stone courses with distinct axial depths (0.88–1.30 m), stepped crown bosses, and deeper coffer returns. Each nested portal continues its stepped arch section into the jambs. The end wall uses these concentric frames plus segmented stone fields to frame a cool focus, while smaller warm pools pick out the pendants and edges of the pleated curtains.

`HallToon.gdshaderinc` bands the per-light normal response on architecture, door and decor with softened transitions, keeping distance falloff and shadow attenuation continuous. `HallInk.gdshader` multiplies in silhouette and stronger normal creases. Mortar, ribs and panel separations are present as mesh or material features, so their lines remain without the screen pass. `HallFinish.gdshader` adds world-scale stone mottling and directional runner and wood wear. Optional SDFGI is probe-based indirect lighting; the lab uses deliberate interior keys and fill by default and has no hardware ray-tracing path.

## Regenerate editable geometry in Blender 4.2

```powershell
& .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --headless --path . --quit-after 15 -- --architecture-lab --hall-recipe=.runtime/hall-recipe.json --lab-components=.runtime/hall-components.json
blender --background --factory-startup --python-exit-code 1 --python tools/blue_prince_lab/build_geometry_nodes.py -- .runtime/hall-recipe.json .runtime/hall-components.json .runtime/academy-hall.blend
```

The Blender asset uses **Cube → Instance on Points** with per-point dimensions for masonry, **Extrude Mesh** for arched segments and pleats, and profile courses for the octagonal columns. Its component collections assemble the generated Godot mesh sources as editable Geometry Nodes objects. The Blender file captures the assembled rest pose; the component generators, wind, hinges, materials and physics run in Godot. The `.blend` and intermediate receipts stay under `.runtime/`.

## Verification

```powershell
$Godot = '.runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe'
foreach ($test in 'banner_test','gear_check','lamp_check','door_test','stairs_check') {
    & $Godot --headless --path . -s "res://tools/blue_prince_lab/$test.gd"
}
& .runtime/python/Scripts/python.exe tools/blue_prince_lab/hall_e2e.py
```

The last command uses the live game MCP bridge and its real Forward+ viewport. It checks the entrance projections, compares Toon-only, Toon + Ink, continuous diffuse, and SDFGI, operates the tourbillon, gears, door and cabinet, checks cloth and pendulum deflection from the same gust, and walks through the opened doorway and up the stairs. PNGs and an `architecture-report.json` are written under `.runtime/rogue-mcp/`.
