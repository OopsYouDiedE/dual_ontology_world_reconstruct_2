extends SceneTree
## Contract regression. Runs the two published rules as the player would:
##   A) two lines on the plate → the first seer must break, the second must hold;
##   B) three loud iron steps → remembered, and one metronome throw pardons it.
## Also checks that a legal pass does NOT breach and that Hale reports his read.

var level
var fails:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,what:String)->void:
	if ok:print("  ok  "+what)
	else:push_error("FAIL "+what);fails+=1

func frames(n:int)->void:
	for i in n:await physics_frame

func run()->void:
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	await frames(6)
	var c=level.contracts

	# --- A.1 legal: the player was first, Hale joins, the player leaves, Hale holds.
	c.a_step(.1,1,c.Seer.PLAYER,true,false)
	check(c.a_state=="idle","single seer is not an overlap")
	var ev:String=c.a_step(.1,2,c.Seer.PLAYER,true,true)
	check(ev=="overlap" and c.a_role==c.Seer.PLAYER,"two lines open an overlap and record the first seer")
	check("移开" in c.a_hint(),"player-first hint tells the player to break line")
	ev=""
	for i in 8:
		ev=c.a_step(.1,1,c.Seer.PLAYER,false,true)
		if ev=="release":break
	check(ev=="release" and c.a_state=="idle","first seer leaving while the second holds closes the overlap")
	c.reset()

	# --- A.2 breach: the first seer never leaves inside the grace window.
	c.a_step(.1,2,c.Seer.PLAYER,true,true)
	ev=""
	for i in 14:
		ev=c.a_step(.12,2,c.Seer.PLAYER,true,true)
		if ev=="breach":break
	check(ev=="breach" and c.a_state=="blackout","nobody yielding past the grace window breaches contract A")
	check("先看见者" in c.a_reason,"the breach names the first seer's clause")
	c.reset()

	# --- A.3 breach: Hale saw first, the player is second and blinks first.
	c.a_step(.1,2,c.Seer.HALE,true,true)
	ev=c.a_step(.1,1,c.Seer.HALE,false,true)
	check(ev=="breach" and "后看见者" in c.a_reason,"the second seer leaving first is a breach")
	c.reset()

	# --- A.4 legal: Hale saw first and leaves, the player (second) holds.
	c.a_step(.1,2,c.Seer.HALE,true,true)
	ev=""
	for i in 8:
		ev=c.a_step(.1,1,c.Seer.HALE,true,false)
		if ev=="release":break
	check(ev=="release" and c.a_state=="idle","second seer holding the plate closes the overlap")
	c.reset()

	# --- Contract B: three loud steps make one call, three calls remember you.
	check(c.b_loud_step()=="" and c.b_beads()==1,"first loud step only fills a bead")
	c.b_loud_step()
	var ev_b:String=c.b_loud_step()
	check(ev_b=="call" and c.b_calls==1,"three loud steps are one call")
	for i in 6:c.b_loud_step()
	check(c.b_remembered,"three calls make the hunter remember you")
	check(c.b_hint()!="","the HUD line reports the remembered state")
	check(c.b_pardon(),"a metronome throw pardons the remembered state")
	check(not c.b_remembered and c.b_pardons==0,"the pardon is spent and cannot repeat")
	for i in 9:c.b_loud_step()
	check(c.b_remembered and not c.b_pardon(),"a second remember cannot be pardoned")

	# --- Quiet time erodes a partial tally instead of freezing it.
	c.reset()
	c.b_loud_step();c.b_loud_step()
	for i in 26:c.b_quiet(.2)
	check(c.b_beads()==0,"standing still lets the partial tally decay")

	# --- Manual carries both contracts on their own pages.
	var pages:Array=c.manual_pages(true)
	check(pages.size()==5,"manual combines both systems across five pages")
	check("Contract A" in pages[1] and "Third clause" in pages[1],"page 2 is contract A")
	check("Contract B" in pages[2] and "Handover" in pages[2],"page 3 is contract B")
	check("Field annotation" in pages[0],"page 1 keeps the field annotation")

	# --- The wheel only offers orders that can run right now.
	level.walker.position=Vector3(34.6,.03,0.)
	level.eye.look_at(Vector3(36.,1.57,0.))
	var items:Array=level.order_options()
	check(items.size()>=2,"the wheel offers more than one order at the gate")
	check(items.any(func(i):return i.id=="try_gate"),"the gate order is present when the gate is focused")
	check(not items.any(func(i):return i.id=="north"),"the bridge order is absent before the shaft")

	# --- Deaths are answered with the clause that was broken.
	check("契约A" in level.rule_clause_for("违反契约A：两人都不移开视线"),"contract A deaths map to the clause card")
	check("契约B" in level.rule_clause_for("违反契约B：铁网呼唤"),"contract B deaths map to the clause card")

	# Exercise the actual ray-to-contract wiring, rather than passing an invented first seer.
	level.walker.position=Vector3(24.65,.02,7.75);level.hale.position=level.archive.WINDOW
	var at_board:Vector3=level.archive.PLATE-level.hale.position-Vector3.UP*1.57
	for hale_first in [true,false]:
		level.contracts.reset();level.prior_seer=0
		level.archive.gaze=at_board if hale_first else Vector3.ZERO
		level.eye.look_at(Vector3(24.65,1.57,4.) if hale_first else level.archive.PLATE)
		level.contract_hooks(level.walker.position,.016)
		level.archive.gaze=at_board;level.eye.look_at(level.archive.PLATE)
		level.contract_hooks(level.walker.position,.016)
		check(level.contracts.a_role==(c.Seer.HALE if hale_first else c.Seer.PLAYER),"live gaze order: Hale first = %s"%hale_first)
		if hale_first:
			level.archive.gaze=Vector3.ZERO
			for tick in 42:level.contract_hooks(level.walker.position,.016)
			check(level.contracts.trust_notes.has("contract_a"),"a legal hand-off awards the live contract")
		else:
			level.archive.gaze=Vector3.ZERO;level.contract_hooks(level.walker.position,.016)
			check(level.retry>0. and level.contracts.a_state=="blackout","second seer leaving triggers the live failure")
	print("PASS: contracts A and B, wheel gating, manual pages (%d checks failed)"%fails)
	level.queue_free()
	for tick in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0 if fails==0 else 1)
