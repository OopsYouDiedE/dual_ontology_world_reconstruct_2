extends SceneTree
const Cast = preload("res://scenes/rogue_crossing/ProductionCast.gd")
func _initialize()->void:
 run.call_deferred()

func run()->void:
 var stage:=Node3D.new()
 root.add_child(stage)
 var env:=WorldEnvironment.new()
 env.environment=Environment.new()
 env.environment.background_mode=Environment.BG_COLOR
 env.environment.background_color=Color("424959")
 env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color=Color("c5cfdf")
 env.environment.ambient_light_energy=0.65
 stage.add_child(env)
 var key:=DirectionalLight3D.new()
 key.rotation_degrees=Vector3(-38,-32,0)
 key.light_energy=1.45
 stage.add_child(key)
 var hale:=Node3D.new()
 stage.add_child(hale)
 if not Cast.attach(hale,1,true): quit(1); return
 var anim:AnimationPlayer=hale.get_meta("animation_player")
 var rig:Skeleton3D=hale.get_meta("skeleton")
 for clip in [&"idle",&"walk",&"run",&"gate_effort",&"ward",&"watch_plate",&"peek"]:
  var a:=anim.get_animation(clip)
  for i in a.get_track_count():
   var path:=a.track_get_path(i)
   if anim.get_parent().get_node_or_null(NodePath(path.get_concatenated_names()))!=rig or rig.find_bone(path.get_subname(0))<0:
    push_error("Unbound Hale track: %s" % path);quit(1);return
 print("Hale animation tracks resolve on R-05")
 if DisplayServer.get_name()=="headless": quit();return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/hale-review"))
 var cam:=Camera3D.new()
 cam.fov=30
 stage.add_child(cam)
 cam.current=true
 for spec in [["front",Vector3(0,1.26,2.55),&"idle",0.0],["side",Vector3(-2.55,1.41,0),&"idle",0.0],["gate",Vector3(2.1,1.26,1.5),&"gate_effort",0.55]]:
  anim.play(spec[2]);anim.seek(spec[3],true);anim.pause()
  cam.position=spec[1];cam.look_at(Vector3(0,1.19,0))
  for i in 4:await process_frame
  await RenderingServer.frame_post_draw
  var err:=root.get_texture().get_image().save_png("res://.runtime/hale-review/"+spec[0]+".png")
  if err!=OK: quit(1);return
 quit()
