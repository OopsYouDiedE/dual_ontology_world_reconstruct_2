extends SceneTree
const S=preload("../production/building/BuildingSolver.gd")
const STUDY="res://tools/building_construction/production/building/kits/room-kit-study.json"
var failures:=0
func check(ok:bool,why:String)->void:
	if not ok:failures+=1;push_error(why)
func _initialize()->void:
	var p=JSON.parse_string(FileAccess.get_file_as_string(STUDY));var s=S.new()
	check(S.valid(p),"study schema")
	s.build(p);check(s.notes.is_empty(),str(s.notes));check(s.pass_order==["ReservationPass","StructurePass","EnvelopePass","FinishPass"],"pass order")
	check(s.slots["column/0:0:0"].p!=Vector3.ZERO,"reserved footprint displaces column")
	check(s.host.blocked(AABB(Vector3(2.9,1.59,2.09),Vector3.ONE*.04)),"optical path")
	for kind in ["BayCenter","WallPanelCenter","ColumnFace","PipeJunction","Threshold"]:check(not s.host.nearest(kind,Vector3.ZERO).is_empty(),kind)
	check(s.sockets.any(func(o):return o.id=="study/marker" and o.owner=="2:0:0"),"mounted in dark cell")
	check(s.slots["door/Z2:0:0"].w==1.5,"mandatory aperture")
	check(s.sockets.filter(func(o):return o.id=="door/Z2:0:0").size()==1,"shared door unique")
	check(not s.pieces.any(func(o):return o.owner=="2:0:0" and o.mat=="glass"),"dark cell opaque")
	check(s.slots.values().any(func(o):return o.kind=="WindowSlot" and o.low>4),"clerestory height")
	check(is_equal_approx(s.slots["roof/2:0:0"].points[1].y,2.4),"dark cell roof closes at local eave height")
	var column="column/0:0:0";var before=s.slots["column/1:0:0"].p
	p.overrides[column]={"scene":p.mounts[0].scene};s.build(p)
	check(s.sockets.any(func(o):return o.id==column and o.kind=="custom"),"prefab replacement")
	check(not s.pieces.any(func(o):return o.id==column),"original column suppressed");check(s.slots["column/1:0:0"].p==before,"neighbour stable")
	var view=preload("../production/building/BuildingView.gd").new();root.add_child(view);view.render(s,-1,false)
	check(view.find_children("Plaque","MeshInstance3D",true,false).size()==2,"mounted scene and custom column instantiated");view.free()
	p.profiles["0"]={"room_height":2.4,"allow_windows":false};s.build(p)
	check(s.slots["light/0:0:0"].recipe_key=="Flush","low hall flush mount");check(s.slots.values().any(func(o):return o.owner=="0:0:0" and o.get("recipe_key")=="Blind"),"blind fallback")
	p.reservations[2].end=p.reservations[2].apex;check(not S.valid(p),"reject degenerate cone")
	print("Room kit contract: %d failures"%failures);quit(int(failures!=0))
