"""Rebuild the academy hall as editable Blender Geometry Nodes from the Godot recipe.

Blender 4.2: blender -b -t 4 --python tools/blue_prince_lab/build_geometry_nodes.py --
    .runtime/hall-recipe.json .runtime/hall-components.json .runtime/academy-hall.blend
"""
import json
from pathlib import Path
import sys

import bpy


def axes(vector):
    x, y, z = vector
    return x, -z, y


def material(label, color):
    key = f'{label} · #{color}'
    mat = bpy.data.materials.get(key)
    if mat is None:
        mat = bpy.data.materials.new(key)
        srgb = tuple(int(color[i:i+2], 16) / 255 for i in (0, 2, 4))
        linear = tuple(v / 12.92 if v < 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb)
        mat.diffuse_color = (*linear, 1.0)
    return mat


def object_mesh(collection, name, vertices, faces=()):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


def nodes_for(name):
    tree = bpy.data.node_groups.new(name, 'GeometryNodeTree')
    tree.interface.new_socket(name='Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
    tree.interface.new_socket(name='Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
    source = tree.nodes.new('NodeGroupInput')
    source.location = (-650, 200)
    output = tree.nodes.new('NodeGroupOutput')
    output.location = (420, 180)
    return tree, source, output


def set_material(tree, geometry, mat):
    node = tree.nodes.new('GeometryNodeSetMaterial')
    node.location = (220, 180)
    node.inputs['Material'].default_value = mat
    tree.links.new(geometry, node.inputs['Geometry'])
    return node.outputs['Geometry']


def put_boxes(collection, rows, name, mat):
    obj = object_mesh(collection, f'{name} | parametric cuboids', [axes(row['p']) for row in rows])
    size = obj.data.attributes.new('part_size', 'FLOAT_VECTOR', 'POINT')
    for attr, row in zip(size.data, rows):
        x, y, z = row['size']
        attr.vector = (x, z, y)
    tree, source, output = nodes_for(f'{name} | Cube dimensions and repeat positions')
    cube = tree.nodes.new('GeometryNodeMeshCube')
    cube.location = (-640, -40)
    cube.inputs['Size'].default_value = (1, 1, 1)
    dimensions = tree.nodes.new('GeometryNodeInputNamedAttribute')
    dimensions.location = (-640, -190)
    dimensions.data_type = 'FLOAT_VECTOR'
    dimensions.inputs['Name'].default_value = 'part_size'
    instances = tree.nodes.new('GeometryNodeInstanceOnPoints')
    instances.location = (-290, 140)
    realized = tree.nodes.new('GeometryNodeRealizeInstances')
    realized.location = (10, 180)
    tree.links.new(source.outputs['Geometry'], instances.inputs['Points'])
    tree.links.new(cube.outputs['Mesh'], instances.inputs['Instance'])
    tree.links.new(dimensions.outputs['Attribute'], instances.inputs['Scale'])
    tree.links.new(instances.outputs['Instances'], realized.inputs['Geometry'])
    tree.links.new(set_material(tree, realized.outputs['Geometry'], mat), output.inputs['Geometry'])
    obj.modifiers.new('Repeated masonry', 'NODES').node_group = tree
    return obj


def put_wedges(collection, rows, name, mat):
    vertices, faces = [], []
    for row in rows:
        start = len(vertices)
        vertices.extend(map(axes, row['front']))
        faces.append(tuple(range(start, len(vertices))))
    obj = object_mesh(collection, f'{name} | arch wedge profiles', vertices, faces)
    attr = obj.data.attributes.new('depth_vector', 'FLOAT_VECTOR', 'FACE')
    for entry, row in zip(attr.data, rows):
        entry.vector = axes(b - a for a, b in zip(row['front'][0], row['rear'][0]))
    tree, source, output = nodes_for(f'{name} | Solid arch extrusion')
    offset = tree.nodes.new('GeometryNodeInputNamedAttribute')
    offset.data_type = 'FLOAT_VECTOR'
    offset.inputs['Name'].default_value = 'depth_vector'
    offset.location = (-630, -100)
    extrude = tree.nodes.new('GeometryNodeExtrudeMesh')
    extrude.location = (-340, 180)
    extrude.mode = 'FACES'
    extrude.inputs['Individual'].default_value = False
    extrude.inputs['Offset Scale'].default_value = 0.0
    tree.links.new(source.outputs['Geometry'], extrude.inputs['Mesh'])
    tree.links.new(offset.outputs['Attribute'], extrude.inputs['Offset'])
    # Face-mode extrusion shifts the input cap; join a copy of the seed cap back in.
    flip = tree.nodes.new('GeometryNodeFlipFaces')
    flip.location = (-50, 0)
    tree.links.new(extrude.outputs['Mesh'], flip.inputs['Mesh'])
    join = tree.nodes.new('GeometryNodeJoinGeometry')
    join.location = (100, 180)
    tree.links.new(source.outputs['Geometry'], join.inputs['Geometry'])
    tree.links.new(flip.outputs['Mesh'], join.inputs['Geometry'])
    tree.links.new(set_material(tree, join.outputs['Geometry'], mat), output.inputs['Geometry'])
    obj.modifiers.new('Voussoir extrusion', 'NODES').node_group = tree
    return obj


def put_component(collection, label, pieces):
    inputs = bpy.data.collections.new(f'{label} | generated mesh sources')
    collection.children.link(inputs)
    inputs.hide_viewport = True
    inputs.hide_render = True
    for piece in pieces:
        # Godot lists front triangles clockwise, Blender uses counterclockwise.
        obj = object_mesh(inputs, piece['name'], [axes(v) for v in piece['vertices']],
                          [face[::-1] for face in piece['faces']])
        obj.data.materials.append(material(label, piece['color']))
    driver = object_mesh(collection, f'{label} | assembled', [])
    tree, _, output = nodes_for(f'{label} | Component assembly')
    source = tree.nodes.new('GeometryNodeCollectionInfo')
    source.location = (-400, 180)
    source.inputs['Collection'].default_value = inputs
    realized = tree.nodes.new('GeometryNodeRealizeInstances')
    realized.location = (-90, 180)
    tree.links.new(source.outputs['Instances'], realized.inputs['Geometry'])
    tree.links.new(realized.outputs['Geometry'], output.inputs['Geometry'])
    driver.modifiers.new('Component mesh assembly', 'NODES').node_group = tree
    return driver


def main():
    recipe_path, component_path, output = map(Path, sys.argv[sys.argv.index('--')+1:])
    recipe = json.loads(recipe_path.read_text())
    pieces = json.loads(component_path.read_text())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root = bpy.context.scene.collection
    hall = bpy.data.collections.new('Grand Stair Hall | architecture')
    assembly = bpy.data.collections.new('Grand Stair Hall | mechanical components')
    root.children.link(hall)
    root.children.link(assembly)
    generated = []
    for label, rgb in recipe['materials']:
        mat = material(label, rgb)
        boxes = [box for box in recipe['boxes'] if box['material'] == label]
        wedges = [arch for arch in recipe['arches'] if arch['material'] == label]
        if boxes:
            generated.append(put_boxes(hall, boxes, label, mat))
        if wedges:
            generated.append(put_wedges(hall, wedges, label, mat))
    for label, component in pieces.items():
        assert component, f'No exported geometry in {label}'
        generated.append(put_component(assembly, label, component))
    deps = bpy.context.evaluated_depsgraph_get()
    counts = {obj.name: len(obj.evaluated_get(deps).data.polygons) for obj in generated}
    assert all(counts.values()), counts
    print(json.dumps(counts, indent=2))
    bpy.ops.wm.save_as_mainfile(filepath=str(output.resolve()))


if __name__ == '__main__':
    main()
