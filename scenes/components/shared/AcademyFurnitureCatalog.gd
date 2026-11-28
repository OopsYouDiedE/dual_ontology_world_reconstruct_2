extends RefCounted
class_name AcademyFurnitureCatalog
## Unified Furniture Catalog & Material Refinement Pipeline for The Sleeping Academy.
## Merges Chapter 1 (Expedition-01 / ArchBuilder recipes) and Mainline (Public Hall /
## KayKit CC0 / Academy GLBs) into one shared catalog with cohesive 1900s European
## manor & cathedral materials (grained varnished walnut, aged oak, brushed antique
## brass, wrought iron, woven linen, wool baize, oxblood leather, beeswax, honed slate).

const Factory := preload("res://tools/building_construction/BuildingConstruction/Shared/ComponentFactory.gd")
const RenderProfile := preload("res://scenes/components/rendering/AcademyRenderProfile.gd")

const GLB_CATALOG := {
	"manor_table_long": {"path": "res://assets/furniture/kaykit_cc0/table_long.glb", "preset": "walnut_varnish"},
	"manor_chair": {"path": "res://assets/furniture/kaykit_cc0/chair.glb", "preset": "walnut_varnish"},
	"academy_side_chair": {"path": "res://assets/props/academy/academy_side_chair.glb", "preset": "walnut_varnish"},
	"manor_stool": {"path": "res://assets/furniture/kaykit_cc0/stool.glb", "preset": "oak_aged"},
	"manor_shelf_large": {"path": "res://assets/furniture/kaykit_cc0/shelf_large.glb", "preset": "walnut_varnish"},
	"manor_chest": {"path": "res://assets/furniture/kaykit_cc0/chest.glb", "preset": "oak_aged"},
	"supply_crates": {"path": "res://assets/furniture/kaykit_cc0/crates_stacked.glb", "preset": "oak_aged"},
	"brass_candle_triple": {"path": "res://assets/furniture/kaykit_cc0/candle_triple.glb", "preset": "brass_antique"},
}

const RECIPE_CATALOG := {
	"bookshelf": {"recipe": "Cabinets/Bookshelf", "preset": "walnut_varnish"},
	"reception_desk": {"recipe": "Tables/ReceptionDesk", "preset": "walnut_varnish"},
	"dining_table": {"recipe": "Tables/Table", "preset": "oak_aged"},
	"work_counter": {"recipe": "Tables/WorkCounter", "preset": "oak_aged"},
	"bench": {"recipe": "Chairs/Bench", "preset": "oak_aged"},
	"bed": {"recipe": "Beds/Bed", "preset": "oak_aged"},
	"linen_cabinet": {"recipe": "Cabinets/LinenCabinet", "preset": "walnut_varnish"},
	"medicine_cabinet": {"recipe": "Cabinets/MedicineCabinet", "preset": "oak_aged"},
	"washstand": {"recipe": "Props/Washstand", "preset": "oak_aged"},
	"crockery_shelf": {"recipe": "Props/CrockeryShelf", "preset": "oak_aged"},
	"privacy_screen": {"recipe": "Props/Screen", "preset": "walnut_varnish"},
	"chalkboard": {"recipe": "Props/Chalkboard", "preset": "slate_honed"},
	"stove": {"recipe": "Props/Stove", "preset": "iron_wrought"},
	"kitchen_hood": {"recipe": "Props/KitchenHood", "preset": "iron_wrought"},
	"banker_lamp": {"recipe": "Lighting/BankerLamp", "preset": "brass_antique"},
	"caged_lamp": {"recipe": "Lighting/CagedLamp", "preset": "brass_antique"},
	"schematic": {"recipe": "Props/Schematic", "preset": "linen_cream"},
	"crates": {"recipe": "Props/Crates", "preset": "oak_aged"},
}

static var _mat_cache: Dictionary = {}

static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## Unified high-craft material presets shared by every piece of furniture in Chapter 1 & Mainline.
static func material(preset: String) -> StandardMaterial3D:
	if _mat_cache.has(preset):
		return _mat_cache[preset]

	var m := StandardMaterial3D.new()
	var wood_albedo := _load_tex(RenderProfile.TRI_WOOD_ALBEDO)
	var wood_normal := _load_tex(RenderProfile.TRI_WOOD_NORMAL)

	match preset:
		"walnut_varnish":
			m.albedo_color = Color("5a3b28")
			if wood_albedo != null:
				m.albedo_texture = wood_albedo
				m.uv1_triplanar = true
				m.uv1_scale = Vector3(0.85, 0.85, 0.85)
			if wood_normal != null:
				m.normal_enabled = true
				m.normal_texture = wood_normal
				m.normal_scale = 0.55
			m.metallic = 0.04
			m.roughness = 0.46
			m.metallic_specular = 0.55
			m.clearcoat_enabled = true
			m.clearcoat = 0.42
			m.clearcoat_roughness = 0.28
			m.rim_enabled = true
			m.rim = 0.14
			m.rim_tint = 0.35
		"oak_aged":
			m.albedo_color = Color("765339")
			if wood_albedo != null:
				m.albedo_texture = wood_albedo
				m.uv1_triplanar = true
				m.uv1_scale = Vector3(0.95, 0.95, 0.95)
			if wood_normal != null:
				m.normal_enabled = true
				m.normal_texture = wood_normal
				m.normal_scale = 0.65
			m.metallic = 0.02
			m.roughness = 0.62
			m.metallic_specular = 0.44
			m.clearcoat_enabled = true
			m.clearcoat = 0.18
			m.clearcoat_roughness = 0.42
		"brass_antique":
			m.albedo_color = Color("c99c4a")
			m.metallic = 0.86
			m.roughness = 0.28
			m.metallic_specular = 0.72
			m.rim_enabled = true
			m.rim = 0.24
			m.rim_tint = 0.45
		"iron_wrought":
			m.albedo_color = Color("282d35")
			m.metallic = 0.74
			m.roughness = 0.46
			m.metallic_specular = 0.52
		"linen_cream":
			m.albedo_color = Color("ded6c6")
			m.metallic = 0.0
			m.roughness = 0.94
			m.metallic_specular = 0.12
		"wool_baize":
			m.albedo_color = Color("2a4d3e")
			m.metallic = 0.0
			m.roughness = 0.90
			m.metallic_specular = 0.16
			m.rim_enabled = true
			m.rim = 0.18
			m.rim_tint = 0.25
		"leather_oxblood":
			m.albedo_color = Color("5e2620")
			m.metallic = 0.04
			m.roughness = 0.52
			m.metallic_specular = 0.48
			m.clearcoat_enabled = true
			m.clearcoat = 0.24
			m.clearcoat_roughness = 0.36
		"beeswax_candle":
			m.albedo_color = Color("f0e2c0")
			m.metallic = 0.0
			m.roughness = 0.56
			m.emission_enabled = true
			m.emission = Color("ffcf80")
			m.emission_energy_multiplier = 0.22
		"slate_honed":
			m.albedo_color = Color("1f242b")
			m.metallic = 0.04
			m.roughness = 0.74
			m.metallic_specular = 0.38
		_:
			return material("oak_aged")

	_mat_cache[preset] = m
	return m

## Intelligent sub-part material refinement: upgrades flat/plastic recipe or GLB meshes
## while preserving visual contrast between wood, brass hardware, iron, cushions, linen, books, and wax.
static func refine_furniture_materials(root: Node, default_preset: String = "walnut_varnish", preserve_textured_glb := false) -> void:
	if root == null:
		return
	var book_palette := ["leather_oxblood", "wool_baize", "walnut_varnish", "slate_honed"]
	var book_idx := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var n := mi.name.to_lower()
		# Keep emissive lamp glass, glowing shades, and schematics untouched
		if "shade" in n or "bulb" in n or "flame" in n or "glass" in n or "ember" in n or "paper" in n or "schematic" in n:
			continue
		if preserve_textured_glb:
			var existing := mi.get_active_material(0)
			if existing is StandardMaterial3D and (existing as StandardMaterial3D).albedo_texture != null:
				var tuned := (existing as StandardMaterial3D).duplicate() as StandardMaterial3D
				if default_preset == "brass_antique":
					tuned.metallic = 0.65
					tuned.roughness = 0.34
					tuned.clearcoat_enabled = true
					tuned.clearcoat = 0.20
				else:
					tuned.roughness = clampf(tuned.roughness, 0.44, 0.68)
					tuned.clearcoat_enabled = true
					tuned.clearcoat = 0.28 if default_preset == "walnut_varnish" else 0.14
					tuned.clearcoat_roughness = 0.32
					tuned.albedo_color = tuned.albedo_color.lerp(Color("d6c4ae"), 0.15)
				mi.material_override = tuned
				continue

		if "candle" in n or "wax" in n:
			mi.material_override = material("beeswax_candle")
		elif "brass" in n or "handle" in n or "knob" in n or "hinge" in n or "clasp" in n or "lamp" in n:
			mi.material_override = material("brass_antique")
		elif "iron" in n or "hood" in n or "stove" in n or "grate" in n or "pipe" in n or "metal" in n:
			mi.material_override = material("iron_wrought")
		elif "board" in n or "slate" in n or "chalk" in n:
			mi.material_override = material("slate_honed")
		elif "pillow" in n or "sheet" in n or "linen" in n or "mattress" in n or "fabric" in n or "cloth" in n or "panel" in n:
			mi.material_override = material("linen_cream")
		elif "cushion" in n or "pad" in n or "blanket" in n or "baize" in n or "felt" in n:
			mi.material_override = material("wool_baize")
		elif "book" in n or "volume" in n or "tome" in n:
			mi.material_override = material(book_palette[book_idx % book_palette.size()])
			book_idx += 1
		else:
			mi.material_override = material(default_preset)

## Spawn a unified GLB prop by catalog ID or resource path.
static func spawn_glb(parent: Node3D, id_or_path: String, pos: Vector3, yaw := 0.0, uniform_scale := 1.0, preset_override := "") -> Node3D:
	var path := id_or_path
	var preset := preset_override
	if GLB_CATALOG.has(id_or_path):
		var entry: Dictionary = GLB_CATALOG[id_or_path]
		path = str(entry.path)
		if preset.is_empty():
			preset = str(entry.preset)
	if preset.is_empty():
		preset = "walnut_varnish"
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * uniform_scale
	parent.add_child(inst)
	# Preserve baked dungeon/academy textures with refined PBR clearcoat & metallic tuning when present
	refine_furniture_materials(inst, preset, true)
	return inst

## Spawn a unified ArchBuilder procedural recipe prop by catalog ID or relative recipe path.
static func spawn_recipe(parent: Node3D, id_or_recipe: String, pos: Vector3, yaw := 0.0, params := {}, preset_override := "") -> Node3D:
	var recipe := id_or_recipe
	var preset := preset_override
	if RECIPE_CATALOG.has(id_or_recipe):
		var entry: Dictionary = RECIPE_CATALOG[id_or_recipe]
		recipe = str(entry.recipe)
		if preset.is_empty():
			preset = str(entry.preset)
	if preset.is_empty():
		preset = "oak_aged"
	var full_path := Factory.COMPONENT_ROOT + recipe.get_base_dir() + "/Recipe" + recipe.get_file() + ".gd"
	var part := Factory.create(full_path)
	if part == null:
		return null
	part.recipe_parameters.merge(params, true)
	part.position = pos
	part.rotation.y = yaw
	parent.add_child(part)
	refine_furniture_materials(part, preset, false)
	return part

static func catalog_summary() -> Dictionary:
	return {
		"glb_count": GLB_CATALOG.size(),
		"recipe_count": RECIPE_CATALOG.size(),
		"material_presets": [
			"walnut_varnish", "oak_aged", "brass_antique", "iron_wrought",
			"linen_cream", "wool_baize", "leather_oxblood", "beeswax_candle", "slate_honed"
		],
	}
