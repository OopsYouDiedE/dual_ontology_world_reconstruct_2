extends SceneTree
const S=preload("../production/building/BuildingSolver.gd")
const V=preload("../production/building/BuildingView.gd")
var errors=[]
func expect(test:bool,what:String)->void:
	if not test:errors.append(what);printerr("FAIL ",what)
func _initialize()->void:run.call_deferred()
func run()->void:
	var p=S.example();var s=S.new();s.build(p);var snapshot=JSON.stringify(s.pieces);s.build(JSON.parse_string(JSON.stringify(p)));expect(snapshot==JSON.stringify(s.pieces),"JSON deterministic replay")
	var q={"version":1,"seed":6,"mode":"repair","cells":{"0:0:0":0,"1:0:0":0},"rooms":{"1:0:0":"second"},"cores":{},"overrides":{}};s.build(q);expect(s.wall_hosts.size()==7,"two independent adjacent rooms -> seven boundaries")
	var d=s.sockets.filter(func(o):return o.kind=="door" and o.rooms[1]=="1:0:0");expect(d.size()==1,"one shared door")
	q.overrides["column/0:0:0"]={"shift":[.35,.15]};q.overrides["light/0:0:0"]={"hidden":true};q.cells["2:0:0"]=2;s.build(q);expect(s.sockets.all(func(o):return o.id!="light/0:0:0"),"suppression survives extension");expect(s.pieces.any(func(r):return r.id=="column/0:0:0" and abs(r.p.x-.35)<.001),"pinned column shift")
	var v=V.new();root.add_child(v);v.render(s,-1,false);await physics_frame;await physics_frame
	if d.size():
		var id=d[0].id;var closed=v.sound_loss("0:0:0","1:0:0");expect(v.switch_door(id),"open shared door");expect(v.sound_loss("0:0:0","1:0:0")<closed,"sound passes through open port");expect(v.doors[id].link.enabled,"door navlink opens")
	expect("0 blocked" in v.audit_sockets(),"eye-height interaction ray "+v.audit_sockets());print(v.bake_routes());expect(v.get_node("WalkRegion").navigation_mesh.get_polygon_count()>0,"real navigation mesh")
	for seed_value in range(32):
		var auto=S.generate(seed_value);expect(S.valid(auto),"valid generated plan");s.build(auto);expect(s.entries.size()==1,"connected ground entry");expect(s.active_cores.size()>=2,"connected shafts")
	p.cores["0:0:0"]="spiral";p.spiral_radius=1.2;s.build(p);expect(s.active_cores["0:0:0"]=="stair","compact shaft repaired to U stair");p.mode="strict";s.build(p);expect(not s.active_cores.has("0:0:0"),"strict mode reports unresolved spiral")
	var raw=S.example();raw.cells["3:0:2"]=5;s.build(raw);expect(s.active_cores.get("3:0:1")=="service","riser continues through upper storey");expect(s.facets.size()>0 and s.roofs.size()>0,"architectural meshes and roof skin")
	v.free();print("Structure generator test: ",errors.size()," failures");quit(1 if errors else 0)
