"""Quad retopology of a hero's Tripo parts, one part at a time, for build_tripo_parts.py.

    .runtime/cast-pass/blender.sh --python tools/cast/fit/retopo_parts.py -- --hero quer
    sh tools/cast/fit/retopo_parts.sh quer          # reruns after a QuadriFlow crash until done

Each part of reference/tripo-parts/<hero>.glb (in the import frame) is cleaned, thickened if it is an open
sheet, voxel-remeshed into a closed shell and QuadriFlow-remeshed into even quads (edge about 1 % of the
figure's height, so the wireframe reads at a glance), then projected back onto the Tripo surface (a sheet onto
its thickened copy, so it stays a thin closed shell) and relaxed. Parts with fewer than 300 faces or smaller than 3 % of the height (buttons, laces, studs) and
parts QuadriFlow rejects keep their Tripo triangles.

Results go to .runtime/facefit/parts-retopo/<hero>/<part>.npz (vertices, face sizes, face indices) or
<part>.keep; progress.json names the part being remeshed, so a crash marks it .keep on the next run.
"""
import argparse
import json
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np

FIT = Path(__file__).resolve().parent
sys.path.append(str(FIT))
from retopo import clean_for_quadriflow  # noqa: E402

ROOT = FIT.parents[2]
PARTS = FIT.parent / "reference" / "tripo-parts"
CACHE = ROOT / ".runtime" / "facefit" / "parts-retopo"


def short(name):
    return name.replace("tripo_part_", "p").replace("_Clone", "").split(".")[0]


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def clean(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=2e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    open_sheet = any(e.is_boundary for e in bm.edges)
    bm.to_mesh(o.data)
    bm.free()
    return open_sheet


def drop_nested(result):
    """A voxel shell of a part that encloses a hollow (a head around its mouth and eye sockets) has a second,
    inner shell; projected back it would land on the outer surface and fight it. Delete every connected
    piece whose bounding box lies inside another piece's."""
    bm = bmesh.new()
    bm.from_mesh(result.data)
    seen, comps = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        comp, stack = [], [f]
        seen.add(f.index)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        co = np.array([tuple(v.co) for g in comp for v in g.verts])
        comps.append((comp, co.min(0), co.max(0)))
    drop = []
    for i, (ci, lo, hi) in enumerate(comps):
        for j, (_, lo2, hi2) in enumerate(comps):
            if i != j and (lo >= lo2).all() and (hi <= hi2).all():
                drop += ci
                break
    if drop:
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(result.data)
    bm.free()


def remesh(o, height):
    """Voxel shell + QuadriFlow + projection back onto a copy of the original. Returns the new object or None."""
    source = o.copy()
    source.data = o.data.copy()
    bpy.context.scene.collection.objects.link(source)
    co = np.array([tuple(v.co) for v in o.data.vertices])
    extent = float(np.ptp(co, axis=0).max())
    area = sum(p.area for p in o.data.polygons)
    edge = 0.0058 * height
    faces = int(np.clip(area / edge ** 2, 40, 6000))
    sheet = clean(o)
    if sheet:
        sol = o.modifiers.new("Thick", "SOLIDIFY")
        sol.thickness, sol.offset = 0.0035 * height, 0.0
        activate(o)
        bpy.ops.object.modifier_apply(modifier=sol.name)
        # project onto the thickened sheet, not the bare one: each wall of the closed remesh then settles on
        # its own side, so the part stays a thin closed shell (no wall fighting, no torn edges to outline)
        bpy.data.objects.remove(source, do_unlink=True)
        source = o.copy()
        source.data = o.data.copy()
        bpy.context.scene.collection.objects.link(source)
    result = None
    for k in (1.0, 1.6, 2.5):
        trial = o.copy()
        trial.data = o.data.copy()
        bpy.context.scene.collection.objects.link(trial)
        activate(trial)
        trial.data.materials.clear()
        trial.data.remesh_voxel_size = min(0.0024 * height * k, extent / 6)
        trial.data.use_remesh_fix_poles = False
        bpy.ops.object.voxel_remesh()
        if len(trial.data.polygons) < 8 or not clean_for_quadriflow(trial):
            bpy.data.objects.remove(trial, do_unlink=True)
            continue
        dense = len(trial.data.polygons)
        bpy.ops.object.quadriflow_remesh(target_faces=faces, use_preserve_sharp=False, use_preserve_boundary=False,
                                         use_mesh_symmetry=False, seed=0)
        if 12 <= len(trial.data.polygons) < dense:
            result = trial
            break
        bpy.data.objects.remove(trial, do_unlink=True)
    if result is not None:
        activate(result)
        drop_nested(result)
        wrap = result.modifiers.new("Wrap", "SHRINKWRAP")
        wrap.target = source
        if sheet:
            # the walls lie a sheet's thickness apart: a projection along the normal could reach the far wall
            wrap.wrap_method = "NEAREST_SURFACEPOINT"
        else:
            wrap.wrap_method = "PROJECT"
            wrap.use_project_x = wrap.use_project_y = wrap.use_project_z = False
            wrap.use_negative_direction = wrap.use_positive_direction = True
            wrap.project_limit = 0.012 * height
        bpy.ops.object.modifier_apply(modifier=wrap.name)
        smooth = result.modifiers.new("Relax", "CORRECTIVE_SMOOTH")
        smooth.factor, smooth.iterations, smooth.smooth_type = 0.25, 3, "LENGTH_WEIGHTED"
        smooth.use_only_smooth = True
        bpy.ops.object.modifier_apply(modifier=smooth.name)
        new = np.array([tuple(v.co) for v in result.data.vertices])
        ratio = np.ptp(new, axis=0).max() / max(extent, 1e-9)
        if not 0.85 < ratio < 1.15:
            bpy.data.objects.remove(result, do_unlink=True)
            result = None
    bpy.data.objects.remove(source, do_unlink=True)
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--hero", required=True)
    a = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    out = CACHE / a.hero
    out.mkdir(parents=True, exist_ok=True)
    prog = out / "progress.json"
    if prog.exists():
        doing = json.loads(prog.read_text()).get("doing")
        if doing and not (out / f"{doing}.npz").exists() and not (out / f"{doing}.keep").exists():
            (out / f"{doing}.keep").write_text("quadriflow crashed\n")
            print("CRASHED_KEEP", doing)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(PARTS / f"{a.hero}.glb"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        activate(o)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    allco = np.concatenate([[tuple(v.co) for v in o.data.vertices] for o in meshes])
    height = float(np.ptp(allco[:, 2]))
    done = kept = 0
    for o in sorted(meshes, key=lambda o: o.name):
        name = short(o.name)
        if (out / f"{name}.npz").exists() or (out / f"{name}.keep").exists():
            continue
        co = np.array([tuple(v.co) for v in o.data.vertices])
        if len(o.data.polygons) < 300 or np.ptp(co, axis=0).max() < 0.03 * height:
            (out / f"{name}.keep").write_text("small\n")
            kept += 1
            continue
        prog.write_text(json.dumps({"doing": name}))
        new = remesh(o, height)
        if new is None:
            (out / f"{name}.keep").write_text("rejected\n")
            kept += 1
            continue
        m = new.data
        verts = np.array([tuple(v.co) for v in m.vertices], np.float32)
        sizes = np.array([len(f.vertices) for f in m.polygons], np.int32)
        idx = np.array([i for f in m.polygons for i in f.vertices], np.int32)
        np.savez(out / f"{name}.npz", co=verts, sizes=sizes, idx=idx)
        bpy.data.objects.remove(new, do_unlink=True)
        done += 1
        print("PART", name, len(o.data.polygons), "->", len(sizes), flush=True)
    prog.write_text(json.dumps({"doing": None}))
    print("RETOPO_PARTS_DONE", a.hero, "remeshed", done, "kept", kept)


if __name__ == "__main__":
    main()
