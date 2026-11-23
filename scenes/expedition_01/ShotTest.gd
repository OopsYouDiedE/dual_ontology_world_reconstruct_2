extends SceneTree
## Review capture: godot --path . --script res://scenes/expedition_01/ShotTest.gd -- <out_dir> <tag> [font.ttf]
## Needs a real renderer (not --headless). Writes 1280x720 PNGs of the key beats of the level.
var level
var out:="user://shots"
var tag:="shot"
func _initialize()->void:
	var a:=OS.get_cmdline_user_args()
	if a.size()>0:out=a[0]
	if a.size()>1:tag=a[1]
	if a.size()>2:
		var f:=FontFile.new();f.load_dynamic_font(a[2]);Engine.set_meta("review_font",f)
	run.call_deferred()
func shot(name:String,frames:=45)->void:
	for i in frames:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s_%s.png"%[out,tag,name])
	print("saved ",name)
func put(pos:Vector3,yaw:float,pitch:=0.)->void:
	level.walker.position=pos;level.walker.velocity=Vector3.ZERO;level.walker.rotation.y=yaw;level.eye.rotation.x=pitch
func run()->void:
	root.size=Vector2i(1280,720)
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	for i in 6:await physics_frame
	if OS.get_environment("SHOT_LITE")!="":
		root.msaa_3d=Viewport.MSAA_DISABLED;root.use_debanding=false
		for w in level.find_children("*","WorldEnvironment",true,false):w.environment.sdfgi_enabled=false
	# One beat per process keeps software-renderer memory bounded: ... -- out tag font beat
	var beat:=OS.get_cmdline_user_args()[3] if OS.get_cmdline_user_args().size()>3 else "all"
	if beat in ["all","intro"]:await shot("01_intro",3)
	if beat in ["all","arcade"]:put(Vector3(1,.05,0),-PI/2);await shot("02_arcade",60)
	if beat in ["all","board"]:put(Vector3(24.65,.05,7.7),PI,-.45);await shot("03_b3_board",60)
	if beat in ["all","loft"]:put(Vector3(33.3,.64,17.05),-PI/2);level.eye.look_at(Vector3(34.3,.73,14.75));await shot("08_inspection",60)
	if beat in ["all","lever"]:put(Vector3(38.2,.05,10.2),0.,0.);level.eye.look_at(Vector3(36.3,1.35,7.72));level.learned=true;await shot("04_b5_lever",60)
	if beat in ["all","shaft"]:
		level.line_once("release","主闸开了！……嘘，听见井底的声音没？压低脚步，别跑！")
		put(Vector3(49.4,.05,10.5),-PI/2,-.2);level.released=true;level.hunter.wake();level.hunter.position=Vector3(55,-9.9,10);level.hunter.state="hunt";await shot("05_shaft_hunter",50)
	if beat in ["all","book"]:level.toggle_book();await shot("06_manual",30)
	quit()
