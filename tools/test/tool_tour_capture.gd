extends SceneTree
## Captures real-window screenshots of the level/item tools for docs/production/tools-guide.md.
## Needs a real renderer:
## & .runtime/godot/4.7.2/Godot_v4.7.2-stable_mono_win64_console.exe --path . --rendering-method forward_plus --windowed --resolution 1600x900 -s res://tools/test/tool_tour_capture.gd

const Simulator := preload("res://tools/building_construction/BuildingSimulator.tscn")
const Library := preload("res://tools/building_construction/ComponentLibrary.tscn")
const Factory := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const Assembly := preload("res://tools/building_construction/production/assembly/ComponentAssembly.gd")
const R01Level := preload("res://scenes/levels/Chapter1R01Level.gd")

const OUT := "res://docs/production/media/tools"

func _initialize() -> void:
	run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := ProjectSettings.globalize_path("%s/%s.jpg" % [OUT, name])
	print("saved %s %s" % [name, img.save_jpg(path, 0.86)])

func entry(catalog: Dictionary, id: String) -> Dictionary:
	for e in catalog.items:
		if e.id == id:
			return e
	return {}

func tab(node: Node, title: String) -> void:
	for tc in node.find_children("*", "TabContainer", true, false):
		for i in tc.get_tab_count():
			if tc.get_tab_title(i) == title:
				tc.current_tab = i

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600, 900)

	# 1. ArchBuilder (BuildingSimulator): plan + 3D preview, Build tab
	var sim := Simulator.instantiate()
	root.add_child(sim)
	await frames(12)
	sim.reset_views()  # same as pressing Center once the window has its final size
	await shot("01_archbuilder_overview")
	tab(sim, "Furniture")
	await frames(4)
	await shot("02_archbuilder_props")
	sim.queue_free()
	await frames(3)

	# 2. Component Library (item property tool): a chest with its interaction data
	var lib := Library.instantiate()
	root.add_child(lib)
	await frames(6)
	var catalog: Dictionary = lib.catalog
	var placed := []
	for spec in [["RecipeTable", Vector3(0, 0, 0)], ["RecipeChest", Vector3(1.6, 0, 0.4)], ["RecipeBookshelf", Vector3(-1.8, 0, -0.6)]]:
		var part: Node3D = lib._make_part(entry(catalog, spec[0]))
		lib.candidates.add_child(part, true)
		part.position = spec[1]
		part.owner = lib.candidates
		lib._own_interaction(part)
		placed.append(part)
	lib.target = Vector3(0, 0.6, 0)
	lib.distance = 6.5
	lib._update_camera()
	for i in lib.category.item_count:
		if str(lib.category.get_item_metadata(i)) == "Props":
			lib.category.select(i)
			lib._refresh(i)
	lib._select(placed[1])
	await frames(6)
	await shot("03_library_chest_interaction")
	lib._select(placed[2])
	await frames(4)
	await shot("04_library_make_selectable")
	lib.queue_free()
	await frames(3)

	# 3. A level built on AcademyLevelBase: in-game prompt + F2 blueprint inspector
	var lvl := R01Level.new()
	root.add_child(lvl)
	await frames(10)
	await shot("05_level_runtime_prompt")
	# Same scene descriptors, Detroit presenter (restore the saved preference afterwards).
	var saved_mode: int = lvl.dual_ui.mode
	lvl.dual_ui.set_mode(DualModeInteractionHud.Mode.DISTRIBUTED_DETROIT)
	await frames(4)
	await shot("05b_level_runtime_detroit")
	lvl.dual_ui.set_mode(saved_mode)
	lvl.set_blueprint_inspector_visible(true)
	await frames(4)
	await shot("06_level_f2_inspector")
	lvl.queue_free()
	await frames(3)
	quit(0)
