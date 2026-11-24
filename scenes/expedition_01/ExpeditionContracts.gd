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
	if a_role==Seer.PLAYER:return "契约A 第二码：你先看见的，你先移开——我顶着。"
	return "契约A 第二码：我先看见，我移开；你盯着别眨眼。"

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
		if b_pardons>0:return "三次了……它记住你了。快把节拍器扔下去，换成它的注意。"
		return "三次了。这次没有能赎回的东西了——静步，别再出声。"
	if b_calls>0:return "又一声。井底在数你的脚步，别跑。"
	return ""

## ---- Manual pages ---------------------------------------------------------
static func manual_pages(annotated:bool,locale:="en")->Array[String]:
	if not locale.begins_with("zh"):
		var first:="[b]Shift log[/b]   01 / 05\n\nThe amber plate reacts to a witness, even through glass. Academy orders forbid direct observation. Below the shaft, the blind hunter hears iron footsteps."
		if annotated:first+="\n\n[color=#862f25]Field annotation: one steady gaze supports the plate. Two gazes overload it.[/color]"
		return [first,
			"[b]Contract A | Third clause[/b]   02 / 05\n\nOne plate, one witness. If a second watcher joins, the first must look away within one second. The newcomer must keep watching until the hand-off is complete.\n\nIf neither yields, or the newcomer looks away first, the plate goes dark for three seconds.",
			"[b]Contract B | Handover book[/b]   03 / 05\n\nThree running beats on iron make one call. After three calls the hunter remembers you. Quiet steps wear away an unfinished call.\n\nThrow a metronome to buy silence. The shaft accepts this bargain once per expedition.",
			"[b]Field controls[/b]   04 / 05\n\nReset the isolation gate in the archive and recover the core.\n\nShift: walk/run   Ctrl: quiet   Space: jump   RMB: aim\nE: use or talk   R: lamp   F: stomp to draw the hunter\nQ on Hale: hold/follow. Elsewhere: orders. Scroll and press E, or choose a number.",
			"[b]Shaft inscriptions[/b]   05 / 05\n\n[color=#862f25]Shared Footfall[/color]\nThe well counts sounds, not heads. When your steps fall together it hears a meal. One walks; one listens.\n\n[color=#862f25]One Lamp[/color]\nOne flame is allowed below. Two wicks sound like two sets of boots. Put out your lamp and walk by your companion's light."]
	var pages:Array[String]=[]
	pages.append("[b]远征员随身规则手册[/b]　01 / 05\n[color=#796346]━━━━━━━━━━━━━━━━━━━━[/color]\n\n井区交班记录　琥珀异常板遇目光即生异变，隔窗目击亦须登记。\n\n学院守则摘录　严禁直视异常板，违者按失控事故处置。\n\n值守须知　井底栖有盲目听觉异体。铁网步声直通井底，深井值守严禁奔跑。")
	if annotated:
		pages[0]+="\n\n[font_size=16][color=#862f25]手写批注　单道目光持续注视可锁稳板面。\n　　　　　双目同视即刻失控。[/color][/font_size]"
	pages.append("[b]契约 A · 值班者条例 第三码[/b]　02 / 05\n[color=#796346]━━━━━━━━━━━━━━━━━━━━[/color]\n\n[color=#862f25]一　同一块板面，每次只容一人注视。[/color]\n\n[color=#862f25]二　两人同时看见时，后看见者继续注视，\n　　先看见者一秒内移开。[/color]\n\n[color=#862f25]三　两者都不移开，或后看见者先移开，\n　　板面三秒后整块熄灭，井底听见一切。[/color]\n\n[color=#68503b]→ 准星旁的契约行会告诉你此刻是「先」还是「后」。[/color]")
	pages.append("[b]契约 B · 锚定厅交接簿 手抄页[/b]　03 / 05\n[color=#796346]━━━━━━━━━━━━━━━━━━━━[/color]\n\n[color=#862f25]一　铁网上的每一步，都会被井底听成一次呼唤。[/color]\n\n[color=#862f25]二　连续三声跑动的呼唤而不回以静步，\n　　井底会记住你。[/color]\n\n[color=#862f25]三　被记住后，只有投出会响的东西，\n　　能换回一次清静；一次远征只换一次。[/color]\n\n[color=#68503b]→ 面板上的三颗铁珠，就是它数到第几声。[/color]")
	pages.append("[b]出勤备忘[/b]　04 / 05\n[color=#796346]━━━━━━━━━━━━━━━━━━━━[/color]\n\n前班踏响铁网后落闸封井。备用源核滞留对岸，须由档案翼总控室复位隔离闸。\n\n[color=#4c3a26]Shift　切换走／跑　　右键　精瞄　　Space　短跳\nCtrl　按住静步　　　E　互动　　　Q　指令环／对准 Hale 切换留守\nR　提灯　F　跺脚[/color]\n\n[color=#68503b]← / →　翻页　　　　1　合册[/color]")
	pages.append("[b]井区规则抄本[/b]　05 / 05\n[color=#796346]━━━━━━━━━━━━━━━━━━━━[/color]\n\n[color=#862f25]其一 · 同声律[/color]\n井底只数声音，不数人头。两个人的脚步叠在一起，它会当成一顿饭——一个人走，另一个站着听。\n\n[color=#862f25]其二 · 独灯律[/color]\n井里只许点一盏灯。两盏灯芯一起爆响，井底会听成两个人的脚步。熄掉自己那盏，借同伴的光走。")
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
