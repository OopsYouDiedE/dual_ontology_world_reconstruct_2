"""Run using Blender 5.0+ in --background --factory-startup --disable-autoexec mode."""
import bpy
import csv
import hashlib
import json
import re
import sys
from pathlib import Path


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def geometry_groups():
    return sorted((g for g in bpy.data.node_groups if g.type == 'GEOMETRY'), key=lambda g: g.name)


def describe(g):
    return dict(name=g.name, nodes=len(g.nodes), links=len(g.links),
                inputs=[(s.name, s.socket_type, s.identifier) for s in g.interface.items_tree
                        if s.item_type == 'SOCKET' and s.in_out == 'INPUT'],
                outputs=[(s.name, s.socket_type) for s in g.interface.items_tree
                         if s.item_type == 'SOCKET' and s.in_out == 'OUTPUT'],
                groups=sorted({n.node_tree.name for n in g.nodes if getattr(n, 'node_tree', None)}),
                node_types=sorted({n.bl_idname for n in g.nodes}))


def extract(source, out):
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
    # Authors linked Essentials via absolute paths to their own Blender install.
    # Append the identically named bundled groups and remap users (including duplicates).
    fixed = {}
    for old in list(bpy.data.node_groups):
        if not old.library:
            continue
        filename = Path(old.library.filepath).name
        bundled = Path(bpy.utils.system_resource('DATAFILES'))/'assets'/'nodes'/filename
        key = filename, old.name
        if not bundled.is_file():
            raise FileNotFoundError(bundled)
        if key not in fixed:
            with bpy.data.libraries.load(str(bundled), link=False) as (available, loaded):
                assert old.name in available.node_groups, key
                loaded.node_groups = [old.name]
            fixed[key] = loaded.node_groups[0]
        old.user_remap(fixed[key]); bpy.data.node_groups.remove(old)
    groups = geometry_groups()
    records = [describe(g) for g in groups]
    for group in groups:
        group.use_fake_user = True
        if not group.asset_data:
            group.asset_mark()
    # Include all ID dependencies through Blender's native library writer.
    bpy.data.libraries.write(str(out/'nodes.blend'), set(groups), fake_user=True,
                             compress=True, path_remap='RELATIVE_ALL')
    singles = out/'groups'
    singles.mkdir(exist_ok=True)
    for i, (group, record) in enumerate(zip(groups, records)):
        name = re.sub(r'[^\w.-]', '_', group.name)[:80]
        path = singles/f'{i:03}-{name}.blend'
        bpy.data.libraries.write(str(path), {group}, fake_user=True, compress=True,
                                 path_remap='RELATIVE_ALL')
        record['file'] = path.relative_to(out).as_posix()
    bpy.ops.wm.open_mainfile(filepath=str(out/'nodes.blend'), load_ui=False, use_scripts=False)
    actual = {g.name:describe(g) for g in geometry_groups()}
    diffs = [(r['name'], k, v, actual.get(r['name'], {}).get(k)) for r in records
             for k,v in r.items() if k != 'file' and actual.get(r['name'], {}).get(k) != v]
    assert not diffs, str(diffs[:3])[:4000]
    # Verify every standalone file advertises its root and its nested geometry groups.
    by_name = {r['name']: r for r in records}
    for r in records:
        required, todo = set(), [r['name']]
        while todo:
            key = todo.pop()
            if key not in required:
                required.add(key)
                todo.extend(x for x in by_name[key]['groups'] if x in by_name)
        with bpy.data.libraries.load(str(out/r['file'])) as (available, _):
            assert required <= set(available.node_groups), r['name']
    with (out/'index.csv').open('w', encoding='utf-8-sig', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['Root group','Nodes','Links','Inputs','Direct subgroups','Standalone file'])
        for r in records:
            writer.writerow([r['name'],r['nodes'],r['links'],len(r['inputs']),'; '.join(r['groups']),r['file']])
    dump(out/'inventory.json', dict(source=source.name, sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
         blender=bpy.app.version_string, groups=records, external=bpy.utils.blend_paths(absolute=True, packed=False)))


def probe(out, name):
    # Use an empty scene; append only the root and the dependencies of the extracted asset.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with bpy.data.libraries.load(str(out/'nodes.blend')) as (_, loaded):
        loaded.node_groups = [name]
    root = loaded.node_groups[0]
    bpy.ops.mesh.primitive_cube_add(size=4)
    obj = bpy.context.object
    mod = obj.modifiers.new('Probe', 'NODES')

    # Optional knob perturbation: Blender ... -- probe DIR GROUP SOCKET VALUE
    args = sys.argv[sys.argv.index('--')+4:]
    if args:
        socket = next(s for s in root.interface.items_tree if s.item_type == 'SOCKET'
                      and s.in_out == 'INPUT' and s.name == args[0])
        socket.default_value = json.loads(args[1])
    mod.node_group = root
    # Explicitly realize instances; to_mesh alone would undercount instanced geometry.
    tree = bpy.data.node_groups.new('ProbeRealize', 'GeometryNodeTree')
    for side in ('INPUT','OUTPUT'):
        tree.interface.new_socket(name='Geometry', in_out=side, socket_type='NodeSocketGeometry')
    a,b,c = [tree.nodes.new(t) for t in ('NodeGroupInput','GeometryNodeRealizeInstances','NodeGroupOutput')]
    tree.links.new(a.outputs[0], b.inputs['Geometry']); tree.links.new(b.outputs[0], c.inputs[0])
    obj.modifiers.new('Realize', 'NODES').node_group = tree
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); mesh = ev.to_mesh()
    print('PROBE_JSON '+json.dumps(dict(group=name, override=args, vertices=len(mesh.vertices), faces=len(mesh.polygons), bounds=[list(ev.bound_box[0]),list(ev.bound_box[6])])), flush=True)
    if mesh.polygons:
        preview = bpy.data.objects.new('EvaluatedMesh', mesh.copy())
        bpy.context.collection.objects.link(preview)
        bpy.ops.object.select_all(action='DESELECT'); preview.select_set(True)
        bpy.context.view_layer.objects.active = preview
        file = out/(re.sub(r'[^\w.-]', '_', '_'.join([name]+args))+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(file), use_selection=True, export_materials='NONE')
    ev.to_mesh_clear()


if __name__ == '__main__':
    mode, folder, arg = sys.argv[sys.argv.index('--')+1:][:3]
    out = Path(folder).resolve(); out.mkdir(parents=True, exist_ok=True)
    if mode == 'extract':
        extract(Path(arg).resolve(), out)
    elif mode == 'probe':
        probe(out, arg)
    else:
        raise ValueError(mode)
