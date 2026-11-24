extends SceneTree
## Review capture. One process, several framings. Uses --rendering-method
## gl_compatibility because this sandbox has llvmpipe (Forward+ SDFGI needs VRAM).
var level:Node3D
var out:=""

func _initialize()->void:run.call_deferred()

func frames(n:int)->void:
	for i in n:await process_frame

func place(pos:Vector3,yaw:float,pitch:float)->void:
	level.walker.position=pos
	level.walker.rotation.y=yaw
	level.eye.rotation=Vector3(pitch,0,0)
	level.polish.set_physics_process(true)
	for i in 26:await physics_frame
	await frames(6)

func shot(name:String)->void:
	var img:=root.get_viewport().get_texture().get_image()
	img.save_png(out+"/"+name+".png")
	print("CAPTURED ",name," ",img.get_size())

func run()->void:
	out=OS.get_environment("SHOT_DIR")
	if out=="":out="/home/user/shots"
	level=preload("res://scenes/expedition_01/Expedition.tscn").instantiate()
	root.add_child(level)
	await frames(70)
	level.polish.fade_a=0.

	# 1. A1 arcade, opening framing.
	await place(Vector3(2.2,.05,0.),-PI*.5,-.03)
	shot("01-arcade")

	# 2. A2 quiet niche: tally wall, bench, oil crate, run door.
	await place(Vector3(10.2,.05,3.2),-PI*.42,-.10)
	level.toast("A2 侧龛 · 站定才提得起的灯油")
	await frames(20)
	shot("02-a2-niche")

	# 3. The earth-cut run, looking into B2.
	await place(Vector3(16.4,.05,6.6),-PI*.5,-.04)
	await frames(14)
	shot("03-a2-run")

	# 4. B3 plate with the contract-A readout live.
	await place(Vector3(23.85,.05,10.0),0.,-.42)
	level.tutorial_room=true
	level.contracts.a_state="overlap"
	level.contracts.a_role=level.contracts.Seer.PLAYER
	level.contracts.a_timer=.35
	level.contracts.a_hold=.2
	level.contracts.b_steps=2
	level.contracts.b_calls=1
	for i in 40:await physics_frame
	await frames(4)
	shot("04-b3-contract")

	# 5. Command wheel at the segregation gate (in front of it, not inside the bars).
	await place(Vector3(33.2,.05,0.),-PI*.5,-.05)
	level.contracts.soft_reset()
	level.walker.position=Vector3(35.15,.05,0.)
	level.wheel.bind([{"id":"try_gate","title":"让 Hale 试闸","hint":"他会连拉两下，确认落死","cost":"代价：约 1.1 秒，信任 +1"},{"id":"hold","title":"原地待命","hint":"停在当前房间，别跟进来","cost":"召回需要你走回来"},{"id":"advise","title":"听他的建议","hint":"Hale 会说出他此刻看到的风险","cost":"仅信息，不消耗时间"}])
	level.wheel.reveal()
	level.wheel_open=true
	for i in 26:await process_frame
	shot("05-command-wheel")
	level.wheel.dismiss()
	level.contracts.soft_reset()

	# 6. C1 shaft span, north window sightline.
	await place(Vector3(49.4,.05,10.5),-PI*.5,-.06)
	level.released=true
	level.hunter.wake()
	for i in 30:await physics_frame
	await frames(4)
	shot("06-c1-shaft")

	# 7. Rule manual, contract pages.
	level.toggle_book()
	level.book_page=1
	level.render_book()
	for i in 16:await process_frame
	shot("07-manual-contract-a")
	level.book_page=2
	level.render_book()
	for i in 10:await process_frame
	shot("08-manual-contract-b")
	level.toggle_book()
	quit(0)
