# Exposed gear train

Instance `Gears.tscn`. Its origin is the lower mounting datum, centered left/right; the back of the plate is flush with local Z = 0 and the display faces +Z. Leave an envelope of X ±0.99 m, Y 0–1.46 m and Z 0–0.38 m. Light the front obliquely with shadows enabled to show the cut teeth and the gap behind the open spokes.

Route your interaction to `interact()`. It toggles and returns the new state and emits `running_changed(active)`. Read `is_running`, `driver_angle`, or `follower_angle` from the root. The gear wheels have a fixed 30:22 tooth ratio, with the follower counter-rotating at 15/11 of the driver speed. When stopped, both wheels retain their phase. Animation starts in-game; the editor shows the generated static assembly. A room owns its interaction collider or hotspot.

The dark blue-gray plate and narrow trim pick up the cool paneling and simple trim bands in the Blue Prince architecture contact sheet. The muted brass, highlighted tooth bevels and open spokes make the mechanism readable at room distance. All geometry is generated in Godot; there are no imported meshes or Blender dependencies. Meshing is kinematically driven.

Run with Godot 4.7.2: `godot --headless --path . --script res://tools/blue_prince_lab/gear_check.gd`. The check tests a full tooth engagement at 121 samples, a mesh depth and shaft-spacing sanity check, the angular ratio, and the start/stop behavior.
