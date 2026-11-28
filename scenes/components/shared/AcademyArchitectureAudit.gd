extends RefCounted
class_name AcademyArchitectureAudit
## Source-level guard that keeps every level, item, UI and post-render on ONE pipeline.
##
## Each rule names a construct that only the shared pipeline may use, and the files that
## implement that pipeline. Any other formal-runtime file using it is a bypass and fails
## `tools/test/architecture_unity_test.gd` (and `tools/inspect_level.py`).
##
##   level logic ─▶ AcademyLevelRuntime.install()            (UI stack, input routing)
##                   └▶ AcademyInteractionDirector ─▶ DualModeInteractionHud (presenter)
##   scene items ─▶ AcademyInteractable / AcademyInteractionSchema descriptors
##   rendering   ─▶ AcademyLevelPipeline.bootstrap_viewport ─▶ AcademyStage (env/ink/essence)
##   items       ─▶ AcademyFurnitureCatalog / ComponentFactory (catalog.json)

const FORMAL_DIRS := [
	"res://scenes/components",
	"res://scenes/levels",
	"res://scenes/rogue",
	"res://scenes/rogue_camp",
	"res://scenes/rogue_crossing",
	"res://scenes/rogue_player",
	"res://scenes/rogue_rules",
	"res://scenes/rogue_view",
	"res://scenes/expedition_01",
]

const SELF_PATH := "res://scenes/components/shared/AcademyArchitectureAudit.gd"
const PIPELINE := "res://scenes/components/shared/AcademyLevelPipeline.gd"
const RUNTIME := "res://scenes/components/shared/AcademyLevelRuntime.gd"
const DIRECTOR := "res://scenes/components/interaction/AcademyInteractionDirector.gd"
const STAGE := "res://scenes/components/rendering/AcademyStage.gd"
const HUD := "res://scenes/components/shared/DualModeInteractionHud.gd"
const PRESENTER := "res://scenes/components/shared/UnifiedDialoguePresenter.gd"
const WHEEL := "res://scenes/components/shared/UnifiedTeammateWheel.gd"

## id, regex, allowed files, why
const RULES := [
	{"id": "ui.hud_instance", "pattern": "(DualModeInteractionHud|DualHud|DualInteractionHud)\\.new\\(",
		"allow": [PIPELINE], "why": "Interaction UI is created only by AcademyLevelRuntime.install()."},
	{"id": "ui.dialogue_instance", "pattern": "(UnifiedDialoguePresenter|DialoguePresenter)\\.new\\(",
		"allow": [PIPELINE, "res://scenes/components/shared/StoryDirector.gd"], "why": "Captions/voice come from the runtime (cutscenes reuse the same presenter)."},
	{"id": "ui.wheel_instance", "pattern": "(UnifiedTeammateWheel|TeammateWheel)\\.new\\(",
		"allow": [PIPELINE], "why": "The Q teammate wheel is created only by the runtime."},
	{"id": "ui.raw_components", "pattern": "preload\\(\"res://scenes/components/shared/(AcademyCaptions|AcademyCommandWheel)\\.gd\"\\)",
		"allow": [PRESENTER, WHEEL], "why": "Raw caption bar / wheel widgets are wrapped by the unified presenter and wheel."},
	{"id": "ui.direct_sync", "pattern": "\\.sync_groups\\(",
		"allow": [DIRECTOR], "why": "Levels publish interaction descriptors; only the director talks to the presenter."},
	{"id": "ui.stack_bootstrap", "pattern": "bootstrap_ui_stack\\(",
		"allow": [RUNTIME, PIPELINE], "why": "Install AcademyLevelRuntime instead of assembling the UI stack."},
	{"id": "render.stage_env", "pattern": "(Stage|AcademyStage)\\.(environment|ink|apply_to_viewport|create_compatibility_fill_light)\\(",
		"allow": [PIPELINE, STAGE], "why": "Render stage + post passes come from AcademyLevelPipeline.bootstrap_viewport()."},
	{"id": "render.post_pass", "pattern": "(EssenceShiftPass|InkPass)(\\.gd\"\\))?\\.create\\(|post/(EssenceShiftPass|InkPass)\\.gd",
		"allow": [STAGE], "why": "Post-render passes are attached only by AcademyStage."},
	{"id": "render.blue_prince_lab", "pattern": "res://scenes/blue_prince_lab/",
		"allow": [], "why": "Formal runtime must not depend on the experimental blue_prince_lab."},
	{"id": "render.shared_to_expedition", "pattern": "res://scenes/expedition_01/",
		"allow_prefix_block": "res://scenes/components", "why": "Shared components must not depend on a specific level."},
	{"id": "items.catalog_json", "pattern": "building_construction/catalog\\.json",
		"allow": [], "why": "Load items via ComponentFactory.load_catalog() / AcademyFurnitureCatalog."},
]

## Returns {ok, violations: [{rule, file, line, text, why}], scanned}
static func scan(dirs: Array = FORMAL_DIRS) -> Dictionary:
	var files: PackedStringArray = []
	for d in dirs:
		_collect(str(d), files)
	var compiled := []
	for rule in RULES:
		var re := RegEx.new()
		re.compile(str(rule.pattern))
		compiled.append(re)
	var violations: Array[Dictionary] = []
	for path in files:
		if path == SELF_PATH:
			continue
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		for ri in RULES.size():
			var rule: Dictionary = RULES[ri]
			if _allowed(rule, path):
				continue
			var re: RegEx = compiled[ri]
			for li in lines.size():
				var line := lines[li]
				var code := line.split("#", true, 1)[0] if not line.strip_edges().begins_with("##") else ""
				if code.strip_edges().is_empty():
					continue
				if re.search(code) != null:
					violations.append({"rule": rule.id, "file": path, "line": li + 1, "text": line.strip_edges(), "why": rule.why})
	return {"ok": violations.is_empty(), "violations": violations, "scanned": files.size()}

static func format_report(report: Dictionary) -> String:
	var out: PackedStringArray = ["Architecture audit: %s (%d files)" % ["PASS" if report.ok else "FAIL", int(report.scanned)]]
	for v in report.violations:
		out.append("  [%s] %s:%d  %s\n      -> %s" % [v.rule, v.file, v.line, v.text, v.why])
	return "\n".join(out)

static func _allowed(rule: Dictionary, path: String) -> bool:
	if rule.has("allow_prefix_block"):
		return not path.begins_with(str(rule.allow_prefix_block))
	return path in (rule.get("allow", []) as Array)

static func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect(full, out)
		elif entry.get_extension() in ["gd", "tscn"]:
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
