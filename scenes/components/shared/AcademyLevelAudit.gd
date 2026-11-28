extends RefCounted
class_name AcademyLevelAudit
## Non-bypassable structural, epistemic-firewall, furniture-catalog, and AI-route validator
## for every level inheriting AcademyLevelBase. Also generates human-readable Markdown design sheets.

const FurnitureCatalog := preload("res://scenes/components/shared/AcademyFurnitureCatalog.gd")

## Terms strictly prohibited in early-game player-facing text/dialogues (goal.md Epistemic Firewall)
const FORBIDDEN_EARLY_TERMS := [
	"源质", "十二条对赌契约", "对赌契约", "恶魔", "四锚", "单实体锁", "双世界", "魔法隐藏",
	"备用源核", "契约A", "契约B", "契约 A", "契约 B", "Prima Materia", "DemonEntityLock"
]

static func validate_manifest(manifest: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	var level_id := str(manifest.get("level_id", ""))
	if level_id.is_empty():
		errors.append("Manifest missing required 'level_id'")
	if str(manifest.get("title", "")).is_empty():
		errors.append("Manifest missing required 'title'")

	var caps: Dictionary = manifest.get("capabilities", {})
	if caps.is_empty():
		errors.append("Manifest missing required 'capabilities' (use AcademyLevelPipeline.capabilities_*())")

	var allow_deep_lore := bool(manifest.get("allow_deep_lore", false))

	# 1. Validate Objects (must come from unified AcademyFurnitureCatalog unless kind == "architectural")
	var object_ids := {}
	for obj in manifest.get("objects", []):
		var oid := str(obj.get("id", ""))
		if oid.is_empty():
			errors.append("Object entry missing 'id'")
			continue
		if object_ids.has(oid):
			errors.append("Duplicate object id: %s" % oid)
		object_ids[oid] = true
		var kind := str(obj.get("kind", "glb"))
		var cid := str(obj.get("catalog_id", ""))
		if kind == "glb" and not FurnitureCatalog.GLB_CATALOG.has(cid):
			errors.append("Object '%s' references unknown GLB catalog_id '%s' (must register in AcademyFurnitureCatalog)" % [oid, cid])
		elif kind == "recipe" and not FurnitureCatalog.RECIPE_CATALOG.has(cid):
			errors.append("Object '%s' references unknown recipe catalog_id '%s' (must register in AcademyFurnitureCatalog)" % [oid, cid])

	# 2. Validate Dialogues & Epistemic Firewall
	var dialogue_ids := {}
	for dlg in manifest.get("dialogues", []):
		var did := str(dlg.get("id", ""))
		if did.is_empty():
			errors.append("Dialogue entry missing 'id'")
			continue
		dialogue_ids[did] = true
		var text_zh := str(dlg.get("text_zh", ""))
		var text_en := str(dlg.get("text_en", ""))
		if text_zh.is_empty() and text_en.is_empty():
			errors.append("Dialogue '%s' has empty text_zh and text_en" % did)
		if not allow_deep_lore:
			for term in FORBIDDEN_EARLY_TERMS:
				if term in text_zh or term in text_en:
					errors.append("EPISTEMIC FIREWALL VIOLATION in dialogue '%s': forbidden term '%s'" % [did, term])

	# 3. Validate Interactables & Hotspots
	var interact_ids := {}
	var action_ids := {}
	for grp in manifest.get("interactables", []):
		var gid := str(grp.get("id", ""))
		if gid.is_empty():
			errors.append("Interactable group missing 'id'")
			continue
		interact_ids[gid] = true
		if not allow_deep_lore:
			for term in FORBIDDEN_EARLY_TERMS:
				if term in str(grp.get("title", "")):
					errors.append("EPISTEMIC FIREWALL VIOLATION in interactable title '%s': '%s'" % [gid, term])
		var hs: Array = grp.get("hotspots", [])
		if hs.is_empty():
			errors.append("Interactable group '%s' must declare at least 1 hotspot" % gid)
		for h in hs:
			var hid := str(h.get("id", ""))
			var act := str(h.get("action_id", ""))
			if hid.is_empty() or act.is_empty():
				errors.append("Hotspot in '%s' missing 'id' or 'action_id'" % gid)
			action_ids[act] = true
			if not (h.get("world_pos") is Vector3):
				errors.append("Hotspot '%s' missing Vector3 'world_pos'" % hid)

	# 4. Validate Triggers
	for trg in manifest.get("triggers", []):
		var tid := str(trg.get("id", ""))
		if tid.is_empty():
			errors.append("Trigger entry missing 'id'")
		if str(trg.get("how", "")).is_empty():
			errors.append("Trigger '%s' missing trigger mechanism 'how'" % tid)
		var dlg_ref := str(trg.get("dialogue_id", ""))
		if not dlg_ref.is_empty() and not dialogue_ids.has(dlg_ref):
			errors.append("Trigger '%s' references unknown dialogue_id '%s'" % [tid, dlg_ref])

	# 5. Validate AI Routes (waypoints + >=3.0s telegraph rule on teammate mistake nodes)
	for route in manifest.get("ai_routes", []):
		var aid := str(route.get("actor_id", ""))
		if aid.is_empty():
			errors.append("AI route missing 'actor_id'")
		var wps: Array = route.get("waypoints", [])
		if wps.is_empty():
			errors.append("AI route '%s' has no waypoints" % aid)
		for wi in wps.size():
			var wp: Dictionary = wps[wi]
			if not (wp.get("pos") is Vector3):
				errors.append("AI route '%s' waypoint #%d missing Vector3 'pos'" % [aid, wi])
			if bool(wp.get("is_rule_mistake", false)):
				var fs := float(wp.get("foreshadow_sec", 0.0))
				if fs < 3.0:
					errors.append("AI route '%s' waypoint #%d is a rule-mistake node but foreshadow_sec=%.1fs (< 3.0s fair-telegraph floor)" % [aid, wi, fs])
			var dref := str(wp.get("dialogue_id", ""))
			if not dref.is_empty() and not dialogue_ids.has(dref):
				errors.append("AI route '%s' waypoint #%d references unknown dialogue_id '%s'" % [aid, wi, dref])

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"counts": {
			"objects": manifest.get("objects", []).size(),
			"interactables": manifest.get("interactables", []).size(),
			"dialogues": manifest.get("dialogues", []).size(),
			"triggers": manifest.get("triggers", []).size(),
			"ai_routes": manifest.get("ai_routes", []).size(),
		},
	}

static func export_markdown(manifest: Dictionary) -> String:
	var audit := validate_manifest(manifest)
	var lines: PackedStringArray = []
	lines.append("# 关卡设计清单：%s (`%s`)" % [str(manifest.get("title", "")), str(manifest.get("level_id", ""))])
	lines.append("")
	lines.append("- **校验状态**：`%s`（错误 %d 条）" % ["PASS" if audit.ok else "FAIL", audit.errors.size()])
	var caps: Dictionary = manifest.get("capabilities", {})
	lines.append("- **能力特例**：`allow_jump=%s`, `allow_lamp=%s`, `allow_stomp=%s`, `allow_command_wheel=%s`" % [
		str(caps.get("allow_jump", false)), str(caps.get("allow_lamp", false)),
		str(caps.get("allow_stomp", false)), str(caps.get("allow_command_wheel", true))
	])
	lines.append("")
	lines.append("## 1. 场景物体（统一家具库 `AcademyFurnitureCatalog`）")
	lines.append("| ID | 资产类型 | 家具库 ID | 坐标 | 分区 |")
	lines.append("|---|---|---|---|---|")
	for obj in manifest.get("objects", []):
		var p: Vector3 = obj.get("pos", Vector3.ZERO)
		lines.append("| `%s` | %s | `%s` | `(%.2f, %.2f, %.2f)` | %s |" % [
			str(obj.get("id", "")), str(obj.get("kind", "")), str(obj.get("catalog_id", "")),
			p.x, p.y, p.z, str(obj.get("zone", "-"))
		])
	lines.append("")
	lines.append("## 2. 可交互点（双模三态 `DualModeInteractionHud`）")
	lines.append("| 组 ID | 标题 | 局部热点 | 动作动词 | 触发动作 ID | 解锁条件 |")
	lines.append("|---|---|---|---|---|---|")
	for grp in manifest.get("interactables", []):
		for h in grp.get("hotspots", []):
			lines.append("| `%s` | %s | %s | %s | `%s` | %s |" % [
				str(grp.get("id", "")), str(grp.get("title", "")), str(h.get("part_name", "")),
				str(h.get("verb", "")), str(h.get("action_id", "")), str(h.get("unlock_when", "默认开放"))
			])
	lines.append("")
	lines.append("## 3. 触发方式总表")
	lines.append("| 触发 ID | 触发方式 | 来源对象 | 条件 | 结果动作 / 台词 |")
	lines.append("|---|---|---|---|---|")
	for trg in manifest.get("triggers", []):
		lines.append("| `%s` | %s | `%s` | %s | %s |" % [
			str(trg.get("id", "")), str(trg.get("how", "")), str(trg.get("source_id", "-")),
			str(trg.get("condition", "无")), str(trg.get("effect", trg.get("dialogue_id", "-")))
		])
	lines.append("")
	lines.append("## 4. 台词清单（已过认知防火墙校验）")
	lines.append("| 台词 ID | 说话人 | 声线 | 台词内容（中文） |")
	lines.append("|---|---|---|---|")
	for dlg in manifest.get("dialogues", []):
		lines.append("| `%s` | %s | `%s` | %s |" % [
			str(dlg.get("id", "")), str(dlg.get("speaker", "独白")),
			str(dlg.get("voice_profile", "resident")), str(dlg.get("text_zh", ""))
		])
	lines.append("")
	lines.append("## 5. AI 动作路线与规则前摇")
	for route in manifest.get("ai_routes", []):
		lines.append("### 角色：%s (`%s`)" % [str(route.get("actor_name", "")), str(route.get("actor_id", ""))])
		lines.append("| 序号 | 路径点坐标 | 动作 | 关联规则 | 前摇秒数 | 联动台词 |")
		lines.append("|---|---|---|---|---|---|")
		var wps: Array = route.get("waypoints", [])
		for wi in wps.size():
			var wp: Dictionary = wps[wi]
			var p: Vector3 = wp.get("pos", Vector3.ZERO)
			lines.append("| %d | `(%.2f, %.2f, %.2f)` | %s | `%s` | %.1fs | `%s` |" % [
				wi + 1, p.x, p.y, p.z, str(wp.get("action", "")),
				str(wp.get("rule_tag", "-")), float(wp.get("foreshadow_sec", 0.0)), str(wp.get("dialogue_id", "-"))
			])
	return "\n".join(lines) + "\n"
