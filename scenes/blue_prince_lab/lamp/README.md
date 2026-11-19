# Suspended oil lamp

Instance `Lamp.tscn` at the roof hook, with local +Y upright and unit scale. Yaw is allowed. The oil light rests 0.992 m below the origin at the default hang length. Feed the instance `set_wind(Vector3)` with the shared world-space air velocity in m/s; the lamp holds that sample until the next update. Send `Vector3.ZERO` when the draft stops.

The first Blue Prince image in `.runtime/visual-reference/sources.json` (grand hall) guides the warm suspended silhouette against cool architecture. This fixture is an original eight-sided copper and brass oil lantern with a tinted globe, modeled procedurally in Godot. The fixed rose and hook sit above a separate moving assembly. Relative airspeed, gravity and damping drive the swing on physics ticks.

One shadow-enabled omni light, with a 3.4 m range, follows the flame. Housing meshes skip the shadow pass to keep the lamp from occluding itself. For repeating fixtures, disable `shadow_enabled` on less important instances.

Standalone check: run Godot with `--headless --path . --disable-render-loop --fixed-fps 60 --script res://tools/blue_prince_lab/lamp_check.gd`.
