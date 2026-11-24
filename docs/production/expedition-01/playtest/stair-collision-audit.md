# Expedition 01 — east and west stair collision audit

**Result (2026-11-24):** Both production spirals already use a navigable helical ramp assembled from convex wedges. The player climbed both public approaches to the upper landings using normal movement, without jumping. The west recovery climb from the caisson floor also passed. Keep the production geometry as shipped for this audit.

## Evidence

Instantiated the unmodified working-tree `Expedition.tscn` in Godot 4.7.2 .NET, headless at fixed 60 FPS, with the full production fixture. Rays used layer 1 and excluded the player. Capsule probes used the production `CharacterBody3D.test_move` and its 60° floor limit. The walk checks used the production physics process and quiet/forward inputs, with waypoints at 1.02 m radius; they placed the player once at each approach and let the controller do the climb. This is a targeted physics replay, not a full story run or a visual rendering check.

| Measurement | West (x = 49.15 m) | East (x = 73.35 m) |
|---|---:|---:|
| Visual tread meshes / children on those meshes | 126 / 0 | 41 / 0 |
| Independent convex collision hulls | 630 | 205 |
| Downward rays across angular slices and radii: hits / total | 6,786 / 6,786 | 2,205 / 2,205 |
| Of those, hits on another collider in the full fixture | 48 | 23 |
| Center-route rise/run across angular seams | 0.771–0.777 | 0.771–0.777 |
| Radial seam pairs: both rays hit / pairs sampled | 504 / 504 | 164 / 164 |
| Radial pairs touching another collider; excluded from delta | 4 | 2 |
| Largest height difference across remaining radial pairs (±4 mm from seam) | 0.032 mm | 0.032 mm |
| Center-route capsule support: passes / queries | 378 / 378 | 123 / 123 |
| Grounded position after public approach → upper landing | (49.151, 4.801, 11.713) | (73.351, 4.801, 11.713) |

`ExpeditionKit.gd` builds decorative `HelicalTread` boxes with collision disabled. Each 11.71 cm rise is spanned by five radial `ConvexPolygonShape3D` strips with sloped tops, nominally 15 mm above the stepped reference at the nosing. The west includes 85 additional interval slices below the public approach. The angular seam measurement brackets interior wedge boundaries at index ±0.02; the radial measurement brackets each shared strip boundary at the midpoint of its chord. The center-seam grade is about 38°. Across the wider sweep, some rays hit steep wedge faces (minimum normal Y ≈ 0.167) or other colliders; the walk and capsule results apply to the tested center route, not every radius.

**Upper transfer:** The point rays expose a local discontinuity. At x = stair center, the last sloped hit just before the final seam was at Y ≈ 4.813 m. The straight tangent samples at z = 9.12 and 9.45 m missed within ±0.22 m of Y = 4.8 m; the slab was hit at z = 9.47 m and farther along. The real capsule crossed this transfer on both walks and settled grounded at Y ≈ 4.801 m. The playable route therefore works with the current capsule and controller even though the tangent is not a continuous raycast surface through the transfer.

**West recovery:** The existing `ShaftRecoveryTest.gd` passed: real fall inside the caisson, landing on the recovery floor, normal movement up the lower west spiral, grounded return to the public landing at Y ≈ 0.00084 m, and retry on a separate out-of-bounds fall.

## Reproduce

From the repository root, with the project-local Godot executable assigned to `$engine`:

```powershell
& $engine --headless --path . --fixed-fps 60 --script res://docs/production/expedition-01/playtest/stair-audit.gd
& $engine --headless --path . --fixed-fps 60 --script res://scenes/expedition_01/ShaftRecoveryTest.gd
```

Both exited 0. Local ignored evidence: `.runtime/stair-audit.gd`, `.runtime/stair-audit.log`, and `.runtime/stair-audit-recovery.log`.
