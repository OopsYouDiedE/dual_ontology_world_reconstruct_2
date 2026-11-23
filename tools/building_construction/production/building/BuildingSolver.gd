extends RefCounted
const KitType=preload("kits/RoomStyleKit.gd")
## Integer building-space addresses remain stable across redraws and serialisation.
const BAY := 4.2
const RISE := 3.3
const MOVE := 1
const SIGHT := 2
const USE := 4
const SOUND := 8
const TYPES := ["Hall", "Gallery", "Laboratory", "Mezzanine", "Observatory", "Pump room","Dark cell"]
const FINISH := ["cream","wood_light","green","stone","book_blue","stone_dark","stone_dark"]
const GRID := 12
const LEVELS := 4

static func key(x:int,z:int,l:int)->String: return "%d:%d:%d" % [x,z,l]
static func address(k:String)->Vector3i:
	var a=k.split(":"); return Vector3i(int(a[0]),int(a[1]),int(a[2]))
static func example()->Dictionary:
	var p={"version":1,"seed":17,"cells":{},"overrides":{},"cores":{},"mode":"repair"}
	for l in 2:
		for z in 3:
			for x in 4:
				if z==2 and x>=2: continue
				p.cells[key(x,z,l)] = (0 if x<2 else 2) if l==0 else (3 if x<2 else 4)
	p.cells[key(3,1,0)]=5 # Pump annex beside the laboratory and riser.
	p.cores[key(0,0,0)]="stair"; p.cores[key(3,0,0)]="service"
	return p
static func triple(a)->bool:
	if not a is Array or a.size()!=3:return false
	for v in a:if typeof(v) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(v):return false
	return true
static func valid(p:Variant)->bool:
	if not p is Dictionary or p.get("version")!=1: return false
	if not p.get("rooms",{}) is Dictionary:return false
	if not (p.get("spiral_radius",1.6) is float or p.get("spiral_radius",1.6) is int):return false
	for field in ["cells","cores","overrides"]:
		if not p.get(field) is Dictionary:return false
	if not (p.get("seed") is float or p.get("seed") is int) or p.get("mode") not in ["repair","strict"]:return false
	for k in p.cells.keys()+p.cores.keys():
		var a=str(k).split(":"); if a.size()!=3:return false
		for v in a:
			if not v.is_valid_int():return false
		var pos=address(k)
		if k!=key(pos.x,pos.y,pos.z) or pos.x<0 or pos.y<0 or pos.z<0 or pos.x>=GRID or pos.y>=GRID or pos.z>=LEVELS:return false
	for v in p.cells.values():
		if not (v is float or v is int) or int(v)!=v or v<0 or v>=TYPES.size():return false
	for v in p.cores.values():
		if v not in ["stair","spiral","service"]:return false
	for o in p.overrides.values():
		if not o is Dictionary:return false
		if o.has("shift"):
			if not o.shift is Array or o.shift.size()!=2:return false
			for n in o.shift:
				if not (n is float or n is int) or absf(n)>0.65:return false
	if not p.get("profiles",{}) is Dictionary or not p.get("reservations",[]) is Array or not p.get("mounts",[]) is Array:return false
	for cfg in p.get("profiles",{}).values():
		if not cfg is Dictionary or typeof(cfg.get("room_height",RISE)) not in [TYPE_INT,TYPE_FLOAT] or not (float(cfg.get("room_height",RISE))>=2.4 and float(cfg.get("room_height",RISE))<=6.):return false
		if typeof(cfg.get("allow_windows",true))!=TYPE_BOOL:return false
		if cfg.has("kit"):
			if not cfg.kit is String or not cfg.kit.begins_with("res://") or not cfg.kit.ends_with(".tres") or not ResourceLoader.exists(cfg.kit):return false
			if not load(cfg.kit) is KitType:return false
	for o in p.overrides.values():
		if o.has("scene") and (not o.scene is String or not scene_ok(o.scene)):return false
	var edges={}
	for r in p.get("reservations",[]):
		if not r is Dictionary:return false
		match r.get("kind",""):
			"footprint","operation":
				if not triple(r.get("min")) or not triple(r.get("size")) or r.size.min()<=0:return false
			"cone":
				if not triple(r.get("apex")) or not triple(r.get("end")) or preload("kits/MechanismHost.gd").vec(r.apex).is_equal_approx(preload("kits/MechanismHost.gd").vec(r.end)) or typeof(r.get("radius")) not in [TYPE_INT,TYPE_FLOAT] or r.radius<=0:return false
			"opening":
				if not r.get("edge") is String or edges.has(r.edge) or r.get("type") not in ["door","window"]:return false
				edges[r.edge]=true
				for n in ["head","sill","width"]:if r.has(n) and typeof(r[n]) not in [TYPE_FLOAT,TYPE_INT]:return false
				if r.get("width",1.35)<=.1 or r.get("width",1.35)>BAY-.45 or r.get("head",2.24)<=r.get("sill",0.) or r.get("sill",0.)<0:return false
			_:return false
	for m in p.get("mounts",[]):
		if not m is Dictionary or not m.get("id") is String or not m.get("anchor") is String or not triple(m.get("near")) or not m.get("scene") is String or not scene_ok(m.scene):return false
	return true

static func generate(seed_value:int)->Dictionary:
	var p=example();p.seed=seed_value;p.cells.clear();p.cores.clear();var rng=RandomNumberGenerator.new();rng.seed=seed_value
	var bays=rng.randi_range(3,5);var depth=rng.randi_range(2,4)
	for l in range(2+rng.randi_range(0,1)):
		for x in bays:
			for z in depth:
				if x>=2 and z>=2:continue
				p.cells[key(x,z,l)]= (0 if x<2 else (5 if x==bays-1 else 2)) if l==0 else (3 if x<2 else 4)
		if l>0:p.cores[key(0,0,l-1)]="spiral" if seed_value%2 else "stair"
	p.cores[key(bays-1,0,0)]="service";return p

static func room_tag(p:Dictionary,k:String)->String:return str(p.get("rooms",{}).get(k,int(p.cells.get(k,-1))))
var pieces:Array=[]
var skins:Array=[]
var sockets:Array=[]
var roofs:Array=[]
var choices:Dictionary={}
var facets:Array=[]
var notes:Array=[]
var layout:Dictionary
var hull:Dictionary={}
var entries:Dictionary={}
var wall_hosts:Dictionary={}
var active_cores:Dictionary={}
var links:Array=[]
var cell_owner:String
const KITS=[preload("kits/HallKit.tres"),preload("kits/GalleryKit.tres"),preload("kits/HallKit.tres"),preload("kits/HallKit.tres"),preload("kits/ObservatoryKit.tres"),preload("kits/PumpRoomKit.tres"),preload("kits/DarkCellKit.tres")]
var host=preload("kits/MechanismHost.gd").new()
var slots:Dictionary={}
var emissions:Array=[]
var pass_order:Array=[]
var heights:Array=[]
var envelope_queue:Array=[]
var finish_queue:Array=[]
var supported:Dictionary={}
func profile(k:String)->Dictionary:return layout.get("profiles",{}).get(room_tag(layout,k),{})
func kit(k:String):
	var path=profile(k).get("kit","")
	return load(path) if path!="" else KITS[int(layout.cells[k])]
func room_height(k:String)->float:return float(profile(k).get("room_height",RISE))
func datum(level:int)->float:
	var y=0.;for i in level:y+=heights[i]
	return y
func enabled(k:String,pass_name:String)->bool:return pass_name in kit(k).passes
func run_extensions(phase:String,keys:Array)->void:
	for k in keys:
		cell_owner=k
		if phase!="ReservationPass" and not enabled(k,phase):continue
		for script in kit(k).extensions.get(phase,[]):script.new().run(self,k)
func slot(kind:String,id:String,k:String,p:Vector3,args:Dictionary={},style=null)->Dictionary:
	var q={"id":id,"kind":kind,"owner":k,"p":p,"height":room_height(k),"yaw":0.};q.merge(args,true);slots[id]=q
	emissions.append([q,kit(k) if style==null else style]);return q

static func scene_ok(path:String)->bool:return path.begins_with("res://") and path.ends_with(".tscn") and ResourceLoader.exists(path,"PackedScene")
func box(id:String,p:Vector3,sz:Vector3,mat:String,mask:=3,axis:=0.0)->void:
	pieces.append({"id":id,"owner":cell_owner,"p":p,"size":sz,"mat":mat,"mask":mask,"yaw":axis})
func socket(id:String,kind:String,p:Vector3,more:Dictionary={})->void:
	var s={"id":id,"kind":kind,"p":p,"owner":cell_owner};s.merge(more);sockets.append(s)
func pick(id:String,kind:String,p:Vector3)->Dictionary:
	choices[id]={"kind":kind,"p":p,"owner":cell_owner};return layout.overrides.get(id,{})
func repair(id:String,message:String)->bool:
	notes.append(id+" · "+message);return layout.mode=="repair"
func build(plan:Dictionary)->void:
	layout=plan;pieces.clear();skins.clear();facets.clear();roofs.clear();sockets.clear();choices.clear();notes.clear();hull.clear();links.clear();active_cores.clear();wall_hosts.clear()
	var keys=plan.cells.keys();keys.sort();slots.clear();emissions.clear();supported.clear();envelope_queue.clear();finish_queue.clear();pass_order.clear()
	pass_order.append("ReservationPass");host.reset(plan);heights=[]
	for l in LEVELS:heights.append(0.)
	for k in keys:var l=address(k).z;heights[l]=maxf(heights[l],room_height(k))
	for l in LEVELS:if heights[l]==0.:heights[l]=RISE
	run_extensions("ReservationPass",keys);find_entries(keys);reserve_cores(plan)
	pass_order.append("StructurePass");build_frame(keys);run_extensions("StructurePass",keys)
	pass_order.append("EnvelopePass")
	for row in envelope_queue:
		cell_owner=row[5];wall.callv(row)
	for edge in host.holes:
		if not wall_hosts.has(edge):notes.append(edge+" · required opening has no host wall")
	make_roofs();run_extensions("EnvelopePass",keys)
	pass_order.append("FinishPass")
	for job in finish_queue:
		cell_owner=job[0]
		if enabled(cell_owner,"FinishPass"):job[1].callv(job[2])
	finish_queue.clear();run_extensions("FinishPass",keys)
	for job in emissions:
		cell_owner=job[0].owner;preload("kits/SlotCompiler.gd").emit(self,job[0],job[1])
	emissions.clear()
	for inst in plan.get("mounts",[]):
		var a=host.nearest(inst.anchor,host.vec(inst.near),inst.get("owner",""))
		if a.is_empty():notes.append(inst.id+" · no matching anchor");continue
		cell_owner=a.owner;socket(inst.id,"custom",a.p,{"scene":inst.scene,"normal":a.normal,"yaw":atan2(a.normal.x,a.normal.z)})
func reserve_cores(plan:Dictionary)->void:
	for k in plan.cores.keys():
		var v=address(k);var above=key(v.x,v.y,v.z+1)
		if not plan.cells.has(k) or not plan.cells.has(above): notes.append(k+" · shaft needs two occupied levels");continue
		var kind=plan.cores[k]
		if kind=="spiral":
			# Standard compact spiral: 10 risers/turn, 18 risers total. Expand to 14/turn when the bay permits.
			if float(heights[v.z])*10/18.0-0.16<2.0:
				if not repair(k,"compact spiral headroom → expanded radius / 14 risers per turn"):continue
		if kind=="spiral" and float(plan.get("spiral_radius",1.60))<1.50:
			if not repair(k,"enlarged spiral exceeds reserved radius → U stair"):continue
			kind="stair"
		active_cores[k]=kind
		if kind=="service":
			for h in range(v.z+1,LEVELS-1):
				var next=key(v.x,v.y,h);if not plan.cells.has(next) or not plan.cells.has(key(v.x,v.y,h+1)) or plan.cores.has(next):break
				active_cores[next]=kind
func build_frame(keys:Array)->void:
	var plan=layout;var columns={};var beams={};var lit_rooms={}
	for k in keys:
		cell_owner=k;var c=address(k);var x=c.x;var z=c.y;var l=c.z;var t=int(plan.cells[k]);var y=datum(l);var base=Vector3(x*BAY,y,z*BAY);var mid=base+Vector3(BAY/2,0,BAY/2);var below=key(x,z,l-1)
		if l>0 and not plan.cells.has(below):notes.append(k+" · unsupported floor: extend lower storey")
		var hole=str(active_cores.get(below,""));var up=str(active_cores.get(k,""))
		slot("SlabSlot","slab/"+k,k,base,{"hole":"trench" if kit(k).service_floor and hole=="" and up=="" else hole})
		finish_queue.append([k,slot,["FloorFinishSlot","paving/"+k,k,base,{"type":5 if kit(k).service_floor else (0 if t==5 else t),"hole":hole,"up":up}]])
		host.anchor("center/"+k,"BayCenter",k,mid)
		if up=="" and hole=="" and not host.blocked(AABB(base+Vector3(0,room_height(k)-.35,0),Vector3(BAY,.35,BAY))):finish_queue.append([k,slot,["CeilingSlot","ceiling/"+k,k,mid,{"polygon":PackedVector3Array([base,base+Vector3.RIGHT*BAY,base+Vector3(BAY,0,BAY),base+Vector3.BACK*BAY])}]])
		if up!="":slot("CoreSlot","core/"+k,k,base,{"core":up})
		for dx in 2:
			for dz in 2:
				var ci=key(x+dx,z+dz,l);var cp=Vector3((x+dx)*BAY,y,(z+dz)*BAY)
				if not columns.has(ci):
					var owner=k
					for ox in [-1,0]:
						for oz in [-1,0]:
							var neighbour=key(x+dx+ox,z+dz+oz,l)
							if not plan.cells.has(neighbour) or not enabled(neighbour,"StructurePass") or kit(neighbour).variants.get("ColumnSlot")=="none":continue
							if not enabled(owner,"StructurePass") or kit(owner).variants.get("ColumnSlot")=="none" or room_height(neighbour)>room_height(owner):owner=neighbour
					var axis_id="column/"+key(x+dx,z+dz,0);var o=pick("column/"+ci,"column",cp);var shift=plan.overrides.get(axis_id,o).get("shift",[0,0]);cp+=Vector3(shift[0],0,shift[1]);columns[ci]=cp
					var size=Vector3(.44,room_height(owner),.44);var orig=cp;var clear=false
					for offset in [Vector3.ZERO,Vector3.RIGHT*.55,Vector3.LEFT*.55,Vector3.BACK*.55,Vector3.FORWARD*.55]:
						cp=orig+offset
						if host.blocked(AABB(cp-Vector3(.22,0,.22),size)):continue
						columns[ci]=cp;clear=true
						if enabled(owner,"StructurePass"):
							slot("ColumnSlot","column/"+ci,owner,cp,{"radius":.22});
							if kit(owner).variants.get("ColumnSlot","")!="none":supported[ci]=true
						break
					if not clear and enabled(owner,"StructurePass") and kit(owner).variants.get("ColumnSlot")!="none":notes.append("column/"+ci+" · all support positions reserved")
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var nb=key(x+d.x,z+d.y,l);var horizontal=d.y!=0;var sx=x+int(d.x>0);var sz=z+int(d.y>0);var edge=("X" if horizontal else "Z")+key(sx,sz,l)
			var a=key(sx,sz,l);var b=key(sx+int(horizontal),sz+int(not horizontal),l)
			if not beams.has(edge) or (enabled(k,"StructurePass") and kit(k).variants.get("BeamSlot")!="none" and (not enabled(beams[edge][2],"StructurePass") or kit(beams[edge][2]).variants.get("BeamSlot")=="none" or room_height(k)>=room_height(beams[edge][2]))):beams[edge]=[a,b,k]
			var exterior=not plan.cells.has(nb)
			if not exterior and (wall_hosts.has(edge) or (room_tag(plan,nb)==room_tag(plan,k) and not host.holes.has(edge))):continue
			wall_hosts[edge]=[k,nb if not exterior else ""];var center=mid+Vector3(d.x,0,d.y)*BAY/2
			if enabled(k,"EnvelopePass"):envelope_queue.append([edge,center,d,t,-1 if exterior else int(plan.cells[nb]),k,nb])
		if up=="" and hole=="":
			var lid="light/"+k;var override=pick(lid,"light",mid+Vector3.UP*2.8)
			if not override.get("hidden",false):
				for offset in [Vector3.ZERO,Vector3.RIGHT*.86,Vector3.LEFT*.86,Vector3.BACK*.86]:
					if not host.blocked(AABB(mid+offset+Vector3(-.18,room_height(k)-.70,-.18),Vector3(.36,.70,.36))):
						finish_queue.append([k,slot,["CeilingLightSlot",lid,k,mid+offset]]);break
		var rid="%d/%s"%[t,l];if not lit_rooms.has(rid):socket("zone/"+k,"zone",mid+Vector3.UP*RISE/2);lit_rooms[rid]=true
		if not plan.cells.has(key(x,z,l+1)):hull[k]=true
	for e in beams:
		var row=beams[e];cell_owner=row[2];var aa:Vector3=columns[row[0]];var bb:Vector3=columns[row[1]];var v=bb-aa
		var h=room_height(cell_owner);var top=Vector3.UP*(h-(1.35 if kit(cell_owner).variants.get("BeamSlot")=="arcade" else .65));var bounds=AABB(aa+top,Vector3.ZERO).expand(bb+Vector3.UP*h).grow(.16)
		if enabled(cell_owner,"StructurePass") and not host.blocked(bounds):slot("BeamSlot","beam/"+e,cell_owner,(aa+bb)*.5,{"a":aa,"b":bb,"yaw":-atan2(v.z,v.x),"seated":supported.has(row[0]) and supported.has(row[1])})

func find_entries(keys:Array)->void:
	entries.clear();var seen={}
	for k in keys:
		if seen.has(k) or address(k).z!=0:continue
		var queue=[k];seen[k]=true;var best=-1;var entry_key=""
		while not queue.is_empty():
			var at=queue.pop_front();var c=address(at)
			for d in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
				var nb=key(c.x+d.x,c.y+d.y,0)
				if not layout.cells.has(nb):
					# Prefer a free approach over routing the entrance beneath the half landing.
					var rank=3 if not layout.cores.has(at) else (2 if d==Vector2i.RIGHT else 0)
					if rank>best:
						entries.erase(entry_key);entries[at]=d;entry_key=at;best=rank
				elif not seen.has(nb):seen[nb]=true;queue.append(nb)
func shell_rise(k:String)->float:
	var c=address(k)
	return heights[c.z] if layout.cells.has(key(c.x,c.y,c.z+1)) else room_height(k)
func wall(id:String,center:Vector3,d:Vector2i,t:int,other:int,k:String,nb:String)->void:
	var n=Vector3(d.x,0,d.y);var along=Vector3(-n.z,0,n.x);var yaw=-atan2(along.z,along.x);var shared=other>=0
	var hgt=room_height(k);var boundary:float=maxf(shell_rise(k),shell_rise(nb)) if shared else shell_rise(k);var req:Dictionary=host.holes.get(id,{})
	var entrance=entries.get(k,Vector2i.ZERO)==d
	var door=req.get("type","door" if shared or entrance else "window")=="door"
	var w:float=req.get("width",1.35 if door else 1.95);var low:float=0. if door else req.get("sill",1.05);var high:float=req.get("head",minf(2.38,hgt-.16) if door or hgt<=4.8 else hgt-.55)
	var opened=door or req.has("type") or (not shared and profile(k).get("allow_windows",kit(k).exterior_windows) and kit(k).variants.get("WindowSlot")!="blind");var thick=.44 if t==5 and not shared and d==Vector2i.RIGHT else .22
	var host_height=minf(hgt,room_height(nb)) if shared else hgt
	if high>host_height-.04:
		notes.append(id+" · opening head exceeds host");high=host_height-.04
	if req.is_empty() and not door and hgt>4.8:low=hgt-1.65
	if low>=high:low=maxf(0.,high-.4)
	if req.has("type") and not door:opened=true
	var geo={"n":n,"along":along,"yaw":yaw,"w":w,"thick":thick,"door":door,"low":low,"high":high,"open":opened,"edge":id,"boundary":boundary,"d":d,"type":t,"other":other,"required":req.has("type")}
	slot("ShellSlot","shell/"+id,k,center,geo)
	for face in ([-1,1] if shared else [-1]):
		var owner=k if face<0 else nb;var side=geo.duplicate();side.n=-face*n;side.along=-face*along
		var finish_id=id+"/trim"+("/reverse" if face>0 else "")
		finish_queue.append([owner,slot,["WallFinishSlot",finish_id,owner,center,side]])
		host.anchor(finish_id,"WallPanelCenter",owner,center+along*(w*.5+.35)+n*face*(thick*.5+.013)+Vector3.UP*1.5,n*face)
	if door:
		var did="door/"+id;pick(did,"door",center);geo.rooms=[k,nb];geo.interlock="airlock/%d/"%address(k).z+room_tag(layout,k if t==5 else nb) if 5 in [t,other] else ""
		slot("DoorSlot",did,k,center,geo,kit(nb) if shared and other==5 and t!=5 else kit(k));host.anchor(did,"Threshold",k,center,-n)
		var mount=center+along*(w/2+.26)-n*(thick/2+.045)+Vector3.UP*1.6
		socket("panel/"+id,"panel",mount,{"target":did,"yaw":yaw,"normal":-n,"caption":TYPES[t]});links.append([did,k,nb])
	else:
		slot("WindowSlot","window/"+id,k,center,geo)
		var h=absi((id+str(layout.seed)).hash());var sign_side=1 if h%2 else -1
		var at=center+along*sign_side*(BAY/2-.50)-n*.43
		if not active_cores.has(k) and not active_cores.has(key(address(k).x,address(k).y,address(k).z-1)) and t<6 and h%3==0 and not host.blocked(AABB(at-Vector3(.55,0,.55),Vector3(1.1,2,1.1))):
			socket("fixture/"+id,"fixture",at,{"type":t,"yaw":yaw})


func facet(k:String,mat:String,a:Vector3,b:Vector3,c:Vector3,mask:=0,normals:Array=[])->void:
	facets.append([k,mat,a,b,c,mask,normals])
func height_at(x:float,z:float,bounds:Array)->float:
	var dist=INF
	for edge in bounds:
		var close:Vector2=Geometry2D.get_closest_point_to_segment(Vector2(x,z),edge[0],edge[1]);dist=minf(dist,maxf(absf(close.x-x),absf(close.y-z)))
	return dist*.38
func make_roofs()->void:
	var borders={};var seams={}
	for k in hull:
		var c=address(k);if not borders.has(c.z):borders[c.z]=[]
		for dir in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var neighbour=key(c.x+dir.x,c.y+dir.y,c.z);if hull.has(neighbour) and is_equal_approx(room_height(k),room_height(neighbour)):continue
			var a=Vector2(c.x+int(dir.x>0),c.y+int(dir.y>0))*BAY;var b=a+(Vector2.RIGHT if dir.y!=0 else Vector2.DOWN)*BAY;borders[c.z].append([a,b])
	for k in hull:
		if not enabled(k,"EnvelopePass"):continue
		var c=address(k);cell_owner=k;var pts=[]
		for uv in [Vector2(.5,.5),Vector2.ZERO,Vector2(.5,0),Vector2(1,0),Vector2(1,.5),Vector2.ONE,Vector2(.5,1),Vector2(0,1),Vector2(0,.5)]:
			var x=(c.x+uv.x)*BAY;var z=(c.y+uv.y)*BAY;pts.append(Vector3(x,datum(c.z)+room_height(k)+height_at(x,z,borders[c.z]),z))
		var west=key(c.x-1,c.y,c.z)
		if kit(k).dome and (not hull.has(west) or not kit(west).dome):
			slot("DomeSlot","dome/"+k,k,pts[0],{"points":pts});continue
		slot("RoofSlot","roof/"+k,k,pts[0],{"points":pts})
		for i in 8:
			var a:Vector3=pts[0];var b:Vector3=pts[1+i];var v:Vector3=pts[1+(i+1)%8];var n=(v-a).cross(b-a).normalized()
			for pair in [[a,b,v],[b,v,a],[v,a,b]]:
				var u:Vector3=pair[0];var w:Vector3=pair[1];var key1=str(u.snapped(Vector3.ONE*.001));var key2=str(w.snapped(Vector3.ONE*.001));var id=key1+key2 if key1<key2 else key2+key1
				if seams.has(id):
					var old=seams[id];if old[0].dot(pair[2]-u)>.012 and n.dot(old[1]-u)>.012:socket("valley/"+id,"valley",u,{"end":w})
				else:seams[id]=[n,pair[2]]
