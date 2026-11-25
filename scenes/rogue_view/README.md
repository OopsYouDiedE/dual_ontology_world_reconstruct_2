# Rogue room view

`RogueRoomView.tscn` displays a walkable perspective projection of authored FreeSO lot data with the original detective rig/controller. Its 3D viewport uses Forward+ SDFGI at the displayed 3D frame size. With `expedition_view` (the campaign) the picture fills the window and the viewport takes the expedition stage from `AcademyStage.gd`: environment, MSAA, ink strength, FOV, eye height, look sensitivity and pitch limit. Click anywhere in the picture to take the view; Esc or losing window focus releases it. Q/R orbit only the third-person view. The **Overhead plan** button opens a high-contrast, full-resolution native tile plan; on a two-floor blueprint, the floor selector includes the upper gallery. Movement pauses while the plan is open.

## Run integration

```gdscript
view.exit_selected.connect(travel) # zero-based index in exits
view.landmark_inspected.connect(reveal_puzzle)

view.set_instance_id(current_room_id)
view.set_blueprint_room(title, exits, xml_path)
if has_snapshot:
    view.set_freeso_room(title, exits, json_path)
view.set_inspection_target(encounter_pending)
```

- Call `set_instance_id` before presentation. Reusing the ID preserves the player pose during encounter/HUD changes; a new ID starts at the next authored entry. The entry point is up to two walkable tiles inside its open threshold, checking native walls and furniture anchors.
- `set_blueprint_room(title, exits, xml_path) -> Error` reads upstream `XmlHouseData`. Invalid or missing sources fall back to a text heading and the supplied topology links, without substitute geometry. `set_freeso_room` / `set_freeso_snapshot` display bridge data; on failure they restore the last valid blueprint for this room instance if available. Both accept calls before `_ready()`.
- `set_inspection_target(active)` enables inspection during a pending encounter with no available travel exits. The current landmark gets a ground ring. Use the project's `interact` action (**E / controller A**) or click a projected target while within reach and with line of sight. Both play the original interaction animation and emit `landmark_inspected`. Run can also provide its accessible Inspect room button.
- `exit_selected(index)` is emitted by a projected threshold interaction or its travel link. Authored exit thresholds take priority; the open entry can serve as a return route. Links beyond the number of authored thresholds stay available in the HUD. `player_observation()` reports exact position, velocity, grounded state, animation/action, prompt, target positions, projected click positions and `available_interact`.

## Data provenance

Blueprint floors and wall segments use zero-based architectural levels; XML objects use one-based levels and native hexadecimal GUIDs. The adjacent authored `plan_landmarks.json` names existing objects and open thresholds. A window callout only applies when a native object row matches its GUID, cell, floor and direction and the host wall edge exists. The projection cuts that wall visually and fits a frame and transparent glazing while retaining wall collision. Historical reserve comments do not create windows.

A VM snapshot uses `freeso.lot-snapshot.v1` from the bridge. Avatars and objects use native sub-tile positions (`x16`/`y16`); unplaced, hidden and contained furniture is omitted. Multi-tile furniture groups prefer the reported native base object. Academy art dresses recognized authored XML shells and depicts known GUIDs at their source anchors; VM snapshots use generic GUID art without a template shell. These are projections of the lot data; FreeSO remains responsible for native catalog assets and simulation.

## Check

```powershell
<Godot-4.7.2-mono-console.exe> --headless --path . --script res://scenes/rogue_view/tests/freeso_snapshot_test.gd
```
