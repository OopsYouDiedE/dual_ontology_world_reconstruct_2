extends "Masonry.gd"
## A1 service route. All interaction and mechanical state lives here.
const WEST:=15.
const EAST:=27.
const WALL_Z:=-2.2
const RUN_Z:=-7.4
const GATE_X:=24. # Under the solid pier between clerestory bays.
const HEAD:=2.35
const HALF_DOOR:=.8
const LIFT:=2.38
const DURATION:=1.65
const OIL_ADD:=4.
const OIL_CAP:=65.
const OIL_POINT:=Vector3(25.55,1.04,-8.17)
const HANDLES:=[Vector3(GATE_X-.76,1.24,-6.65),Vector3(GATE_X+.76,1.24,-6.65)]
var leaf:AnimatableBody3D
var weight:Node3D
var ropes:Array[Node3D]=[]
var handles:Array[Node3D]=[]
var oil_tin:Node3D
var oil_grip:Node3D
var elapsed:=0.
var moving:=false
var opened:=false
var oil_taken:=false
var level:Node3D

static func extend_north_wall(kit, windows:Array)->void:
	# Masonry.wall accepts one vertical opening per X interval. Split the two
	# window bays at the jambs, then put the lintel strip back under each window.
	var openings:=[]
	for window in windows:
		var x:float=(window[0]+window[1])*.5
		if x in [WEST,EAST]:
			openings.append([window[0],x-HALF_DOOR,window[2],window[3]])
			openings.append([x-HALF_DOOR,x+HALF_DOOR,0.,window[3]])
			openings.append([x+HALF_DOOR,window[1],window[2],window[3]])
			kit.rect("MaintenanceLintelStone",x,(HEAD+window[2])*.5,WALL_Z,HALF_DOOR*2.,window[2]-HEAD,.2)
		else:openings.append(window)
	kit.wall(true,WALL_Z,0.,36.,5.2,openings)

func build()->void:
	group("A1_MaintenanceLoop")
	# Three floor rectangles with flush, overlapping seams; wall ends overlap.
	for x in [WEST,EAST]:
		slab(x,-4.38,2.12,4.42)
		box("EntrySoffit",Vector3(x,2.68,-4.38),Vector3(2.22,.22,4.42),"brick")
		for side in [-1.,1.]:
			var outer:bool=(x==WEST and side<0.) or (x==EAST and side>0.)
			var end:float=-8.54 if outer else -6.28
			box("EntryWall",Vector3(x+side*1.1,1.36,(end+WALL_Z)*.5),Vector3(.2,2.72,WALL_Z-end),"brick")
			box("PortalJamb",Vector3(x+side*.87,HEAD*.5,-2.3),Vector3(.14,HEAD,.29),"iron")
		box("PortalHead",Vector3(x,HEAD+.09,-2.3),Vector3(1.88,.18,.29),"iron")
		# A raised, light iron strap reads across the dark lintel even in grayscale.
		box("MaintenanceLintelStrap",Vector3(x,HEAD+.09,-2.066),Vector3(1.70,.074,.035),"joint",false)
		for dx in [-.77,-.64,.64,.77]:
			box("MaintenanceStrapRivet",Vector3(x+dx,HEAD+.09,-2.042),Vector3(.041,.041,.021),"iron",false)
		var parked_leaf:=box("DoorParkedOpen",Vector3(x-.97,1.11,-3.04),Vector3(.10,2.22,1.36),"iron") as MeshInstance3D
		var ochre:=mat("iron").duplicate() as StandardMaterial3D
		ochre.albedo_color=Color("805833");parked_leaf.material_override=ochre
		plaque("MAINTENANCE",Vector3(x,2.65,-2.065),1.22)
		lamp(Vector3(x,2.36,-3.65))
	slab(21.,RUN_Z,14.23,2.25)
	box("RunInnerWall",Vector3(21.,1.48,-6.29),Vector3(10.02,2.96,.2),"brick")
	box("RunOuterWall",Vector3(21.,1.48,-8.53),Vector3(14.42,2.96,.20),"brick")
	for span in [Vector2(13.79,GATE_X-.31),Vector2(GATE_X+.31,28.21)]:
		box("RunRoof",Vector3((span.x+span.y)*.5,3.13,RUN_Z),Vector3(span.y-span.x,.22,2.44),"brick")
	for x in [GATE_X-.28,GATE_X+.28]:
		box("LiftPocketCheek",Vector3(x,3.84,RUN_Z),Vector3(.15,1.77,2.44),"brick")
	box("LiftPocketCap",Vector3(GATE_X,4.87,RUN_Z),Vector3(.71,.22,2.44),"brick")
	for x in [17.3,25.75]:lamp(Vector3(x,2.48,-7.38))
	# Lift pocket above the lintel. The body and its collision travel together.
	box("LiftLintel",Vector3(GATE_X,2.68,RUN_Z),Vector3(.58,.52,2.00),"iron")
	for z in [-8.39,-6.42]:
		box("LiftGuide",Vector3(GATE_X,1.40,z),Vector3(.31,2.8,.16),"iron")
	leaf=AnimatableBody3D.new();leaf.name="CounterweightLeaf";leaf.collision_layer=3
	section.add_child(leaf);leaf.position=Vector3(GATE_X,1.17,RUN_Z)
	var shape:=BoxShape3D.new();shape.size=Vector3(.14,2.34,1.92)
	var collision:=CollisionShape3D.new();collision.shape=shape;leaf.add_child(collision)
	var panel:=box("RivetedLeaf",leaf.position,shape.size,"door_green",false)
	panel.reparent(leaf)
	for y in [-.82,0.,.82]:
		var strap:=box("LeafStrap",leaf.position+Vector3(0.,y,0.),Vector3(.17,.065,1.88),"iron",false)
		strap.reparent(leaf)
	# Exposed upper cross-shaft and a caged weight down the inner jamb.
	beam(Vector3(GATE_X-.28,2.83,-7.83),Vector3(GATE_X+.28,2.83,-7.83),.15,"iron")
	beam(Vector3(GATE_X-.28,2.83,-6.50),Vector3(GATE_X+.28,2.83,-6.50),.15,"iron")
	beam(Vector3(GATE_X,2.83,-7.83),Vector3(GATE_X,2.83,-6.5),.023,"brass")
	weight=box("Counterweight",Vector3(GATE_X,2.45,-6.5),Vector3(.19,.25,.19),"brass",false)
	for x in [GATE_X-.19,GATE_X+.19]:
		for z in [-6.65,-6.41]:beam(Vector3(x,.08,z),Vector3(x,2.73,z),.024,"iron")
	for z in [-7.83,-6.5]:ropes.append(beam(Vector3(GATE_X,2.83,z),Vector3(GATE_X,2.31,z),.019,"iron"))
	for p in HANDLES:
		var pivot:=Node3D.new();section.add_child(pivot);pivot.position=p;handles.append(pivot)
		var grip:=box("PullHandle",p+Vector3(0.,.12,0.),Vector3(.09,.30,.09),"brass",false)
		grip.reparent(pivot)
		beam(p,Vector3(GATE_X,p.y,p.z),.024,"iron")
	beam(Vector3(GATE_X,1.24,-6.65),Vector3(GATE_X,2.83,-6.50),.027,"iron")
	box("OilWorkSurface",OIL_POINT+Vector3(0.,-.22,0.),Vector3(.76,.12,.52),"iron")
	oil_tin=box("MaintenanceOil",OIL_POINT,Vector3(.24,.33,.19),"brass",false)
	oil_grip=beam(OIL_POINT+Vector3(-.09,.20,0.),OIL_POINT+Vector3(.09,.20,0.),.021,"iron")
	set_physics_process(false)

func lamp(p:Vector3)->void:
	box("ShadedLamp",p,Vector3(.26,.13,.22),"iron",false)
	var glow:=OmniLight3D.new();section.add_child(glow);glow.position=p+Vector3.DOWN*.13
	glow.light_color=Color("ffe3af");glow.light_energy=.7;glow.omni_range=3.4

func target(eye:Camera3D,walker:CharacterBody3D)->String:
	if walker.position.z>-5.5 or walker.position.x<17. or walker.position.x>26.:return ""
	if not moving and not opened:
		for p in HANDLES:
			if visible_target(eye,walker,p):return "maintenance_lift"
	if not oil_taken and visible_target(eye,walker,OIL_POINT):return "maintenance_oil"
	return ""

func visible_target(eye:Camera3D,walker:CharacterBody3D,p:Vector3)->bool:
	var delta:=p-eye.global_position
	if delta.length()>1.65 or (-eye.global_basis.z).dot(delta.normalized())<.95:return false
	var ray:=PhysicsRayQueryParameters3D.create(eye.global_position,p,5,[walker.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func operate(id:String,lv)->void:
	if id=="maintenance_lift" and not moving and not opened:
		level=lv;moving=true;set_physics_process(true)
		lv.sound_at("lever",Vector3(GATE_X,1.24,RUN_Z),-24.,8.)
	elif id=="maintenance_oil" and not oil_taken:
		if lv.oil>=OIL_CAP-.01:
			lv.say("油灯已满。");return
		lv.oil=minf(OIL_CAP,lv.oil+OIL_ADD);oil_taken=true;oil_tin.hide();oil_grip.hide()
		lv.sound_at("relay_tap",OIL_POINT,-22.,6.)
		lv.say("已用检修储油补充灯油。")

func _physics_process(dt:float)->void:
	var previous:=elapsed;elapsed=minf(DURATION,elapsed+dt)
	if previous<.19 and elapsed>=.19:level.sound_at("chain",Vector3(GATE_X,2.83,RUN_Z),-24.,9.)
	var progress:=smoothstep(.19,DURATION,elapsed)
	leaf.position.y=1.17+LIFT*progress
	weight.position.y=2.45-2.07*progress
	for i in handles.size():handles[i].rotation.z=(1. if i==0 else -1.)*.68*smoothstep(0.,.19,elapsed)
	var ends:=[minf(2.82,leaf.position.y+1.10),weight.position.y+.125]
	for i in ropes.size():
		ropes[i].position.y=(2.83+ends[i])*.5
		ropes[i].scale.y=(2.83-ends[i])/.52
	if elapsed>=DURATION:
		opened=true;moving=false;set_physics_process(false)
		level.sound_at("relay_answer",Vector3(GATE_X,2.56,RUN_Z),-23.,8.)
