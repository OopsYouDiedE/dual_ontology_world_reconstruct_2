extends RefCounted
## Stable expedition identities; visuals are supplied by the production cast.
const Cast := preload("ProductionCast.gd")
const NAMES := ["Quer", "Ada", "Silas", "Ione", "Cedric", "Shen", "Alma", "Noor", "Lucian", "Vale", "Lidia", "Felix", "Blythe", "Oren", "Sera", "Qingyue"]
const COBALT := ["Quer", "Silas", "Shen", "Noor", "Lucian", "Felix", "Sera", "Qingyue"]
const OCHRE := ["Ada", "Ione", "Alma", "Vale", "Lidia", "Oren"]
const JOBS := ["return porter", "wash courier", "switchboard attendant", "linen clerk", "night foreman", "parcel runner", "ward nurse", "line inspector", "archive clerk", "pump mechanic", "photographer", "signal runner", "bell keeper", "witness clerk", "freight porter", "survey reader"]
const JOBS_ZH := ["折返搬运工", "清洗信使", "总机值守员", "布草文书", "夜班工头", "包裹跑腿", "病房护士", "线路巡检员", "档案文书", "水泵技师", "摄影记录员", "信号跑手", "守钟人", "证词书记员", "货运搬运工", "测绘抄表员"]
const ACCOUNTS := [
	"My enclosure opened after the third pull. My sheet says there were four.",
	"Papers from the lower rail were dry, including the ones carried past the damp gauge.",
	"When we divided the line, I logged two replies. On the main line the slip printed three.",
	"There’s a dry packet on each ward bench. The central admission slip has no readable names.",
	"The empty cage is on my manifest. The boy swears he heard it as loaded.",
	"I kept the tag with the date on it. The return stamped that same tag a day ahead.",
	"I pulled the inner catch and signed the receipt. The ward camera shows somebody else doing it.",
	"I listened from the second booth. The captain was silent the whole time.",
	"The red sheet was posted in my hand. I was here, filing a different form.",
	"My gauge moved when the drain rose. The window on the far side was dry.",
	"Only one test strip had the right face under its name. I brought both to compare.",
	"Two isolated spools carried matching names, one list a minute before the other.",
	"I rang once when the hall doors shut. We heard the same bell again from behind us.",
	"The signed accounts are filed at opposite desks. Compare two before committing the party.",
	"I tightened the brake and ducked down through the service rail. The heavy cage didn’t move.",
	"I traced both audited routes off the return reel. They end under the same bell."
]

static func edition(id: String) -> String:
	if id in COBALT: return "Cobalt"
	if id in OCHRE: return "Ochre"
	return "Ivory"

static func witness(id: String) -> String:
	return ACCOUNTS[NAMES.find(id)]

static func job(id: String) -> String:
	return JOBS[NAMES.find(id)]

static func job_localized(id: String, is_en: bool) -> String:
	var idx := NAMES.find(id)
	if idx < 0: return ""
	return JOBS[idx] if is_en else JOBS_ZH[idx]

static func edition_localized(ed: String, is_en: bool) -> String:
	if is_en: return ed
	match ed:
		"Cobalt": return "钴蓝版"
		"Ochre": return "赭石版"
		_: return "象牙版"

const HERO_IDS := ["detective", "hale", "quer", "lucian", "demon"]

static func attach(parent: Node3D, id: String) -> bool:
	var low := id.to_lower()
	if low in HERO_IDS and Cast.attach_hero(parent, low):
		return true
	if id == "detective": return Cast.attach(parent)
	var variant := NAMES.find(id)
	return variant >= 0 and Cast.attach(parent, variant)

static func encounter(seed_value: int, slot: int) -> String:
	var candidates := COBALT if slot == 0 else OCHRE
	var index: int = (str(seed_value) + "/survivor/" + str(slot)).sha256_buffer()[0] % candidates.size()
	return candidates[index]
