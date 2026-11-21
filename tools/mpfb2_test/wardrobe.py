"""Fit stock MPFB clothes on the cast and verify each actor's own embedded action."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from style_pilot import (
    ExportService, HumanService, LocationService, TargetService, activate, duplicate,
    export, landmarks, unmask_coords,
)

from build import animate, body_copy, export as export_fit, material
from muscle import CAST, FEATURED_CAST
from featured_look import review_eyes, review_skin

OUTFITS = {
    'suit': 'male_elegantsuit01',
    'jacket': 'male_casualsuit05',
    'shirt': 'male_casualsuit03',
}
CAST_OUTFITS = {
    'halvard': {'jacket': 'male_casualsuit05', 'workwear': 'male_worksuit01'},
    'jane': {'shorts': 'female_casualsuit02', 'sport': 'female_sportsuit01'},
    'qingyue': {'skirt': 'female_elegantsuit01', 'jeans': 'female_casualsuit01'},
    'lucian': {'shirt': 'male_casualsuit03'},
    'ward': {'suit': 'male_elegantsuit01'},
    'shending': {'workwear': 'male_worksuit01'},
    'caretaker': {'suit': 'male_elegantsuit01'},
}
for actor in FEATURED_CAST:
    CAST_OUTFITS[actor]['fitted'] = 'male_casualsuit06'
CAST_SHOES = {actor: 'shoes05' if actor == 'jane' else 'shoes04' for actor in CAST_OUTFITS}
SHOES = 'shoes04'
FRAMES = {'rest': 1, 'reach': 19, 'knee': 55}


def read_glb(path):
    with path.open('rb') as f:
        assert f.read(4) == b'glTF' and struct.unpack('<I', f.read(4))[0] == 2
        f.read(4)
        size, kind = struct.unpack('<II', f.read(8))
        assert kind == 0x4e4f534a
        doc = json.loads(f.read(size))
        size, kind = struct.unpack('<II', f.read(8))
        assert kind == 0x004e4942
        blob = f.read(size)
    return doc, blob


def floats(doc, blob, index, dimensions):
    acc = doc['accessors'][index]
    view = doc['bufferViews'][acc['bufferView']]
    assert acc['componentType'] == 5126 and 'byteStride' not in view
    offset = view.get('byteOffset', 0) + acc.get('byteOffset', 0)
    return blob[offset:offset + 4*acc['count']*dimensions]


def motion_digest(path):
    """Hash every embedded native animation channel, independent of accessor ordering."""
    doc, blob = read_glb(path)
    assert [a['name'] for a in doc['animations']] == ['MPFB_Pose_Check']
    anim = doc['animations'][0]
    channels = []
    for channel in anim['channels']:
        # Rig clip contains only native node transform tracks.
        target = channel['target']
        sampler = anim['samplers'][channel['sampler']]
        item = [doc['nodes'][target['node']]['name'], target['path'], sampler.get('interpolation', 'LINEAR')]
        for role in ('input', 'output'):
            kind = doc['accessors'][sampler[role]]['type']
            item.append(floats(doc, blob, sampler[role], {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[kind]).hex())
        channels.append(item)
    return hashlib.sha256(json.dumps(sorted(channels)).encode()).hexdigest()


def fit_donor(master, reference_dir):
    """The original workbench lacks MPFB fitting helpers; recover those from its recipe."""
    meta = Path(LocationService.get_mpfb_data('mesh_metadata'))/'hm08_config.json'
    hd = json.loads(meta.read_text())['dimensions']['Head']
    preset = reference_dir/'human.r05-styled.json'
    target = reference_dir/'custom'/'academy-style-masc-v1.target'
    data = json.loads(preset.read_text(encoding='utf-8-sig'))
    row = [entry for entry in data['targets'] if entry['target'] == target.stem]
    assert len(row) == 1 and row[0]['value'] == 1.0, row
    # Load built-ins through the ordinary preset path, and explicitly supply the local .target.
    settings = HumanService.get_default_deserialization_settings()
    settings.update(feet_on_ground=False, subdiv_levels=0)
    data['targets'] = [entry for entry in data['targets'] if entry is not row[0]]
    donor = HumanService.deserialize_from_dict(data, settings)
    TargetService.load_target(donor, str(target), name=target.stem, weight=1.0)
    sole, height, _ = landmarks(donor, hd['zmax'], hd['zmin'])
    scale = 1.77/height
    activate(donor)
    donor.scale = (scale,)*3
    donor.location.z = -sole*scale
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    rig = HumanService.add_builtin_rig(donor, 'game_engine')
    # Match the exact authoring rig. This rig is only for MPFB weight interpolation.
    original_rig = next(m.object for m in master.modifiers if m.type == 'ARMATURE')
    assert set(rig.data.bones.keys()) == set(original_rig.data.bones.keys())
    max_rest_error = max(abs(rig.data.bones[name].matrix_local[r][c] - bone.matrix_local[r][c])
                         for name, bone in original_rig.data.bones.items() for r in range(4) for c in range(4))
    assert max_rest_error < 2e-5, max_rest_error
    points = unmask_coords(donor)
    group = donor.vertex_groups['body'].index
    ids = [v.index for v in donor.data.vertices if any(g.group == group for g in v.groups)]
    tree = KDTree(len(ids))
    for i in ids:
        tree.insert(points[i], i)
    tree.balance()
    pairs = [tree.find(v.co) for v in master.data.vertices]
    error = max(dist for _, _, dist in pairs)
    assert error < 2e-5 and len({i for _,i,_ in pairs}) == len(pairs), error
    return donor, rig, original_rig, [i for _,i,_ in pairs], max_rest_error, error


def fit_clothes(donor, rig, slug, label):
    path = Path(LocationService.get_user_data())/'clothes'/slug/(slug + '.mhclo')
    assert path.exists(), path
    garment = HumanService.add_mhclo_asset(path, donor, subdiv_levels=0, material_type='GAMEENGINE')
    garment.name = garment.data.name = label
    bpy.context.view_layer.update()
    world = garment.matrix_world.copy()
    garment.parent = rig
    garment.matrix_world = world
    mods = [mod for mod in garment.modifiers if mod.type == 'ARMATURE']
    assert len(mods) == 1, (slug, mods)
    mods[0].object = rig
    group = donor.vertex_groups.get('Delete.'+slug)
    covered = set() if group is None else {
        v.index for v in donor.data.vertices if any(g.group == group.index and g.weight > 0.0001 for g in v.groups)
    }
    assert covered, slug
    # Review rig uses the original base-color maps. Strip the rough/normal texture inputs
    # the Toon shader does not use, so their detail cannot obscure the layer comparison.
    for m in garment.data.materials:
        for node in m.node_tree.nodes:
            if node.type == 'BSDF_PRINCIPLED':
                for n in ('Normal','Roughness','Metallic','Specular IOR Level'):
                    for link in list(node.inputs[n].links):
                        m.node_tree.links.remove(link)
                node.inputs['Roughness'].default_value = 0.92
                node.inputs['Metallic'].default_value = 0.0
    return garment, covered


def key_count(obj):
    return len(obj.data.shape_keys.key_blocks) if obj.data.shape_keys else 0


def bake_stock_mask(master, indices):
    body = duplicate(master, 'Wardrobe masked body')
    group = body.vertex_groups.new(name='Wardrobe stock delete group')
    group.add(indices, 1.0, 'REPLACE')
    mod = body.modifiers.new(group.name, 'MASK')
    mod.vertex_group = group.name
    mod.invert_vertex_group = True
    activate(body)
    ExportService.bake_modifiers_remove_helpers(body, bake_masks=True, remove_helpers=False)
    assert key_count(body) == key_count(master)
    assert len(body.data.vertices) < len(master.data.vertices)
    return body


def evaluated_mesh(obj):
    target = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [target.matrix_world @ v.co for v in target.data.vertices], [tuple(p.vertices) for p in target.data.polygons]


def overlap_samples(master, garment):
    """Sample cloth points below the original skin by >2 mm; report mesh fit, not visual holes."""
    report = {}
    for label, frame in FRAMES.items():
        bpy.context.scene.frame_set(frame)
        points, faces = evaluated_mesh(master)
        tree = BVHTree.FromPolygons(points, faces)
        points, _ = evaluated_mesh(garment)
        depths = []
        for v in points:
            hit, normal, _, distance = tree.find_nearest(v, 0.06)
            if hit is not None and distance > .002 and (v-hit).dot(normal) < -.0019:
                depths.append(distance * 1000)
        report[label] = {'inside_2mm_vertices': len(depths), 'sample_vertices': len(points),
                         'max_depth_mm': round(max(depths, default=0), 1)}
    return report


def silhouette_fit(garment, master, stature):
    """Plain short sleeves, separate shirt/trouser pigments, controlled ease at the waist."""
    verts = garment.data.vertices
    graph = [set() for _ in verts]
    for e in garment.data.edges:
        a, b = e.vertices
        graph[a].add(b)
        graph[b].add(a)
    pending = set(range(len(verts)))
    groups = []
    while pending:
        seed = pending.pop()
        group, queue = {seed}, [seed]
        while queue:
            for nxt in graph[queue.pop()] & pending:
                pending.remove(nxt)
                queue.append(nxt)
                group.add(nxt)
        groups.append(group)
    assert len(groups) == 2, [len(g) for g in groups]  # Stock short-sleeve topology.
    transform = garment.matrix_world.copy()
    inverse = transform.inverted()
    shirt = max(groups, key=lambda g: sum((transform @ verts[i].co).z for i in g) / len(g))
    points, faces = evaluated_mesh(master)
    skin = BVHTree.FromPolygons(points, faces)
    moved = []
    for i in shirt:
        vertex = verts[i]
        point = transform @ vertex.co
        # Fade the pull over the shirt's waist and ribs. Sleeves, hem and collar retain stock fit.
        z = point.z / stature
        influence = max(0, min(1, (z - .56) / .035, (.745 - z) / .050))
        if not influence:
            continue
        hit, normal, _, distance = skin.find_nearest(point, .045)
        if hit is None or distance <= .012 or (point-hit).dot(normal) <= 0 or abs(normal.z) > .58:
            continue
        horizontal = Vector((normal.x, normal.y, 0)).normalized()
        pull = min(.013, (distance - .012) * .75) * influence
        dest = point - horizontal * pull
        closest, next_normal, _, _ = skin.find_nearest(dest, .06)
        if closest is None or (dest-closest).dot(next_normal) < .007:
            continue
        vertex.co = inverse @ dest
        moved.append(pull)
    garment.data.materials.clear()
    garment.data.materials.append(material('Plain sage jersey', (.36, .42, .35)))
    garment.data.materials.append(material('Plain slate twill', (.18, .23, .26)))
    for polygon in garment.data.polygons:
        polygon.material_index = 0 if polygon.vertices[0] in shirt else 1
    garment.data.update()
    return {'shirt_vertices': len(shirt), 'shirt_vertices_drawn_in': len(moved),
            'max_inset_mm': round(1e3 * max(moved, default=0), 2), 'target_waist_clearance_mm': 12}


def verify_fit_body(master, original):
    """Check coverage-independent positions against the existing fit GLB and map HM08 indices."""
    doc, blob = read_glb(original)
    mesh = next(m for m in doc['meshes'] if m['name'] == 'Review_Body')
    exported = set()
    for prim in mesh['primitives']:
        values = floats(doc, blob, prim['attributes']['POSITION'], 3)
        exported.update(struct.iter_unpack('<3f', values))
    tree = KDTree(len(master.data.vertices))
    for v in master.data.vertices:
        tree.insert((v.co.x, v.co.z, -v.co.y), v.index)
    tree.balance()
    pairs = [tree.find(Vector(v)) for v in exported]
    error = max(dist for _, _, dist in pairs)
    assert error < 2e-6 and len({i for _, i, _ in pairs}) == len(master.data.vertices), error
    return error


def verify_fit_rig(original, variant):
    """Compare joint transforms and inverse bind matrices by name, independent of export order."""
    def labeled_joints(path):
        doc, blob = read_glb(path)
        skin, = doc['skins']
        ibms = struct.iter_unpack('<16f', floats(doc, blob, skin['inverseBindMatrices'], 16))
        result = {}
        parents = {child: node['name'] for node in doc['nodes'] for child in node.get('children', [])}
        for idx, ibm in zip(skin['joints'], ibms, strict=True):
            joint = doc['nodes'][idx]
            label = joint['name']
            assert 'matrix' not in joint
            result[label] = (parents.get(idx), [*joint.get('translation', [0, 0, 0]),
                             *joint.get('rotation', [0, 0, 0, 1]), *joint.get('scale', [1, 1, 1]), *ibm])
        return result

    source, generated = labeled_joints(original), labeled_joints(variant)
    assert len(source) == 53 and source.keys() == generated.keys()
    max_error = 0.0
    for name, (parent, transform) in source.items():
        assert generated[name][0] == parent, name
        max_error = max(max_error, *(abs(a-b) for a, b in zip(transform, generated[name][1], strict=True)))
    assert max_error < 2e-6, max_error
    return max_error


def build_fit(actor, outfit, source, original, out):
    slug = CAST_OUTFITS[actor][outfit]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    settings = HumanService.get_default_deserialization_settings()
    settings.update(feet_on_ground=False, subdiv_levels=0)
    data = json.loads((source/'presets'/f'human.{actor}-fit.json').read_text(encoding='utf-8'))
    donor = HumanService.deserialize_from_dict(data, settings)
    meta = Path(LocationService.get_mpfb_data('mesh_metadata'))/'hm08_config.json'
    hd = json.loads(meta.read_text())['dimensions']['Head']
    sole, height, _ = landmarks(donor, hd['zmax'], hd['zmin'])
    scale = (CAST | FEATURED_CAST)[actor][3]/height
    activate(donor)
    donor.scale = (scale,)*3
    donor.location.z = -sole*scale
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    rig = HumanService.add_builtin_rig(donor, 'game_engine')
    asset = Path(LocationService.get_user_data())/'eyes/low-poly/low-poly.mhclo'
    eyes = HumanService.add_mhclo_asset(asset, donor, asset_type='Eyes', subdiv_levels=0,
                                       material_type='GAMEENGINE')
    eyes.data.name = 'Review_Eyes'
    review_eyes(eyes, actor)
    master = body_copy(donor, 'Review_Body')
    error = verify_fit_body(master, original)
    review_skin(master, actor)
    points = unmask_coords(donor)
    body_group = donor.vertex_groups['body'].index
    ids = [v.index for v in donor.data.vertices if any(g.group == body_group for g in v.groups)]
    tree = KDTree(len(ids))
    for i in ids:
        tree.insert(points[i], i)
    tree.balance()
    pairs = [tree.find(v.co) for v in master.data.vertices]
    assert max(dist for _, _, dist in pairs) < 2e-5 and len({i for _, i, _ in pairs}) == len(pairs)
    garment, covered = fit_clothes(donor, rig, slug, 'Wardrobe_Outfit')
    shoes, feet = fit_clothes(donor, rig, CAST_SHOES[actor], 'Wardrobe_Shoes')
    fit = silhouette_fit(garment, master, (CAST | FEATURED_CAST)[actor][3]) if outfit == 'fitted' else None
    animate(rig, arm_drop=8)  # Same authoring path as muscle.py --design-fit; hash against this actor below.
    overlap = overlap_samples(master, garment)
    bpy.context.scene.frame_set(1)
    body = bake_stock_mask(master, [v.index for v, (_, i, _) in zip(master.data.vertices, pairs, strict=True)
                                   if i in covered or i in feet])
    master.name = master.data.name = 'Wardrobe hidden source'
    body.name = body.data.name = 'Review_Body'
    name = f'{actor}_{outfit}'
    stats = export_fit(out, name, rig, [body, eyes, garment, shoes])
    variant = out/f'{name}.glb'
    digest = motion_digest(original)
    assert motion_digest(variant) == digest, f'{name}: native animation sampler bytes changed'
    receipt = {'actor': actor, 'outfit': outfit, 'asset': slug, 'shoes': CAST_SHOES[actor],
               'motion_sha256': digest, 'rig_and_bind_max_diff': verify_fit_rig(original, variant),
               'body_fit_max_error_m': error, 'skin_vertices_masked': len(master.data.vertices)-len(body.data.vertices),
               'geometry_overlap_unmasked': overlap, **stats}
    if fit is not None:
        receipt['silhouette_fit'] = fit
    (out/f'wardrobe-{name}.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print('CAST_WARDROBE_PASS', json.dumps(receipt), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor', default='r05', choices=('r05', *CAST_OUTFITS))
    parser.add_argument('--outfit', required=True)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--original-glb', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    source, out = args.source.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    original = args.original_glb.resolve()
    choices = OUTFITS if args.actor == 'r05' else CAST_OUTFITS[args.actor]
    if args.outfit not in choices:
        parser.error(f'{args.actor} outfits: {", ".join(choices)}')
    if args.actor != 'r05':
        build_fit(args.actor, args.outfit, source, original, out)
        return
    original_digest = motion_digest(original)
    short = args.outfit
    slug = OUTFITS[short]
    bpy.ops.wm.open_mainfile(filepath=str(source/'r05-baked-workbench.blend'), load_ui=False)
    bpy.ops.preferences.addon_enable(module='bl_ext.user_default.mpfb')
    bpy.context.scene.frame_set(1)
    master = bpy.data.objects['Academy_HeadBody']
    # Isolate authoring meshes before MPFB creates its fitting-only donor.
    base_meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH'
                   and o.name not in {'Academy_HeadBody', 'Shirt', 'Shorts'}]
    donor, donor_rig, rig, match, rest_error, body_error = fit_donor(master, source)
    garment, covered = fit_clothes(donor, rig, slug, 'Wardrobe_Outfit')
    shoes, feet = fit_clothes(donor, rig, SHOES, 'Wardrobe_Shoes')
    skin_overlap = overlap_samples(master, garment)
    bpy.context.scene.frame_set(1)
    mask = [i for i, index in enumerate(match) if index in covered or index in feet]
    body = bake_stock_mask(master, mask)
    master.name = master.data.name = 'Wardrobe hidden source'
    body.name = body.data.name = 'Academy_HeadBody'
    # The donor and its duplicate rig are excluded from the GLB. The original rig owns the action.
    bpy.data.objects.remove(donor, do_unlink=True)
    bpy.data.objects.remove(donor_rig, do_unlink=True)
    stats = export(out, f'r05_{short}', rig, [body, *base_meshes, garment, shoes])
    same_action = motion_digest(out/f'r05_{short}.glb') == original_digest
    assert same_action, f'{short}: native animation sampler bytes changed'
    assert stats['blend_shapes']['Academy_HeadBody'] == 67
    receipt = {
        'outfit': short, 'asset': slug, 'shoes': SHOES,
        'motion_sha256': original_digest, 'rig_rest_matrix_max_diff': rest_error,
        'body_fit_max_error_m': body_error,
        'skin_vertices_masked': len(master.data.vertices)-len(body.data.vertices),
        'geometry_overlap_unmasked': skin_overlap, **stats,
    }
    (out/f'wardrobe-{short}.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print('R05_WARDROBE_PASS', json.dumps(receipt), flush=True)


if __name__ == '__main__':
    main()
