extends RefCounted
## 输入回执与字数监控共用实际可见区域，跳过闭合书页、透明提示及屏外文本。

static func collect(root: Node, screen: Viewport, output: Array, spatial := true) -> void:
	if root == null: return
	if root is SubViewport and root.has_meta("physical_book_view"):
		var book: Node = root.get_meta("physical_book_view")
		if not is_instance_valid(book) or not book.is_active(): return
	if root is CanvasItem:
		if not root.is_visible_in_tree() or not _canvas_visible(root): return
	if root is Node3D and not root.is_visible_in_tree(): return
	if root is Control and (root is Label or root is BaseButton or root is RichTextLabel):
		var rect: Rect2 = root.get_global_rect()
		var ancestor := root.get_parent()
		while ancestor != null and not ancestor is Viewport:
			if ancestor is Control and ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
			ancestor = ancestor.get_parent()
		_append(root, _screen_rect(root.get_viewport(), screen, rect), output)
	elif spatial and root is Label3D and root.modulate.a > 0.001:
		var viewport := root.get_viewport()
		var camera := viewport.get_camera_3d()
		if camera != null and not camera.is_position_behind(root.global_position):
			var bounds: AABB = root.get_aabb()
			var rect := Rect2(camera.unproject_position(root.to_global(bounds.position)), Vector2.ZERO)
			for index in 8:
				var point: Vector3 = root.to_global(bounds.get_endpoint(index))
				if not camera.is_position_behind(point): rect = rect.expand(camera.unproject_position(point))
			_append(root, _screen_rect(viewport, screen, rect), output)
	for child in root.get_children(): collect(child, screen, output, spatial)

static func _canvas_visible(item: CanvasItem) -> bool:
	if item.self_modulate.a <= 0.001: return false
	var ancestor: Node = item
	var opacity := 1.0
	while ancestor != null and not ancestor is Viewport:
		if ancestor is CanvasItem: opacity *= ancestor.modulate.a
		ancestor = ancestor.get_parent()
	return opacity > 0.001

static func _screen_rect(viewport: Viewport, screen: Viewport, rect: Rect2) -> Rect2:
	rect = rect.intersection(viewport.get_visible_rect())
	if not rect.has_area(): return Rect2()
	if viewport == screen: return rect
	if viewport.has_meta("physical_book_view"):
		return viewport.get_meta("physical_book_view").screen_rect_for_control(null, rect).intersection(screen.get_visible_rect())
	var container := viewport.get_parent() as SubViewportContainer
	if container == null or not container.is_visible_in_tree(): return Rect2()
	var destination := container.get_global_rect()
	var scale := destination.size / Vector2(viewport.size)
	return Rect2(destination.position + rect.position * scale, rect.size * scale).intersection(screen.get_visible_rect())

static func _append(node: Node, rect: Rect2, output: Array) -> void:
	if not rect.has_area(): return
	var text: String = node.get_parsed_text() if node is RichTextLabel else str(node.text)
	if text.is_empty(): return
	output.append({"text": text, "x": rect.position.x, "y": rect.position.y, "width": rect.size.x,
		"height": rect.size.y, "class": node.get_class(), "path": str(node.get_path()),
		"disabled": node.disabled if node is BaseButton else false})
