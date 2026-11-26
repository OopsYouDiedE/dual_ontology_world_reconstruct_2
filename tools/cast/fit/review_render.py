"""Review renders of a hero GLB in Blender: flat toon shading, Freestyle ink lines, and a sun that always
comes from the upper left of the camera side, whichever way the camera looks at the figure.

    blender -b --factory-startup --python tools/cast/fit/review_render.py -- <hero.glb> <out prefix> \
        [--views front,back,left,right,face,face_left,face_right,back_head] [--clip idle --frame 0]

Each view writes <out prefix>_<view>.png. The sun is placed relative to the camera (up 45 degrees, 40 degrees
to its left, on the camera's side of the figure), so front and back reviews are lit the same way and a
shadow on the left cheek means the same thing in every view. The toon ramp has three bands like the
game's SoftToonLight; lines are Freestyle silhouettes, creases and borders at 1.6 px.
"""
import argparse
import math
import sys

import bpy
from mathutils import Euler, Matrix, Vector

VIEWS = {
    # name: (yaw of the camera around the figure, degrees; 0 = in front), framing
    "front": (0, "body"), "back": (180, "body"), "left": (90, "body"), "right": (-90, "body"),
    "face": (0, "face"), "face_left": (35, "face"), "face_right": (-35, "face"), "back_head": (180, "face"),
}


def toon_material(src):
    """Albedo x three-band toon ramp of the diffuse light, as the game's finish."""
    m = bpy.data.materials.new(src.name + "_review")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tex = None
    if src.use_nodes:
        bsdf = src.node_tree.nodes.get("Principled BSDF")
        if bsdf and bsdf.inputs["Base Color"].is_linked:
            img = bsdf.inputs["Base Color"].links[0].from_node.image
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = img
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(s2r.outputs["Color"], bw.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (0.55, 0.57, 0.66, 1)
    els[1].position, els[1].color = 0.12, (0.78, 0.79, 0.84, 1)
    e = els.new(0.38)
    e.color = (1.0, 1.0, 1.0, 1)
    nt.links.new(bw.outputs[0], ramp.inputs[0])
    mul = nt.nodes.new("ShaderNodeMixRGB")
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(ramp.outputs[0], mul.inputs[1])
    if tex:
        nt.links.new(tex.outputs["Color"], mul.inputs[2])
    else:
        mul.inputs[2].default_value = (0.8, 0.8, 0.8, 1)
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(mul.outputs[0], em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("glb")
    p.add_argument("out")
    p.add_argument("--views", default="front,back,face,face_left,face_right,back_head")
    p.add_argument("--clip", default="idle")
    p.add_argument("--frame", type=int, default=0)
    p.add_argument("--res", type=int, default=900)
    args = p.parse_args(a)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.glb)
    sc = bpy.context.scene
    rig = next((o for o in sc.objects if o.type == "ARMATURE"), None)
    if rig and rig.animation_data:
        act = next((x for x in bpy.data.actions if x.name.split("_")[0] == args.clip or x.name == args.clip), None)
        if act:
            rig.animation_data.action = act
    sc.frame_set(args.frame)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for o in meshes:
        for slot in o.material_slots:
            if slot.material:
                slot.material = toon_material(slot.material)
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        m = ev.to_mesh()
        pts += [o.matrix_world @ v.co for v in m.vertices]
        ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    head_z = hi.z - 0.13
    if rig:
        hb = next((b for b in rig.pose.bones if b.name.endswith("Head")), None)
        if hb:
            head_z = (rig.matrix_world @ hb.head).z + 0.09
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("review")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.62, 0.64, 0.66, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sc.render.use_freestyle = True
    sc.render.line_thickness_mode = "ABSOLUTE"
    sc.render.line_thickness = 1.6
    fs = sc.view_layers[0].freestyle_settings
    ls = fs.linesets[0] if len(fs.linesets) else fs.linesets.new("ink")
    ls.select_silhouette = ls.select_border = ls.select_crease = True
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("ink")
    ls.linestyle.color = (0.08, 0.07, 0.07)
    ls.linestyle.thickness = 1.6
    sc.view_layers[0].freestyle_settings.crease_angle = math.radians(120)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 4.0
    sun.data.angle = math.radians(2)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    for name in args.views.split(","):
        yaw, frame = VIEWS[name]
        y = math.radians(yaw)
        if frame == "body":
            cz, size = (lo.z + hi.z) / 2, (hi.z - lo.z) * 1.06
            sc.render.resolution_x, sc.render.resolution_y = int(args.res * 0.62), args.res
        else:
            cz, size = head_z, 0.42
            sc.render.resolution_x = sc.render.resolution_y = args.res
        cx = (lo.x + hi.x) / 2
        cam.data.ortho_scale = size
        # camera on a circle around the figure (facing -Y at yaw 0), looking at it
        cam.location = (cx + 6 * math.sin(y), -6 * math.cos(y), cz)
        cam.rotation_euler = (math.radians(90), 0, y)
        # sun from the camera's upper left, on the camera's side: rotate a light that shines along the
        # camera's view direction by 40 degrees to the left and 45 degrees down
        sun.rotation_euler = (cam.matrix_world.to_3x3() @ Euler((math.radians(-45), math.radians(-40), 0)).to_matrix()).to_euler()
        sc.render.filepath = f"{args.out}_{name}.png"
        bpy.ops.render.render(write_still=True)
    print("REVIEW", args.glb, args.views)


if __name__ == "__main__":
    main()
