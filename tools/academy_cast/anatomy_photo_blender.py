"""Embed the front projection as a hidden, diagnostic-only collection in .blend.

Run in Blender background after the material-free GLBs have been exported.
No external references survive packing; geometry and the original materials are
unchanged. Enable the photo collection and Material Preview to inspect it.
"""
from pathlib import Path
import sys
import bpy

WIDTH=311; HEIGHT=401; HALF=155; H=400


def node_group(image):
    g=bpy.data.node_groups.new('Front ref projection — diagnostic','ShaderNodeTree')
    g.interface.new_socket(name='Pure surface',in_out='INPUT',socket_type='NodeSocketShader')
    g.interface.new_socket(name='Review surface',in_out='OUTPUT',socket_type='NodeSocketShader')
    n=g.nodes; l=g.links
    source=n.new('NodeGroupInput'); dest=n.new('NodeGroupOutput')
    uv=n.new('ShaderNodeUVMap');uv.uv_map='Reference front XZ'
    tex=n.new('ShaderNodeTexImage');tex.image=image;tex.extension='CLIP'
    l.new(uv.outputs['UV'],tex.inputs['Vector'])
    geo=n.new('ShaderNodeNewGeometry'); dot=n.new('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT'
    dot.inputs[1].default_value=(0,-1,0);l.new(geo.outputs['Normal'],dot.inputs[0])
    clamp=n.new('ShaderNodeMapRange');clamp.clamp=True;clamp.inputs['From Min'].default_value=.06
    clamp.inputs['From Max'].default_value=.40;l.new(dot.outputs['Value'],clamp.inputs['Value'])
    mask=n.new('ShaderNodeMath'); mask.operation='MULTIPLY'
    l.new(clamp.outputs['Result'],mask.inputs[0]);l.new(tex.outputs['Alpha'],mask.inputs[1])
    emit=n.new('ShaderNodeEmission');l.new(tex.outputs['Color'],emit.inputs['Color'])
    mix=n.new('ShaderNodeMixShader');l.new(mask.outputs[0],mix.inputs[0]);l.new(source.outputs[0],mix.inputs[1]);l.new(emit.outputs[0],mix.inputs[2]);l.new(mix.outputs[0],dest.inputs[0]);
    return g


def photo_material(original,g):
    mat=original.copy();mat.name=original.name+' | front ref'
    nodes=mat.node_tree.nodes;links=mat.node_tree.links
    node=nodes.new('ShaderNodeGroup');node.node_tree=g
    node.location=(50,100)
    out=next(n for n in nodes if n.type=='OUTPUT_MATERIAL' and n.is_active_output)
    surface=out.inputs['Surface'];old=surface.links[0].from_socket
    links.new(old,node.inputs[0]); links.new(node.outputs[0],surface)
    return mat


def add_photo(path,png,target):
    bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    originals=next(c for c in scene.collection.children if c.name.startswith('02 / Sculpture'))
    image=bpy.data.images.load(str(png));image.pack(); g=node_group(image)
    reference=bpy.data.collections.new('04 / Photo projection — material preview only');scene.collection.children.link(reference)
    mats={}; scale=1.77 if path.name.startswith('01-') else 1.
    for orig in originals.all_objects:
        ob=orig.copy();ob.data=orig.data.copy();ob.name=orig.name.replace(' / Sculpt',' / Photo');reference.objects.link(ob)
        uv=ob.data.uv_layers.new(name='Reference front XZ')
        for j,loop in enumerate(ob.data.loops):
            x,_,z=orig.matrix_world@ob.data.vertices[loop.vertex_index].co
            uv.data[j].uv=((HALF+x/scale*H+.5)/WIDTH,(z/scale*H+.5)/HEIGHT)
        for i,m in enumerate(ob.data.materials):
            if m.name not in mats:mats[m.name]=photo_material(m,g)
            ob.data.materials[i]=mats[m.name]
    reference.hide_viewport=True;reference.hide_render=True
    scene.render.engine='BLENDER_EEVEE_NEXT'
    notes=bpy.data.texts.get('Read first — anatomy QA')
    notes.write('\nPhoto compare: hide 01 and 02, enable 04 in the Outliner, then switch viewport to Material Preview.\n'
                'Photo projection comes from the supplied front image. Return to 01 or 02 to inspect unpainted geometry.\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(target),compress=True)
    assert image.packed_file is not None, str(png)
    print('PACKED PROJECTION',target.name,flush=True)


if __name__=='__main__':
    models,maps,dest=(Path(a).resolve() for a in sys.argv[sys.argv.index('--')+1:])
    dest.mkdir(exist_ok=True,parents=True)
    for p in sorted(models.glob('*.blend')):
        png=maps/f'{p.stem}-front-rgba.png'
        add_photo(p,png,dest/p.name)
