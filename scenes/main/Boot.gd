extends Control

const Launch := preload("res://scenes/main/LaunchRoute.gd")
const PROBE_SCRIPT := "res://scenes/main/LifeBridge.cs"
const FONT := preload("res://assets/external/NotoSerifSC/NotoSerifSC.ttf")

func _ready() -> void:
	var route := Launch.resolve(OS.get_cmdline_user_args())
	var problem := str(route.get("error", ""))
	if problem.is_empty() and route.mode in ["title", "--dv-campaign-lab"]:
		problem = _diagnose(route.mode == "--dv-campaign-lab")
	if problem.is_empty():
		_enter.call_deferred(route.scene)
		return
	push_error(problem)
	_show(problem)

func _enter(scene: String) -> void:
	var status := get_tree().change_scene_to_file(scene)
	if status != OK:
		var message := "Could not open %s (%s)." % [scene, error_string(status)]
		push_error(message)
		_show(message)


func _diagnose(campaign_lab: bool) -> String:
	# 正式游戏（DualWorldMain）为纯 GDScript，标准版 Godot 可直接进入标题页与正篇；
	# 仅当在 .NET 版 Godot 下且 C# 程序集编译损坏时才提示修复编译。
	if not ClassDB.class_exists("CSharpScript"):
		return "The campaign lab requires Godot .NET and a compiled C# assembly." if campaign_lab else ""
	var probe: Script = load(PROBE_SCRIPT)
	if probe == null or not probe.can_instantiate():
		return "The C# assembly could not load. Build the project with tools/build/Build.ps1 (Windows) or tools/build/build.sh (Linux) using the .NET 8 SDK, then launch again."
	return ""

func _show(message: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.055, 0.075, 0.1)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(720, 0)
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	var heading := Label.new()
	heading.text = "Could Not Start · Blessed Are the Sleeping"
	heading.add_theme_font_override("font", FONT)
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", Color("e0794a"))
	column.add_child(heading)
	var body := Label.new()
	body.text = message
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.add_theme_font_override("font", FONT)
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", Color("eadcbd"))
	column.add_child(body)
	var quit := Button.new()
	quit.text = "Quit"
	quit.add_theme_font_override("font", FONT)
	quit.pressed.connect(func(): get_tree().quit(1))
	column.add_child(quit)
