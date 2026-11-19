"""Build a local, noncommercial inspection exhibit from A26's original STL archive.

Run with Blender background; both the input ZIP and the output GLB stay in .runtime.
The poses below are authoring transforms for an exhibit, not manufacturing tolerances.
"""
from hashlib import sha256
from math import radians
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile
import sys

import bpy
from mathutils import Vector

ARCHIVE_SHA256 = '0eff0d11071f4841b60d43aa295fe142dabb0d551048e1242f4b96adaef0d9be'
SCALE = 0.0122  # source mm -> metres in the deliberately enlarged exhibit
R0 = (0, 0, 0)
# Mesh name/finish, rest transform in the source parts' millimetre units, exploded shift.
PARTS = {
    'outerracev2': ('Bearing race', 'patina', (0, 0, -11), R0, (0, 0, 0)),
    '60touterbevel-v2': ('60T outer bevel ring', 'brass', (0, 0, -4), (0, 0, 90), (0, 0, 12)),
    '20touterbevel': ('20T bevel and bearing bridge', 'brass', (45, 0, 24), (0, -90, 0), (34, 0, 18)),
    'better10tbevel-v2': ('10T bevel pinion', 'steel', (29, 0, 35), (0, 90, 0), (28, 0, 34)),
    'prescherframe': ('Cantilevered carrier', 'patina', (0, 0, 28), R0, (1, 0, 23)),
    '30tgearpres': ('30T carrier gear', 'brass', (1, -1, 24), R0, (-22, 0, 12)),
    'frameapin': ('Cage bridge A', 'brass', (0, 0, 36), R0, (-16, 0, 29)),
    'framebpres': ('Cage bridge B', 'brass', (0, 0, 61), (180, 0, 0), (10, 2, 48)),
    '12tescpin': ('12T escape wheel and pinion', 'steel', (2, -18, 40), R0, (30, -13, 37)),
    'palletspin': ('Guard-pin pallet fork', 'steel', (-13, -13, 42), (0, 0, 154), (-38, -9, 37)),
    'rollerpin': ('Balance roller', 'brass', (0, 0, 56), R0, (-20, 9, 51)),
    'balancewheelmdd': ('Balance wheel', 'brass', (0, 0, 62), R0, (0, 0, 62)),
    'springpin': ('Hairspring and collet', 'steel', (0, 0, 72), R0, (17, 12, 79)),
}
FINISHES = {'patina': ((0.11, 0.19, 0.24, 1), 0.50),
            'brass': ((0.66, 0.37, 0.13, 1), 0.6),
            'steel': ((0.57, 0.68, 0.72, 1), 0.43)}


def main(archive: Path, output: Path):
    runtime = (Path(__file__).resolve().parents[2] / '.runtime').resolve()
    if not all(p.resolve().is_relative_to(runtime) for p in (archive, output)) or output.suffix != '.glb':
        raise ValueError('The archive and the .glb must remain under .runtime')
    if sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        raise ValueError('ZIP does not match the original archived A26 release')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    materials = {}
    for name, (color, metal) in FINISHES.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = color
        mat.metallic = metal
        mat.roughness = 0.54
        materials[name] = mat
    exhibit = bpy.data.objects.new('A26_Triaxial_Tourbillon_Model_II', None)
    bpy.context.collection.objects.link(exhibit)
    exhibit.rotation_euler = (radians(50), 0, radians(-17))
    exhibit['source_archive_sha256'] = ARCHIVE_SHA256
    exhibit['source'] = 'Triaxial Tourbillon Model II by A26 (Thingiverse #2761730)'
    exhibit['license'] = 'CC BY-NC 3.0 per included LICENSE.txt; local inspection only'
    exhibit['assembly'] = 'Illustrative rest poses; not calibrated for tooth contact'
    manifest = {"archive_sha256": ARCHIVE_SHA256, "parts": {}}
    with TemporaryDirectory(dir=output.parent) as staging, ZipFile(archive) as bundle:
        for filename, (label, finish, position, angles, shift) in PARTS.items():
            part_path = Path(staging) / (filename + '.stl')
            part_path.write_bytes(bundle.read(f'files/{filename}.stl'))
            bpy.ops.object.select_all(action='DESELECT')
            bpy.ops.wm.stl_import(filepath=str(part_path), global_scale=SCALE)
            mesh, = bpy.context.selected_objects
            mesh.name = "A26_" + filename.replace("-", "_")
            mesh["caption"] = label
            mesh.data.name = filename
            mesh.parent = exhibit
            mesh.location = Vector(position) * SCALE
            mesh.rotation_euler = tuple(map(radians, angles))
            mesh.data.materials.append(materials[finish])
            mesh['source_stl'] = filename + '.stl'
            # Blender's +Z up / +Y back is converted to Godot's +Y up / -Z forward.
            mesh['explode'] = [shift[0] * SCALE, shift[2] * SCALE, -shift[1] * SCALE]
            manifest['parts'][mesh.name] = {'label': label, 'finish': finish,
                                             'explode': list(mesh['explode'])}
    bpy.context.view_layer.update()
    min_z = min((part.matrix_world @ Vector(p)).z for part in exhibit.children for p in part.bound_box)
    exhibit.location.z = 0.73 - min_z
    bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB', export_extras=True)
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f'Exported {len(exhibit.children)} source parts, {sum(len(p.data.polygons) for p in exhibit.children)} faces: {output}')


if __name__ == '__main__':
    main(*(Path(p).resolve() for p in sys.argv[sys.argv.index('--') + 1:]))
