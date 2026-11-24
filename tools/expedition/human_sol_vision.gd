extends RefCounted
## First-person depth proxy. No scene traversal, named anchors, navmesh or game-rule queries.
const RANGE:=9.

func hit(eye:Camera3D, space:PhysicsDirectSpaceState3D, excluded:RID, probe:Vector3)->Dictionary:
	if eye.is_position_behind(probe):return {}
	var pixel:=eye.unproject_position(probe)
	var area:=eye.get_viewport().get_visible_rect().grow(-8.)
	if not area.has_point(pixel):return {}
	var origin:=eye.project_ray_origin(pixel)
	var ray:=eye.project_ray_normal(pixel)
	if origin.distance_to(probe)>RANGE:return {}
	var query:=PhysicsRayQueryParameters3D.create(origin,origin+ray*RANGE,7,[excluded])
	# Hidden colliders are deliberately transparent to perception (still solid to Sol).
	for i in 8:
		var result:=space.intersect_ray(query)
		if result.is_empty():return {"empty":true}
		var shape_owner:=result.collider as Node3D
		if shape_owner!=null and shape_owner.is_visible_in_tree() and result.collider.get_parent() is GeometryInstance3D:
			return {"point":result.position,"normal":result.normal}
		var omit:=query.exclude;omit.append(result.rid);query.exclude=omit
	return {}

func sample(eye:Camera3D, body:CharacterBody3D, near_floor:=false)->Array:
	var space:=eye.get_world_3d().direct_space_state
	var excluded:=body.get_rid()
	var feet:=body.global_position
	var lanes:=[]
	var ranges:=[1.75,2.25,2.85,3.55,4.4,5.4,6.5]
	if near_floor:ranges.push_front(1.25);ranges.push_front(.85)
	for angle:float in [0.,-.16,.16,-.31,.31,-.47,.47,-.62,.62,-.77,.77]:
		var dir:=(-body.global_basis.z).rotated(Vector3.UP,angle)
		var side:=dir.cross(Vector3.UP)*.30
		var depth:=0.
		for distance:float in ranges:
			var end:=feet+dir*distance
			var ground:=hit(eye,space,excluded,end+Vector3.DOWN*.035)
			if near_floor and ground.is_empty() and distance<1.75:continue
			if not ground.has("point") or ground.normal.y<.60 or Vector3(ground.point).distance_to(end)>.43:break
			var clear:=true
			for offset:Vector3 in [-side,side]:
				var chest:=end+offset+Vector3.UP*.76
				var sight:=hit(eye,space,excluded,chest)
				if sight.is_empty() or (sight.has("point") and eye.global_position.distance_to(sight.point)<eye.global_position.distance_to(chest)-.03):
					clear=false;break
			if not clear:break
			depth=distance
		if depth>0.:
			var end:=feet+dir*minf(depth,2.25)
			lanes.append({"depth":depth,"turn":angle,"end":Vector2(end.x,end.z)})
	return lanes


# Label anchors stay inside the sensor. The policy receives text and screen-relative
# turn only, and only after visibility and an opaque line-of-sight test.
func read_labels(eye:Camera3D, body:CharacterBody3D, world:Node)->Array:
	var space:=eye.get_world_3d().direct_space_state
	var labels:=[]
	var pending:Array[Node]=[world]
	while not pending.is_empty():
		var node:Node=pending.pop_back()
		if node is Label3D:
			var label:=node as Label3D
			if not label.is_visible_in_tree() or label.modulate.a<.25 or label.no_depth_test:continue
			if (label.layers & eye.cull_mask)==0:continue
			var p:=label.global_position
			var delta:=p-eye.global_position
			var distance:=delta.length()
			if distance<.1 or distance>RANGE or eye.is_position_behind(p):continue
			if not label.double_sided and label.billboard==BaseMaterial3D.BILLBOARD_DISABLED and label.global_basis.z.dot(-delta)<=0.:continue
			var pixel:=eye.unproject_position(p)
			if not eye.get_viewport().get_visible_rect().grow(-32.).has_point(pixel):continue
			# Approximate glyph size in pixels; reject tiny and edge-on text.
			var glyph:=label.font_size*label.pixel_size
			var scale_y:=label.global_basis.y.length()
			var y_axis:=eye.global_basis.y if label.billboard!=BaseMaterial3D.BILLBOARD_DISABLED else label.global_basis.y.normalized()
			if eye.unproject_position(p+y_axis*glyph*scale_y).distance_to(pixel)<8.:continue
			if label.billboard==BaseMaterial3D.BILLBOARD_DISABLED and absf(label.global_basis.z.normalized().dot(delta/distance))<.17:continue
			var sight:=hit(eye,space,body.get_rid(),p)
			if sight.is_empty() or (sight.has("point") and eye.global_position.distance_to(sight.point)<distance-.01):continue
			var local:=body.global_basis.inverse()*delta
			labels.append({"text":label.text,"turn":atan2(-local.x,-local.z)})
		else:
			pending.append_array(node.get_children())
	return labels

## Horizontal offsets to the two flanks, measured only by current screen rays.
func flanks(eye:Camera3D, body:CharacterBody3D)->Dictionary:
	var result:={}
	var space:=eye.get_world_3d().direct_space_state
	var forward:=-body.global_basis.z
	var origin:=eye.global_position
	for flank:int in [-1,1]:
		var side:=forward.rotated(Vector3.UP,flank*PI*.5)
		var gap:=INF
		for angle:float in [.38,.59,.80]:
			var ray:=forward.rotated(Vector3.UP,flank*angle)
			var surface:=hit(eye,space,body.get_rid(),origin+ray*3.-Vector3.UP*.45)
			if not surface.has("point") or absf(surface.normal.y)>.30:continue
			if absf(Vector3(surface.normal).dot(side))<.60:continue
			gap=minf(gap,(Vector3(surface.point)-origin).dot(side))
		if gap<3.:result[flank]=gap
	return result

## Coarse rendered-person detector. Animated joint samples approximate a skinned
## silhouette; eligibility comes from a visible skinned mesh, not an actor ID.
## No rig, world point, node name or facing/AI state leaves the sensor.
func people(eye:Camera3D, body:CharacterBody3D, world:Node)->Array:
	var rigs:Dictionary={}
	var pending:Array[Node]=[world]
	while not pending.is_empty():
		var node:Node=pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D:continue
		var mesh:=node as MeshInstance3D
		if mesh.mesh==null or mesh.skin==null or not mesh.is_visible_in_tree() or (mesh.layers & eye.cull_mask)==0:continue
		var rig:=mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if rig!=null:rigs[rig]=true
	var found:=[]
	for rig:Skeleton3D in rigs:
		var figure:=silhouette(eye,body,rig)
		if not figure.is_empty():found.append(figure)
	return found

func silhouette(eye:Camera3D, body:CharacterBody3D, rig:Skeleton3D)->Dictionary:
	if rig.get_bone_count()<12 or not rig.is_visible_in_tree():return {}
	if rig.global_position.distance_to(eye.global_position)>RANGE+2.:return {}
	var joints:=PackedVector3Array()
	var low:=INF
	var high:=-INF
	for i in rig.get_bone_count():
		var joint:Vector3=rig.global_transform*rig.get_bone_global_pose(i).origin
		joints.append(joint);low=minf(low,joint.y);high=maxf(high,joint.y)
	var height:=high-low
	if height<1.0 or height>2.5:return {}
	var space:=eye.get_world_3d().direct_space_state
	var visible_bands:=0
	var total:=Vector3.ZERO
	var upper:=-INF
	var lower:=INF
	# Multiple body bands avoid treating a lone occluded limb or a screen sliver as a person.
	for band:float in [.35,.56,.75,.91]:
		var mid:=low+height*band
		var sum:=Vector3.ZERO
		var count:=0
		for joint:Vector3 in joints:
			if absf(joint.y-mid)<height*.095:sum+=joint;count+=1
		if count==0:continue
		var sample:=sum/count
		var sight:=hit(eye,space,body.get_rid(),sample)
		if sight.is_empty() or (sight.has("point") and eye.global_position.distance_to(sight.point)<eye.global_position.distance_to(sample)-.04):continue
		var y:=eye.unproject_position(sample).y
		upper=maxf(upper,y);lower=minf(lower,y)
		visible_bands+=1;total+=sample
	if visible_bands<2 or upper-lower<24.:return {}
	var delta:=body.global_basis.inverse()*(total/visible_bands-eye.global_position)
	return {"turn":atan2(-delta.x,-delta.z),"range":Vector2(delta.x,delta.z).length()}
