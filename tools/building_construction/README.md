# ArchBuilder

Restored from `eee8091`. Run `res://tools/building_construction/BuildingSimulator.tscn` directly from a Godot project checkout. The editor starts its own draft and does not consume a Run room ID or write a Run save.

## Building files and consumers

- **File → Save JSON / Save YAML** writes the editable ArchBuilder building document. **Import JSON or YAML** reopens it. For code, `ArchitectState.new().restore(text: String) -> bool` validates and normalizes the document; `.data` has `activeLayerId`, `layers`, `walls`, `stairs`, `railings`, and `props`. In the editor, `BuildingSimulator.load_build(text: String) -> bool` imports through the editor's undo history.
- **File → Export Godot Scene** writes a `.tscn` and its same-name `.gd` companion. Save both within the project to reuse the result. Load the `.tscn` as a `PackedScene`, call `instantiate()`, and add the result under a `Node3D`. The exported root provides `authored_scene: Dictionary`. `candidates/BuildingCandidate.tscn` is a checked-in example.
- For authored-plan occupancy and room access, `BuildingSpace.new().setup(building: Dictionary, layer_idx := 0, declared_capacities := {}, live_doors := {})` accepts this building dictionary. A gameplay integration still needs to select a level, spawn, interactions, and navigation. Packed geometry is not a Run room registration.
- ArchBuilder JSON/YAML and exported scene data are separate from FreeSO XmlHouse XML and VM snapshots. They are not valid inputs to `RogueRoomView.set_blueprint_room` or `set_freeso_room`. There is no automatic conversion or import into Run.

## Assembling existing components

In ArchBuilder, open **Props → Open Component Library**. Choose a part, then click the actual support or joint in the viewport. **R** rotates a free placement (or rolls a pipe); **F** exchanges the joining end, or changes sides when fitting a handrail to a flight. The status line explains why an unsupported placement was refused.

| To assemble | Where to click |
| --- | --- |
| Door, window or wall hanging | Either face of a wall. A Smart Wall cuts the insert profile out of its mesh and collision; leave clear space for a moving leaf. |
| Floor, flight or rail | Click near a platform edge or the end of a run. A Smart Railing on a Smart Stair follows that flight's slope and width. |
| Furniture, tabletop objects or pendants | Use the floor, a supporting worktop, or a Smart Floor Zone with its ceiling enabled. Footprint and height come from the placed geometry. |
| Valve, pipe or flange | Click near a free port. The mating faces align in opposite directions and the occupied end is reserved. |
| Dock or rowboat | Click the water surface. The dock sets its deck above the waterline; the boat checks the water extends under the hull. |

The outline shows attachments under their supports. Deleting a support removes its attachments; **Undo** restores the assembly. **Save Candidate** and **Open Candidate** preserve the component hierarchy and configured links as a Godot scene, separately from an ArchBuilder floor plan.

In a component's inspector, choose an existing activity and use **Open activity** to operate it in place. A button, door, gear or activity can drive a compatible target chosen in the inspector. The Vesper Index is included; west-wing rooms, folio pages and the physical panel button appear when their corresponding project scripts are installed. These controls reuse the original component motion and puzzle rules. Building a candidate does not change the seeded Run generator.

## Model production

Catalog entries identify the live `line`, `rule`, or `assembly` generator. The component inspector edits generator parameters; the entry tooltip shows the implementation. See [生产管线技术说明](production/README.zh-CN.md).

## Check

Run with Godot .NET 4.7.2:

```text
godot --headless --path . --script res://tools/test/building_candidate_unit.gd
```

The restored project building MCP is opt-in at `mcp/building/client.py` for real viewport input and captures. The standalone editor does not load archived story scenes, the old Life Simulation shell, or the original art viewer.
