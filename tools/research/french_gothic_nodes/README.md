# French Gothic Geometry Nodes — reproducible extraction

Reference: IRCSS / Blender-Geometry-Node-French-Houses, revision `b49b3c1dca15a57f3696e23c6f3ba8badf1fa6a3`. `main` is the preferred working library; `demo` preserves the older variants separately. The model is a stylised cathedral, not a surveyed reconstruction of Notre-Dame de Paris. This is an offline Blender reference experiment; it changes no Godot scenes or ArchBuilder recipes.

## Use a library

In Blender use File → Append → `main/nodes.blend` → NodeTree → select the group; alternatively register the library directory in Preferences → File Paths → Asset Libraries. Each `groups/*.blend` contains its named root and dependencies. These are library files, so opening one as a scene shows an empty viewport. Use `index.csv` to find the exact file and `inventory.json` for input sockets, dependencies and node types. The archives include field utilities and author variants as well as buildings; not every group is a mesh-generating modifier.

Start with `Generate Cathedral Combined` for the massing, `GenerateChurchBuildingB` for the body, `ChurchFrontTowers` for the facade towers and `DomaTower` for the central tower. For ArchBuilder-scale work, inspect `ArcsFromEdges`, `WindowFromEdges`, and `Gothic SupportColumn From EDge` first. The combined group's three direct dependencies are listed in the index. `ChurchA-Front` is a separate entry point.

## Reproduce on Windows

From the repository root, with Blender 5.0.1 available:

```powershell
$blender = (Resolve-Path '.runtime/french-gn/blender-5.0.1-windows-x64/blender.exe').Path
& ./tools/research/french_gothic_nodes/run.ps1 -Blender $blender
& ./tools/research/french_gothic_nodes/probe.ps1 -Blender $blender -LibraryDir .runtime/french-gn/main
py -3 ./tools/research/french_gothic_nodes/pack.py
```

The extractor verifies both upstream SHA-256 hashes, appends stock Blender groups referenced by installation-specific paths from the running Blender's bundled Essentials, and writes native editable libraries. It reopens the aggregate and compares group interfaces, counts, node types and named dependencies against the loaded source. It reads each standalone file's library directory and verifies the root and its transitive geometry-group names. This structural check is separate from functional testing. The smoke tests append one root group to an empty scene, use a four-unit cube as the test geometry when needed, realize instances, count vertices and polygons, and export material-free GLB snapshots. The extra square tower case changes `Height` to `12.0` before instantiation. Assets, logs and snapshots live under `.runtime/french-gn/`. Polygon counts refer to Blender mesh polygons, before glTF triangulation.

## Attribution and scope

Upstream repository: https://github.com/IRCSS/Blender-Geometry-Node-French-Houses . Copyright (c) 2025 Shahriar Shahrabi; original notice in `LICENSE.upstream`. The inventories also include stock Blender utility groups. Geometry tests do not verify third-party materials or source texture licensing; review these separately before shipping. The source includes machine-specific image paths, and the sample GLBs intentionally contain no materials. Generated files are kept outside the game content tree.

## Observed results — 2026-11-25

Blender 5.0.1: main 111 groups (17,630 nodes / 21,148 links); demo 168 groups (23,599 nodes / 28,395 links). 181 distinct group names across both archives; numbered variants were deliberately kept. All 279 standalone root directories passed the dependency-name check. Source main triggered a newer-file warning in 5.0.1; an independent Blender 5.3.0 extraction produced an identical main inventory. In the older demo, `Color in Range` and `HangingBanners` have different graph counts between Blender versions; the distributed demo is the 5.0.1 output. The 11 functional cases (10 root groups and one parameter override) are recorded in `tested-probes.json`. The GLBs show geometry only; no collision, walkability, production LOD or measured building dimensions were tested.

### Editable interior / exterior assembly (Blender 5.0.1)

After extracting the main library, run from the repository root in PowerShell:

```powershell
$b = '.runtime/french-gn/blender-5.0.1-windows-x64/blender.exe'
$d = '.runtime/french-gn/main'
$t = 'tools/research/french_gothic_nodes'
& $b -b --factory-startup --python-exit-code 1 -P "$t/assembly.py" -- $d
& $b -b --factory-startup "$d/cathedral-controls.blend" --python-exit-code 1 -P "$t/check_assembly.py"
```

Open `cathedral-controls.blend`, select `Cathedral | select to edit`, and use the `Cathedral controls` modifier. `Exterior` and `Interior` isolate branches. The exterior uses the upstream combined church; the nave is an original procedural study with a slab, paired columns, pointed arcades, transverse ribs and crossing diagonal ribs. Width and length scale act on both branches. Changing Bays redistributes the frames over a fixed 20-unit run. The graph does not generate masonry vault webs or a timber roof structure. Dimensions are design controls, not survey measurements. The check reopens the saved assembly, evaluates controls and visibility, and writes `assembly-checks.json`, `assembly-interior.png` and `assembly-section.png` without changing the blend file.

### Whole-building structural study and fidelity test

The expanded scene preserves the upstream exterior as its own layer. The nave, vault webs, galleries, transept wings, chevet fan, timber frames, projecting buttresses and tower stairs are interpretive additions sized to the example envelope. The nave has four-part bays; the trusses cover two straight roof runs. This is not a surveyed reconstruction. Shell shape controls are not a general collision solver for the additions.

After building `cathedral-controls.blend` above, use the same `$b`, `$d` and `$t`:

```powershell
& $b -b --factory-startup --python-exit-code 1 -P "$t/full_structure.py" -- $d
& $b -b --factory-startup "$d/cathedral-structure.blend" --python-exit-code 1 -P "$t/check_structure.py"
```

The check evaluates all nine layers individually, exercises a control on each layer, and compares the default exterior against a fresh append from `nodes.blend` using SHA-256 of ordered positions, face corner indices and face starts. See `structure-checks.json` beside the blend. This comparison covers default exterior geometry, not materials, conjectural interiors or historical fidelity.

### Upstream components in an interior bay (isolated test)

Run `& $b -b --factory-startup --python-exit-code 1 -P "$t/source_bay.py" -- $d` after extracting the main library. The output `original-group-bay.blend` reopens with two bays. `ArcsFromEdges` supplies the live contour: its full output includes a wall panel, so the adapter samples the 17 outline points at pinned `DecorRes=3` and builds a rectangular section. Recheck that ordering for another upstream version. `Gothic SupportColumn From EDge` supplies two crossed edge supports per station; alignment, seats and layout are local. `GenerateStairCase` is a separately toggled straight stair sample. The recipe reopens the saved scene, checks group references, seats at 1/2/4 bays, shared-boundary counts for matching dimensions, and stair width response, then writes a PNG and `original-group-checks.json`. This fixture does not modify the whole-church scene or certify watertight joints.

### Whole-building Godot review

With the default `cathedral-structure.blend` generated above, run:

```powershell
& $b -b --factory-startup "$d/cathedral-structure.blend" --python-exit-code 1 -P "$t/export_whole.py"
& .runtime/python/Scripts/python.exe "$t/godot_whole.py"
```

The export verifies the nine branches sum to the default evaluated face count. The game MCP captures six real Forward+ views and checks named layers, shell visibility, native scale, SSAO and SDFGI. Inspect `godot-whole-*.png` and `godot-whole.json` beside the blend. Chalk and wood-toned review overrides are used instead of source textures. The interior pair shares a camera. This is visual QA, not collision or performance certification.
