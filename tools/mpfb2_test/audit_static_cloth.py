"""Measure static body/underwear intersections without modifying the source GLBs."""
import argparse
import json
from pathlib import Path
import sys

import bpy
from mathutils.bvhtree import BVHTree


MODELS = ('02-lucian', '03-ward', '04-shen-ding', '07-caretaker')


def mesh_data(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    obj.data.calc_loop_triangles()
    tris = [tuple(tri.vertices) for tri in obj.data.loop_triangles]
    return points, tris


def check(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path), merge_vertices=True)
    body, body_tri = mesh_data(bpy.data.objects['Body'])
    cloth, cloth_tri = mesh_data(bpy.data.objects['Underwear'])
    body_bvh = BVHTree.FromPolygons(body, body_tri, all_triangles=True)
    cloth_bvh = BVHTree.FromPolygons(cloth, cloth_tri, all_triangles=True)
    hits = body_bvh.overlap(cloth_bvh)
    affected = {index for _, index in hits}
    heights = [sum(cloth[i].z for i in cloth_tri[index]) / 3 for index in affected]
    # Ignore triangles sharing a geometric corner, including duplicated glTF seam vertices.
    corners = [{tuple(cloth[i]) for i in tri} for tri in cloth_tri]
    self_hits = sum(i < j and not corners[i] & corners[j] for i, j in cloth_bvh.overlap(cloth_bvh))
    return {'body_cloth_pairs': len(hits), 'garment_triangles': len(cloth_tri),
            'garment_triangles_touching_body': len(affected),
            'overlap_center_z_m_range': [round(min(heights), 3), round(max(heights), 3)] if heights else [],
            'nonadjacent_garment_self_overlap_pairs': self_hits}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    results = {name: check(args.source.resolve() / (name + '.glb')) for name in MODELS}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    print('STATIC_CLOTH_AUDIT', json.dumps(results), flush=True)


if __name__ == '__main__':
    main()
