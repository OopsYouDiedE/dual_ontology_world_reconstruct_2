extends RefCounted
## Two publishable rules of this level, written as enforceable clauses and
## wired to systems that already exist (gaze count, iron footfalls, hunter).
##
## CONTRACT A — 《值班者条例 · 第三码》 plate custody
##   1. 同一块板面，每次只容一人注视。
##   2. 两人同时看见时，后看见者须继续注视；先看见者须在一秒内移开视线。
##   3. 若两人都不移开，或后看见者先移开，板面三秒后整块熄灭，井底听见一切。
##
## CONTRACT B — 《锚定厅交接簿 · 手抄页》 iron calls
##   1. 铁网上的每一步都会被井底听成一次呼唤。
##   2. 连续三次跑（不静步）踩响铁网而不回以静步，井底会记住你。
##   3. 被记住后，只有投出会响的东西能换回一次清静；一次远征只换一次。

enum Seer { NONE, PLAYER, HALE }

const A_GRACE := 1.0          # first seer must break line within this window
const A_HOLD := .62           # second seer must keep the line this long
const A_BLACKOUT := 3.0       # plate dies for this long after a breach
const B_CALLS := 3            # loud iron steps that make up one "call out"
const B_PARDON := 1           # metronome throws that can buy silence back

var a_role := Seer.NONE       # who saw the plate first in this overlap
var a_timer := 0.             # overlap duration
var a_hold := 0.              # second seer's continuous gaze inside the overlap
var a_state := "idle"         # idle | overlap | breach | blackout
var a_blackout := 0.
var a_breaches := 0
var a_warned := false

var b_calls := 0              # completed call-outs (0..B_CALLS)
var b_steps := 0              # loud iron steps toward the next call-out
var b_remembered := false
var b_pardons := B_PARDON
var b_pardon_used := false
var b_breaches := 0
var b_grace := 0.             # quiet time that decays one loud step

var trust := 0                # Hale's confidence in the player (0..3)
var trust_notes := {}

func reset()->void:
	a_role=Seer.NONE;a_timer=0.;a_hold=0.;a_state="idle";a_blackout=0.;a_reason=""
	a_breaches=0;a_warned=false
	b_calls=0;b_steps=0;b_remembered=false;b_pardons=B_PARDON;b_pardon_used=false;b_breaches=0;b_grace=0.
	trust=0;trust_notes.clear()

## Walking away from the plate is not a breach — the custody rule only binds
## two lines that are actually on the same board.
func a_abandon()->void:
	if a_state!="overlap":return
	a_state="idle";a_role=Seer.NONE;a_timer=0.;a_hold=0.

## Retry only forgives the level; the contracts keep their own ledgers.
func soft_reset()->void:
	a_state="idle";a_role=Seer.NONE;a_timer=0.;a_hold=0.;a_blackout=0.;a_reason=""
	b_steps=0;b_grace=0.

func award(id:String)->void:
	if trust_notes.has(id):return
	trust_notes[id]=true
	trust=mini(3,trust+1)

## ---- Contract A -----------------------------------------------------------
## `first` is who was already watching when the second line joined.
## One tick of the plate custody rule. `first` is who was already watching when
## the other line joined. Legal ends:
##   * the first seer leaves inside the grace window and the second holds;
##   * the first seer never leaves        -> breach (plate blackout);
##   * the second seer leaves first       -> breach (it was taught the wrong way).
func a_step(dt:float,count:int,first:int,self_watching:bool,hale_watching:bool)->String:
	if a_state=="blackout":
		a_blackout-=dt
		if a_blackout<=0.:a_state="idle";a_role=Seer.NONE;a_timer=0.;a_hold=0.
		return ""
	if count>=2:
		if a_state!="overlap":
			a_state="overlap";a_role=first;a_timer=0.;a_hold=0.
			return "overlap"
	elif a_state!="overlap":
		return ""
	a_timer+=dt
	var first_w:=self_watching if a_role==Seer.PLAYER else hale_watching
	var second_w:=hale_watching if a_role==Seer.PLAYER else self_watching
	if first_w and second_w:
		if a_timer>A_GRACE:return a_breach("先看见者未在窗口内移开视线")
		return "overlap"
	if not first_w and second_w:
		a_hold+=dt
		if a_hold>=A_HOLD:
			a_state="idle";a_role=Seer.NONE;a_timer=0.;a_hold=0.
			return "release"
		return "overlap"
	if first_w and not second_w:return a_breach("后看见者先移开视线")
	return a_breach("两条视线同时消失")

func a_breach(reason:String)->String:
	a_state="blackout";a_blackout=A_BLACKOUT;a_breaches+=1
	a_reason=reason
	a_timer=0.;a_hold=0.
	return "breach"
var a_reason:=""

func a_hint()->String:
	if a_state=="blackout":return "契约A · 板面熄灭 %.1fs"%maxf(0.,a_blackout)
	if a_state=="overlap":
		if a_role==Seer.PLAYER:return "契约A · 你先看见 → 移开视线 %.1fs"%maxf(0.,A_GRACE-a_timer)
		return "契约A · 你在后 → 继续注视 %.1fs"%maxf(0.,A_HOLD-a_hold)
	return ""

func a_line()->String:
	if a_role==Seer.PLAYER:return "你先看到的。看我这边，板子交给我。"
	return "我先看到的。我转开，你盯住它。"

## ---- Contract B -----------------------------------------------------------
## Returns "call" when a full set of three loud iron steps completes.
func b_loud_step()->String:
	if b_remembered:return ""
	b_steps+=1
	if b_steps>=B_CALLS:
		b_steps=0;b_calls+=1
		if b_calls>=B_CALLS:
			b_remembered=true
			b_breaches+=1
			return "remembered"
		return "call"
	return ""

func b_quiet(dt:float)->void:
	if b_remembered or b_steps==0:return
	b_grace+=dt
	if b_grace>1.2:
		b_grace=0.
		b_steps=maxi(0,b_steps-1)

## A thrown metronome buys one clean slate; a second call-out cannot be pardoned.
func b_pardon()->bool:
	if not b_remembered or b_pardons<=0:return false
	b_pardons-=1;b_pardon_used=true;b_remembered=false;b_calls=0;b_steps=0;b_grace=0.
	return true

func b_beads()->int:return b_steps
func b_hint()->String:
	if b_remembered:return "契约B · 井底已经记住你（投出节拍器可赎回）"
	if b_steps>0:return "契约B · 铁网呼唤 %d/%d"%[b_calls*B_CALLS+b_steps,B_CALLS*B_CALLS]
	return ""

func b_line(level)->String:
	if b_remembered:
		if b_pardons>0 and level.equipped:return "把节拍器扔远点，试试能不能引开它！"
		return "听那动静。把脚步放轻。"
	if b_calls>0:return "你听，井里又响了一声。慢点走。"
	return ""

## ---- Manual pages ---------------------------------------------------------
static func manual_pages(annotated:bool,sound_read:=false,light_read:=false)->Array[String]:
	var pages:Array[String]=[]
	var first:="[b]井区值班日志[/b]　01 / 05\n\n夜班交接：井区已封，琥珀板的观测记录仍在档案翼。接班人到岗后请核查。\n\n昨夜有人跑过铁网。脚步声刚停，井下就传来撞击声。"
	if annotated:first+="\n\n[color=#862f25]手写批注　隔窗也算目击。只剩一道目光时，板面的波纹慢慢平了。[/color]"
	pages.append(first)
	pages.append("[b]观察窗交班记录[/b]　02 / 05\n\n夜班末，窗台上的铅笔滚到了地上。我弯腰去捡，身后的同事喊了一声。我再抬头时，玻璃外只剩一片暗色。\n\n早班来时请带块干布。窗上都是手印，迎着灯看不清。")
	pages.append("[b]铁网巡夜记录[/b]　03 / 05\n\n送油的人跑过栈桥，铁网响得盖住了我的喊声。他在栏杆边站住后，下面还响了一阵，像有什么蹭着井壁往上爬。\n\n油壶搁在入口，桥上没人应声。我先回去叫人。")
	pages.append("[b]出勤备忘[/b]　04 / 05\n\n昨夜封井后，备用源核仍留在对岸。稳压室向井区发出调拨令：回收源核，交回锚定厅。\n\n交班时清点灯油与人员，两项都要记在册上。")
	var inscriptions:="[b]井区刻文抄本[/b]　05 / 05"
	if sound_read:inscriptions+="\n\n[color=#862f25]同声律[/color]\n井底只数声音。两个人的脚步叠在一起，它会当成一顿饭。一个人走，另一个站着听。"
	if light_read:inscriptions+="\n\n[color=#862f25]独灯律[/color]\n井里只许点一盏灯。两盏灯芯一起爆响，井底会听成两个人的脚步。"
	if not sound_read and not light_read:inscriptions+="\n\n留页待抄。"
	pages.append(inscriptions)
	return pages

static func region_card(id:String)->Dictionary:
	match id:
		"arcade":return {"title":"A1 沉浸长廊","rule":"契约B · 铁网步声直通井底","note":"长廊石面安静，但学跑的地方在这里。"}
		"niche":return {"title":"A2 侧龛","rule":"契约B · 静步成契","note":"龛内的灯油只奖给不用跑的人。"}
		"archive":return {"title":"B1 / B2 档案翼","rule":"契约A · 单人注视优先","note":"隔窗也算目击，登记在册。"}
		"trial":return {"title":"B3 试验区","rule":"契约A · 先看见者先移开","note":"准星旁的契约行说明此刻你是谁。"}
		"pump":return {"title":"B6 泵房","rule":"契约B · 合闸会吵醒井底","note":"省掉总控室，就要换一次呼唤。"}
		"release":return {"title":"B5 总控室","rule":"契约A · 通闸不改视线","note":"黄铜总闸在此复位。"}
		"shaft":return {"title":"C1 源井","rule":"契约A + B 同时生效","note":"桥面看视线，脚下数呼唤。"}
		"underdeck":return {"title":"C2 桥下检修道","rule":"契约B · 板面不会看见你","note":"没有视线审判，只有脚步的账。"}
		"return":return {"title":"C5 检修回廊","rule":"——","note":"井底听不见这一段。"}
	return {}
