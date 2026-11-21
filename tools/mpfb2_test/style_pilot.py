"""MPFB2 → Academy style pilot. Run inside pinned Blender with an isolated MPFB profile."""
import argparse
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build import (HumanService, LocationService, TargetService, activate, animate, apply_modifier,
                   coat, duplicate, evaluated, glb_json, material)
from detail_look import R05_FACE, refine
from muscle import apply_local_targets, coverage, landmarks
from bl_ext.user_default.mpfb.services import ExportService, FaceService
from bl_ext.user_default.mpfb.ui.create_assets.maketarget import MakeTargetObjectProperties
from bl_ext.user_default.mpfb.ui.apply_assets.assetlibrary.assetsettingspanel import ASSET_SETTINGS_PROPERTIES

STYLE = {"masc": (0.12, 0.15, 0.13), "fem": (0.14, 0.12, 0.11)}
IDENTITY = {
    "chin-width": .20, "chin-bones": .16, "chin-height": -.12,
    "{side}-cheek-bones": .22, "{side}-cheek-volume": -.14,
    "nose-width2": -.22, "nose-point-width": -.16, "nose-scale-depth": .13,
    "{side}-eye-height2": .15, "mouth-scale-horiz": -.13,
    "mouth-lowerlip-volume": -.11,
}


def smooth(lo, hi, x):
    t = min(1.0, max(0.0, (x - lo) / (hi - lo)))
    return t*t*(3-2*t)


def clean():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.orphans_purge(do_recursive=True)


def unmask_coords(o):
    states = [(m, m.show_viewport) for m in o.modifiers]
    for m, _ in states:
        m.show_viewport = False
    out = [v.co.copy() for v in evaluated(o).vertices]
    for m, state in states:
        m.show_viewport = state
    return out


def style_target(folder, name, params, crown, chin):
    b = HumanService.create_human(feet_on_ground=False)
    b.shape_key_clear()  # Start from the literal HM08 Basis, not blended Phenotype.
    activate(b)
    MakeTargetObjectProperties.set_value("name", name, entity_reference=b)
    assert bpy.ops.mpfb.create_maketarget_target() == {"FINISHED"}
    key = b.data.shape_keys.key_blocks[name]
    points = [v.co.copy() for v in b.data.vertices]
    adjacency = [[] for v in points]
    for edge in b.data.edges:
        a, c = edge.vertices
        adjacency[a].append(c)
        adjacency[c].append(a)
    h = points[crown].z - points[chin].z
    top, jaw = points[crown].z, points[chin].z
    body_ids = {v.index for v in b.data.vertices if any(g.group == b.vertex_groups["body"].index for g in v.groups)}
    sole, height, _ = landmarks(b, crown, chin)
    head, palm, relief = params
    hand_x = max(abs(v.x) for v in points)
    hands = [v for v in points if abs(v.x) > hand_x*.89]
    wrist_center = sum((v for v in hands), Vector()) / len(hands)
    for i, co in enumerate(points):
        x, y, z = co
        up = (z - sole)/height
        hx = smooth(jaw - 0.22*h, jaw + .14*h, z)
        wx = smooth(hand_x*.77, hand_x*.89, abs(x))
        calf = smooth(.035,.075,up)*(1-smooth(.14,.21,up))
        signs = 1 if x > 0 else -1
        d = Vector((head*hx*x, head*.82*hx*(y-points[crown].y), head*hx*(z-jaw)))
        d += palm*wx*Vector((x-signs*hand_x*.87, y-wrist_center.y, z-wrist_center.z))
        d += .024*calf*Vector((x-signs*.09, y+.015, 0))
        # Regional neighbour smoothing; protect eyes, lips, nasal profile and silhouette.
        neck = math.exp(-((up-.83)/.026)**2)*math.exp(-((abs(x)-.071)/.065)**2)
        ribs = math.exp(-((up-.635)/.057)**2)*math.exp(-((abs(x)-.115)/.062)**2)
        knee = math.exp(-((up-.295)/.030)**2)*smooth(.022,.047,abs(x))
        cheek = math.exp(-((z-(jaw+.31*h))/(.12*h))**2)*math.exp(-((abs(x)-.18*h)/(.10*h))**2)
        if i in body_ids and y < -.025 and adjacency[i]:
            v = sum((points[j] for j in adjacency[i]), Vector())/len(adjacency[i])-co
            d += v * min(.62, (neck + ribs + knee + cheek)*relief*3.2)
        key.data[i].co = co+d
    path = folder / f"{name}.target"
    assert bpy.ops.mpfb.write_maketarget_target(filepath=str(path)) == {"FINISHED"}
    assert path.is_file() and path.stat().st_size > 3000
    bpy.data.objects.remove(b, do_unlink=True)
    return path


def garment(model, parts, kind, fabric, collar=None):
    obj = duplicate(model, kind)
    obj.shape_key_clear()
    activate(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in parts], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    if collar is not None:
        bmesh.ops.bisect_plane(bm, geom=[*bm.verts,*bm.edges,*bm.faces], dist=0.00001,
                              plane_co=(0,0,collar), plane_no=(0,0,1), clear_outer=True)
    bmesh.ops.dissolve_degenerate(bm, dist=0.000001, edges=list(bm.edges))
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context="EDGES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal.normalized()*.007
    bm.to_mesh(obj.data)
    bm.free()
    assert len(obj.data.polygons) > 100
    solid = obj.modifiers.new("Opaque tailored fabric thickness", "SOLIDIFY")
    solid.thickness, solid.offset = .004, 0
    solid.use_even_offset = True
    apply_modifier(obj, solid)
    bevel = obj.modifiers.new("Physical cuff / collar edges", "BEVEL")
    bevel.width, bevel.segments, bevel.angle_limit = .0016, 2, math.radians(42)
    apply_modifier(obj, bevel)
    # The extracted/solidified cuffs can inherit degenerate bevel loops.
    # Validate before export so Blender's glTF writer needn't mutate the mesh.
    obj.data.validate()
    obj.data.update()
    coat(obj, fabric)
    return obj


def hair(model, rig, top, jaw):
    h = top-jaw
    mesh = model.data
    xyz = [v.co.copy() for v in mesh.vertices]
    upper = [v for v in xyz if v.z > top-.29*h]
    oy = (max(v.y for v in upper)+min(v.y for v in upper))*.5
    center = Vector((0, oy, top-.35*h))
    tree = BVHTree.FromPolygons(xyz, [list(p.vertices) for p in mesh.polygons])

    def on_scalp(t, phi, clearance):
        d = Vector((math.sin(t)*math.sin(phi), -math.sin(t)*math.cos(phi), math.cos(t)))
        p, _, _, _ = tree.ray_cast(center, d, h)
        assert p is not None, (t, phi)
        return p+d*clearance

    def skin_to_head(obj, mat):
        if obj.type == "CURVE":
            activate(obj)
            bpy.ops.object.convert(target="MESH")
            obj = bpy.context.object
        assert "head" in rig.data.bones
        obj.parent = rig
        group = obj.vertex_groups.new(name="head")
        group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        deform = obj.modifiers.new("Head follow", "ARMATURE")
        deform.object = rig
        coat(obj, mat)
        return obj

    n, rings = 40, 10
    hair_mat = material("Dark walnut solid hair", (.047,.031,.026))
    cap = [on_scalp(0, 0, .008)]
    for i in range(1,rings+1):
        for j in range(n):
            phi = 2*math.pi*j/n
            max_t = 1.07+.79*(.5-.5*math.cos(phi))
            cap.append(on_scalp(max_t*i/rings, phi, .008))
    faces = [(0, 1+j, 1+(j+1)%n) for j in range(n)]
    for i in range(rings-1):
        a = 1+i*n
        faces.extend((a+j, a+j+n, a+(j+1)%n+n, a+(j+1)%n) for j in range(n))
    m = bpy.data.meshes.new("Scalp shell")
    m.from_pydata(cap, [], faces)
    cap_obj = bpy.data.objects.new("Hair_Cap", m)
    bpy.context.collection.objects.link(cap_obj)
    bm=bmesh.new(); bm.from_mesh(m); bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(m); bm.free()
    if sum(p.normal.z for p in m.polygons[:n]) < 0:
        for p in m.polygons:
            p.flip()
    solid = cap_obj.modifiers.new("Hair shell", "SOLIDIFY")
    solid.thickness = .003
    apply_modifier(cap_obj, solid)
    result = [skin_to_head(cap_obj, hair_mat)]
    curve = bpy.data.curves.new("Swept sculpted locks", 'CURVE')
    curve.dimensions, curve.resolution_u, curve.bevel_resolution = '3D', 7, 2
    curve.bevel_depth, curve.use_fill_caps = .019, True
    for j in range(7):
        phi = -.98+j*.32
        spline = curve.splines.new('BEZIER')
        spline.bezier_points.add(4)
        for k, (t, turn, lift, radius) in enumerate(((1.10,0,.009,.15),(.82,.15,.017,.94),
                                                     (.52,.37,.024,1.13),(.32,.70,.017,.77),
                                                     (.53,1.71,.008,.2))):
            p = spline.bezier_points[k]
            p.co = on_scalp(t, phi+turn, lift)
            p.handle_left_type = p.handle_right_type = 'AUTO'
            p.radius = radius
    locks = bpy.data.objects.new("Hair_SolidLocks", curve)
    bpy.context.collection.objects.link(locks)
    result.append(skin_to_head(locks, material("Chestnut carved locks", (.073,.043,.031))))
    return result


def fitted_brows(body, eyes, rig):
    """Opaque stylized brows, bound to neutral HM08 triangles and their brow keys."""
    verts = [v.co.copy() for v in body.data.vertices]
    body.data.calc_loop_triangles()
    tris = [tuple(tri.vertices) for tri in body.data.loop_triangles]
    tree = BVHTree.FromPolygons(verts, tris, all_triangles=True)
    eye = [v.co for v in eyes.data.vertices if v.co.x > 0]
    center = sum(eye,Vector())/len(eye)
    assert .015 < center.x < .070 and 1.53 < center.z < 1.72, center
    points, weights, faces = [], [], []
    for side in (-1,1):
        start=len(points)
        for i in range(13):
            t=i/12
            x=side*center.x*(.50+1.17*t)
            mid=center.z+.022+.007*smooth(0,.63,t)-.012*smooth(.60,1,t)
            # Broad inner wedge and fine outer tip, matching the reference silhouette.
            w=.0069*max(.06,(.70+.30*smooth(0,.16,t)-.36*t)*(1-smooth(.58,1.02,t)))
            for sign in (-1,1):
                p,n,index,_=tree.ray_cast(Vector((x,-1,mid+sign*w)),Vector((0,1,0)),2)
                assert p is not None
                tri=tris[index]
                a,b,c=(verts[j] for j in tri)
                e1,e2,q=b-a,c-a,p-a
                aa,ab,bb=e1.dot(e1),e1.dot(e2),e2.dot(e2)
                u=(bb*q.dot(e1)-ab*q.dot(e2))/(aa*bb-ab*ab)
                v=(aa*q.dot(e2)-ab*q.dot(e1))/(aa*bb-ab*ab)
                points.append(p+Vector((0,-.0013,0))); weights.append((tri,(1-u-v,u,v)))
        for i in range(12):
            idx=start+2*i
            face=(idx,idx+2,idx+3,idx+1)
            faces.append(face if side>0 else face[::-1])
    mesh=bpy.data.meshes.new('Brows'); mesh.from_pydata(points,[],faces); mesh.update()
    obj=bpy.data.objects.new('Brows',mesh); bpy.context.collection.objects.link(obj)
    obj.parent=rig
    group=obj.vertex_groups.new(name='head')
    group.add(list(range(len(points))),1.0,'REPLACE')
    deform=obj.modifiers.new('Head follow','ARMATURE'); deform.object=rig
    coat(obj,material('Painted walnut brows',(.045,.024,.017)))
    source=body.data.shape_keys
    if source:
        obj.shape_key_add(name='Basis')
        for key in source.key_blocks:
            if not key.name.startswith('brow'):
                continue
            target=obj.shape_key_add(name=key.name)
            for k,(ids,coeffs) in enumerate(weights):
                target.data[k].co=points[k]+sum(((key.data[j].co-verts[j])*c for j,c in zip(ids,coeffs)),Vector())
    return obj

def ramp_cavity(mesh):
    adj = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a,b = edge.vertices
        adj[a].append(b); adj[b].append(a)
    dst = mesh.color_attributes.new(name="CavityBake", type='FLOAT_COLOR', domain='POINT')
    for i, (v, ns) in enumerate(zip(mesh.vertices, adj)):
        p = v.co
        avg = sum((mesh.vertices[j].co for j in ns),Vector())/max(1,len(ns))
        radius = sum((mesh.vertices[j].co-p).length for j in ns)/max(1,len(ns))
        concave = (avg-p).dot(v.normal)/max(.0006,radius)
        pigment = 1-.15*smooth(.055,.26,concave)
        dst.data[i].color = (pigment,pigment,pigment,1)


def bake_color(obj, folder):
    """Cycles emission bake: neutral pigment × low-amplitude AO × cavity."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 12
    scene.render.bake.margin = 7
    ramp_cavity(obj.data)
    mesh = obj.data
    mat = obj.data.materials[0]
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    out = nodes.get('Material Output')
    shader = nodes.get('Principled BSDF')
    tex = nodes.new('ShaderNodeTexImage')
    image = bpy.data.images.new('Academy Skin - AO and cavity', 512, 512, alpha=False)
    tex.image = image
    nodes.active = tex
    ao = nodes.new('ShaderNodeAmbientOcclusion')
    ao.samples, ao.only_local = 8, True
    ao.inputs['Distance'].default_value = .034
    cavity = nodes.new('ShaderNodeVertexColor')
    cavity.layer_name = 'CavityBake'
    sub = nodes.new('ShaderNodeMath'); sub.operation='MULTIPLY_ADD'
    links.new(ao.outputs['AO'],sub.inputs[0]); sub.inputs[1].default_value=.24; sub.inputs[2].default_value=.76
    mult=nodes.new('ShaderNodeMixRGB'); mult.blend_type='MULTIPLY'; mult.inputs[0].default_value=1
    links.new(sub.outputs[0],mult.inputs[1]); links.new(cavity.outputs[0],mult.inputs[2])
    tint=nodes.new('ShaderNodeMixRGB'); tint.blend_type='MULTIPLY'; tint.inputs[0].default_value=1
    tint.inputs[1].default_value=mat.diffuse_color; links.new(mult.outputs[0],tint.inputs[2])
    emit=nodes.new('ShaderNodeEmission'); links.new(tint.outputs[0],emit.inputs[0]); links.new(emit.outputs[0],out.inputs['Surface'])
    activate(obj)
    rig_mods = [m for m in obj.modifiers if m.type == 'ARMATURE']
    for m in rig_mods:
        m.show_render = m.show_viewport = False
    assert bpy.ops.object.bake(type='EMIT') == {'FINISHED'}
    for m in rig_mods:
        m.show_render = m.show_viewport = True
    image.filepath_raw = str(folder / 'r05-pigment.png')
    image.file_format = 'PNG'; image.save(); image.pack()
    for nd in (ao,cavity,sub,mult,tint,emit):
        nodes.remove(nd)
    links.new(shader.outputs[0],out.inputs['Surface']); links.new(tex.outputs['Color'],shader.inputs['Base Color'])
    attrs = mesh.color_attributes
    attrs.remove(attrs['CavityBake'])
    return image.size[:]



def ink_mask(mesh, jaw, top):
    alpha = mesh.color_attributes.new(name='AcademyInk', type='BYTE_COLOR', domain='POINT')
    mesh.color_attributes.active_color = alpha
    h=top-jaw
    max_x=max(abs(v.co.x) for v in mesh.vertices)
    for v,k in zip(mesh.vertices,alpha.data):
        x,y,z=v.co
        hand=smooth(.84*max_x,.95*max_x,abs(x))
        center=(1-smooth(.085*h,.18*h,abs(x)))*smooth(jaw,jaw+.10*h,z)*(1-smooth(jaw+.52*h,jaw+.65*h,z))
        center*=1-smooth(-.085,-.046,y)
        k.color=(1,1,1,1-.68*max(hand,center))

def selective_normals(model, jaw, top):
    """Compare the weighted normal transfer on a shape-key-free scratch copy."""
    activate(model)
    clone = duplicate(model, 'Normals working copy')
    clone.shape_key_clear()
    for m in list(clone.modifiers):
        clone.modifiers.remove(m)
    before = [n.vector.copy() for n in clone.data.corner_normals]
    zspan = top-jaw
    verts = clone.data.vertices
    front = [v.co.y for v in verts if jaw+.31*zspan < v.co.z < jaw+.58*zspan and .14*zspan < abs(v.co.x) < .31*zspan]
    eye_y = sorted(front)[len(front)//3]
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=1.,
                                        location=(0, eye_y+.113, jaw+.43*zspan))
    proxy = bpy.context.object
    proxy.scale = (.102,.116,.148)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for poly in proxy.data.polygons:
        poly.use_smooth=True
    group=clone.vertex_groups.new(name='FaceNormal_OnlyCheeks')
    n=0
    for v in verts:
        x,y,z=v.co; f=(z-jaw)/zspan; side=abs(x)/zspan
        w = smooth(.18,.25,f)*(1-smooth(.48,.57,f))*smooth(.115,.19,side)*(1-smooth(.29,.39,side))
        w *= 1-smooth(eye_y+.009,eye_y+.046,y)
        if w>.008:
            group.add([v.index],w,'REPLACE'); n+=1
    transfer=clone.modifiers.new('Selective cheek normals','DATA_TRANSFER'); transfer.object=proxy
    transfer.use_loop_data=True; transfer.data_types_loops={'CUSTOM_NORMAL'}
    transfer.loop_mapping='POLYINTERP_NEAREST'; transfer.mix_mode='MIX'; transfer.mix_factor=.36
    transfer.vertex_group=group.name
    apply_modifier(clone,transfer)
    after=[n.vector.copy() for n in clone.data.corner_normals]
    assert n > 30 and len(before)==len(after)
    angles = [math.degrees(a.angle(b)) for a,b in zip(before,after) if a.angle(b)>math.radians(.1)]
    assert len(angles)>35
    model.data.normals_split_custom_set([tuple(v) for v in after])
    bpy.data.objects.remove(proxy,do_unlink=True); bpy.data.objects.remove(clone,do_unlink=True)
    return {"weighted_vertices":n,"changed_corners":len(angles),"mean_deg":sum(angles)/len(angles),"max_deg":max(angles)}


def export(folder, name, rig, meshes):
    activate(rig)
    for o in meshes:
        o.select_set(True)
    path = folder / f'{name}.glb'
    assert bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
                                     export_morph=True,export_animations=True,export_vertex_color="ACTIVE") == {'FINISHED'}
    glb = glb_json(path)
    assert len(glb['skins']) == 1 and len(glb['skins'][0]['joints']) == 53
    tris, counts = {}, {}
    for obj in glb['meshes']:
        tris[obj['name']] = sum(glb['accessors'][p['indices']]['count']//3 for p in obj['primitives'])
        counts[obj['name']] = len(obj.get('extras',{}).get('targetNames',[]))
        assert all('JOINTS_0' in p['attributes'] for p in obj['primitives']),obj['name']
    if name != 'r05-base':
        assert counts['Academy_HeadBody'] == 67, counts
        skin = next(m for m in glb['meshes'] if m['name']=='Academy_HeadBody')
        assert all('COLOR_0' in p['attributes'] for p in skin['primitives'])
    return {"triangles":tris,"blend_shapes":counts,"bytes":path.stat().st_size}


def load_preset(file):
    settings=HumanService.get_default_deserialization_settings()
    settings.update(feet_on_ground=False,subdiv_levels=0)
    return HumanService.deserialize_from_json_file(str(file),settings)


def verify_preset(preset, target, expected):
    # Verify standard MPFB JSON lookup with a scene-local extra asset root. Never
    # copy a generated target into the user's main MPFB library or preferences.
    scene = bpy.context.scene
    settings = ASSET_SETTINGS_PROPERTIES
    old = settings.get_value("second_root", entity_reference=scene)
    settings.set_value("second_root", str(target.parent.parent), entity_reference=scene)
    try:
        body = load_preset(preset)
        try:
            key = body.data.shape_keys.key_blocks.get(target.stem)
            assert key is not None and abs(key.value-1.0)<1e-6, target.stem
            loaded = unmask_coords(body)
            assert len(loaded) == len(expected)
            error = max((a-b).length for a,b in zip(loaded, expected))
            assert error < 0.0001, error
            return error
        finally:
            bpy.data.objects.remove(body, do_unlink=True)
    finally:
        settings.set_value("second_root", old, entity_reference=scene)


def specimen(out, preset, target, indices, identity=IDENTITY):
    crown, chin = indices
    styled = target is not None
    body = load_preset(preset)
    original = unmask_coords(body)
    preset_error = None
    if styled:
        apply_local_targets(body, identity)
        style = TargetService.load_target(body,str(target),name=target.stem,weight=1.0)
        assert style.value==1
        # Deserialization can find the custom target if installed in the editable custom-target library.
        snapshot = out/'human.r05-styled.json'
        HumanService.serialize_to_json_file(body,str(snapshot),save_clothes=False)
    coords = unmask_coords(body)
    if styled:
        preset_error = verify_preset(snapshot,target,coords)
    sole, h, head = landmarks(body,crown,chin)
    uniform=1.77/h
    activate(body); body.scale=(uniform,)*3; body.location.z=-sole*uniform
    bpy.ops.object.transform_apply(location=True,rotation=False,scale=True)
    top,jaw = 1.77,1.77-head*uniform
    rig = HumanService.add_builtin_rig(body,'game_engine')
    assert len(rig.data.bones)==53
    data = Path(LocationService.get_user_data())
    assets = [('Eyes','eyes/low-poly/low-poly.mhclo','Eyes'),
              ('Brows','eyebrows/eyebrow006/eyebrow006.mhclo','Eyebrows')]
    if styled:
        assets += [('Teeth','teeth/teeth_base/teeth_base.mhclo','Teeth'),
                   ('Tongue','tongue/tongue01/tongue01.mhclo','Tongue')]
    fitted=[]
    for name,path,kind in assets:
        o=HumanService.add_mhclo_asset(data/path,body,asset_type=kind,subdiv_levels=0,material_type='GAMEENGINE')
        o.name=o.data.name=name; fitted.append(o)
    activate(body); TargetService.bake_targets(body)
    body.name=body.data.name='Academy_HeadBody'
    if styled:
        FaceService.load_targets(body,False,True,True)
        # MHCLO indices refer to the master, so interpolate before removing helpers.
        FaceService.interpolate_targets(body)
        assert 'browInnerUp' in fitted[1].data.shape_keys.key_blocks
    activate(body)
    ExportService.bake_modifiers_remove_helpers(body,bake_masks=True,remove_helpers=True)
    assert len(body.data.vertices)==13380
    body.name = body.data.name = "Academy_HeadBody"
    coat(body,material('Skin flat pigment',(.49,.29,.20)))
    stock_brow = fitted[1]
    bpy.data.objects.remove(stock_brow,do_unlink=True)
    fitted[1] = fitted_brows(body, fitted[0], rig)
    parts=coverage(body,rig.data.bones)
    collar=rig.data.bones['neck_01'].head_local.z-.016
    shirt={p.index for p in body.data.polygons if (p.index in parts and p.center.z>1.77*.568)
           or (collar-.022 < p.center.z < collar+.036 and abs(p.center.x)<.111)}
    shorts=parts-shirt
    meshes=[body,*fitted,
            garment(body,shirt,'Shirt',material('Dusty slate shirt',(.09,.15,.15)),collar=collar),
            garment(body,shorts,'Shorts',material('Walnut charcoal shorts',(.08,.061,.046))),
            *hair(body,rig,top,jaw)]
    animate(rig,arm_drop=14)
    receipt={"head_ratio":h/head,"head_cm":head*uniform*100,"preset_height_cm":h*100,
             "visible_vertices":len(body.data.vertices),"style_changed_hm08_vertices":sum((a-b).length>.0001 for a,b in zip(original,coords))}
    if styled:
        receipt['preset_roundtrip_max_error_m']=preset_error
        receipt['albedo_size']=bake_color(body,out)
        ink_mask(body.data,jaw,top)
        receipt['stock_normals']=export(out,'r05-stock-normals',rig,meshes)
        receipt['data_transfer']=selective_normals(body,jaw,top)
        receipt['fitted']=export(out,'r05-styled',rig,meshes)
        bpy.ops.file.pack_all()
        bpy.ops.wm.save_as_mainfile(filepath=str(out/'r05-baked-workbench.blend'))
    else:
        receipt['base']=export(out,'r05-base',rig,meshes)
    return receipt


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True); p.add_argument('--presets',type=Path,required=True)
    p.add_argument("--detail-pass", action="store_true", help="Apply second-pass R-05 facial weights")
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="bl_ext.user_default.mpfb")
    bpy.context.scene.render.threads_mode='FIXED'; bpy.context.scene.render.threads=8
    meta=json.loads((Path(LocationService.get_mpfb_data('mesh_metadata'))/'hm08_config.json').read_text())
    hd=meta['dimensions']['Head']; ids=(hd['zmax'],hd['zmin'])
    custom = out/'custom'
    custom.mkdir(exist_ok=True)
    targets={k:style_target(custom,f'academy-style-{k}-v1',v,*ids) for k,v in STYLE.items()}
    # Check that the same standard HM08 target format works on the Jane role preset.
    jane=load_preset(args.presets/'human.jane-fit.json'); _,h0,head0=landmarks(jane,*ids)
    TargetService.load_target(jane,str(targets['fem']),name=targets['fem'].stem,weight=1.)
    _,h1,head1=landmarks(jane,*ids); assert h1/head1<h0/head0
    clean()
    preset=(args.presets/'human.detective-fit.json').resolve()
    base=specimen(out,preset,None,ids)
    clean()
    identity = refine(IDENTITY, R05_FACE) if args.detail_pass else IDENTITY
    styled=specimen(out,preset,targets['masc'],ids,identity)
    r={'base':base,'styled':styled,'jane_target_smoke':{'base':h0/head0,'styled':h1/head1}}
    (out/'blender-receipt.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    print('ACADEMY_STYLE_PASS',json.dumps(r),flush=True)


if __name__=='__main__':
    main()
