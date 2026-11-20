# Academy look studies

Launch with `-- --architecture-lab`. The second row switches between five authored views. `H` toggles the HUD. The regular seeded expedition is unchanged.

| View | Visual reference | Academy treatment |
| --- | --- | --- |
| **Service Stairs / Stair Anomaly** (`7` / `8`) | [Blue Prince](https://store.steampowered.com/app/1569580/Blue_Prince/) for strong room identity; [The Exit 8](https://store.steampowered.com/app/2653790/The_Exit_8/) for a visual baseline. | An enamel sign, maintenance cabinet, exposed pipes and railed stair shaft. Hold the first-person camera, props and lights fixed. The flight leads down to B1 in the baseline and up to 01 in the anomaly. |
| **Archive / Ledger** (`9` / `0`) | [Crow Country](https://store.steampowered.com/app/1996010/Crow_Country/) for furniture that tells you how a room is used; [SIGNALIS](https://store.steampowered.com/app/1262350/SIGNALIS/) for layered document reading. | Catalogue drawers, paper boxes and a night desk. Cool window light frames a warm task lamp. Click the open register to read the night porter's correction. |
| **Meridian 03** (`5`) | Three spherical or three-axis mechanisms compared below. | A freestanding exhibit: cool wall, blue cradle and warm balance wheel. Click it to start or stop all three axes. |

## Style baseline

- **Shape:** an eye-level approach, a dominant room-specific silhouette, simple two-tone planes and fine outlines. Put the room identifier on a physical sign.
- **Palette:** blue-gray plaster, ink-dark framing, muted cupboard green, ochre hardware and paper, burgundy textiles. Reserve saturated colors for an object or route worth noticing.
- **Light:** room fixtures and exterior window light have separate roles. Anchor the scene with cool shapes and use warm lamps to direct attention. Compare Toon, Ink, Glow and SDFGI independently in the lab.
- **Evidence:** hold the camera and room fixtures fixed for anomaly pairs. Offer a stable detail shot for information a player can locate from a distance and read up close.

## Spherical tourbillon selection

Judged the manufacturer and entrant photos by silhouette at room distance, legibility in three-quarter view, and which forms still carry the look when small features are removed.

| Candidate | Read in the academy frame |
| --- | --- |
| **Vianney Halter - [Deep Space Tourbillon](https://www.gphg.org/en/watches/deep-space-tourbillon)** | **Selected.** The blue open cradle and pale bridge leave large gaps around the bright balance. The side and oblique photos show a silhouette that still reads when separated from the case and dial. |
| Jaeger-LeCoultre - [Duometre Heliotourbillon Perpetual](https://www.jaeger-lecoultre.com/us-en/news/watchmaking/duometre-heliotourbillon-perpetual) | A tightly interleaved sphere with a distinctive ruby hub. The silver-on-silver structure reads best in macro; its dense overlaps compete for shape at display distance. |
| Girard-Perregaux - [Planetarium Tri-Axial](https://www.gphg.org/en/watches/planetarium-tri-axial) | A compact and symmetrical cage. The adjacent globe contributes much of the composition. The isolated cage leaves less open space than Halter's. |

`Meridian.gd` builds an original blue cradle, two bright carrier rails, a silver bearing bridge, a brass balance, ruby accents and a coarse escape wheel. The local Y/X/Z pivots have authored periods of 26, 13 and 7 seconds, respectively. This is a kinematic exhibit; the escape wheel does not drive the pivots. The case, dial, branding and external meshes are omitted.

| Geometry metric | Count |
| --- | ---: |
| Optional local A26 GLB, measured from exported index buffers | 59,898 triangles |
| Meridian, measured from Godot mesh buffers after batching | **2,640 triangles / 16 material surfaces** |
| Meridian budget asserted by the live test | **3,000 triangles / 16 surfaces** |

The count includes the bearings and the mechanism's own foot, and excludes the stone pedestal and chamber. Batching is per material within each moving pivot. The A26 asset remains a separate, opt-in comparison.

## Capture and verification

```powershell
& .runtime/python/Scripts/python.exe tools/blue_prince_lab/look_studies_e2e.py --clean
```

The check uses the normal game entry and live MCP bridge. It verifies the shared stair camera and opposite directions, opening the ledger by clicking it, the mechanism's three-axis start and stop, and the mesh budget. The `--clean` captures are real 1280x720 Forward+ with SDFGI enabled and the HUD hidden. PNGs and the report are written under `.runtime/rogue-mcp/`.
