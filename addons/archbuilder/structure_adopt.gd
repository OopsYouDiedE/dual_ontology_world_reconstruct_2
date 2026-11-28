@tool
extends RefCounted
## Click selection for generated geometry. Godot only makes a node clickable in the 3D
## viewport (gives it a gizmo) when it has an owner in the edited scene; meshes that @tool
## pieces build at load time have none, so clicking the Public Hall hit nothing.
## The editor plugin adopts such meshes: owner = their nearest authored ancestor (the
## piece), tagged with GENERATED_META. Godot then selects the piece when its mesh is
## clicked (deepest editable node), the scene tree dock hides the meshes, and they are
## still never saved (only nodes owned by the scene root are packed).

const META := &"_structure_generated"

## Visible geometry, plus roots of scenes instanced at build time (catalog GLBs, whose own
## meshes are owned by that root). No collision shapes or lights: their gizmos would clutter.
static func wants(node: Node) -> bool:
	return node.owner == null and (node is GeometryInstance3D or (node is Node3D and node.scene_file_path != ""))

## Adopt one node if it is generated geometry inside `root` (the edited scene). Returns true
## when adopted. Must run after the editor had its chance to own a node it added itself.
static func adopt(node: Node, root: Node) -> bool:
	if root == null or not is_instance_valid(node) or not wants(node) or node == root or not node.is_inside_tree():
		return false
	if not root.is_ancestor_of(node):
		return false
	var a := node.get_parent()
	while a != null and a != root and a.owner == null:
		a = a.get_parent()
	if a == null or a == root:
		return false
	node.set_meta(META, true)
	node.owner = a
	return true

## Adopt every generated mesh under root (scene opened before the plugin, rebuilds…).
static func sweep(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	for node in root.find_children("*", "Node3D", true, false):
		if adopt(node, root):
			count += 1
	return count
