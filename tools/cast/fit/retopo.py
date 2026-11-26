"""Retopologise each hero's Tripo model into a clean, single quad mesh at game resolution.

    blender -b --python tools/cast/fit/retopo.py -- --heroes detective,hale,quer,lucian [--faces 30000]

Only Tripo's geometry is used (its UVs and colours are discarded): the parts are joined, turned to face
-Y like MPFB, scaled to the hero's stature with the soles on the floor, voxel-remeshed into one closed
surface, then QuadriFlow-remeshed into evenly sized quads. Output: .runtime/facefit/retopo/<hero>.blend
(object '<hero>_retopo') plus front/side/three-quarter wireframe renders for review.
"""
import argparse
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

FIT = Path(__file__).resolve().parent
ROOT = FIT.parents[2]
REF = FIT.parent / "reference"
OUT = ROOT / ".runtime" / "facefit" / "retopo"
HEIGHT = {"detective": 1.76, "hale": 1.80, "quer": 1.56, "lucian": 1.86}


def load_tripo(hero):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(REF / "tripo" / f"{hero}.glb"))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in [o for o in bpy.data.objects if o is not obj]:
        bpy.data.objects.remove(o, do_unlink=True)
    obj.name = f"{hero}_tripo"
    # Tripo faces +X; MPFB faces -Y. Transform the mesh data directly (no operator context involved).
    from mathutils import Matrix
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.data.transform(Matrix.Rotation(-math.pi / 2, 4, "Z"))
    co = np.array([tuple(v.co) for v in obj.data.vertices])
    lo, hi = co.min(0), co.max(0)
    assert hi[0] - lo[0] > hi[1] - lo[1], ("Tripo model is not facing -Y after the turn", hi - lo)
    s = HEIGHT[hero] / (hi[2] - lo[2])
    obj.data.transform(Matrix.Translation((-(lo[0] + hi[0]) / 2 * s, -(lo[1] + hi[1]) / 2 * s, -lo[2] * s))
                       @ Matrix.Scale(s, 4))
    obj.data.update()
    # Tripo cloth (coats, scarves, capes) is a single-sided sheet; thinner than a voxel it breaks into lace.
    # Give every sheet a centred thickness first so the voxel pass sees solid cloth.
    sol = obj.modifiers.new("Thick", "SOLIDIFY")
    sol.thickness, sol.offset, sol.use_even_offset = 0.012, 0.0, False
    bpy.ops.object.modifier_apply(modifier=sol.name)
    return obj


def make_manifold(obj):
    """Voxel output can keep pinched vertices where thin parts touch; QuadriFlow needs a clean manifold."""
    import bmesh
    for _ in range(4):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bad = [v for v in bm.verts if not v.is_manifold]
        if not bad:
            bm.free()
            break
        bmesh.ops.delete(bm, geom=bad, context="VERTS")
        edges = [e for e in bm.edges if e.is_boundary]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
        bm.to_mesh(obj.data)
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # Keep only the largest shell (stray specks would also fail QuadriFlow).
    seen, shells = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, shell = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            shell.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        shells.append(shell)
    shells.sort(key=len, reverse=True)
    small = [f for sh in shells[1:] if len(sh) < 200 for f in sh]
    bmesh.ops.delete(bm, geom=small, context="FACES")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def edge_report(mesh):
    """(edges not shared by exactly two faces, edges whose two faces disagree on winding)."""
    uses = {}
    bad_dir = 0
    for p in mesh.polygons:
        vs = list(p.vertices)
        for a, b in zip(vs, vs[1:] + vs[:1]):
            key, d = (min(a, b), max(a, b)), a < b
            if key in uses:
                bad_dir += uses[key][0] == d
                uses[key] = (d, uses[key][1] + 1)
            else:
                uses[key] = (d, 1)
    odd = sum(1 for _, c in uses.values() if c != 2) + (len(mesh.edges) - len(uses))
    return odd, bad_dir


def clean_for_quadriflow(obj):
    """Alternate edit-mode cleanup (which itself can pinch edges) with manifold repair until QuadriFlow's
    precondition holds: every edge in exactly two consistently wound faces."""
    for _ in range(8):
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.0002)
        bpy.ops.mesh.dissolve_degenerate(threshold=0.0002)
        bpy.ops.mesh.delete_loose()
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.quads_convert_to_tris()
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        odd, bad = edge_report(obj.data)
        if not odd and not bad:
            return True
        make_manifold(obj)
    return False


def retopo(hero, voxel, faces):
    """Voxel-remesh then QuadriFlow. Thin parts (straps, braids, scarves) leave pinch points that QuadriFlow
    rejects; coarser voxels close them, and a shrinkwrap onto the untouched Tripo surface brings the
    detail back afterwards. Every attempt starts from a fresh import."""
    for size in (voxel, 0.008, 0.012, 0.016):
        obj = load_tripo(hero)
        source = obj.copy()
        source.data = obj.data.copy()
        source.name = obj.name + "_source"
        bpy.context.scene.collection.objects.link(source)
        # Tripo parts overlap and hide inner faces; a fine voxel pass keeps only the outer skin, so the
        # shrinkwrap below cannot pull vertices onto buried surfaces.
        bpy.ops.object.select_all(action="DESELECT")
        source.select_set(True)
        bpy.context.view_layer.objects.active = source
        source.data.remesh_voxel_size = 0.004
        source.data.use_remesh_fix_poles = False
        bpy.ops.object.voxel_remesh()
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        obj.data.materials.clear()
        obj.data.remesh_voxel_size = size
        obj.data.use_remesh_fix_poles = False
        bpy.ops.object.voxel_remesh()
        clean_for_quadriflow(obj)
        dense = len(obj.data.polygons)
        bpy.ops.object.quadriflow_remesh(target_faces=faces, use_preserve_sharp=False, use_preserve_boundary=False,
                                         use_mesh_symmetry=False, seed=0)
        if len(obj.data.polygons) < dense * 0.5:
            break
        print("RETOPO_RETRY voxel", size, "rejected")
    else:
        raise RuntimeError(f"QuadriFlow rejected {hero} at every voxel size")
    for layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(layer)
    wrap = obj.modifiers.new("Wrap", "SHRINKWRAP")
    wrap.target = source
    wrap.wrap_method = "PROJECT"
    wrap.use_project_x = wrap.use_project_y = wrap.use_project_z = False
    wrap.use_negative_direction = wrap.use_positive_direction = True
    wrap.project_limit = 0.02
    bpy.ops.object.modifier_apply(modifier=wrap.name)
    smooth = obj.modifiers.new("Relax", "CORRECTIVE_SMOOTH")
    smooth.factor, smooth.iterations, smooth.smooth_type = 0.25, 3, "LENGTH_WEIGHTED"
    smooth.use_only_smooth = True
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    bpy.data.objects.remove(source, do_unlink=True)
    return obj, dense, len(obj.data.polygons), size


def wire_renders(obj, hero):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light, sh.color_type, sh.single_color = "STUDIO", "SINGLE", (0.82, 0.80, 0.76)
    sh.show_object_outline = False
    mod = obj.modifiers.new("Wire", "WIREFRAME")
    mod.thickness = 0.0012
    mod.use_replace = False
    sc.render.resolution_x, sc.render.resolution_y = 700, 1400
    h = HEIGHT[hero]
    for yaw in (0, 35, 90):
        for o in [o for o in bpy.data.objects if o.type == "CAMERA"]:
            bpy.data.objects.remove(o, do_unlink=True)
        cd = bpy.data.cameras.new("c")
        cd.type, cd.ortho_scale = "ORTHO", h * 1.08
        cam = bpy.data.objects.new("c", cd)
        sc.collection.objects.link(cam)
        r = math.radians(yaw)
        cam.location = Vector((math.sin(r) * 8, -math.cos(r) * 8, h / 2))
        cam.rotation_euler = (math.pi / 2, 0, r)
        sc.camera = cam
        sc.render.filepath = str(OUT / f"{hero}-wire-{yaw}.png")
        bpy.ops.render.render(write_still=True)
    obj.modifiers.remove(mod)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--heroes", default="detective,hale,quer,lucian")
    p.add_argument("--faces", type=int, default=30000)
    p.add_argument("--voxel", type=float, default=0.005)
    a = p.parse_args(sys.argv[sys.argv.index("--") + 1:])
    OUT.mkdir(parents=True, exist_ok=True)
    for hero in a.heroes.split(","):
        obj, dense, quads, used = retopo(hero, a.voxel, a.faces)
        obj.name = f"{hero}_retopo"
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT / f"{hero}.blend"))
        wire_renders(obj, hero)
        print("RETOPO", hero, "voxel", used, "voxel faces", dense, "quads", quads)


if __name__ == "__main__":
    main()
