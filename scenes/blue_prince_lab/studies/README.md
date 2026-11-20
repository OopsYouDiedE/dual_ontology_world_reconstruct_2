# Academy look studies

Launch with `-- --architecture-lab`. The second row switches between the authored views. `H` toggles the HUD. Public Hall and Observatory also share the movement, mounted below walkable glass.

| View | Visual reference | Academy treatment |
| --- | --- | --- |
| **Service Stairs / Stair Anomaly** (`7` / `8`) | [Blue Prince](https://store.steampowered.com/app/1569580/Blue_Prince/) for strong room identity; [The Exit 8](https://store.steampowered.com/app/2653790/The_Exit_8/) for a visual baseline. | An enamel sign, maintenance cabinet, exposed pipes and railed stair shaft. Hold the first-person camera, props and lights fixed. The flight leads down to B1 in the baseline and up to 01 in the anomaly. |
| **Archive / Ledger** (`9` / `0`) | [Crow Country](https://store.steampowered.com/app/1996010/Crow_Country/) for furniture that tells you how a room is used; [SIGNALIS](https://store.steampowered.com/app/1262350/SIGNALIS/) for layered document reading. | Catalogue drawers, paper boxes and a night desk. Cool window light frames a warm task lamp. Click the open register to read the night porter's correction. |
| **Meridian 03** (`5`) | Three spherical or three-axis mechanisms compared below. | Reconstructed Deep Space case, dial and three moving cages. Click it to start or stop all three axes. |

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

`Meridian` is the existing control name. It now shows a reconstruction from Halter’s oblique and profile photographs. The stepped bezel, chapter ring, blued peripheral pointers, blue swing, pierced silver bridge, gold balance, hairspring, ruby and crown are separate visible features. Only the dial lettering uses a texture. The inner, middle and outer pivots take 40 seconds, 6 minutes and 30 minutes per turn. The balance oscillates at 3 Hz; the peripheral minute and hour hands complete their own turns in one and twelve hours. The watch starts on entry; click the centre to pause and resume at the same pose. Internal parts hidden in the photographs are approximations; motion is kinematic.

| Godot mesh-buffer measurement (highest detail) | Triangles | Material surfaces |
| --- | ---: | ---: |
| Complete watch, including dial lettering and crystal | **8,266** | **13** |
| Moving assembly alone | **3,336** | Included above |
| Enforced ceilings | 8,500 complete / 3,500 moving | 16 complete |

The count excludes the stand and room. The older local 59,898-triangle A26 print model depicts a different assembly and is not used to construct this watch.

## Capture and verification

```powershell
& .runtime/python/Scripts/python.exe tools/blue_prince_lab/look_studies_e2e.py --clean
```

The check uses the normal game entry and live MCP bridge. It verifies the shared stair camera and opposite directions, opening the ledger by clicking it, the mechanism's three-axis start and stop, and the mesh budget. The `--clean` captures are real 1280x720 Forward+ with SDFGI enabled and the HUD hidden. PNGs and the report are written under `.runtime/rogue-mcp/`.
