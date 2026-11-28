extends RefCounted
## Authored documents and marked-up controls. These are observations and procedures, never the room simulation.

const TITLES := {
	"intake": "Night Dispatch", "returns": "Undeliverable Office", "exchange": "Blind Switchboard",
	"wash": "Pump Archive", "lift": "Counterweight House", "airlock": "Dry Ward",
	"shutter": "Curator’s Barrier", "hall": "Public Hall", "darkroom": "Fixing Room",
	"relay": "Dispatch Exchange", "meridian": "Observatory"
}
const FIXTURES := {
	"intake": ["Dispatch instructions", "Issue hatch", "Returned packets"],
	"returns": ["Misdelivery register", "Dead-letter reel", "Return hatch"],
	"exchange": ["Switchboard notice", "Speaking trumpet", "Booth separator"],
	"wash": ["Pump log", "Diverting handwheel", "Condensate gauge"],
	"lift": ["Freight manifest", "Winding drum", "Safety dog"],
	"airlock": ["Dry Ward notice", "Inner locker", "Pass-through locker"],
	"shutter": ["Curator’s amendment", "Bell register", "Drawbar"],
	"hall": ["Arrival book", "Witness pigeonholes", "Survey reel"],
	"darkroom": ["Processing notes", "Negative carrier", "Bath regulator"],
	"relay": ["Routing docket", "Dispatch horn", "Insulated relay"],
	"meridian": ["Dawn register", "Bell regulator", "Manual winding wheel"]
}
const BRIEF := {
	"intake":"A field manual waits at the dispatch cabinet. Approach it and press E.",
	"returns":"Someone taps from inside the return enclosure. Their last three knocks came back as four.",
	"exchange":"Two crews left two incompatible instructions on the same speaking line.",
	"wash":"There are wet fingerprints on the inner face of the gauge glass.",
	"lift":"An empty freight cage moves like someone is still inside it.",
	"airlock":"The attendant rang the admission bell with the lockers open. The bell is still ringing.",
	"shutter":"Red ink on the drawbar tells you to cross before the bell. The Public Hall is just beyond it.",
	"hall":"Safe ground. The return desks are still staffed. File an expedition route to open the outer wing.",
	"darkroom":"Your group shows up on an undeveloped negative. The figures don’t line up with the people beside you.",
	"relay":"The dispatch horn is sending back replies nobody has made yet.",
	"meridian":"The hall is waiting to hear a morning bell with your party’s names on the record."
}

const R18n := preload("res://scenes/components/shared/R18n.gd")

# The four directions are deliberately portable survival practices, with local exceptions.
const IVORY := [
	"1 / At a speaking tube, keep your mouth closed until the line falls quiet. Keep a companion in sight.",
	"2 / Carry papers under your coat. If the coat is wet inside, leave the papers in a dry drawer and go around.",
	"3 / In a ward, carry your packet through on your person. Set down heavy tools before stepping onto a moving threshold.",
	"4 / Take a shutter after the bell. If the pull is still fighting you, back into a recess and let someone read the room."
]
const IVORY_ZH := [
	"1 / 面对传声筒时，线路未静前切勿开口；始终让同伴处于视野之内。",
	"2 / 文件贴身收入外套内侧。若衬里受潮，将文件留在干燥抽屉中，绕行通过。",
	"3 / 进入隔离病房时，随身携带你的文书袋；踏上活动门槛前，先放下重型器具。",
	"4 / 听到钟声后再拉动闸门。若拉杆仍在反向抗力，退回壁龛，让同伴先行读房。"
]
const VERSIONS := {
	"Ivory": ["Wait for quiet at a speaking tube; stay in sight.", "Keep your packet on you until the far side."],
	"Cobalt": ["Give one reply while a call is still held; stay in speaking booth until they acknowledge it.", "Leave your packet in the pass-through before you cross."],
	"Ochre": ["Keep speech off the main line. File the reply on the relay before moving.", "Keep a wet packet in the open tray until it dries; carry it yourself afterward."]
}
const VERSIONS_ZH := {
	"Ivory": ["传声筒待静后再答话；保持同伴在视线内。", "随身携带文书袋直至抵达对岸。"],
	"Cobalt": ["呼叫未断时先作一次应答；留在通话亭内直到对方确认。", "通过前先将文书袋留在传递窗内。"],
	"Ochre": ["勿在主线通话；先在中继台登记答复再移动。", "潮湿的文书袋留在敞口托盘晾干后再随身带走。"]
}

static func ivory_lines() -> Array:
	return IVORY if R18n.is_en() else IVORY_ZH

static func version_lines(edition: String) -> Array:
	var table := VERSIONS if R18n.is_en() else VERSIONS_ZH
	return table.get(edition, table["Ivory"])

static func notice(stage: String, v: bool) -> String:
	match stage:
		"intake": return "NIGHT DISPATCH / Visitors\nEach watch draws one authorised Ivory copy. If the issue hatch repeats a name, take a returned packet and check for the ivory thread. The captain’s copy goes with the captain."
		"returns": return "UNDL. / Night return ledger\nThe unsent clasp was taken from the %s row. The %s tag is dated tomorrow. During repairs, return porters tied off the cord and opened with their own key.\nA voice inside the cabinet says ‘Use either tag. I put both there.’" % (["ASH", "REED"] if v else ["REED", "ASH"])
		"exchange": return "ALL LINES ANSWER ON FIRST CALL / Permanent order, unsigned.\nBelow it: two failed calls share one line on the maintenance sheet. One successful call sits alone on a separate line. The relay spool was marked ‘one at a time.’\nSomeone scratched a diagonal through the word ALL."
		"wash": return "PUMP ARCHIVE / Drawings must be returned dry.\nA porter circled the %s gutter on the only delivery marked DRY. The other page clings to its sleeve.\nA courier’s note underneath: ‘My lining held. I only had to stop once at the drip tray.’" % ("cistern" if v else "yard")
		"lift": return "FREIGHT / Carriage docket\nThe empty cage was logged as %s. The balancing shoe goes on the opposite run. The porter who came around underneath signed the brake log first.\nA thumbprint overlaps the superintendent’s instruction to release the dog on arrival." % ("yard-heavy" if v else "hall-heavy")
		"airlock": return "DRY WARD / Lay all packets in the pass-through. Enter together.\nThe nurse’s after-action note lists two sets of dry prints, on opposite benches. The names in the jointly signed admission slot have been blotted through.\nThe lockers have independent catches. The inner catch takes a travel pin."
		"shutter": return "RED AMENDMENT / CROSS BEFORE THE BELL.\nIn the prior watch the certification shows %s. Under a bootprint: ‘wheel backed off first’. An older maintenance tag points to the service shoe under the drawbar." % ("two overlapping seals" if v else "a torn second seal")
		"hall": return "ARRIVALS / Hall return desk\nRecord the two independent depositions here, or take the annotated survey off the reel. Each desk keeps its own record. A shared agreement must say what changed and who saw it."
		"darkroom": return "FIXING ROOM / Test strip register\nThe only legible contact print shows the %s emulsion. A cook recovered the reverse image by closing the carrier and rewinding it before copying.\nIn the margin: ‘One print had our names, but our faces came from another case.’" % ("copper-side" if v else "black-side")
		"relay": return "EXCHANGE / Single dispatch order\nThe return shows %s. Two sheets from divided lines still agree about the names. Their arrival times differ by one minute.\nWhen the superintendent signed a common order, two witnesses stayed to hear it read." % ("a repeat under the same signature" if v else "a rest between separate signatures")
		"meridian": return "DAWN REGISTER / Names on bell slips\nAt the last opening, the register was signed only after the return line was closed. The other shift kept the register safe by carrying the sealed docket to the manual winder.\nOne slip has room for the name of every member of your group."
	return ""

static func observation(stage: String, group: int, v: bool) -> String:
	if group == 0: return notice(stage, v)
	match stage:
		"intake": return "A wire links the issue latch to a roll of blank passes." if group == 1 else "One returned folio has a length of ivory thread caught in its binding."
		"returns": return "The tag jammed behind the little brass screw reads %s." % ("ASH" if v else "REED") if group == 1 else "The service key can be turned after the reel is restrained."
		"exchange": return "A reply comes back in the interval between the knocks. Your two orders claim that same interval." if group == 1 else "One throw connects two separate booths. The spool under the dog plate takes one signal per turn."
		"wash": return "Both outlets drip upward. One copper collar still has dry dust on its lip." if group == 1 else "The sleeve is intact. Under the awning there’s space to stop and let it drip."
		"lift": return "The cage pulls toward the %s side. The empty drum is polished on the opposite flange." % ("yard" if v else "hall") if group == 1 else "The small escape catch is behind the dog lever, under the stationary service rail."
		"airlock": return "One shelf is broad enough to spread a wet packet. The other is a dry bench for the person carrying their own papers." if group == 1 else "A pin can hold the inner door while the outer locker is used on its own."
		"shutter": return "The bell mark is scratched into the fixed ring, not the moving needle." if group == 1 else "The shoe has an old wear line where it can rest against the service ledge."
		"hall": return "Accounts from the return office and the ward were filed under different stamps." if group == 1 else "The survey overlays two routes. Both are signed at the Hall; both end at the Observatory."
		"darkroom": return "The carrier has a black enamel face and a polished copper back. Each takes one piece of glass." if group == 1 else "A pencil line lies just under the regulator’s halfway stop. Someone stopped the last wash there."
		"relay": return "The iris can be closed without disconnecting the private side of the relay." if group == 1 else "The insulated reel has two separate windings. Both slips will fit, one per winding."
		"meridian": return "A blank return column sits opposite the signature line." if group == 1 else "Two hands are drawn on the wheel cap. The docket clamp has a clean rectangle where a paper sat."
	return ""
