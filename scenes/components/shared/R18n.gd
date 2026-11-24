extends RefCounted
## Lightweight runtime bilingual localization (r18n) for The Sleeping Academy.
## Works in both full gameplay and headless SceneTree tests without requiring an
## autoload. Default locale is "zh" unless overridden via --lang=en or set_locale().

const LOCALE_META := &"r18n_locale"
const SUPPORTED := ["zh", "en"]

const STRINGS := {
	# HUD & controls
	"hud.oil": {"zh": "灯油　%d%%", "en": "Lamp Oil  %d%%"},
	"hud.obj.fetch": {"zh": "取回备用源核", "en": "Recover Spare Core"},
	"hud.obj.return": {"zh": "带源核回锚定厅", "en": "Return Core to Anchor Hall"},
	"hud.mode.quiet": {"zh": "静步", "en": "Quiet"},
	"hud.mode.walk": {"zh": "步行", "en": "Walk"},
	"hud.mode.run": {"zh": "奔跑", "en": "Run"},
	"hud.note.quiet_well": {"zh": "　· 静步压住了脚音", "en": "  · Quiet steps suppress echo"},
	"hud.note.hunt": {"zh": "　· 井底已闻声", "en": "  · The shaft heard you"},
	"hud.note.iron_watch": {"zh": "　· 留意铁网上的脚音", "en": "  · Watch iron-grate footsteps"},
	"hud.note.bait": {"zh": "　· 井底的动静被引开了", "en": "  · The hunter is drawn away"},
	"hud.note.pair_loud": {"zh": "　· 同声律！脚步叠上了", "en": "  · Unison Rule! Footsteps overlapped"},
	"hud.note.both_lamp": {"zh": "　· 独灯律！只许一盏灯", "en": "  · Single-Lamp Rule! Extinguish one"},
	"hud.tick.pair_loud": {"zh": "同声律 · 两人的脚步叠在一起", "en": "UNISON RULE · Overlapping footsteps"},
	"hud.tick.both_lamp": {"zh": "独灯律 · 两盏灯同时亮着", "en": "SINGLE-LAMP RULE · Two lanterns lit"},
	"hud.time": {"zh": "经过 %d:%02d", "en": "Elapsed %d:%02d"},
	"hud.hale_prefix": {"zh": "Hale　▸ %s", "en": "Hale  ▸ %s"},
	"hud.step_prefix": {"zh": "当前步骤：%s", "en": "Step: %s"},
	"hud.lang_badge": {"zh": "[F8] 中文", "en": "[F8] EN"},
	"hud.lang_switched": {"zh": "界面语言：简体中文", "en": "Language: English"},
	"hud.start_toast": {"zh": "I 手册与操作　·　F8 切换中/英　·　点击画面开始", "en": "I Manual & Controls  ·  F8 ZH/EN  ·  Click to start"},
	"hud.sens": {"zh": "视角灵敏度 %d%%", "en": "Look Sensitivity %d%%"},
	"hud.book_controls": {
		"zh": "← / → 翻页　　I / 1 / Esc 合册　　F8 切换语言\nWASD 移动　Shift 切换走／跑　Ctrl 按住静步　Space 跳跃　右键稳视\nE 互动　Q 指令　R 提灯　F 跺脚",
		"en": "← / → Turn Page    I / 1 / Esc Close    F8 Switch Language\nWASD Move   Shift Walk/Run   Ctrl Quiet   Space Hop   RMB Steady Aim\nE Interact   Q Orders   R Lantern   F Stomp"
	},
	# Step targets (unified, no mid-level language switching)
	"goal.arcade": {"zh": "沿主廊前往隔离闸", "en": "Follow the arcade to the isolating gate"},
	"goal.enter_hall": {"zh": "走进锚定厅 · 稳压区", "en": "Step into Anchor Hall · Stabilizer"},
	"goal.return_hall": {"zh": "沿主廊返回锚定厅 · 稳压区", "en": "Return down the arcade to Anchor Hall"},
	"goal.return_gallery": {"zh": "沿检修回廊返回主廊", "en": "Follow the service gallery back to the arcade"},
	"goal.evacuate": {"zh": "上螺旋梯 · 经绿门撤离", "en": "Climb the spiral stair and exit via the green door"},
	"goal.bridge_go": {"zh": "Hale 已就位 · 看前方过桥", "en": "Hale is posted · watch ahead and cross"},
	"goal.hale_think": {"zh": "Hale 正在考虑", "en": "Hale is considering"},
	"goal.hale_north": {"zh": "Hale 正前往北窗", "en": "Hale is heading to the north window"},
	"goal.enter_shaft": {"zh": "进源井 · 静步接近桥头", "en": "Enter the caisson · approach the span quietly"},
	"goal.trial_cross": {"zh": "盯住琥珀板面并平稳通过", "en": "Hold your gaze on the amber plate and cross"},
	"goal.trial_lock": {"zh": "通过试验板 · 单人稳视可锁定承重", "en": "Cross the trial plate · a steady solo gaze locks it"},
	"goal.control_room": {"zh": "前往总控室复位隔离闸", "en": "Reset the isolating gate in the control room"},
	"goal.window_opt": {"zh": "可选：与 Hale 隔窗对照 · 左侧进 B3 门", "en": "Optional: compare gazes with Hale · B3 door on the left"},
	"goal.through_b3": {"zh": "经 B3 试验区前往总控室", "en": "Reach the control room through B3"},
	"goal.archive_door": {"zh": "从右侧绿门进档案翼找总闸", "en": "Take the green archive door on the right to find the release"},
	# Hale status
	"hale.posting": {"zh": "前往北窗", "en": "Heading to North Window"},
	"hale.holding": {"zh": "北窗就位", "en": "Holding North Window"},
	"hale.hold": {"zh": "原地留守", "en": "Holding Position"},
	"hale.gate": {"zh": "试推铁闸", "en": "Testing Gate"},
	"hale.follow": {"zh": "跟随中", "en": "Following"},
	# Command wheel
	"wheel.controls": {"zh": "鼠标点选 / 滚轮　E 确认　数字键直选　Q 取消", "en": "Click / Scroll   E Confirm   1-5 Quick Pick   Q Cancel"},
	# Prompts
	"prompt.gate_busy": {"zh": "Hale 正在试铁闸…", "en": "Hale is testing the gate…"},
	"prompt.gate": {"zh": "[E] 晃动铁闸　[Q] 请 Hale 试试", "en": "[E] Shake Gate   [Q] Ask Hale to Try"},
	"prompt.note": {"zh": "[E] 阅读残页", "en": "[E] Read Torn Page"},
	"prompt.loot": {"zh": "[E] 取灯油", "en": "[E] Take Lamp Oil"},
	"prompt.clock": {"zh": "[E] 取节拍器", "en": "[E] Take Metronome"},
	"prompt.clock_locked": {"zh": "节拍器柜 · 已锁", "en": "Metronome Locker · Locked"},
	"prompt.lever": {"zh": "[E] 扳下总闸", "en": "[E] Pull Master Release"},
	"prompt.core": {"zh": "[E] 拔出源核", "en": "[E] Extract Spare Core"},
	"prompt.return": {"zh": "[E] 撞开应急门", "en": "[E] Push Emergency Door"},
	"prompt.exit": {"zh": "[E] 开启气密门", "en": "[E] Open Airlock"},
	"prompt.north_recall": {"zh": "[Q] 召回 Hale", "en": "[Q] Recall Hale"},
	"prompt.north_post": {"zh": "[Q] 指派 Hale 盯桥", "en": "[Q] Post Hale at North Window"},
	"prompt.throw": {"zh": "[E] 投出节拍器", "en": "[E] Throw Metronome"},
	"prompt.hale": {"zh": "[Q] %s　[E] 交谈", "en": "[Q] %s   [E] Talk"},
	"prompt.hale_hold": {"zh": "留守", "en": "Hold"},
	"prompt.hale_follow": {"zh": "跟随", "en": "Follow"},
	"prompt.solo_exit": {"zh": "[E] 应急滑门 · 独自撤离", "en": "[E] Emergency Slide · Solo Exit"},
	"prompt.stele1": {"zh": "[E] 阅读规则刻板 · 同声律", "en": "[E] Read Stele · Unison Rule"},
	"prompt.stele2": {"zh": "[E] 阅读规则刻板 · 独灯律", "en": "[E] Read Stele · Single-Lamp Rule"},
	"prompt.maint_lift": {"zh": "[E] 拉动配重手柄", "en": "[E] Pull Counterweight Handle"},
	"prompt.maint_oil": {"zh": "[E] 补充灯油", "en": "[E] Refill Lamp Oil"},
	"prompt.vault_oil": {"zh": "[E] 取备用灯油", "en": "[E] Take Reserve Oil"},
	"prompt.niche_oil": {"zh": "[E] 取灯油（站稳）", "en": "[E] Take Oil (Stand Still)"},
	# Oil grace warning
	"warn.catwalk_oil": {"zh": "灯油见底！快退回实墙安全区（%.1fs）", "en": "Oil spent! Step off the catwalk now (%.1fs)"},
}

static func locale() -> String:
	if Engine.has_meta(LOCALE_META):
		var cur := String(Engine.get_meta(LOCALE_META))
		if cur in SUPPORTED:
			return cur
	for arg in OS.get_cmdline_user_args():
		if arg == "--lang=en":
			Engine.set_meta(LOCALE_META, "en")
			return "en"
		if arg == "--lang=zh":
			Engine.set_meta(LOCALE_META, "zh")
			return "zh"
	Engine.set_meta(LOCALE_META, "zh")
	return "zh"

static func set_locale(lang: String) -> String:
	var target := lang if lang in SUPPORTED else "zh"
	Engine.set_meta(LOCALE_META, target)
	return target

static func toggle_locale() -> String:
	return set_locale("en" if locale() == "zh" else "zh")

static func is_en() -> bool:
	return locale() == "en"

static func pick(zh: String, en: String) -> String:
	return en if is_en() else zh

static func t(key: String, args: Array = []) -> String:
	var entry: Variant = STRINGS.get(key, null)
	var text := key
	if entry is Dictionary:
		text = String(entry.get(locale(), entry.get("zh", key)))
	if not args.is_empty():
		return text % args
	return text
