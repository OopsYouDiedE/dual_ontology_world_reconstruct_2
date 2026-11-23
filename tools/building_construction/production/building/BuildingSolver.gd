extends RefCounted
## Integer building-space addresses remain stable across redraws and serialisation.
const BAY := 4.2
const RISE := 3.3
const MOVE := 1
const SIGHT := 2
const USE := 4
const SOUND := 8
const TYPES := ["Hall", "Gallery", "Laboratory", "Mezzanine", "Observatory", "Pump room"]
const FINISH := ["cream","wood_light","green","stone","book_blue","stone_dark"]
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

static func room_tag(p:Dictionary,k:String)->String:return str(p.get("rooms",{}).get(k,p.cells.get(k,-1)))
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
	var keys=plan.cells.keys();keys.sort();find_entries(keys);var columns={};var beams={};var lit_rooms={}
	for k in plan.cores.keys():
		var v=address(k);var above=key(v.x,v.y,v.z+1)
		if not plan.cells.has(k) or not plan.cells.has(above): notes.append(k+" · shaft needs two occupied levels");continue
		var kind=plan.cores[k]
		if kind=="spiral":
			# Standard compact spiral: 10 risers/turn, 18 risers total. Expand to 14/turn when the bay permits.
			if RISE*10/18.0-0.16<2.0:
				if not repair(k,"compact spiral headroom → expanded radius / 14 risers per turn"):continue
		if kind=="spiral" and float(plan.get("spiral_radius",1.60))<1.50:
			if not repair(k,"enlarged spiral exceeds reserved radius → U stair"):continue
			kind="stair"
		active_cores[k]=kind
		if kind=="service":
			for h in range(v.z+1,LEVELS-1):
				var next=key(v.x,v.y,h);if not plan.cells.has(next) or not plan.cells.has(key(v.x,v.y,h+1)) or plan.cores.has(next):break
				active_cores[next]=kind
	for k in keys:
		cell_owner=k;var c=address(k);var x=c.x;var z=c.y;var l=c.z;var t=int(plan.cells[k]);var y=l*RISE;var base=Vector3(x*BAY,y,z*BAY);var mid=base+Vector3(BAY/2,0,BAY/2);var below=key(x,z,l-1)
		if l>0 and not plan.cells.has(below):notes.append(k+" · unsupported floor: extend lower storey")
		var hole=str(active_cores.get(below,""));var up=str(active_cores.get(k,""))
		floor_plate(k,base,"trench" if t==5 and hole=="" and up=="" else hole)
		preload("BayDetails.gd").dress(self,k,base,t,hole,up)
		if up!="":core(k,base,up)
		for dx in 2:
			for dz in 2:
				var ci=key(x+dx,z+dz,l);var cp=Vector3((x+dx)*BAY,y,(z+dz)*BAY)
				if not columns.has(ci):
					var axis_id="column/"+key(x+dx,z+dz,0);var o=pick("column/"+ci,"column",cp);var shift=plan.overrides.get(axis_id,o).get("shift",[0,0]);cp+=Vector3(shift[0],0,shift[1]);columns[ci]=cp
					box("column/"+ci,cp+Vector3.UP*1.55,Vector3(0.23,3.1,0.23),"stone")
					for tier in [[.42,.045,.09],[.36,.121,.062],[.29,.19,.076]]:
						box("plinth/"+ci,cp+Vector3.UP*tier[1],Vector3(tier[0],tier[2],tier[0]),"stone_dark" if tier[1]<.1 else "cream")
					box("capital/"+ci,cp+Vector3.UP*3.03,Vector3(0.36,0.14,0.36),"cream")
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var nb=key(x+d.x,z+d.y,l);var horizontal=d.y!=0;var sx=x+int(d.x>0);var sz=z+int(d.y>0);var edge=("X" if horizontal else "Z")+key(sx,sz,l)
			var a=key(sx,sz,l);var b=key(sx+int(horizontal),sz+int(not horizontal),l)
			beams[edge]=[a,b,k];var exterior=not plan.cells.has(nb)
			if not exterior and (room_tag(plan,nb)==room_tag(plan,k) or wall_hosts.has(edge)):continue
			wall_hosts[edge]=[k,nb if not exterior else ""];var center=mid+Vector3(d.x,0,d.y)*BAY/2
			wall(edge,center,d,t,-1 if exterior else int(plan.cells[nb]),k,nb)
		if up=="" and hole=="":
			var lid="light/"+k;var override=pick(lid,"light",mid+Vector3.UP*2.8)
			if not override.get("hidden",false):socket(lid,"light",mid+Vector3.UP*2.8)
		var rid="%d/%s"%[t,l];if not lit_rooms.has(rid):socket("zone/"+k,"zone",mid+Vector3.UP*RISE/2);lit_rooms[rid]=true
		if not plan.cells.has(key(x,z,l+1)):hull[k]=true
	for e in beams:
		var row=beams[e];cell_owner=row[2];var aa:Vector3=columns[row[0]];var bb:Vector3=columns[row[1]];var v=bb-aa
		box("beam/"+e,(aa+bb)/2+Vector3.UP*3.15,Vector3(v.length(),0.3,0.21),"wood_dark",3,-atan2(v.z,v.x))
		preload("BayDetails.gd").beam_corbels(self,"beam/"+e,aa,bb)
	make_roofs()

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
func floor_plate(k:String,b:Vector3,hole:String)->void:
	var lo=Vector2.ZERO;var hi=Vector2.ZERO
	if hole=="trench":lo=Vector2(2.44,1.24);hi=Vector2(3.0,2.96)
	elif hole=="service":lo=Vector2(.6,.6);hi=Vector2(1.28,1.28)
	elif hole=="stair":lo=Vector2(.43,.18);hi=Vector2(2.85,3.84)
	elif hole=="spiral":lo=Vector2(.5,.5);hi=Vector2(3.7,3.7)
	var rects=[[0,0,BAY,BAY]] if hole=="" else [[0,0,lo.x,BAY],[hi.x,0,BAY,BAY],[lo.x,0,hi.x,lo.y],[lo.x,hi.y,hi.x,BAY]]
	for i in rects.size():
		var r=rects[i];box(k+"/slab%d"%i,b+Vector3((r[0]+r[2])/2,-.09,(r[1]+r[3])/2),Vector3(r[2]-r[0],.18,r[3]-r[1]),"stone")
	if hole not in ["","trench"]:
		for rx in [lo.x,hi.x]:box(k+"/guard",b+Vector3(rx,.53,(lo.y+hi.y)/2),Vector3(.055,1.06,hi.y-lo.y),"gold",1)
		if hole=="stair":
			box(k+"/guard-low-end",b+Vector3(1.055,.53,hi.y),Vector3(1.25,1.06,.055),"gold",1)
		var closed_z=lo.y if hole=="stair" else hi.y
		box(k+"/guard",b+Vector3((lo.x+hi.x)/2,.53,closed_z),Vector3(hi.x-lo.x,1.06,.055),"gold",1)
func core(k:String,b:Vector3,kind:String)->void:
	if kind=="service":
		box(k+"/riser",b+Vector3(.94,RISE/2,.94),Vector3(.34,RISE,.34),"gold");socket("valve/"+k,"valve",b+Vector3(.94,1.2,1.2),{"network":"riser/%d/%d"%[address(k).x,address(k).y]});return
	var start:Vector3;var end:Vector3;var rails=[PackedVector3Array(),PackedVector3Array()]
	if kind=="spiral":
		var center=b+Vector3(2.1,0,2.1);var delta=TAU/14.;var offset=-PI/2-17*delta
		for i in 18:
			var a=offset+i*delta;var p=center+Vector3(cos(a),0,sin(a))*.88+Vector3.UP*((i+1)*RISE/18.-.075)
			box(k+"/tread%d"%i,p,Vector3(1.45,.15,.69),"wood_light",3,-a)
			var edge=p+Vector3(cos(a)*.69,1.,sin(a)*.69);rails[0].append(edge)
			if i%2==0:box(k+"/baluster%d"%i,edge-Vector3.UP*.46,Vector3(.04,.92,.04),"gold",1)
			if i==0:start=p+Vector3.UP*.1
		end=center+Vector3(0,RISE,-1.62);box(k+"/landing",end-Vector3.UP*.075,Vector3(.9,.15,.56),"wood")
	else:
		var turn_z=1.08;var entry_z=3.84;var half=RISE*.5
		for flight in 2:
			var x=.99 if flight==0 else 2.29
			var foot=b+Vector3(x,half*flight,entry_z if flight==0 else turn_z)
			var head=b+Vector3(x,half*(flight+1),turn_z if flight==0 else entry_z)
			var side=Vector3.RIGHT*.55*(1 if flight==0 else -1)
			facet(k,"walk_proxy",foot-side,head+side,foot+side,MOVE)
			facet(k,"walk_proxy",foot-side,head-side,head+side,MOVE)
			var detail=preload("BayDetails.gd")
			for dx in [-.50,.50]:
				var offset=Vector3.RIGHT*dx
				detail.stair_guard(self,k,foot+offset,head+offset)
				var underside=offset-Vector3.UP*.10
				detail.sweep(self,k,"wood_dark",PackedVector3Array([foot+underside,head+underside]),PackedVector2Array([Vector2(-.05,-.09),Vector2(-.05,.09),Vector2(.05,.09),Vector2(.05,-.09)]),3)
			for i in 9:
				var pos=foot.lerp(head,(i+.5)/9.)+Vector3.UP*(half/18.-.08)
				box(k+"/tread%d"%(flight*9+i),pos,Vector3(1.1,.16,(entry_z-turn_z)/9.),"wood_light",SIGHT)
		start=b+Vector3(.99,0,entry_z);end=b+Vector3(2.29,RISE,entry_z)
		box(k+"/landing",b+Vector3(1.64,half-.08,(.18+turn_z)*.5),Vector3(2.4,.16,turn_z-.18),"wood")
		var perimeter=[Vector3(.49,half,turn_z),Vector3(.49,half,.22),Vector3(2.79,half,.22),Vector3(2.79,half,turn_z)]
		for i in 3:preload("BayDetails.gd").stair_guard(self,k,b+perimeter[i],b+perimeter[i+1])
		for z in [.30,turn_z-.06]:
			box(k+"/landing-joist",b+Vector3(1.64,half-.25,z),Vector3(2.4,.18,.14),"wood_dark")
			for x in [.52,2.76]:
				box(k+"/landing-post",b+Vector3(x,(half-.34)*.5,z),Vector3(.14,half-.34,.14),"wood")
	for path in rails:
		preload("BayDetails.gd").sweep(self,k,"wood_dark",path,PackedVector2Array([Vector2(-.035,-.03),Vector2(-.035,.03),Vector2(.035,.03),Vector2(.035,-.03)]))
	links.append([k,start,end]);socket("stairs/"+k,"link",start,{"end":end})
func wall(id:String,center:Vector3,d:Vector2i,t:int,other:int,k:String,nb:String)->void:
	var n=Vector3(d.x,0,d.y);var along=Vector3(-n.z,0,n.x);var yaw=-atan2(along.z,along.x);var shared=other>=0
	var entrance=entries.get(k,Vector2i.ZERO)==d
	var door=shared or entrance;var w=1.35 if door else 1.95;var low=0.0 if door else 1.05;var high=2.38;var thick=.44 if t==5 and not shared and d==Vector2i.RIGHT else .22
	var spans=[[-BAY/2,-w/2,0,RISE],[w/2,BAY/2,0,RISE],[-w/2,w/2,high,RISE]]
	var niche=not door and t==5 and d==Vector2i.RIGHT
	if niche:
		var depth=.34;var back=.075
		if depth+back>thick:
			niche=repair(id,"valve niche deeper than wall → project exterior backing pier")
		if niche:
			# Carve a local rectangle in the positive jamb, retain material around its perimeter.
			var jamb=spans[1];spans.remove_at(1);var middle=(jamb[0]+jamb[1])*.5;var left=middle-.31;var right=middle+.31
			spans.append_array([[jamb[0],left,0,RISE],[right,jamb[1],0,RISE],[left,right,0,1.08],[left,right,1.85,RISE]])
			var origin=center+along*middle-n*thick/2;box(id+"/niche-back",origin+n*(depth+back*.5)+Vector3.UP*1.465,Vector3(.62+2*back,.77+2*back,back),"stone_dark",3,yaw)
			for h in [1.08,1.85]:box(id+"/niche-return",origin+n*depth/2+Vector3.UP*h,Vector3(.62,back,depth),"stone",3,yaw)
			for j in [-1,1]:box(id+"/niche-side",origin+n*depth/2+along*j*.31+Vector3.UP*1.465,Vector3(back,.77,depth),"stone",3,yaw)
	if low>0:spans.append([-w/2,w/2,0,low])
	for i in spans.size():
		var r=spans[i];var p=center+along*((r[0]+r[1])*.5)+Vector3.UP*((r[2]+r[3])*.5);var sz=Vector3(r[1]-r[0],r[3]-r[2],thick)
		box(id+"/wall%d"%i,p,sz,"stone",3,yaw)
		for side in [-1,1]:
			var mat=FINISH[t] if side<0 else (FINISH[other] if shared else "stone_dark")
			box(id+"/finish",p+n*side*(thick*.5+.006),Vector3(sz.x,sz.y,.012),mat,0,yaw)
	preload("BayDetails.gd").wall_trim(self,k,id,center,along,n,w,thick,door)
	if shared:preload("BayDetails.gd").wall_trim(self,k,id+"/reverse",center,-along,-n,w,thick,door)
	if door:
		preload("BayDetails.gd").arch(self,k,center+Vector3.UP*high,along,n,w/2)
		var did="door/"+id;var o=pick(did,"door",center);var style=o.get("style","iron" if 5 in [t,other] else "oak")
		socket(did,"door",center,{"yaw":yaw,"width":w,"wall_depth":thick,"height":high,"style":style,"rooms":[k,nb],"interlock":"airlock/%d/"%address(k).z+room_tag(layout,k if t==5 else nb) if 5 in [t,other] else ""})
		var mount=center+along*(w/2+.26)-n*(thick/2+.045)+Vector3.UP*1.6
		socket("panel/"+id,"panel",mount,{"target":did,"yaw":yaw,"normal":-n,"caption":TYPES[t]});links.append([did,k,nb])
	else:
		box(id+"/glass",center+Vector3.UP*((low+high)/2),Vector3(w,high-low,.035),"glass",MOVE,yaw)
		for i in 4:box(id+"/mullion",center+along*((i/3.-.5)*w)+Vector3.UP*((low+high)/2),Vector3(.045,high-low,.07),"wood_dark",MOVE,yaw)
		box(id+"/sill",center+Vector3.UP*low,Vector3(w+.12,.07,.33),"cream",3,yaw)
		var h=absi((id+str(layout.seed)).hash());var sign_side=1 if h%2 else -1
		var at=center+along*sign_side*(BAY/2-.50)-n*.43
		if not active_cores.has(k) and not active_cores.has(key(address(k).x,address(k).y,address(k).z-1)) and h%3==0:
			socket("fixture/"+id,"fixture",at,{"type":t,"yaw":yaw})
		box(id+"/patina",center+along*sign_side*(BAY*.5-.32)-n*.12+Vector3.UP*.09,Vector3(.54,.12,.012),"stone_dark",0,yaw)

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
			if hull.has(key(c.x+dir.x,c.y+dir.y,c.z)):continue
			var a=Vector2(c.x+int(dir.x>0),c.y+int(dir.y>0))*BAY;var b=a+(Vector2.RIGHT if dir.y!=0 else Vector2.DOWN)*BAY;borders[c.z].append([a,b])
	for k in hull:
		var c=address(k);cell_owner=k;var pts=[]
		for uv in [Vector2(.5,.5),Vector2.ZERO,Vector2(.5,0),Vector2(1,0),Vector2(1,.5),Vector2.ONE,Vector2(.5,1),Vector2(0,1),Vector2(0,.5)]:
			var x=(c.x+uv.x)*BAY;var z=(c.y+uv.y)*BAY;pts.append(Vector3(x,(c.z+1)*RISE+height_at(x,z,borders[c.z]),z))
		if int(layout.cells[k])==4 and not hull.has(key(c.x-1,c.y,c.z)) or (int(layout.cells[k])==4 and layout.cells.get(key(c.x-1,c.y,c.z),-1)!=4):
			preload("BayDetails.gd").dome(self,k,pts);continue
		for i in 8:
			var a:Vector3=pts[0];var b:Vector3=pts[1+i];var v:Vector3=pts[1+(i+1)%8];roofs.append([k,a,b,v]);var n=(v-a).cross(b-a).normalized()
			for pair in [[a,b,v],[b,v,a],[v,a,b]]:
				var u:Vector3=pair[0];var w:Vector3=pair[1];var key1=str(u.snapped(Vector3.ONE*.001));var key2=str(w.snapped(Vector3.ONE*.001));var id=key1+key2 if key1<key2 else key2+key1
				if seams.has(id):
					var old=seams[id];if old[0].dot(pair[2]-u)>.012 and n.dot(old[1]-u)>.012:socket("valley/"+id,"valley",u,{"end":w})
				else:seams[id]=[n,pair[2]]
