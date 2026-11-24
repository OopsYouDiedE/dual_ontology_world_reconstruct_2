extends SceneTree
## Conditional UI checks, separate from unguided route rates. Each arm gets a fresh scene.
const Policy=preload("human_sol_policy.gd")
const Scene=preload("res://scenes/expedition_01/Expedition.tscn")
var results:=[]

func _initialize()->void:run.call_deferred()

func run()->void:
	var failures:=0
	for kind:String in ["note","stele1","stele2"]:
		for read:bool in [false,true]:
			var lv=Scene.instantiate();root.add_child(lv)
			preload("collision_fixture.gd").apply_lightweight(lv)
			await physics_frame
			var point:Vector3={"note":Vector3(23.6,1.03,4),"stele1":lv.STELE_A,"stele2":lv.STELE_B}[kind]
			var ready:=false
			for offset:Vector3 in [Vector3.BACK,Vector3.FORWARD,Vector3.LEFT,Vector3.RIGHT]:
				lv.walker.global_position=point+offset*1.25-Vector3.UP*1.42
				lv.walker.velocity=Vector3.ZERO;lv.walker.look_at(Vector3(point.x,lv.walker.global_position.y,point.z));lv.eye.look_at(point)
				await physics_frame
				if lv.focus()==kind and "阅读" in lv.prompt.text and lv.prompt.is_visible_in_tree():ready=true;break
			lv.set_physics_process(false)
			var prompt:String=lv.prompt.text
			var intent:Dictionary=Policy.new("direct").decide({"place":Vector2.ZERO,"heading":0.,"orders":[],"captions":[],"prompt":prompt if read else "","lanes":[]})
			var pressed:bool=intent.get("key",0)==KEY_E
			if pressed:
				for down:bool in [true,false]:
					var event:=InputEventKey.new();event.physical_keycode=KEY_E;event.pressed=down;Input.parse_input_event(event)
			await physics_frame
			var id:String={"note":"archive_note","stele1":"stele_sound","stele2":"stele_light"}[kind]
			var delivered:=false
			for entry:Dictionary in lv.captions.entries.values():
				if entry.get("id","")==id:delivered=true
			var ok:=ready and pressed==read and delivered==read
			if not ok:failures+=1
			results.append({"site":kind,"enabled":read,"prompt":prompt,"pressed":pressed,"delivered":delivered,"ok":ok})
			lv.queue_free();await process_frame
	print("READING_SITES ",JSON.stringify(results));quit(1 if failures else 0)
