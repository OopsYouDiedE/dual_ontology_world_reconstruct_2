# Classical stone stairs

Instance `Stairs.tscn`, or attach `Stairs.gd` to a Node3D. Align its local origin with the lower floor at the first riser. Keep unit scale for meter measurements; yaw can be set freely. Connect the upper floor at local `(0, 1.65, -4.80)`.

| Feature | Local measurement |
| --- | --- |
| Stone deck width | 2.500 m |
| Flight | 10 treads of 0.380 m, 10 risers of 0.165 m |
| Flight run / rise | 3.800 m toward −Z / 1.650 m toward +Y |
| Landing | 2.500 × 1.000 m, from z = −3.800 to −4.800 m |
| Rail centerlines | x = ±1.160 m, center height 0.900 m above the collision grade |
| Clear width | 2.140 m between guard colliders, 2.076 m between opposite decorative newel caps |

The Blue Prince official Grand Hall still (first Blue Prince entry in `.runtime/visual-reference/sources.json`) informed the cool gray stone, pale layered edges and repeating classical profiles. Godot generates the stonework and faceted balusters at runtime and in the editor. The step silhouette stays crisp while the player walks on a continuous grade (23.47°) and a level landing. Set the exported collision layer to one included in the controller’s mask; a CharacterBody3D should use floor snapping and a maximum floor angle greater than the stair pitch.

Independent headless check, from the repository root:

```powershell
& .runtime/godot/4.7.2-standard/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/blue_prince_lab/stairs_check.gd
```
