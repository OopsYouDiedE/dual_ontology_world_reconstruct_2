# ArchBuilder

Restored from `eee8091`. Open **Open ArchBuilder** in Run from a Godot project checkout, or run `res://tools/building_construction/BuildingSimulator.tscn` directly. `BuildTools.open_archbuilder() -> int` returns the editor process ID (or `-1` on failure). The editor starts its own draft and does not consume a Run room ID or write a Run save.

## Building files and consumers

- **File → Save JSON / Save YAML** writes the editable ArchBuilder building document. **Import JSON or YAML** reopens it. For code, `ArchitectState.new().restore(text: String) -> bool` validates and normalizes the document; `.data` has `activeLayerId`, `layers`, `walls`, `stairs`, `railings`, and `props`. In the editor, `BuildingSimulator.load_build(text: String) -> bool` imports through the editor's undo history.
- **File → Export Godot Scene** writes a `.tscn` and its same-name `.gd` companion. Save both within the project to reuse the result. Load the `.tscn` as a `PackedScene`, call `instantiate()`, and add the result under a `Node3D`. The exported root provides `authored_scene: Dictionary`. `candidates/BuildingCandidate.tscn` is a checked-in example.
- For authored-plan occupancy and room access, `BuildingSpace.new().setup(building: Dictionary, layer_idx := 0, declared_capacities := {}, live_doors := {})` accepts this building dictionary. A gameplay integration still needs to select a level, spawn, interactions, and navigation. Packed geometry is not a Run room registration.
- ArchBuilder JSON/YAML and exported scene data are separate from FreeSO XmlHouse XML and VM snapshots. They are not valid inputs to `RogueRoomView.set_blueprint_room` or `set_freeso_room`. There is no automatic conversion or import into Run.

## Check

Run with Godot .NET 4.7.2:

```text
godot --headless --path . --script res://tools/test/building_candidate_unit.gd
```

The restored project building MCP is opt-in at `mcp/building/client.py` for real viewport input and captures. The standalone editor does not load archived story scenes, the old Life Simulation shell, or the original art viewer.
