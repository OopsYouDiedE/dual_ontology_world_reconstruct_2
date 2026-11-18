# Rogue room view

Instantiate `RogueRoomView.tscn` under a `Control`. Give it available area (e.g. `SIZE_EXPAND_FILL` vertically in a `VBoxContainer`). The room uses an isolated 384×216 SubViewport, nearest-neighbor upscaling, and Forward+ SDFGI. Host renderer selection remains the project's responsibility.

```gdscript
var view = preload("res://scenes/rogue_view/RogueRoomView.tscn").instantiate()
view.exit_selected.connect(travel) # zero-based index in exits
add_child(view)

# snapshot_path is assigned by the caller for the current lot.
var status: Error = view.set_freeso_room(room_label, exits, snapshot_path, 1)
if status != OK:
    # The view has already switched to the topology map. The caller can log status.
    pass
```

- `set_room(label: String, exits: Array)`: explicitly shows **Topology navigation map**, clearing any previous VM data.
- `set_freeso_room(label: String, exits: Array, path: String, level: int = 1) -> Error`: reads the caller-selected JSON file. Use `res://`, `user://`, or an absolute path. Call again after the publisher replaces the file; the view neither launches the VM nor watches files.
- `set_freeso_snapshot(label: String, exits: Array, snapshot: Dictionary, level: int = 1) -> Error`: same operation when the caller already decoded JSON. Both APIs support calls before `_ready()`; failed calls clear the VM data and render the topology map for the provided label/exits.
- Exits are strings or dictionaries with a `label` field. In the VM view they are separate travel buttons. In the topology map they appear as symbolic doors. Both emit `exit_selected(index: int)` in input order. No mapping from VM walls/doors to rogue exits is inferred.

## Native snapshot contract

Read `freeso.lot-snapshot.v1` as emitted by `tools/freeso_bridge/SnapshotBridge.cs`. `lot.walls[].mask` contains the six native edge/diagonal bits; `lot.floors[].pattern` identifies occupied floor tiles. Placed avatars use `x16` and `y16` in sixteenths of a tile. Levels are 1-based. The displayed room is one lot floor. The academy-wide connection graph has no shared world-coordinate or floor requirement.
