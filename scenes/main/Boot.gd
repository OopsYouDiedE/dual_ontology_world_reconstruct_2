extends Control
## 启动自检。Main.gd 依赖 C# 桥（LifeBridge.cs / CampaignBridge.cs / ModelCatalog.cs）：
## - 用标准版 Godot 打开时，.cs 没有加载器，Main.gd 解析失败，整个窗口只剩空白底色；
## - C# 程序集没编译（NuGet 还原失败等）时，同样会得到一个起不来的 Main。
## 这里先检查，再切换到 Main.tscn；检查失败时在屏幕上写明原因与处理办法。

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const PROBE_SCRIPT := "res://scenes/main/LifeBridge.cs"
const FONT := preload("res://assets/external/NotoSerifSC/NotoSerifSC.ttf")

func _ready() -> void:
	var problem := _diagnose()
	if problem.is_empty():
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	push_error(problem)
	_show(problem)

func _diagnose() -> String:
	if not ClassDB.class_exists("CSharpScript"):
		return "当前运行的是标准版 Godot（不含 C#）。\n\n本项目的核心规则、DV 解析器与存读档都在 C# 中，必须使用 Godot .NET (mono) 4.7.2 打开。\n\n处理：下载 Godot_v4.7.2-stable_mono，并安装 .NET SDK 8.0.x。"
	var probe: Script = load(PROBE_SCRIPT)
	if probe == null or not probe.can_instantiate():
		return "C# 程序集尚未编译成功，无法创建 LifeBridge。\n\n常见原因：NuGet 还原失败（NU1301 本地源不存在）、未安装 .NET SDK 8、或编译出错。\n\n处理：在项目根执行 tools/build/build.sh（Windows 用 tools/build/Build.ps1），修好报错后重新运行。"
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
	heading.text = "无法启动 · 安眠者有福"
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
	quit.text = "退出"
	quit.add_theme_font_override("font", FONT)
	quit.pressed.connect(func(): get_tree().quit(1))
	column.add_child(quit)
