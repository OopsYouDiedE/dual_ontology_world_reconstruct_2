# Hinged architectural joinery

Instantiate `Door.tscn` or `Cabinet.tscn`, or attach `Door.gd` / `Cabinet.gd`
to an empty `Node3D`. Geometry and collision are built in `_ready()`. Use unit
scale; place and rotate the root. The local front is **+Z**, up is **+Y**.

- **Door**: floor-level origin at the center of the wall aperture (`z = 0`).
  Cut a **1.45 m wide × 2.60 m high** clear aperture; the jamb and header sit
  outside those limits. Face trim spans 1.66 m; overall height is 2.70 m.
  Leaf dimensions are 1.426 × 2.568 × 0.064 m before trim and hardware.
  The hinge is on local −X; allow 1.47 m of sweep depth on the +Z side.
- **Cabinet**: floor-level origin beneath the middle of the case; the case
  measures **1.02 × 1.19 × 0.48 m** (width × height × depth), before knobs.
  Two 0.434 m leaves open toward +Z to expose two solid shelf surfaces.
  Leave about 0.72 m clear along +Z measured from the root.

## Runtime API

- `interact()` toggles the target and reverses a swing in progress.
- `set_open(open: bool, immediate := false)` sets the target explicitly.
  Use `immediate = true` for initial placement or state restoration.
- `is_open` is the commanded state. `open_changed(open: bool)` fires when
  that target changes, including on an immediate change.
- Set `swing_seconds` and `collision_layer` before adding to the scene tree.
  Collision queries against a new pose should run after a physics tick.
- The caller owns input, sound, locks and clearance policy. Moving leaves
  use box approximations attached to their actual physics-driven hinge bodies.

The supplied Blue Prince reference sheet informed the cool painted casework,
stepped casing profiles, rectangular panels and aged brass fittings. All meshes
and finishes are generated in Godot; no Blender or external art is required.

Headless verification from the project root:
`godot --headless --path . --script res://tools/blue_prince_lab/door_test.gd --quit-after 350`.
