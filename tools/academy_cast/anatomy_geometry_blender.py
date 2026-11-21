"""Background Blender: produce editable anatomy reviews and audited plain GLBs."""
from collections import Counter
import json
from pathlib import Path
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tripo_surface_blender import blend_shape_keys, configure_ui, create, glb_manifest, pairs


from anatomy_repair_blender import carry_cloth, patch_small_terminal_fold, repair_body


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def add_parts(path, root, scale, suffix=''):
    cloth = collection('CLOTH — toggle to inspect body'+suffix, root)
    groom = collection('GROOM — independent facial hair'+suffix,root) if path.name.startswith('04-') else None
    parts = []
    for part in read(path):
        n, v, f, rgb = (part[k] for k in ('name', 'v', 'f', 'color'))
        parent=cloth if n in ('Underwear','Sports top') else (groom if n in ('Moustache','Goatee') else root)
        ob = create(n+suffix, v, f, rgb, scale, parent)
        if n.startswith('Eye '):
            center = (ob.data.vertices[-1].co+ob.data.vertices[-2].co)*.5
            for vert in ob.data.vertices:
                vert.co -= center
            ob.location = center
        parts.append(ob)
    return parts


def audit_body(ob):
    counts, ids = pairs(ob)
    if ids:
        g = ob.vertex_groups.new(name='QA / self-intersection')
        g.add(sorted(ids), 1., 'REPLACE')
    f = [tuple(p.vertices) for p in ob.data.polygons]
    edges = Counter(tuple(sorted((a,b))) for p in f for a,b in zip(p,p[1:]+p[:1]))
    groups = dict(counts)
    return dict(crossings=sum(counts.values()), regions=groups,
                open_edges=sum(n==1 for n in edges.values()),
                edges_over_two_faces=sum(n>2 for n in edges.values()),
                quads=sum(len(p)==4 for p in f), other_faces=sum(len(p)!=4 for p in f))


def improve(parts, source_path, dest, scale):
    body=parts[0]
    old=np.array([list(v.co) for v in body.data.vertices]); a,b=repair_body(body)
    if b < a:
        carry_cloth(old,body,[ob for ob in parts if ob.name.startswith(('Underwear','Sports top'))])
    patch_before,patch_after,lut=patch_small_terminal_fold(body)
    p=read(source_path)
    for row,ob in zip(p,parts):
        row['v']=[list((v.co+ob.location)/scale) for v in ob.data.vertices]
        if ob==body and patch_after<patch_before:
            row['f']=[list(poly.vertices) for poly in ob.data.polygons]
            shades={}
            for c in p[0]['color']:
                shades.setdefault(tuple(c),int(len(shades)))
            byid={jx:c for c,jx in shades.items()}
            row['color']=[byid[poly.material_index] for poly in ob.data.polygons]
    dest.write_text(json.dumps(p,separators=(',',':')),encoding='utf-8')
    return {'before':a,'after_relax':b,'after':patch_after},lut


def add_auricle_groups(ob, groups, lut):
    sizes = {}
    for label, indices in groups.items():
        ids = [int(lut[i]) for i in indices]
        assert len(ids) == len(set(ids)) and min(ids) >= 0, (ob.name, label)
        ob.vertex_groups.new(name=label).add(ids, 1., 'REPLACE')
        sizes[label] = len(ids)
    return sizes


def export_one(out, base, row):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    configure_ui()
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    root = scene.collection
    slug = row['character']
    scale = 1.77 if slug.startswith('01-') else 1.
    prev = read(base/f'{slug}.json')
    low = collection('01 / Low — editable and exported', root)
    hi = collection('02 / Sculpture — enable separately', root)
    prior = collection('03 / Previous version — aligned front', root)
    parts = add_parts(out/f'{slug}-low.json', low, scale)
    body = parts[0]
    assert body.name == 'Body'
    fixes = out/'fitted'; fixes.mkdir(exist_ok=True)
    low_repair,lut=improve(parts,out/f'{slug}-low.json',fixes/f'{slug}-low.json',scale)
    ears_file = out/f'{slug}-ear-vertices.json'
    ears = read(ears_file) if ears_file.exists() else {}
    ear_low = add_auricle_groups(body, ears.get('low', {}), lut)
    rings = read(out/f'{slug}-loops.json')
    rings={k:{n:[int(lut[i]) for i in ids] for n,ids in r.items()} for k,r in rings.items()}
    assert all(i>=0 for r in rings.values() for ids in r.values() for i in ids)
    pos = [tuple(v.co/scale) for v in body.data.vertices]
    blend_shape_keys(body, pos, rings, scale)
    for eye, r in sorted(rings.items()):
        for label, ids in r.items():
            if ids:
                g = body.vertex_groups.new(name=f'Face {eye} / {label}')
                g.add(ids, 1., 'REPLACE')
    audit = audit_body(body)
    revpath = out/'models'; revpath.mkdir(exist_ok=True)
    path = revpath/f'{slug}.glb'
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_morph=False)
    m = glb_manifest(path)
    counts = {}
    for node in m['nodes']:
        if 'mesh' in node:
            counts[node['name']] = sum(m['accessors'][p['indices']]['count']//3 for p in m['meshes'][node['mesh']]['primitives'])
    n = sum(k for name,k in counts.items() if name=='Body' or name.startswith(('Eye ', 'Brow ')))
    assert n <= row['low_body_eye_brow_triangles'] and n <= 5000, (slug,n,row)
    assert {'Body','Eye 1','Eye 2','Underwear','Brow 1','Brow 2'} <= counts.keys()
    assert not m.get('images') and not m.get('textures')
    hs = add_parts(out/f'{slug}-sculpt.json', hi, scale, ' / Sculpt')
    high_repair,high_lut=improve(hs,out/f'{slug}-sculpt.json',fixes/f'{slug}-sculpt.json',scale)
    ear_high = add_auricle_groups(hs[0], ears.get('sculpt', {}), high_lut)
    audit_hi = audit_body(hs[0])
    if ears:
        assert all(not a[k] for a in (audit, audit_hi)
                   for k in ('crossings', 'open_edges', 'edges_over_two_faces')), (slug, audit, audit_hi)
        audit['auricle_vertices'] = ear_low
        audit_hi['auricle_vertices'] = ear_high
    old = create('Previous body',prev['v'],prev['f'],[],scale,prior)
    audit_old = audit_body(old)
    old.display_type = 'WIRE'
    for c in [hi, prior]:
        c.hide_viewport = True
        c.hide_render = True
    for ob in parts[1:]:
        ob.select_set(False)
    for s in bpy.data.screens:
        for a in s.areas:
            if a.type=='VIEW_3D':
                a.spaces.active.region_3d.view_location=(0,0,scale*.5)
                a.spaces.active.region_3d.view_distance=scale*1.68
    scene['Scale'] = '1.77 m design height' if scale==1.77 else '1 m normalized for separate reviews; no canon height assignment'
    scene['Front IoU / review'] = json.dumps(row['front_silhouette_iou'])
    scene['Centroid drift (% height)'] = json.dumps({k:row[k] for k in ('surface_centroid_shift_pct_h','volume_centroid_shift_pct_h')})
    notes = bpy.data.texts.new('Read first — anatomy QA')
    notes.write('LOW = editable review and GLB export. SCULPT = higher-resolution surface; hide LOW before switching.\n'
                'Toggle the CLOTH collection to inspect joints and silhouette. Tab for Edit Mode, Z > Wireframe.\n'
                'Select QA / self-intersection to locate nonadjacent intersecting triangles. Static check only.\n'
                'The two eyes are separate with pole-centered rotation. Mouth preview shape key is not a facial rig.\n'
                'Pure material colors, no texture maps. This is a review candidate; see audit before using in game.\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(revpath/f'{slug}.blend'), compress=True)
    print('AUDITED',slug,n,audit_old['crossings'],audit['crossings'],audit_hi['crossings'],flush=True)
    return dict(character=slug, body_eye_brow_triangles=n, textures=0, by_node=counts,
                low=audit, sculpt=audit_hi, previous=audit_old, local_repair=dict(low=low_repair,sculpt=high_repair))


if __name__=='__main__':
    out,base=(Path(p).resolve() for p in sys.argv[sys.argv.index('--')+1:])
    audits=[export_one(out,base,r) for r in read(out/'anatomy-metrics.json')]
    (out/'blender-audit.json').write_text(json.dumps(audits,indent=2),encoding='utf-8')
