"""Blender background entry point: assemble solid-color audit .blend and GLB files.

blender -b --factory-startup --threads 2 --python tripo_surface_blender.py -- REVIEW_DIR
"""
from pathlib import Path
from collections import Counter
import json
import math
import struct
import sys

import bpy
from mathutils import Quaternion
from mathutils.bvhtree import BVHTree


def color(value):
    """Convert preview sRGB to linear material values."""
    return tuple(((x/255+.055)/1.055)**2.4 if x/255>.04045 else (x/255)/12.92 for x in value)+(1.,)


def material(rgb):
    key='Solid '+''.join(f'{x:02x}' for x in rgb)
    m=bpy.data.materials.get(key)
    if m is None:
        m=bpy.data.materials.new(key); m.diffuse_color=color(rgb);m.use_nodes=True
        mat=m.node_tree.nodes.get('Principled BSDF');mat.inputs['Base Color'].default_value=m.diffuse_color
        mat.inputs['Roughness'].default_value=.83
    return m


def create(name, v, f, rgb, scale, coll):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata([tuple(x*scale for x in p) for p in v],[],f)
    assert not mesh.validate(verbose=True), f'{name}: invalid mesh from Python'
    mesh.update(); ob=bpy.data.objects.new(name,mesh);coll.objects.link(ob)
    if rgb:
        slots={}
        for q,c in zip(mesh.polygons,map(tuple,rgb)):
            if c not in slots:
                slots[c]=len(slots);mesh.materials.append(material(c))
            q.material_index=slots[c];q.use_smooth=True
    mesh.calc_loop_triangles()
    return ob


def pairs(ob):
    m=ob.data;m.calc_loop_triangles();polys=[list(t.vertices) for t in m.loop_triangles]
    verts=[v.co for v in m.vertices]
    bvh=BVHTree.FromPolygons(verts,polys,all_triangles=True,epsilon=0)
    hit_faces=set(); counts=Counter()
    top=max(v.z for v in verts)
    for a,b in bvh.overlap(bvh):
        if a>=b or set(polys[a])&set(polys[b]):continue
        loc=sum((verts[i] for i in polys[a]+polys[b]),verts[0]*0)/6/top
        region=('head' if loc.z>.845 else 'feet' if loc.z<.060 else
                'hands' if abs(loc.x)>.220 and loc.z>.400 else 'trunk_or_leg')
        counts[region]+=1;hit_faces.update(polys[a]);hit_faces.update(polys[b])
    return counts,hit_faces


def glb_manifest(path):
    d=path.read_bytes(); assert d[:4]==b'glTF'
    n,magic=struct.unpack_from('<I4s',d,12);assert magic==b'JSON'
    return json.loads(d[20:20+n])


def blend_shape_keys(body, verts, rings, scale):
    """Review-only opening control, with anchored upper lip and separated inner rim."""
    if '2' not in rings: return
    key=body.shape_key_add(name='Basis')
    k=body.shape_key_add(name='Preview - lower lip open')
    r=rings['2']; points=[verts[i] for i in r['rim']];center=sum(p[2] for p in points)/len(points)
    lo=min(p[2] for p in points); hi=max(p[2] for p in points)
    for name,amount in [('rim',.0050),('support',.0031),('transition',.0016),('inside',.0034)]:
        for i in r[name]:
            t=max(0.,min(1.,(center-verts[i][2])/max((hi-lo)*.46,.0003)))
            k.data[i].co.z-=amount*t*scale
    k.slider_min=0.;k.slider_max=1.


def configure_ui():
    scene=bpy.context.scene; scene.unit_settings.system='METRIC'
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL'
    scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH'
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type!='VIEW_3D': continue
            s=a.spaces.active;s.shading.type='SOLID';s.shading.color_type='MATERIAL';s.shading.show_cavity=True
            s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
            s.region_3d.view_perspective='ORTHO'
            s.region_3d.view_rotation=Quaternion((1.,0.,0.),math.radians(90))
            s.region_3d.view_location=(0,0,.89); s.region_3d.view_distance=2.75


def export_one(output, stats):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    configure_ui()
    bpy.context.preferences.filepaths.save_version=0
    slug=stats['character'];parts=json.loads((output/f'{slug}-parts.json').read_text(encoding='utf-8'))
    d=json.loads((output/f'{slug}.json').read_text(encoding='utf-8'))
    # Scale known detective design to 1.77 m; others keep reference proportions in 1 m review units.
    scale=1.77 if slug.startswith('01-') else 1.
    scene=bpy.context.scene
    c=bpy.data.collections.new('Review model'); scene.collection.children.link(c)
    src=bpy.data.collections.new('SOURCE • hidden overlay');scene.collection.children.link(src)
    co=bpy.data.collections.new('CLOTH • hide for topology'); c.children.link(co)
    source=create('Tripo source shell',d['origin_v'],d['origin_f'],[],scale,src);source.display_type='WIRE'
    source.hide_set(True);source.hide_render=True
    body=None; obs=[]
    names={'body':'Body','eye0':'Eye A','eye1':'Eye B'}
    for part in parts:
        nm=part['name'];ob=create(names.get(nm,nm),part['v'],part['f'],part['color'],scale,c if nm in names else co)
        if nm=='body':
            body=ob
            tags={'0':'Eye A','1':'Eye B','2':'Mouth'}
            for k,r in d['loops'].items():
                for label,idx in r.items():
                    if idx:
                        g=ob.vertex_groups.new(name=f'{tags[k]} / {label}');g.add(idx,1.,'REPLACE')
            blend_shape_keys(ob,d['v'],d['loops'],scale)
        elif nm.startswith('eye'):
            # The two pole midpoint is the geometric eye rotation center.
            center=(ob.data.vertices[-1].co+ob.data.vertices[-2].co)*.5
            for v in ob.data.vertices:v.co-=center
            ob.location=center
        obs.append(ob)
    assert body
    scene['Review scale (m)']=scale;scene['Review scale note']='Detective 1.77m; the other meshes use normalized 1m comparison units.'
    for key in ('total_triangle_equivalent','head_ratio','surface_centroid_shift','closed_volume_centroid_shift'):
        scene[key]=json.dumps(stats[key],ensure_ascii=False)
    if d['chin'] is not None:scene['Chin landmark at review scale']=[x*scale for x in d['chin']]
    text=bpy.data.texts.new('Read first - mesh inspection')
    text.write('SOLID COLOR REVIEW / '+slug+'\n\n'
               'Body is editable. Tab for Edit Mode; Z > Wireframe for visible and occluded edges.\n'
               'Hide CLOTH to inspect abdomen, hip, and upper leg geometry. Skin is intact underneath.\n'
               'The hidden SOURCE overlay is in the same comparison coordinates.\n'
               'Only plain materials; the Tripo textures are not used. The GLB uses triangles; the .blend preserves quads.\n'
               'To find remaining crossings, select the QA / Self-crossing candidates vertex group in Edit Mode.\n'
               'Preview lower-lip opening is a shape-key inspection control, not a production facial rig.\n'
               'Volume centroid uses a capped source shell as reference; equal density assumed.\n')
    sc,sids=pairs(source);bc,bids=pairs(body)
    for ob,ids in [(source,sids),(body,bids)]:
        if ids:ob.vertex_groups.new(name='QA / Self-crossing candidates').add(sorted(ids),1.0,'REPLACE')
    bvh={'source_nonadjacent_triangle_intersections':sum(sc.values()),'body_nonadjacent_triangle_intersections':sum(bc.values()),
         'source_crossings_by_region':dict(sc),'body_crossings_by_region':dict(bc)}
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=body
    folder=output/'models';folder.mkdir(exist_ok=True)
    path=folder/f'{slug}.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_morph=False)
    m=glb_manifest(path); counts={}
    for node in m['nodes']:
        if 'mesh' not in node:continue
        mesh=m['meshes'][node['mesh']]
        counts[node['name']]=sum(m['accessors'][p['indices']]['count']//3 for p in mesh['primitives'])
    body_tris=sum(v for k,v in counts.items() if k=='Body' or k.startswith('Eye '))
    assert body_tris==stats['total_triangle_equivalent'], (slug,body_tris,stats['total_triangle_equivalent'])
    assert not m.get('images') and not m.get('textures'), slug
    for o in obs:o.select_set(o==body)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=='VIEW_3D': a.spaces.active.region_3d.view_location=(0,0,scale*.5);a.spaces.active.region_3d.view_distance=scale*1.68
    bpy.ops.wm.save_as_mainfile(filepath=str(folder/f'{slug}.blend'),compress=True)
    print('VERIFIED',slug,body_tris,counts,bvh,flush=True)
    return dict(character=slug,glb_mesh_tris=counts,glb_body_eyes_tris=body_tris,texture_count=0,**bvh)


if __name__=='__main__':
    p=Path(sys.argv[sys.argv.index('--')+1]).resolve()
    reports=json.loads((p/'metrics.json').read_text(encoding='utf-8'))
    done=[export_one(p,r) for r in reports]
    (p/'blender-audit.json').write_text(json.dumps(done,indent=2),encoding='utf-8')
