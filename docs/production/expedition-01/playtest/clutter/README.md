# Clutter layout / capsule fixture

Independent Godot 4.7.2 headless project. Run from the repository root; `run.py` copies the fixture and request into a unique `.runtime/clutter-run-*` directory. The production project, autoloads and room queue are outside the fixture.

```powershell
$clutter = 'docs/production/expedition-01/playtest/clutter'
python -B "$clutter/run.py" --self-test > .runtime/clutter-report.json
python -B "$clutter/test_api.py" -v
python -B "$clutter/run.py" --sweep > .runtime/clutter-sweep.json
python -B "$clutter/run.py" --room-id graph/entry --seed 31 --density 0.3 --max-layers 5
python -B "$clutter/run.py" --batch .runtime/clutter-requests.json > .runtime/clutter-batch.json
```

`--layout-only` skips capsule walks; `--godot` can override the repository-local executable. CLI exits 1 on an acceptance failure and emits the report. Each run directory includes `report.json` and `godot.log` when available.

## Batch and export contract

Import `run.py` from this directory:

```python
from run import evaluate_rooms, generate_layout

requests = [
    {"room_id": "graph/entry", "seed": 31, "density": 0.3, "max_layers": 5},
    {"room_id": "graph/archive", "seed": 31},
]
report = evaluate_rooms(requests)  # also the JSON array accepted by --batch
accepted = [row for row in report["rooms"] if row["status"] == "pass"]
layout = generate_layout("graph/entry", 31, density=0.3, max_layers=5)
```

- `room_id` is the opaque graph identifier and participates in seeding (SHA-256 prefix XOR seed). `seed` is a JSON-safe signed integer. Request order and duplicates are preserved; identical requests replay on the pinned engine. Geometry uses the same fixture envelope for every graph ID.
- `density=1.0` (default) keeps all eligible candidate stack sites; in `(0,1)` each eligible site is sampled with the given probability, and `0` produces an empty room. Density is a probability, not a target count. `max_layers=3` (default) accepts integers 1–5; the first retained stack reaches the cap, and subsequent stacks choose depths up to the cap. A sparse draw can be empty.
- `clutter-report/v1`: `rooms[]` contains `room_id`, `seed`, `layout`, `layout_errors`, `seed_check`, `max_layer` (actual), `status` (`pass`, `fail`, `layout_only`), and `traversals[]`. Each traversal reports direction, status (`pass`, `blocked`, `fail`), motion frames, waypoints reached, off-floor frames, named contacts and end position. `ok` aggregates requested checks. `evaluate_rooms(..., physics=False)` gives geometry-only status; `generate_layout(...)` returns only the layout and raises for invalid input or failed geometry acceptance.
- `clutter-layout/v1`: units are meters and vectors use `[x,y,z]` (Y up). Export includes `room_id`, `seed`, `density`, `max_layers`, `room_size`, `door_width`, `route_clear_half_width`, floor-level `route[]`, and `items[]` with `id`, `center`, full `size`, `support` (parent ID or empty for floor), and 1-based `layer`. To reconstruct a collider, place an axis-aligned `BoxShape3D` of `size` at `center`. Room is centered in X/Z with floor at Y=0; east/west doorways are centered at Z=0, have 2.1 m headroom, and sit in the end walls at X=±5 m. Route endpoints extend outside both doors.

## Acceptance mechanics

Generation reserves a dogleg with a 1.16 m wide by 2 m high clearance envelope, then places seeded, jittered box stacks. Geometry checks room bounds, pairwise overlaps, route clearance, parent/child face contact, and the cumulative uniform-density center of mass of each supported subtree against its contact rectangle with a 5 cm margin. This is a static single-support box model. The capsule fixture rebuilds the exported boxes, walls, jambs, lintels, ceiling and floor as `StaticBody3D` colliders. It walks a real `CharacterBody3D` with radius 0.32 m, total height 1.75 m and `move_and_slide()` at 60 Hz, matching the expedition capsule dimensions and floor settings. A pass requires reaching all waypoints in each direction, maintaining floor contact and zero non-floor slide contacts. The fixture uses prescribed waypoints; it tests physical passage along the exported route.

`--self-test` covers repeatability, adjacent seeds, signed seed extremes, three-layer stacking, and six negative controls: air gap, unstable overhang, volume overlap, cumulative load shift, door obstruction and headroom obstruction. The last two must physically stall and name the injected collider in addition to failing geometry.

`--sweep` emits `clutter-sweep/v1`: seeds 0–999 for each of 20 density/layer strata (`0, .25, .5, .75, 1` × `1, 2, 3, 5`); the report stores aggregated geometry counts, exact failing inputs and capsule summaries, not coordinates. Seeds 0, 499 and 999 are walked in both directions in each stratum; add `--layout-only` for just geometry.

## Furnished design prototype

`mode: "furnished"` is opt-in per request (CLI `--mode furnished` or Python `generate_layout(..., mode="furnished")`). Omitted `mode` and explicit `"stress"` preserve the old stress generator and report shape. The two layouts use the same 10 x 8 m envelope, door geometry and seed input.

- The **workshop** groups a pedestal workbench, tool cupboard, stool and optional tool tray. The opposite **dispatch** wall groups a drawer counter, stock cupboard, optional outgoing parcel and stock crates. The seed mirrors the groups between the long walls and varies portable dressing. The fixed furniture remains at density 0; density samples the three portable dressing sites. `max_layers` applies to loose floor crates, which intentionally stop at two. Exported `layer` still records the full structural support chain (e.g. pedestal, worktop, tray).
- A straight through aisle joins the doors. `layout.stations[]` gives each work group's `id`, `function`, furniture `target` and approach `route`. `layout.items[]` adds `kind` and `station` for consumers; the usual box collider/support fields still apply. Station approaches reserve the same clearance envelope as the aisle. `rooms[].station_traversals[]` reports `approach` and `return` per station, and both must pass along with `traversals[]` for overall acceptance. These tests walk to the operating position; furniture interaction is outside the fixture.
- `furnished_control=True` runs a negative control with the same stool moved into the workshop approach. The capsule must stall against the stool assembly while the door-to-door aisle still passes.

```powershell
python -B "$clutter/run.py" --room-id prototype/workshop-dispatch --seed 31 --mode furnished
python -B "$clutter/design_review.py"
```

`design_review.py` uses Pillow to draw the same tested collider exports as a labeled axonometric cutaway and top plan. It writes `.runtime/design-review/clutter/before-after.png` (1600 x 960) and `acceptance.json`. The comparison is the first two rows in the report; additional furnished runs cover 16 seeds at three dressing settings. Drawer/door markings in the illustration are graphical details; the export contains the underlying box colliders.
