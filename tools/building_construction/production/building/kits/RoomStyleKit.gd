extends Resource
## Resource-local registry: each Script implements emit(solver, slot) and may
## declare supports(slot). Fallbacks are other keys in the same registry.
@export var recipes:Dictionary={
	"ColumnSlot":preload("ColumnRecipe.gd"),
	"BeamSlot":preload("BeamRecipe.gd"),
	"CeilingSlot":preload("CeilingRecipe.gd"),
	"WallFinishSlot":preload("WallRecipe.gd"),
	"WindowSlot":preload("WindowRecipe.gd"),
	"Blind":preload("WindowRecipe.gd"),
	"DoorSlot":preload("DoorRecipe.gd"),
	"CeilingLightSlot":preload("LightRecipe.gd"),
	"Flush":preload("LightRecipe.gd"),
	"DomeSlot":preload("DomeRecipe.gd"),
	"SlabSlot":preload("SlabRecipe.gd"),
	"CoreSlot":preload("CoreRecipe.gd"),
	"FloorFinishSlot":preload("PavingRecipe.gd"),
	"ShellSlot":preload("ShellRecipe.gd"),
	"RoofSlot":preload("RoofRecipe.gd"),
}
@export var recipe_overrides:Dictionary={} # additive registrations, including new fallback keys
@export var variants:Dictionary={}
@export var fallbacks:Dictionary={"WindowSlot":"Blind","CeilingLightSlot":"Flush"}
@export var capabilities:Dictionary={} # recipe key -> [minimum height, maximum height]
@export var passes:=PackedStringArray(["StructurePass","EnvelopePass","FinishPass"])
@export var service_floor:=false
@export var dome:=false
@export var extensions:Dictionary={} # phase -> Array[Script], run(solver, owner)
@export var exterior_windows:=true

func select(slot:Dictionary)->Dictionary:
	var key:String=slot.kind;var visited={}
	while (recipe_overrides.has(key) or recipes.has(key)) and not visited.has(key):
		visited[key]=true
		var impl=recipe_overrides.get(key,recipes.get(key)).new();slot.variant=variants.get(key,key)
		var limits=capabilities.get(key,[2.4,6.0])
		if slot.height>=limits[0] and slot.height<=limits[1] and (not impl.has_method("supports") or impl.supports(slot)):return {"recipe":impl,"key":key}
		key=fallbacks.get(key,"")
	return {}
