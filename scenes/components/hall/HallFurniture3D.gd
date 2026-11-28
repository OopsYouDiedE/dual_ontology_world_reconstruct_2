@tool
class_name HallFurniture3D
extends GothicHallPiece3D
## One piece of furniture from the unified catalog (AcademyFurnitureCatalog): an ArchBuilder
## recipe (e.g. "Beds/Bed", "Cabinets/Bookshelf") or a GLB, with the catalog's PBR material
## preset. Rotate/move the node to place it; `station_size` reserves a floor footprint
## (in structure axes) that blocks walking and gets a collider.

@export var recipe := "":
	set(v): recipe = v; changed()
@export_file("*.glb") var glb := "":
	set(v): glb = v; changed()
## Material preset (walnut_varnish, oak_aged, brass_antique, iron_wrought, slate_honed,
## linen_cream…); empty = catalog default for the item.
@export var preset := "":
	set(v): preset = v; changed()
@export var params: Dictionary = {}:
	set(v): params = v; changed()
@export var uniform_scale := 1.0:
	set(v): uniform_scale = v; changed()
@export var station_size := Vector2.ZERO:
	set(v): station_size = v; shape_changed()
@export var station_height := 0.0:
	set(v): station_height = v; changed()

func shape_key() -> Array: return [station_size]
func plan_outline() -> PackedVector2Array:
	var s := station_size if station_size != Vector2.ZERO else Vector2(0.5, 0.5)
	var c := to_plan(Vector3.ZERO)
	return PackedVector2Array([c - s * 0.5, c + Vector2(s.x, -s.y) * 0.5, c + s * 0.5, c + Vector2(-s.x, s.y) * 0.5])

func _build() -> void:
	if recipe != "":
		FurnitureCatalog.spawn_recipe(self, recipe, Vector3.ZERO, 0.0, params, preset if preset != "" else recipe_preset(recipe))
	elif glb != "":
		FurnitureCatalog.spawn_glb(self, glb, Vector3.ZERO, 0.0, uniform_scale, preset)
	if station_size != Vector2.ZERO:
		_reserve_station(Vector3.ZERO, station_size, station_height)
