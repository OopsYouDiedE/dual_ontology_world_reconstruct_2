# Academy sandbox blueprints

Eight original room layouts authored in the native FreeSO `XmlHouseData` format. Use the `.xml` files as sandbox blueprints (client `Content/Blueprints/`); the sandbox selector lists the file basenames. Use a clean sandbox profile to test the XML: an existing same-name `LocalHouse/<name>.fsov` can take precedence. These files contain architecture and object placements; the original sandbox creates and runs the SimAntics VM.

## Architectural provenance

The room evidence comes from `git show eee80911fcf64b35273ee3f0f28c42b123eb7c71:tools/building_construction/architect_rooms.json`. The old outlines and openings were snapped to the native tile grid. Door locations are walk-through wall gaps. Each room is centered on a separate 32 × 32 lot. The former story labels locate rooms within the old campus; standalone lots start at native ground level. Furnishings are native catalog analogues arranged to preserve the principal circulation and functional areas.

| XML basename | Old architectural ID | Ground footprint | Preserved layout |
| --- | --- | --- | --- |
| `foyer` | `F01` | 18 × 17 | Three ground thresholds, central hall, side seating and upper U-shaped gallery with banisters |
| `kitchen` | `B-P` | 7 × 6 | Side threshold, north cooking/work line, small dining table |
| `living_hall` | `living_hall` | 10 × 8 | Twin rear thresholds, three record stations, central stand and perimeter seating |
| `lecture` | `lecture` | 10 × 10 | Twin rear thresholds, teaching front and two seating blocks divided by an aisle |
| `clinic` | `clinic` | 9 × 8 | Central rear threshold and four bed positions, with an open central aisle |
| `dining` | `main_dining` | 14 × 12 | Twin rear thresholds, four dining clusters and serving cabinets |
| `valve_gallery` | `b2_valve_gallery` | 8 × 5 | Side threshold and three service cabinet positions along the far wall |
| `service_stair` | `service_stair_M` | 6 × 6 | Twin rear thresholds and a service landing with utility cabinet |

The foyer uses five native `0x28FED160` window object placements on the old window sites. The pinned `TSOClient/FSO.Content.TSO/Content/Objects/catalog_downloads.xml` has an active `s="1"` entry for this GUID (`Windows - Lodge -Small`). The pinned `Content/Patch/TSOPorts/windowslodge.str.piff` identifies `windowslodge.iff` and the localized name `Golden View (small)`. The west host edges are `TopLeft` at `(7,12)`, architectural levels 0 and 1, with XML `dir=6`. The three rear host edges are `TopRight` at `(12,8)`, `(16,8)` and `(19,8)`, architectural level 1, with XML `dir=0`. The wall edges are kept intact for SimAntics to apply the object wall style. The directions target the selected wall edges using the front-wall mapping in `VMEntity.SetWallStyle` / `VMGameObject.PositionChange`; the asset's actual mounting behavior still requires a native sandbox check. Other rooms ledger historical window sites as reserved intact walls.

The foyer's historic split stair, valve machinery and specific clinical props await verified native equivalents. The foyer upper gallery is authored architecture without a native stair connection. The old service-stair record models the landing and contains an empty `stairs` array.

## Native fields and object references

Pinned FreeSO: `4c6b3e8f5835b228723caea3c9f683c62f244f73`. `TSOClient/tso.world/Model/XmlHouse.cs` defines the XML; `tso.simantics/Utils/VMWorldActivator.cs` adds 1 to the architectural levels and uses object levels verbatim. `dir=0/2/4/6` is north/east/south/west. `tso.simantics/Utils/VMArchitectureTools.cs` defines the primary wall bits and their mirrored neighbors (`TopLeft` ↔ `BottomRight` along X, `TopRight` ↔ `BottomLeft` along Y). Styles/patterns `1/0` and `14/251` are the wall and banister pairs in `tso.content/WorldWallProvider.cs`. Floor IDs 9–11 appear in the shipped `FSO.Content.TSO/Content/Blueprints/empty_lot_fso.xml`.

Every furniture GUID was read from a single-tile or master `OBJD` chunk of a pinned `TSOClient/FSO.Content.TSO/Content/Objects/` IFF. Names below use the shipped OBJD label except where a more readable catalog label is given.

| GUID (hex) | Object | IFF basename |
| --- | --- | --- |
| `68EA432A` | Long Island Armchair | `k8lisarmchairts` |
| `B9EA4328` | Elgardian Plant | `k8elgplant` |
| `B7EA4340` | Long Island Deco Floor Lamp | `k8lidfloorlamp` |
| `02B9B1AC` | The Hold'em Cabinets | `Casino_Cabinet-Drawer_CC` |
| `DDEA43F0` | Oblique Kitchen Counter | `k8oblcounterhd` |
| `04EF513C` | Witch's Cauldron stove | `fso-autumn-witchcauldron` |
| `06EA4309` | Oblique Dining Table | `k8obldiningtablets` |
| `5DEA43F0` | Oblique Dining Chair | `k8obldiningchairts` |
| `ACEA43AA` | Long Island Deco Bookcase | `k8lidbookcase` |
| `53EA43A5` | Long Island Deco Desk Chair | `k8liddeskchair` |
| `19EA4376` | Elgardian Single Bed | `k8elgsinglebed` |
| `12EA4376` | Elgardian End Table | `k8elgendtable` |
| `89EA4394` | Luminosity Dining Table | `k8lmypdiningtablets` |
| `3CEA43F8` | Luminosity Dining Chair | `k8lmypdiningchairts` |

Verification: all eight files loaded through the pinned `XmlHouseData.Parse` in a .NET harness. Checks covered known XML fields, tile bounds, reciprocal wall faces, valid direction values, recorded GUIDs and non-overlapping rotated furniture OBJD footprints on floored tiles. The five catalog-verified windows were checked separately against their sidecar references and intact paired host edges. The client and authorized TSO data were unavailable for native placement execution, rendering and routing checks.

`plan_landmarks.json` is display metadata keyed by blueprint basename. Its levels are zero-based like floor and wall records. Threshold rows name real missing wall edges; landmark rows label existing object anchors by architectural role; window rows bind matching object GUIDs, tiles, directions and host edges. This file is for the expedition plan overlay and is not an input to FreeSO.
