extends "Masonry.gd"
const Relay=preload("ServiceSignal.gd")
const CX:=61.0
const CZ:=10.1
const BLIND_ANGLES := [90,210,330]
var gate:Node3D
var leaf:Node3D
var leave_pivot:Node3D
const AIRLOCK_DEPTH := -2.65
const RETURN_ELBOW := 78.52
const WEST_STAIR_X := 49.15
const RETURN_SOUTH := 26.65
const RETURN_WEST := 43.80
const RETURN_GATE_Z := 11.52
const RETURN_PATH := [Vector2(RETURN_ELBOW,12.45),Vector2(RETURN_ELBOW,RETURN_SOUTH),Vector2(RETURN_WEST,RETURN_SOUTH),Vector2(RETURN_WEST,10.1)]
var return_exit_gate:Node3D
var gate_spots:Array[Marker3D]=[]
var north_spot:Marker3D
var bridge:Node3D
var evidence_gate:Node3D
var airlock:Node3D
var test_board:Node3D
var panel:Node3D
var core:Node3D
var supplies:Node3D
var oil_tin:Node3D
var clock_cache:Node3D
var clock_shutter:Node3D
var relay_lamps:Array[MeshInstance3D]=[]
var stair_path:=PackedVector3Array()
var solo_hatch:Node3D
var vault_can:Node3D
var niche_oil:Node3D
var pilgrim_run:Marker3D
var run_lamp:OmniLight3D
const NICHE_DOOR_X:=9.2
const NICHE_Z:=5.1

func build()->void:
	arcade();arcade_details();archive();archive_details();side_niche();side_niche_details();shaft();shaft_details();hardware();return_gallery()
func marker(id:String,where:Vector3)->Marker3D:
	var spot:=Marker3D.new();spot.name=id;section.add_child(spot);spot.position=where;return spot
func arcade()->void:
	group("A1_ImmersionArcade");slab(17.15,0,37.7,4.4);lid(18,0,36,4.4,5.2)
	var lights:=[]
	for i in 6:lights.append([i*6+1,i*6+5,3.6,4.85])
	# Three openings share this wall: the archive side door at 30–32, the A2 niche
	# door at 8.5–9.5 and the A2 pilgrim-run mouth at 17.1–18.3.
	wall(true,-2.2,0,36,5.2,lights);wall(true,2.2,0,36,5.2,[[8.5,9.5,0,2.35],[30.1,31.9,0,2.6]],true)
	for i in 6:
		var x:=3.+6*i;arch(Vector3(x,1.72,-1.97),1.67,.19,.27,false,"trim")
		for dx in [-1.77,1.77]:rect("NicheJamb",x+dx,.86,-1.98,.2,1.72,.26,"trim")
		for dx in [-1,0,1]:rect("ClerestoryMullion",x+dx,4.22,-2.2,.055,1.25,.1,"joint",false)
	for i in 7:
		var x:=i*6.;var end_wall:=i==0 or i==6
		for layer in [[1.79,.29,.60,"chalk"],[1.76,.08,.66,"trim"]]:
			var spring:=Vector3(x,3.1,0)
			if end_wall:arch(spring,layer[0],layer[1],layer[2],true,layer[3])
			else:
				arch(spring,layer[0],layer[1],layer[2],true,layer[3],2.13,PI)
				cut.append(arch(spring,layer[0],layer[1],layer[2],true,layer[3],0.,2.13))
		if end_wall:arch(Vector3(x,3.1,0),1.81,2.1,.45,true,"chalk",0.,PI,true)
		for z in [-1.98,1.98]:
			var parts:=[rect("Pier",x,1.55,z,.6,3.1,.38),rect("Plinth",x,.13,z,.71,.26,.46,"joint"),rect("Capital",x,3.03,z,.72,.16,.52,"trim")]
			if z>0 and not end_wall:cut.append_array(parts)
	airlock=rect("RearSeal",.12,6.,0,.22,4.8,4.2,"iron")
	for z in [-1.5,1.5]:rect("ExitJamb",-.04,1.43,z,.44,2.86,.35,"iron")
	rect("ExitLintel",-.04,2.88,0,.44,.28,3.35,"iron")
	rect("ExitLantern",.24,2.55,0,.12,.17,.47,"brass",false)
	# 应急滑门：气密前室的第二撤离口（独自撤离 / 等队友双出口）。
	solo_hatch=rect("SoloEscapeHatch",-2.6,1.40,1.345,1.02,1.92,.07,"door_green")
	rect("SoloHatchFrame",-2.6,1.42,1.385,1.26,2.16,.04,"iron",false)
	rect("SoloHatchBar",-2.6,1.34,1.315,.86,.09,.05,"brass",false)
	plaque("EMERGENCY SLIDE",Vector3(-2.6,2.66,1.33),1.16)
	slab(-1.99,0,4.30,3.50)
	for z in [-1.55,1.55]:
		rect("AirlockReturnWall",-1.98,1.41,z,4.30,3.03,.30,"brick")
		rect("AirlockSkirt",-1.96,.07,z-signf(z)*.13,4.28,.19,.12,"iron",false)
	lid(-1.98,0,4.34,3.48,2.82)
	rect("AirlockFarWall",-4.06,1.38,0,.30,3.08,3.50,"brick")
	for side in [-1.,1.]:
		var z:float=.54*side
		rect("AnchorHallDoorLeaf",-3.88,1.21,z,.13,2.43,1.06,"door_green")
		for y in [.49,1.74]:
			rect("AnchorHallRaisedPanel",-3.793,y,z,.046,.72,.78,"iron",false)
			for dz in [-.40,.40]:rect("AnchorHallPanelBead",-3.757,y,z+dz,.036,.76,.038,"brass",false)
		beam(Vector3(-3.73,1.07,.16*side),Vector3(-3.73,1.32,.16*side),.026,"brass")
		rect("AnchorHallDoorJamb",-3.78,1.23,1.14*side,.26,2.48,.16,"iron",false)
	rect("AnchorHallDoorCrown",-3.78,2.49,0,.28,.17,2.45,"iron",false)
	plaque("ANCHOR HALL",Vector3(-3.60,2.52,0),1.01,PI*.5)
	for z in [-1.18,1.18]:rect("AirlockLampBody",-3.64,2.19,z,.24,.25,.15,"brass",false)
	gate=Node3D.new();section.add_child(gate);section=gate
	for i in 21:
		var z:float=(i-10)*.174;var h:=3.1+sqrt(1.76*1.76-z*z);rect("Picket",36,h*.5,z,.085,h,.036,"iron",false)
	for y in [.18,1.25,2.68,3.12]:rect("Strap",36,y,0,.10,.075,2.8,"iron",false)
	# Riveted near-side iron grips let Hale plant his fists without reaching through the bars.
	for z in [-1.22,-.50,.50,1.22]:
		for y in [1.065,1.208]:rect("GateGripFastener",35.94,y,z,.09,.048,.075,"iron",false)
		beam(Vector3(35.925,1.065,z),Vector3(35.925,1.208,z),.018,"iron")
	invisible_block(Vector3(36,1.6,0),Vector3(.15,3.2,2.8));section=root_group
	gate_spots.append(marker("HaleGateNear",Vector3(35.43,0.,-.86)))
	gate_spots.append(marker("HaleGateFar",Vector3(35.43,0.,.86)))
	for x in range(1,36,2):rect("PavingJoint",x,.002,0,.034,.008,4.16,"joint",false)
	for z in [-.15,.15]:rect("GuideInlay",18,.006,z,36,.012,.032,"joint",false)
	# 壁龛长椅与练习矮箱：给走跑/跳跃一处有碰撞的练习场。
	for x in [9.,21.]:
		rect("NicheBenchSeat",x,.42,-1.72,1.26,.09,.44,"trim")
		rect("NicheBenchBack",x,.78,-1.92,1.26,.62,.08,"trim")
		for dx in [-.55,.55]:rect("NicheBenchLeg",x+dx,.19,-1.72,.1,.38,.38,"iron")
	rect("PracticeCrate",15.,.24,1.55,.62,.48,.62,"joint")
func invisible_block(p:Vector3,s:Vector3)->void:
	var n:=rect("Barrier",p.x,p.y,p.z,s.x,s.y,s.z,"iron");n.hide()
func archive()->void:
	group("B1_B5_Archive");slab(31,4.85,6,5.3);slab(23.85,5.55,8.3,6.7);rect("RecessFloor",23.9,-.72,12,7.7,.24,6.2,"trim");slab(34.75,14.1,14,2);slab(38.5,10.1,6.5,5.8)
	wall(false,27.9,2.3,8.9,3.8,[[4.1,5.7,0,2.4]]);wall(false,34.1,2.3,7.5,3.8);wall(true,7.5,28,34,3.8,[],true);wall(false,19.7,2.3,8.9,3.8,[[3.2,4.4,1,3.2],[6,7.2,0,2.35]]);wall(true,2.2,19.7,28,3.8,[],true)
	wall(true,8.95,19.8,27.9,4,[[20.15,21.75,0,2.4],[22.25,27.05,.38,2.75]])
	rect("ObservationGlass",24.65,1.565,8.95,4.8,2.37,.055,"glass");for x in [22.25,23.85,25.45,27.05]:rect("Mullion",x,1.565,8.95,.045,2.37,.09,"iron",false)
	wall(false,20,9.05,15.05,4);wall(true,15.15,20,27.75,4,[],true);wall(false,27.8,9.05,15.05,4,[[13.3,14.9,0,2.4]])
	# The recess is below the archive slab. Carry the room enclosure down past it.
	for x in [20.,27.8]:rect("RecessFoundation",x,-.36,12.06,.23,.77,6.28,"brick")
	for z in [8.98,15.15]:rect("RecessFoundation",23.9,-.36,z,7.99,.77,.23,"brick")
	# Fillets cover the lid joints from the occupied side, away from the windows.
	for z in [2.31,8.84]:rect("ArchiveCeilingFillet",23.85,3.70,z,8.16,.15,.18,"brick",false)
	for x in [19.81,27.78]:rect("ArchiveCeilingFillet",x,3.70,5.57,.18,.15,6.64,"brick",false)
	for z in [9.07,15.03]:rect("TrialCeilingFillet",23.90,3.92,z,7.85,.15,.18,"brick",false)
	for x in [20.11,27.69]:rect("TrialCeilingFillet",x,3.92,12.05,.18,.15,6.10,"brick",false)
	# A single walkable crossing: the pit ramp lands on the entry bank only.
	slab(23.9,9.68,7.7,1.48);slab(23.9,14.39,7.7,1.54)
	test_board=rect("AmberTestPlate",23.85,.045,12.02,1.8,.09,3.20,"test_amber")
	for ramp_x in [21.5,26.2]:
		var ramp:=rect("EntryRecoveryRamp",ramp_x,-.35,11.22,2.2,.10,1.80,"brick");ramp.rotation.x=atan2(.60,1.65)
	for x in [21.5,26.2]:
		rect("RampApron",x,-.645,12.09,2.22,.23,.44,"joint",false)
	for x in [21.49,26.24]:
		var width:=2.92 if x<24 else 3.0
		rect("IronGuard",x,.54,13.66,width,1.10,.12,"iron");rect("BrassCap",x,1.10,13.66,width,.06,.15,"brass",false)
	for i in 38:rect("LipStripe",20.15+i*.2,.006,10.38,.19,.012,.10,"brass" if i%2==0 else "iron",false)
	evidence_gate=rect("TrialInterlock",27.8,1.25,14.1,.19,2.5,1.6,"iron")
	wall(true,13,27.8,41.8,2.4,[[28.6,30.1,0,2.3],[38.1,39.7,0,2.4]],false,"dark");service_loft();wall(false,41.85,13,15.2,2.4,[],false,"dark");lid(34.75,14.1,14.23,2.33,2.38)
	for edge in [[27.81,29.0,15.06],[30.8,32.9,15.06],[35.7,38.15,15.06],[39.95,41.84,15.06],[27.81,28.58,13.13],[30.12,38.07,13.13],[39.73,41.84,13.13]]:
		for h in [.075,2.34]:rect("B4SeamCover",(edge[0]+edge[1])*.5,h,edge[2],edge[1]-edge[0],.16,.095,"dark",false)
	wall(true,7.2,35.25,41.75,3.8,[[36.68,37.72,.83,2.35],[37.9,39.5,0,2.4]]);wall(false,35.15,7.2,13,3.8,[[11.3,12.9,0,2.6]]);slab(31.47,12.05,7.4,1.95);wall(true,11.02,27.8,35.15,2.6);lid(31.47,12.05,7.4,1.95,2.6);wall(false,41.85,7.2,13,3.8,[[8.9,11.3,0,2.8]])
	for v in [[31,4.85,6,5],[23.85,5.6,8,6.5],[23.9,12,7.5,6],[38.5,10.1,6.5,5.5]]:lid(v[0],v[1],v[2]+.32,v[3]+.34,3.98 if v[0]==23.9 else 3.73)
	for z in [4.0,6.9]:shelf(23.65,z)
	# Rubble in the blind opening beyond B1, visible across a broken barricade.
	for row in 3:
		for j in 8:
			var n:=rect("Collapse",28.46+j*.72,.30+row*.51,6.85+row*.15,.80,.64,.74,"joint");n.rotation.y=sin(row*9+j)*.32
	for tilt in [-.25,.23]:
		var brace:=rect("SplinteredBrace",31,1.32,6.43,5.3,.23,.18,"book");brace.rotation.z=tilt
	label_at("←  ARCHIVE",Vector3(31,2.3,7.35),PI)
	panel=rect("BrassIsolator",36.3,1.08,7.45,.77,.95,.23,"brass");beam(Vector3(36.3,.96,7.62),Vector3(36.3,1.49,7.94),.065,"iron")
	# Pipe follows the panel wall, corridor return and gate arch. All pipework is non-colliding.
	wall(false,36.0,2.18,7.2,3.8)
	var route:=[Vector3(36.3,1.48,7.42),Vector3(36.3,3.06,7.42),Vector3(36.18,3.06,7.42),Vector3(36.18,3.06,2.05),Vector3(36.18,4.98,2.05),Vector3(36.18,4.98,0)]
	for i in route.size()-1:beam(route[i],route[i+1],.10,"brass")
	for z in [2.68,4.48,6.28]:rect("PipeClamp",36.1,3.06,z,.27,.28,.09,"iron",false)
	supplies=Node3D.new();section.add_child(supplies);section=supplies;rect("SupplyChest",34.14,.26,14.67,.98,.52,.55,"brass");rect("Latch",34.14,.32,14.36,.15,.21,.06,"iron",false);inspection_oil();section=root_group;plaque("B5  /  MASTER RELEASE",Vector3(36.31,3.43,7.34),1.90)
	for x in [37.86,39.54]:rect("ShortcutReceiverStile",x,1.24,7.33,.14,2.48,.14,"door_green",false)
	rect("ShortcutReceiverHead",38.7,2.48,7.33,1.81,.16,.14,"door_green",false)
	slab(38.7,3.1,4.9,8.3);wall(false,41.25,-2,7.2,3.6);wall(true,-2.05,36,41.25,3.6,[],true);rect("GateSightGlass",37.2,1.59,7.2,1.04,1.52,.06,"glass");slab(44,10.1,4.6,2.6);wall(true,8.7,41.85,46.1,3.2);wall(true,11.5,41.85,46.1,3.2,[[42.63,44.97,0,2.65]],true)
## A2 sits on the arcade's north side and is the level's quiet shortcut. Its
## east door feeds a low earth-cut run that opens into B2 through the old
## window bay, so a player who keeps still can skip the B1 vestibule entirely.
## Payoff for stillness: the niche lamp oil only lifts from a stopped stance.
func side_niche()->void:
	group("A2_QuietNiche")
	slab(12.075,4.775,7.35,5.15)
	lid(12.075,4.775,7.55,5.35,3.0)
	wall(false,8.4,2.2,7.35,2.9)                     # west
	wall(true,7.35,8.4,15.75,2.9)                    # north
	wall(false,15.75,2.2,7.35,2.9,[[6.,7.2,0,2.35]]) # east, door to the run
	for x in [8.42,9.58]:rect("NicheDoorJamb",x,1.18,2.2,.14,2.36,.30,"trim")
	rect("NicheDoorHead",9.05,2.46,2.2,1.68,.18,.34,"trim")
	rect("RunDoorHead",15.75,2.46,6.6,.3,.18,1.4,"trim")
	# The earth-cut run: 4 m of low corridor between the niche and B2.
	slab(17.75,6.6,4.0,1.2)
	wall(true,5.98,15.75,19.9,2.55)
	wall(true,7.22,15.75,19.9,2.55)
	lid(17.75,6.6,4.2,1.5,2.55)
	for x in [16.6,18.2]:beam(Vector3(x,.05,6.02),Vector3(x,2.5,6.02),.085,"joint")
	for x in [16.6,18.2]:beam(Vector3(x,.05,7.18),Vector3(x,2.5,7.18),.085,"joint")
	# One crate of lamp oil in the niche, plus the room's own tally board.
	# Reading the room from the door: crates on the east wall, oil on the near one.
	for i in 3:
		rect("NicheCrateLower",16.0,.24+i*.46,3.85+i*.03,.92,.44,.64,"book")
	rect("NicheSack",15.55,.19,5.35,.52,.36,.46,"joint")
	var bench_lamp:=OmniLight3D.new();add_child(bench_lamp)
	bench_lamp.position=Vector3(15.2,2.5,3.2);bench_lamp.light_color=Color("ffcf9a")
	bench_lamp.omni_range=4.2;bench_lamp.light_energy=.55
	niche_oil=Node3D.new();section.add_child(niche_oil);section=niche_oil
	rect("NicheCrate",13.9,.22,5.9,.72,.44,.52,"book")
	rect("NicheOilCan",13.9,.62,5.9,.30,.36,.22,"brass",false)
	section=root_group
	pilgrim_run=marker("PilgrimRunMouth",Vector3(18.6,.05,6.6))
	plaque("A2  /  QUIET  NICHE",Vector3(11.0,2.4,2.36),1.42)
	label_at("02   /   QUIET NICHE",Vector3(18.2,2.2,6.02),PI)

func side_niche_details()->void:
	for x in [10.6,11.4]:rect("NicheBenchLeg",x,.21,4.5,.12,.42,.5,"iron",false)
	rect("NicheBench",11.0,.44,4.5,1.5,.09,.56,"book",false)
	run_lamp=OmniLight3D.new();add_child(run_lamp)
	run_lamp.position=Vector3(12.4,2.55,5.4);run_lamp.light_color=Color("ffd7a0")
	run_lamp.omni_range=6.2;run_lamp.light_energy=.72;run_lamp.shadow_enabled=true
	run_lamp.shadow_bias=.05
	var run_glow:=OmniLight3D.new();add_child(run_glow)
	run_glow.position=Vector3(17.7,1.9,6.6);run_glow.light_color=Color("c8d8e2")
	run_glow.omni_range=3.4;run_glow.light_energy=.42
	for x in [10.4,13.2]:rect("NicheLampBracket",x,2.62,5.4,.16,.16,.04,"brass",false)
	for i in 9:rect("NicheTally",9.0+i*.16,1.32,7.1,.032,.28,.014,"joint",false)
	# Tread plates in the run so its footsteps are audibly wood, not stone.
	for x in [16.2,17.0,17.8,18.6]:rect("RunTreadPlate",x,.005,6.6,.72,.012,1.1,"book",false)

func inspection_oil()->void:
	var parent:=section
	oil_tin=Node3D.new();parent.add_child(oil_tin);section=oil_tin
	rect("OilTin",33.95,.74,14.65,.34,.44,.22,"brass",false)
	for x in [33.86,34.04]:beam(Vector3(x,.96,14.65),Vector3(x,1.05,14.65),.016,"iron")
	beam(Vector3(33.86,1.05,14.65),Vector3(34.04,1.05,14.65),.016,"iron")
	section=parent
func inspection_clock()->void:
	var parent:=section
	clock_cache=Node3D.new();parent.add_child(clock_cache);section=clock_cache
	clock_cache.position=Relay.HATCH
	rect("MetronomeFoot",0,-.16,0,.22,.04,.14,"book",false)
	var case_mesh:=CylinderMesh.new();case_mesh.radial_segments=4;case_mesh.rings=0;case_mesh.bottom_radius=.172;case_mesh.top_radius=.054;case_mesh.height=.34
	var case_body:=MeshInstance3D.new();case_body.mesh=case_mesh;case_body.material_override=mat("book");section.add_child(case_body);case_body.position=Vector3(0,0,0);case_body.rotation.y=PI/4;case_body.scale=Vector3(.71,.85,.49)
	beam(Vector3(-.031,-.125,-.108),Vector3(.050,.124,-.04),.012,"brass")
	section=parent
## A second section through B4: two thresholds, a raised inspection bench and a
## sealed sightline back to the oil chest. Both exits remain downstream of B3.
func service_loft()->void:
	wall(true,15.2,27.8,41.8,2.4,[[29.,30.8,0,2.3],[32.9,35.7,.52,2.20],[38.15,39.95,0,2.3]],true,"dark")
	rect("InspectionGlass",34.3,1.36,15.2,2.8,1.68,.07,"glass")
	# Hooded practical picks out the tools without filling the darkroom.
	rect("BenchLampHood",34.2,1.88,14.98,.56,.09,.22,"iron",false)
	rect("BenchLampLens",34.2,1.82,14.98,.48,.035,.14,"amber",false)
	var bench_light:=SpotLight3D.new();section.add_child(bench_light)
	bench_light.position=Vector3(34.2,1.79,14.95);bench_light.rotation.x=deg_to_rad(-74.)
	bench_light.light_color=Color("ffd39b");bench_light.light_energy=2.4;bench_light.spot_range=2.2;bench_light.spot_angle=48.
	for x in [32.92,35.68]:rect("InspectionJamb",x,1.36,15.2,.075,1.72,.16,"brass",false)
	for y in [.52,2.20]:rect("InspectionFrame",34.3,y,15.2,2.85,.08,.16,"brass",false)
	slab(34.5,16.42,12.,2.52)
	wall(true,17.68,28.5,40.5,3.15,[],true,"brick")
	for x in [28.5,40.5]:wall(false,x,15.2,17.68,3.15,[],false,"brick")
	wall(true,15.2,28.5,40.5,3.15,[[28.5,40.5,0,2.4]],false,"brick")
	lid(34.5,16.43,12.2,2.64,3.15)
	# Ramp tops meet the deck at +0.60 m; landings at either end are level.
	for side in [-1.,1.]:
		var ramp:=rect("ServiceIncline",34.5+side*2.6,.238,16.44,sqrt(4.36),.12,2.44,"iron")
		ramp.rotation.z=-side*atan2(.6,2.)
	rect("InspectionDeck",34.5,.30,16.44,3.2,.60,2.44,"iron")
	for x in [29.9,39.05]:plaque("SIGNAL LOFT",Vector3(x,2.40,15.07),1.34,PI)
	plaque("LAMP OIL",Vector3(34.2,2.18,15.02),1.18,PI)
	for x in [31.,32.5,37.,38.]:
		beam(Vector3(x,1.38,17.46),Vector3(x,1.38,17.59),.085,"iron")
	for run in [Vector2(29.05,34.16),Vector2(34.84,40.05)]:
		beam(Vector3(run.x,1.38,17.48),Vector3(run.y,1.38,17.48),.052,"brass")
	for i in Relay.PORTS.size():
		var point:Vector3=Relay.PORTS[i]
		rect("FeltBaffle",point.x,1.63,17.59,1.10,1.66,.12,"felt_dark",false)
		# A flush tread patch marks where the felt baffle absorbs the metal footfall.
		rect("ListeningMat",point.x,.603,17.09,1.04,.012,1.08,"felt_dark",false)
		rect("RelayPlate",point.x,1.70,17.47,.48,.36,.13,"brass",false)
		rect("RelayKnocker",point.x,1.69,17.372,.16,.18,.070,"iron",false)
		plaque("W  /  LISTEN" if i==0 else "E  /  LISTEN",point+Vector3(0,.33,-.13),.93,PI)
		relay_lamps.append(relay_lamp(point+Vector3(.15,.082,-.075)))
	var h:Vector3=Relay.HATCH
	rect("ClockCabinet",h.x,h.y,17.57,.74,.55,.16,"book",false)
	for x in [h.x-.35,h.x+.35]:rect("ClockCabinetFrame",x,h.y,17.38,.07,.58,.28,"brass",false)
	for y in [h.y-.28,h.y+.28]:rect("ClockCabinetFrame",h.x,y,17.38,.74,.07,.28,"brass",false)
	inspection_clock()
	var parent:=section
	clock_shutter=Node3D.new();parent.add_child(clock_shutter);clock_shutter.position=Vector3(h.x,h.y,17.24);section=clock_shutter
	rect("ClockShutter",0,0,0,.61,.49,.06,"iron",false)
	for i in 4:rect("CabinetFlute",0,-.16+i*.10,-.035,.49,.018,.012,"brass",false)
	section=parent
	plaque("METRONOME",h+Vector3(0,.59,-.14),1.02,PI)
	relay_lamps.append(relay_lamp(h+Vector3(0,.38,-.24)))
	# 规则刻板①《同声律》：立在阁楼北墙，可读（世界内的规则怪谈文本）。
	rect("RuleSteleA",31.5,1.48,17.5,1.1,1.7,.14,"joint")
	rect("RuleSteleAInlay",31.5,1.55,17.415,.86,1.34,.02,"book",false)
func relay_lamp(at:Vector3)->MeshInstance3D:
	var lamp:=rect("RelayLamp",at.x,at.y,at.z,.075,.075,.038,"amber",false) as MeshInstance3D
	var finish:=lamp.material_override.duplicate() as StandardMaterial3D
	finish.emission_enabled=true;finish.emission=Color("ffd580");finish.emission_energy_multiplier=.18
	lamp.material_override=finish;return lamp
func shelf(x:float,z:float)->void:
	var bookcase:=preload("res://tools/building_construction/BuildingConstruction/Cabinets/RecipeBookshelf.gd").new()
	bookcase.recipe_parameters.merge({"width":3.2,"height":1.0,"depth":.48,"shelves":2,"bays":2},true)
	section.add_child(bookcase);bookcase.position=Vector3(x,0,z)
	for item in bookcase.find_children("*","MeshInstance3D",true,false):item.material_override=mat("book")
func polar(rad:float,a:float,y:float)->Vector3:return Vector3(CX+rad*cos(a),y,CZ+rad*sin(a))
func band(id:String,r0:float,r1:float,y0:float,y1:float,a:float,b:float,k:String,solid:=true)->Node3D:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(-1);var v:=PackedVector3Array()
	for ang in [a,b]:
		for y in [y0,y1]:
			for r in [r0,r1]:v.append(polar(r,ang,y))
	for face in [[0,4,6,2],[1,3,7,5],[0,1,5,4],[2,6,7,3],[0,2,3,1],[4,5,7,6]]:
		for j in [2,1,0,3,2,0]:st.add_vertex(v[face[j]])
	st.generate_normals();var n:=MeshInstance3D.new();n.name=id;n.mesh=st.commit();n.material_override=mat(k);section.add_child(n)
	if solid:
		var body:=StaticBody3D.new();body.collision_layer=5 if k=="glass" else 3;var col:=CollisionShape3D.new();var shape:=ConvexPolygonShape3D.new();shape.points=v;col.shape=shape;body.add_child(col);n.add_child(body)
		if id=="SouthServiceWalk":body.add_to_group("expedition_iron_tread")
	return n
func west_stair_entry()->Vector3:return Vector3(WEST_STAIR_X,0.,9.27)
func shaft()->void:
	group("C1_C4_SourceCaisson");platform(-1,2.5);platform(1,3.);slab(CX-14.45,CZ,1.2,2.65,-.018);bridge=rect("SingleGazeSpan",CX,-.11,CZ,18,.22,3.6,"amber");bridge.material_override=mat("amber").duplicate()
	north_spot=marker("HaleNorthWindow",polar(12.45,1.5*PI,4.8))
	var roof:=MeshInstance3D.new();var cap:=CylinderMesh.new();cap.top_radius=14.60;cap.bottom_radius=14.60;cap.height=.32;cap.radial_segments=56;roof.mesh=cap;roof.material_override=mat("chalk");section.add_child(roof);roof.position=Vector3(CX,10.10,CZ);cut.append(roof)
	var bottom:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=14;disc.bottom_radius=14;disc.height=.2;bottom.mesh=disc;bottom.material_override=mat("abyss");section.add_child(bottom);bottom.position=Vector3(CX,-10.1,CZ)
	for i in 56:
		var a:=TAU*i/56.;var b:=TAU*(i+1)/56.;var mid:=(a+b)*.5;var entrance:=absf(mid-PI)<.115;var reveal:=cos(mid-1.03)>.52
		var lower:=band("LowerCaisson",14,14.45,-10,0,a,b,"pit");if reveal:cut.append(lower)
		if i==1:
			band("ReturnThreshold",14,14.45,0,4.8,a,b,"chalk")
			band("ReturnLintel",14,14.45,7.48,10,a,b,"chalk")
		elif not entrance:
			var upper:=band("UpperCaisson",14,14.45,0,10,a,b,"chalk");if reveal:cut.append(upper)
		if entrance:band("PortalHead",14,14.45,2.8,10,a,b,"chalk")
		var corn:=band("Coping",13.85,14.54,9.68,10,a,b,"trim",false);if reveal:cut.append(corn)
		if i%4==1 and i!=1:
			var rib:=box("BrickPilaster",polar(13.87,mid,0),Vector3(.34,20,.48),"joint",false,-mid);if reveal:cut.append(rib)
		if sin(mid)>0:
			# The walk passes below the two clipped stone landings at each root;
			# the slight step keeps their top faces from fighting at the portal.
			band("SouthServiceWalk",12.70,13.95,-.184,-.024,a,b,"iron")
		var stair_gap:=absf(sin(mid))<.35
		if stair_gap:continue
		var floor_ring:=band("ObservationRing",11.55,13.95,4.54,4.8,a,b,"floor");if reveal and absf(mid-PI*.5)>.115:cut.append(floor_ring)
		for tier in [[4.8,5.8,"chalk"],[5.8,6.94,"glass"],[6.94,7.02,"trim"]]:
			var rail:=band("GalleryScreen",11.55,11.63,tier[0],tier[1],a,b,tier[2]);if reveal:cut.append(rail)
		var post:=box("GlazingBar",polar(11.6,a,6.38),Vector3(.07,1.16,.07),"joint",false);if reveal:cut.append(post)
	for deg in BLIND_ANGLES:
		var az:=deg_to_rad(deg);var foot:=polar(11.8,az,4.8)
		box("BlindPier",foot+Vector3.UP*1.75,Vector3(.85,3.5,1.6),"brick",true,-az)
		for h in [.10,1.14,2.28,3.42]:box("PierCourse",foot+Vector3.UP*h,Vector3(.90,.09,1.64),"joint",false,-az)
	for side in [-1,1]:
		var origin:=Vector3(WEST_STAIR_X if side==-1 else CX+12.35,0,CZ-2.0);beam(origin+Vector3.DOWN*.2,origin+Vector3.UP*5.6,.10,"iron")
		if side==-1:beam(origin+Vector3.DOWN*10,origin,.10,"iron")
		for i in range(-85 if side==-1 else 0,42):
			var a:=PI*.5+TAU*i/41.;var p:=origin+Vector3(1.02*cos(a),4.8*i/41.,1.02*sin(a))
			if i<41:
				box("HelicalTread",p-Vector3.UP*.09,Vector3(1.84,.18,.37),"trim",false,-a)
				for strip in 5:stair_wedge(origin,i,.13+strip*.356,.486+strip*.356)
			if side==-1 and i>=0:stair_path.append(p)
			if i>=0:
				var edge:=stair_edge(origin,i)
				if i%3==0 or i==41:beam(edge,edge+Vector3.UP*.95,.029,"iron")
				if i<41:beam(edge+Vector3.UP*.95,stair_edge(origin,i+1)+Vector3.UP*.95,.039,"iron")
	# Upper landing connects the last spiral tread to the gallery. Shortcut opens from the core side.
	var center:=Vector3(CX+13.54,6.1,CZ+2.35)
	for side in [-1.,1.]:rect("ReturnJamb",center.x,center.y,center.z+side*.98,.28,2.7,.16,"iron")
	rect("ReturnHead",center.x,7.47,center.z,.28,.17,2.11,"iron")
	leave_pivot=Node3D.new();leave_pivot.name="ReturnDoorHinge";section.add_child(leave_pivot);leave_pivot.position=center+Vector3(0,0,-.90)
	var door_section:=section;section=leave_pivot
	leaf=rect("EmeraldReturnLeaf",0,0,.90,.14,2.6,1.8,"door_green")
	for z in [.44,1.36]:rect("PressedDoorPanel",-.084,0,z,.035,2.24,.81,"door_green",false)
	rect("BrassPanicBar",-.16,-.15,.90,.09,.09,1.38,"brass",false)
	section=door_section
	core=rect("SourceCore",CX+10.8,1,CZ,.42,.68,.42,"amber");rect("CorePlinth",CX+10.8,.31,CZ,.85,.62,.85,"joint")
	label_at("01   /   SOURCE CAISSON",Vector3(46.1,2.9,CZ),-PI/2)

## The green door leads to the actual south service gallery. Its roof and slope
## stay outside the caisson shell; the far grille opens only from this side.
func stair_edge(origin:Vector3,i:int)->Vector3:
	var a:=PI*.5+TAU*i/41.
	return origin+Vector3(1.83*cos(a),4.8*i/41.,1.83*sin(a))

func return_gallery()->void:
	group("C5_SouthReturnGallery")
	var start:=Vector3(CX+13.43,4.8,CZ+2.35)
	var inner_elbow:=Vector3(RETURN_ELBOW,4.8,start.z)
	var outer_elbow:=Vector3(RETURN_ELBOW,4.8,RETURN_SOUTH)
	var lower_elbow:=Vector3(RETURN_WEST,0.,RETURN_SOUTH)
	var outlet:=Vector3(RETURN_WEST,0.,11.32)
	# Exterior corner pieces overlap at the seams. At each elbow, the inner
	# wall is cut back by half the clear width so the turn remains full size.
	var w:=1.17
	var ramp_start:=outer_elbow+Vector3.LEFT*w
	var ramp_end:=lower_elbow+Vector3.RIGHT*w
	# One roof plate over each elbow. The orthogonal legs meet it at a butt joint,
	# and the graded leg starts/ends at the flat elbow edges, not their centers.
	var runs:=[[start,inner_elbow-Vector3.RIGHT*w],[inner_elbow+Vector3.BACK*w,outer_elbow-Vector3.BACK*w],[ramp_start,ramp_end],[lower_elbow-Vector3.BACK*w,outlet]]
	for i in runs.size():
		gallery_plane("StoneTread",runs[i][0],runs[i][1],2.*w+.33,-.109,.215,"floor")
		gallery_plane("BarrelSoffit",runs[i][0],runs[i][1],2.*w+.38,2.772,.28,"brick")
	for elbow in [inner_elbow,outer_elbow,lower_elbow]:
		box("FlatElbowTread",elbow+Vector3.DOWN*.113,Vector3(2.*w+.08,.237,2.*w+.08),"floor")
		box("FlatElbowSoffit",elbow+Vector3.UP*2.764,Vector3(2.*w+.30,.28,2.*w+.30),"brick")
	gallery_wall(start-w*Vector3.BACK,inner_elbow+w*Vector3.RIGHT-w*Vector3.BACK)
	gallery_wall(start+w*Vector3.BACK,inner_elbow-w*Vector3.RIGHT+w*Vector3.BACK)
	gallery_wall(inner_elbow+w*Vector3.RIGHT-w*Vector3.BACK,outer_elbow+w*Vector3.RIGHT+w*Vector3.BACK)
	gallery_wall(inner_elbow-w*Vector3.RIGHT+w*Vector3.BACK,outer_elbow-w*Vector3.RIGHT-w*Vector3.BACK)
	var outer_pad:=w*Vector3.BACK
	gallery_wall(outer_elbow+w*Vector3.RIGHT+outer_pad,ramp_start+outer_pad)
	gallery_wall(ramp_start+outer_pad,ramp_end+outer_pad)
	gallery_wall(ramp_end+outer_pad,lower_elbow-w*Vector3.RIGHT+outer_pad)
	for ramp_tip in [ramp_start,ramp_end]:
		box("GradeJointSeal",ramp_tip+Vector3.UP*2.614,Vector3(.26,.22,2.67),"brick",false)
		for edge in [-w,w]:
			box("GradeJointPier",ramp_tip+Vector3(0,1.41,edge),Vector3(.36,3.15,.32),"brick")
	# 北墙开岔：阀室分支（规则刻板② + 备用油罐）。直走仍是主路径，绕行耗时换油。
	var vy:=1.09
	var vy0:=lerpf(0.,4.8,(51.6-44.97)/(77.35-44.97))
	var vy1:=lerpf(0.,4.8,(53.0-44.97)/(77.35-44.97))
	gallery_wall(ramp_start-w*Vector3.BACK,Vector3(51.6,vy0,25.48))
	gallery_wall(Vector3(53.0,vy1,25.48),ramp_end-w*Vector3.BACK)
	beam(Vector3(51.6,vy0+2.5,25.48),Vector3(53.0,vy1+2.5,25.48),.10,"iron")
	box("ValveJamb",Vector3(51.6,vy0+1.2,25.48),Vector3(.2,2.4,.34),"trim")
	box("ValveJamb",Vector3(53.0,vy1+1.2,25.48),Vector3(.2,2.4,.34),"trim")
	rect("ValveFloor",52.3,vy-.12,23.76,3.7,.24,3.3,"floor")
	rect("ValveWallW",50.5,vy+1.3,23.9,.2,2.6,3.5,"brick")
	rect("ValveWallE",54.1,vy+1.3,23.9,.2,2.6,3.5,"brick")
	rect("ValveWallS",52.3,vy+1.3,22.25,3.8,2.6,.2,"brick")
	rect("ValveWallN1",51.05,vy+1.16,25.48,1.1,2.6,.2,"brick")
	rect("ValveWallN2",53.55,vy+1.46,25.48,1.1,2.6,.2,"brick")
	rect("ValveLid",52.3,vy+2.7,23.9,3.9,.2,3.6,"chalk")
	# 规则刻板②《独灯律》与备用油罐：绕行的报酬。
	rect("RuleSteleB",52.3,vy+.95,22.38,1.15,1.7,.12,"joint")
	rect("RuleSteleBInlay",52.3,vy+1.0,22.455,.9,1.36,.02,"book",false)
	vault_can=rect("ValveOilCan",53.6,vy+.27,24.7,.32,.5,.26,"brass",false)
	rect("ValveOilCap",53.6,vy+.55,24.7,.14,.08,.14,"iron",false).reparent(vault_can)
	plaque("PRESSURE VAULT",Vector3(52.3,vy+2.2,22.36),1.5)
	marker("GalleryLampV",Vector3(52.3,vy+2.0,24.2))
	gallery_wall(lower_elbow-w*Vector3.RIGHT+w*Vector3.BACK,outlet-w*Vector3.RIGHT)
	gallery_wall(lower_elbow+w*Vector3.RIGHT-w*Vector3.BACK,outlet+w*Vector3.RIGHT)
	# Enamel arrows, copper supply pipe and regularly spaced wall sconces break up the long slope.
	plaque("SERVICE RETURN   ↱",inner_elbow+Vector3(w-.15,2.09,0),1.21,-PI*.5)
	plaque("SERVICE RETURN   ↱",outer_elbow+Vector3(0,2.12,w-.15),1.32,PI)
	plaque("ARCADE   ↱",lower_elbow+Vector3(-w+.15,2.08,0),1.09,PI*.5)
	for i in range(1,8):
		var point:=outer_elbow.lerp(lower_elbow,i/8.)
		for side in [-1.,1.]:
			box("Rib",point+Vector3(0,1.31,side*1.12),Vector3(.18,2.62,.19),"trim",false)
		box("Header",point+Vector3(0,2.60,0),Vector3(.20,.18,2.32),"trim",false)
	var pipe_offset:=Vector3(0,2.26,1.03)
	beam(outer_elbow+pipe_offset,ramp_start+pipe_offset,.046,"brass")
	beam(ramp_start+pipe_offset,ramp_end+pipe_offset,.046,"brass")
	beam(ramp_end+pipe_offset,lower_elbow+pipe_offset,.046,"brass")
	var lamp_index:=0
	for d in [Vector3(78.85,7.06,12.0),Vector3(79.35,6.98,20.03),Vector3(78.45,7.05,27.44),Vector3(69.34,5.96,27.46),Vector3(60.71,4.79,27.46),Vector3(52.28,3.58,27.46),Vector3(43.3,2.29,27.46),Vector3(42.97,2.26,18.71),Vector3(43.15,2.30,12.31)]:
		box("ServiceSconce",d,Vector3(.17,.20,.19),"brass",false)
		marker("GalleryLamp%d"%lamp_index,d);lamp_index+=1
	return_exit_gate=Node3D.new();section.add_child(return_exit_gate)
	return_exit_gate.position=Vector3(RETURN_WEST,0,RETURN_GATE_Z);section=return_exit_gate
	for i in 13:rect("ServiceGrillePicket",i*.17-1.02,1.33,0,.045,2.66,.07,"iron",false)
	for y in [.15,1.1,2.54]:rect("ServiceGrilleRail",0,y,0,2.32,.085,.11,"iron",false)
	invisible_block(Vector3(0,1.33,0),Vector3(2.34,2.66,.14));section=root_group

func gallery_plane(id:String,a:Vector3,b:Vector3,width:float,lift:float,depth:float,k:String)->void:
	var slope:=b-a
	var n:=box(id,(a+b)*.5+Vector3.UP*lift,Vector3(slope.length()+.08,depth,width),k)
	var across:=slope.cross(Vector3.UP).normalized()
	n.basis=Basis(slope.normalized(),across.cross(slope).normalized(),across).scaled_local(n.scale)

func gallery_wall(a:Vector3,b:Vector3)->void:
	var axis:=Vector3(b.x-a.x,0.,b.z-a.z).normalized()
	var across:=axis.cross(Vector3.UP)
	# Grade changes need vertical miter faces. Rotating a whole cuboid tilts
	# those faces and opens a triangular slit against the adjoining flat wall.
	var vertices:=PackedVector3Array()
	for endpoint in [a-axis*.095,b+axis*.095]:
		for dy in [-.19,2.98]:
			for dz in [-.12,.12]:vertices.append(endpoint+Vector3.UP*dy+across*dz)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);surface.set_smooth_group(-1)
	for face in [[0,4,6,2],[1,3,7,5],[0,1,5,4],[2,6,7,3],[0,2,3,1],[4,5,7,6]]:
		for j in [0,1,2,0,2,3]:surface.add_vertex(vertices[face[j]])
	surface.generate_normals()
	var n:=MeshInstance3D.new();n.name="GalleryMasonry";n.mesh=surface.commit();n.material_override=mat("brick");section.add_child(n)
	var body:=StaticBody3D.new();body.collision_layer=3;n.add_child(body)
	var shape:=ConvexPolygonShape3D.new();shape.points=vertices
	var col:=CollisionShape3D.new();col.shape=shape;body.add_child(col)
	if absf(b.y-a.y)>.001:beam(a+Vector3.UP*.08,b+Vector3.UP*.08,.055,"iron")
	# Cornice bands cap the roof/wall seam for both flat and graded legs.
	var d:=b-a
	var finish:=box("SoffitSeamBead",(a+b)*.5+Vector3.UP*2.63,Vector3(d.length()+.18,.16,.31),"brick",false)
	finish.basis=Basis(d.normalized(),across.cross(d).normalized(),across).scaled_local(finish.scale)

func arcade_details()->void:
	# In a section drawing the far spring stays, while the cut side keeps a low plinth.
	for x in [0.,36.]:
		for z in [-1.96,1.96]:rect("PortalReturn",x,2.5,z,.38,5,.35)
		rect("LintelCornice",x,5.06,0,.48,.3,4.42,"trim")
	for t in [[0,30.1],[31.9,36.]]:
		var n:=rect("CutSill",(t[0]+t[1])*.5,.24,2.2,t[1]-t[0],.48,.2,"chalk",false);plates.append(n);n.hide()
	for end in [0.,36.]:
		for j in 3:
			var stair:=rect("SectionStepping",end,.24*(3-j),2.44+j*.32,.48,.48*(3-j),.33,"chalk",false);plates.append(stair);stair.hide()
	for x in [29.98,32.02]:rect("SidePortal",x,1.38,2.18,.22,2.76,.34,"trim",false)
	rect("PortalHead",31,2.74,2.18,2.27,.28,.34,"trim",false)
func archive_details()->void:
	# The A/B party wall belongs to A. Only duplicate its sliced silhouette in a B plate.
	for part in [[31.,7.5,6.,.36,"joint"],[34.82,15.2,14.1,.48,"dark"]]:
		var sill:=rect("SectionSill",part[0],part[3]*.5,part[1],part[2],part[3],.22,part[4],false);plates.append(sill);sill.hide()
	for interval in [[28.,30.1],[31.9,34.1]]:
		var edge:=rect("SectionReturn",(interval[0]+interval[1])*.5,.6,2.2,interval[1]-interval[0],1.2,.24,"chalk",false);plates.append(edge);edge.hide()
	for x in [30.02,31.98]:rect("ArchiveEntryJamb",x,1.27,2.34,.18,2.54,.24,"trim",false)
	rect("ArchiveEntryHead",31,2.6,2.34,2.13,.16,.24,"trim",false)
	for x in [31.5,32.45,35.95]:
		beam(Vector3(x,.12,14.94),Vector3(x,1.99,14.94),.09,"iron")
	for z in [3.5,5.4,7.4]:rect("LibraryDado",19.84,.49,z,.10,.09,1.8,"trim",false)
	for data in [[27.9,4.9,PI/2],[20.95,8.95,0.],[27.8,14.1,PI/2],[38.9,13.,0.],[38.7,7.2,0.]]:
		var center:=Vector3(data[0],0,data[1]);var yaw:float=data[2];var along:=Vector3(cos(yaw),0,sin(yaw))
		for sign_ in [-1,1]:box("DoorCasing",center+along*sign_*.88+Vector3.UP*1.24,Vector3(.16,2.48,.31),"trim",false,-yaw)
		box("DoorLintel",center+Vector3.UP*2.49,Vector3(1.94,.18,.31),"trim",false,-yaw)
	for x in [35.65,36.32,37.0]:
		beam(Vector3(x,1.92,7.39),Vector3(x,1.92,7.51),.19,"brass");beam(Vector3(x,1.92,7.515),Vector3(x,1.92,7.53),.15,"trim");beam(Vector3(x,1.92,7.55),Vector3(x+.08,2.01,7.55),.012,"iron")
	for x in [37.,36.35]:beam(Vector3(x,.12,14.94),Vector3(x,2.2,14.94),.09,"iron")
	for z in [3.2,4.4,6.,7.2]:rect("WindowCasing",19.74,2.1,z,.31,2.32,.095,"trim",false)
	for z in [3.8]:
		for y in [1.,2.,3.2]:rect("ArchiveSash",19.74,y,z,.22,.07,1.26,"trim",false)
	rect("FieldNote",23.6,1.018,4.,.29,.015,.2,"trim",false)
func shaft_details()->void:
	for i in 56:
		var a:=TAU*i/56.;var b:=TAU*(i+1)/56.;band("FoundationRing",13.9,14.52,-10.1,-9.18,a,b,"joint",false)
		if sin((a+b)*.5)<0:
			band("GalleryFascia",11.49,11.68,4.46,4.60,a,b,"trim",false)
			if absf(sin((a+b)*.5))>.35:band("SillCap",11.49,11.68,5.75,5.83,a,b,"trim",false)
	# Tangential landings, beyond the final riser, bridge the stair opening to the gallery.
	for side in [-1,1]:
		var stair_x:=WEST_STAIR_X if side==-1 else CX+12.35
		# Meet the true last nosing without a fictitious 42nd uphill wedge.
		slab(stair_x,CZ+1.94,2.,5.16,4.8)
		var landing_edge:float=stair_x-side*.98
		guard_segment(Vector3(landing_edge,4.8,10.02),Vector3(landing_edge,4.8,14.54))
		var ring_port:=polar(11.61,PI*.122 if side==1 else PI*.878,4.8)
		guard_segment(Vector3(landing_edge,4.8,14.54),ring_port)
		for tip in [-1.,1.]:
			var bridge_end:float=CX+side*9.04
			guard_segment(Vector3(bridge_end,0.,CZ+tip*1.84),Vector3(bridge_end,0.,CZ+tip*(2.46 if side==-1 else 2.96)),.90,.45)
	for z in [CZ-1.84,CZ+1.84]:
		beam(Vector3(CX-9,.45,z),Vector3(CX+9,.45,z),.030,"brass")
		for i in 10:beam(Vector3(CX-9+i*2,0,z),Vector3(CX-9+i*2,.45,z),.029,"iron")

func guard_segment(a:Vector3,b:Vector3,h:=1.04,rail:=.96)->void:
	for y in [.43,rail]:
		if y>.43 or rail>.46:beam(a+Vector3.UP*y,b+Vector3.UP*y,.033,"iron")
	var posts:=maxi(1,ceili(a.distance_to(b)/1.1))
	for i in posts+1:
		var foot:=a.lerp(b,float(i)/posts)
		beam(foot,foot+Vector3.UP*h,.031,"iron")
	var d:=b-a
	var guard:=box("GuardCollision",(a+b)*.5+Vector3.UP*h*.5,Vector3(d.length(),h,.06),"iron",true,-atan2(d.z,d.x))
	guard.hide();guard.get_child(0).collision_layer=1

# Continuous walk surface follows the nosings. A capsule need not step over box corners.
func stair_wedge(origin:Vector3,index:int,inner:float,outer:float)->void:
	var pts:=PackedVector3Array()
	for j in [index,index+1]:
		var angle:float=PI*.5+TAU*j/41.
		for radius in [inner,outer]:
			for h in [-.16,.015]:pts.append(Vector3(radius*cos(angle),4.8*j/41.+h,radius*sin(angle)))
	var shape:=ConvexPolygonShape3D.new();shape.points=pts
	var col:=CollisionShape3D.new();col.shape=shape
	var body:=StaticBody3D.new();body.position=origin;body.add_child(col);section.add_child(body);body.add_to_group("expedition_iron_tread")

# Clip each rectangular landing against the inner shaft radius, leaving the portal throat separate.
func platform(side:int,half_width:float)->void:
	var outline:=PackedVector2Array([Vector2(CX+side*9,CZ-half_width)])
	for j in 13:
		var z:=lerpf(-half_width,half_width,j/12.)
		outline.append(Vector2(CX+side*sqrt(14.*14.-z*z),CZ+z))
	outline.append(Vector2(CX+side*9,CZ+half_width))
	var mesh:=CSGPolygon3D.new();mesh.name="ClippedLanding";mesh.polygon=outline;mesh.depth=.24;mesh.rotation.x=PI/2;mesh.position.y=-.24;mesh.material=mat("floor");mesh.use_collision=true;section.add_child(mesh)

# Hardware follows its moving leaf. Relief stays off the collision layer.
func hardware()->void:
	section=airlock
	for side:float in [-1.,1.]:
		rect("PressedDoorSkin",.54,0,side*.245,.16,.88,.465,"joint",false)
		for i in 5:rect("InsetRib",.66,-.36+i*.16,side*.245,.06,.008,.35,"trim",false)
	section=get_child(1)
	for x in [21.5,26.2]:
		for dx in [-.95,-.47,0.,.47,.95]:
			rect("CastStanchion",x+dx,.59,13.57,.065,1.12,.12,"joint",false)
			rect("AnchorShoe",x+dx,.065,13.57,.17,.13,.22,"brass",false)
		for y in [.20,.86]:rect("GuardRail",x,y,13.53,2.72,.06,.08,"trim",false)
	for z in [10.32,13.73]:
		for side in [-1.,1.]:
			var x:float=23.85+.94*side;rect("PlateSocket",x,.025,z,.26,.05,.23,"iron",false)
			beam(Vector3(x,.05,z),Vector3(x,.069,z),.047,"brass")
	for x in [35.98,36.62]:
		for y in [.78,1.39]:beam(Vector3(x,y,7.58),Vector3(x,y,7.61),.045,"iron")
	section=get_child(2)
	for side in [-1.,1.]:
		for dx in [-.42,.42]:
			var x:float=CX+side*9.66+dx
			for z in [CZ-1.72,CZ+1.72]:rect("SpanAnchor",x,.055,z,.30,.11,.34,"iron",false);beam(Vector3(x,.11,z),Vector3(x,.14,z),.056,"brass")
	# Stepped instrument mount makes the source readable in silhouette.
	for i in 3:rect("CoreCollar",CX+10.8,.64+i*.07,CZ,.69-i*.09,.07,.69-i*.09,"brass",false)
