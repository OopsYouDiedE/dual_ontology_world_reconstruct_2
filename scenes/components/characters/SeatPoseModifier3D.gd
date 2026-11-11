extends SkeletonModifier3D
## Complete-skeleton seat contact. Bone lengths and scales are never changed.
var body: CharacterBody3D
var target: Node3D
var spec: Dictionary
var elapsed := 0.0
var duration := 1.0
var failure := ""
var settled := false
var external_clock := false
var reversing := false
var reverse_start := 1.0
var _bones: Dictionary = {}
var _initial: Dictionary = {}
var _sole_offsets: Dictionary = {}
var _seat_offset := 0.0
var applied_seat_offset := 0.0
var contact_locked := false
var _seat_horizontal := Vector3.ZERO
var _blend := 0.0
var surface_audit: Dictionary = {}
var _pose_revision := 0
var _surface_cache: Dictionary = {}
var _support_shape: CollisionShape3D

static func prepare_geometry(owner_body: CharacterBody3D) -> void:
	var geometry: Dictionary={}
	for mesh: MeshInstance3D in owner_body.visual.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null or mesh.skin==null: continue
		for surface in mesh.mesh.get_surface_count(): geometry[str(mesh.get_instance_id())+":"+str(surface)]=mesh.mesh.surface_get_arrays(surface)
	owner_body.set_meta("seat_geometry",geometry)

func source_arrays(mesh: MeshInstance3D,surface: int) -> Array:
	var geometry: Dictionary=body.get_meta("seat_geometry",{})
	var key:=str(mesh.get_instance_id())+":"+str(surface)
	if not geometry.has(key):
		geometry[key]=mesh.mesh.surface_get_arrays(surface)
		body.set_meta("seat_geometry",geometry)
	return geometry[key]

func on_support(point: Vector3) -> bool:
	if _blend<0.95: return true
	var local: Vector3=_support_shape.global_transform.affine_inverse()*point
	var half: Vector3=_support_shape.shape.size*0.5
	return absf(local.x)<=half.x and absf(local.z)<=half.z

func deformed_vertices(mesh: MeshInstance3D,surface: int) -> PackedVector3Array:
	var key := str(mesh.get_instance_id())+":"+str(surface)
	if _surface_cache.has(key) and int(_surface_cache[key].revision)==_pose_revision: return _surface_cache[key].vertices
	var arrays: Array = source_arrays(mesh,surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var joints = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var transforms: Array[Transform3D] = []
	var skeleton := get_skeleton()
	for binding in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(binding)
		var name := str(mesh.skin.get_bind_name(binding))
		if not name.is_empty(): bone=skeleton.find_bone(name)
		transforms.append(skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(binding))
	var count := int(joints.size()/vertices.size())
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for index in vertices.size():
		var position := Vector3.ZERO
		for slot in count:
			var weight := float(weights[index*count+slot])
			if weight>0: position+=(transforms[int(joints[index*count+slot])]*vertices[index])*weight
		result[index]=position
	_surface_cache[key]={"revision":_pose_revision,"vertices":result}
	return result

func _init() -> void:
	active = false

func begin(owner_body: CharacterBody3D, object: Node3D, declaration: Dictionary, seconds: float) -> bool:
	body = owner_body
	target = object
	spec = declaration.duplicate(true)
	var skeleton := get_skeleton()
	if skeleton == null:
		failure = "seat-skeleton-unavailable"
		return false
	for key in {"hips":"Hips","left_thigh":"LeftUpLeg","left_knee":"LeftLeg","left_foot":"LeftFoot","left_toe":"LeftToeBase","right_thigh":"RightUpLeg","right_knee":"RightLeg","right_foot":"RightFoot","right_toe":"RightToeBase","head":"Head"}:
		var wanted: String = {"hips":"Hips","left_thigh":"LeftUpLeg","left_knee":"LeftLeg","left_foot":"LeftFoot","left_toe":"LeftToeBase","right_thigh":"RightUpLeg","right_knee":"RightLeg","right_foot":"RightFoot","right_toe":"RightToeBase","head":"Head"}[key]
		for index in skeleton.get_bone_count():
			if str(skeleton.get_bone_name(index)).trim_prefix("mixamorig:").trim_prefix("mixamorig_") == wanted:
				_bones[key] = index
				break
		if not _bones.has(key):
			failure = "seat-bone-unavailable:" + wanted
			return false
	for key in ["seat_slot", "seat_surface_slot", "left_foot_slot", "right_foot_slot"]:
		if _slot(key) == null:
			failure = "seat-marker-unavailable:" + key
			return false
	var support_y:=_slot("seat_surface_slot").global_position.y
	for shape: CollisionShape3D in target.find_children("*","CollisionShape3D",true,false):
		if shape.shape is BoxShape3D and shape.get_parent() is StaticBody3D:
			var top: Vector3=shape.global_transform*Vector3(0,shape.shape.size.y*.5,0)
			if absf(top.y-support_y)<.005: _support_shape=shape;break
	if _support_shape==null:
		failure="seat-support-shape-unavailable"
		return false
	for key in ["hips", "left_foot", "right_foot"]: _initial[key] = _position(key)
	for side in ["left","right"]: _initial[side+"_foot_basis"]=skeleton.global_basis*skeleton.get_bone_global_pose(int(_bones[side+"_foot"])).basis
	for side in ["left","right"]: _initial[side+"_toe_pose"]=skeleton.get_bone_pose(int(_bones[side+"_toe"]))
	var surface := measure_surface("seat")
	var left := measure_surface("left")
	var right := measure_surface("right")
	if not surface.is_finite() or not left.is_finite() or not right.is_finite():
		failure = "seat-skinned-surface-unavailable:" + ("pelvis" if not surface.is_finite() else "left-foot" if not left.is_finite() else "right-foot")
		return false
	_seat_offset = _position("hips").y - surface.y
	_seat_horizontal=body.visual.global_basis.z*float(spec.get("pelvis_forward_m",0.0))
	_seat_horizontal.y=0
	applied_seat_offset=_seat_offset
	if _seat_offset <= 0.0 or _seat_offset > 0.20:
		failure = "seat-pelvis-surface-offset-invalid:%.5f" % _seat_offset
		return false
	_sole_offsets.left = _position("left_foot") - left
	_sole_offsets.right = _position("right_foot") - right
	_initial.left_sole = left
	_initial.right_sole = right
	duration = maxf(0.1, seconds)
	elapsed = 0.0
	failure = ""
	settled = false
	active = true
	return true

func _slot(key: String) -> Marker3D:
	if not is_instance_valid(target) or not target.has_method("resolve_interaction_slot"): return null
	return target.resolve_interaction_slot(str(spec.get(key, ""))) as Marker3D

func _position(key: String) -> Vector3:
	var skeleton := get_skeleton()
	return skeleton.global_transform * skeleton.get_bone_global_pose(int(_bones[key])).origin

func foot_position(side: String) -> Vector3:
	return _slot(side+"_foot_slot").global_position+body.visual.global_basis.z*float(spec.get("foot_forward_m",0.0))

func _process_modification() -> void:
	if not active or not is_instance_valid(body) or not is_instance_valid(target): return
	var seat := _slot("seat_surface_slot")
	var seat_position := _slot("seat_slot")
	var left := _slot("left_foot_slot")
	var right := _slot("right_foot_slot")
	if seat == null or seat_position == null or left == null or right == null:
		failure = "seat-marker-unavailable"
		return
	if not external_clock: elapsed += get_process_delta_time()
	_blend = smoothstep(0.0, 1.0, clampf(elapsed / duration, 0.0, 1.0))
	if reversing: _blend = reverse_start * (1.0 - _blend)
	applied_seat_offset=_seat_offset
	var pelvis: Vector3 = _initial.hips.lerp(seat_position.global_position + _seat_horizontal + Vector3.UP * applied_seat_offset, _blend)
	var skeleton := get_skeleton()
	var hip := skeleton.get_bone_global_pose(int(_bones.hips))
	hip.origin = skeleton.global_transform.affine_inverse() * pelvis
	skeleton.set_bone_global_pose(int(_bones.hips), hip)
	for side in ["left", "right"]:
		var marker: Marker3D = left if side == "left" else right
		var desired: Vector3 = _initial[side + "_sole"].lerp(foot_position(side), _blend) + _sole_offsets[side]
		if not _solve_leg(side, desired):
			failure = "seat-leg-target-unreachable:" + side
			return
	settled = elapsed >= duration
	_pose_revision+=1
	if not reversing and not contact_locked and _blend>0.95:
		var contact := measure_surface("seat")
		if contact.is_finite():
			_seat_offset=clampf(_seat_offset+(_slot("seat_surface_slot").global_position.y-contact.y)*_blend*0.5,0.01,0.20)

func _solve_leg(side: String, foot_target: Vector3) -> bool:
	var skeleton := get_skeleton()
	var hip := _position(side + "_thigh")
	var knee := _position(side + "_knee")
	var ankle := _position(side + "_foot")
	var upper := hip.distance_to(knee)
	var lower := knee.distance_to(ankle)
	var vector := foot_target - hip
	var distance := vector.length()
	if distance < absf(upper - lower) + 0.0001 or distance > upper + lower + 0.001: return false
	var direction := vector.normalized()
	distance = minf(distance, upper + lower - 0.000001)
	var forward: Vector3 = body.visual.global_transform.basis.z.normalized()
	var bend := forward - direction * forward.dot(direction)
	if bend.length_squared() < 0.0001: return false
	bend = bend.normalized()
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	var desired_knee := hip + direction * along + bend * height
	_rotate_segment(side + "_thigh", knee - hip, desired_knee - hip)
	knee = _position(side + "_knee")
	_rotate_segment(side + "_knee", _position(side + "_foot") - knee, foot_target - knee)
	# Preserve the measured standing sole orientation. Parent-leg rotation must
	# not rotate the sole offset used to place the real mesh on its floor marker.
	var foot_pose := skeleton.get_bone_global_pose(int(_bones[side+"_foot"]))
	foot_pose.basis=skeleton.global_basis.inverse()*_initial[side+"_foot_basis"]
	skeleton.set_bone_global_pose(int(_bones[side+"_foot"]),foot_pose)
	skeleton.set_bone_pose(int(_bones[side+"_toe"]),_initial[side+"_toe_pose"])
	return true

func _rotate_segment(key: String, current: Vector3, desired: Vector3) -> void:
	if current.length_squared() < 0.0000001 or desired.length_squared() < 0.0000001: return
	var skeleton := get_skeleton()
	var inverse := skeleton.global_transform.basis.inverse()
	var rotation := Quaternion((inverse * current).normalized(), (inverse * desired).normalized())
	var pose := skeleton.get_bone_global_pose(int(_bones[key]))
	pose.basis = Basis(rotation) * pose.basis
	skeleton.set_bone_global_pose(int(_bones[key]), pose)

# Measure the rendered, deformed mesh, restricted to vertices with actual
# pelvis/thigh or foot/toe skin weights. A bone origin is never a contact claim.
func measure_surface(region: String) -> Vector3:
	var skeleton := get_skeleton()
	if skeleton == null: return Vector3.INF
	var selected: Array[int] = []
	if region == "seat":
		selected.append(int(_bones.hips))
		selected.append(int(_bones.left_thigh))
		selected.append(int(_bones.right_thigh))
	else:
		selected.append(int(_bones[region + "_foot"]))
		selected.append(int(_bones[region + "_toe"]))
	var center := _position("hips" if region == "seat" else region + "_foot")
	var points: Array[Vector3] = []
	var minimum := INF
	var audit := {"meshes":0,"vertices":0,"weighted":0,"center":[center.x,center.y,center.z],"bind_samples":[],"weighted_points":[],"triangle_indices":0}
	for mesh: MeshInstance3D in body.visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.skin == null: continue
		audit.meshes+=1
		if audit.bind_samples.is_empty():
			for binding in mini(5,mesh.skin.get_bind_count()): audit.bind_samples.append({"bone":mesh.skin.get_bind_bone(binding),"name":str(mesh.skin.get_bind_name(binding))})
		for surface in mesh.mesh.get_surface_count():
			var original: Array = source_arrays(mesh,surface)
			var vertices := deformed_vertices(mesh,surface)
			var joints = original[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = original[Mesh.ARRAY_WEIGHTS]
			if not (joints is PackedInt32Array or joints is PackedFloat32Array): continue
			if vertices.is_empty() or weights.size() != joints.size() or joints.size() % vertices.size() != 0: continue
			var count := int(joints.size() / vertices.size())
			var influences := PackedFloat32Array()
			influences.resize(vertices.size())
			for index in vertices.size():
				audit.vertices+=1
				var influence := 0.0
				for slot in count:
					var binding: int = joints[index * count + slot]
					if binding < 0 or binding >= mesh.skin.get_bind_count(): continue
					var bone := mesh.skin.get_bind_bone(binding)
					var bone_name := str(mesh.skin.get_bind_name(binding))
					if not bone_name.is_empty(): bone = skeleton.find_bone(bone_name)
					if bone in selected: influence += weights[index * count + slot]
				influences[index]=influence
				if influence < (0.65 if region == "seat" else 0.5): continue
				audit.weighted+=1
				var point: Vector3 = mesh.global_transform * vertices[index]
				if region=="seat" and audit.weighted_points.size()<32: audit.weighted_points.append([point.x,point.y,point.z])
				if region == "seat" and (Vector2(point.x-center.x, point.z-center.z).length() > body.nominal_height*0.22 or point.y < center.y-0.20 or point.y > center.y or not on_support(point)): continue
				minimum = minf(minimum, point.y)
				points.append(point)
			if region == "seat" and points.is_empty():
				# Sparse meshes can have no vertex beneath the pelvis. Sample the
				# actual deformed triangles there, retaining their skin provenance.
				var indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
				audit.triangle_indices+=indices.size()
				for triangle in range(0,indices.size()-2,3):
					var a := indices[triangle]
					var b := indices[triangle+1]
					var c := indices[triangle+2]
					if (influences[a]+influences[b]+influences[c])/3.0<0.5: continue
					var va: Vector3 = mesh.global_transform*vertices[a]
					var vb: Vector3 = mesh.global_transform*vertices[b]
					var vc: Vector3 = mesh.global_transform*vertices[c]
					for x in [-0.145,0.0,0.145]:
						for z in [-0.145,0.0,0.145]:
							var ray := center+Vector3(x,0.02,z)
							var hit = Geometry3D.segment_intersects_triangle(ray,ray-Vector3.UP*0.22,va,vb,vc)
							if hit == null or not on_support(hit): continue
							minimum=minf(minimum,hit.y)
							points.append(hit)
	audit["selected_bones"]=selected
	audit["points"]=points.size()
	surface_audit[region]=audit
	if points.is_empty():
		body.set_meta("seat_surface_audit",surface_audit)
		return Vector3.INF
	var total := Vector3.ZERO
	var count := 0
	for point in points:
		if point.y <= minimum + 0.008:
			total += point
			count += 1
	return total / float(count) if count > 0 else Vector3.INF

func measurement() -> Dictionary:
	var pelvis_surface := measure_surface("seat")
	var left := measure_surface("left")
	var right := measure_surface("right")
	if not pelvis_surface.is_finite() or not left.is_finite() or not right.is_finite(): return {"settled":false,"reason":"seat-deformed-surface-unavailable"}
	return {"settled":settled and failure.is_empty(),"reason":failure,
		"hips":_position("hips"),"left_knee":_position("left_knee"),"right_knee":_position("right_knee"),
		"left_ankle":_position("left_foot"),"right_ankle":_position("right_foot"),
		"seat_error_m":absf(pelvis_surface.y - _slot("seat_surface_slot").global_position.y),
		"left_foot_error_m":left.distance_to(foot_position("left")),
		"right_foot_error_m":right.distance_to(foot_position("right")),
		"pelvis_surface_world":[pelvis_surface.x,pelvis_surface.y,pelvis_surface.z],
		"left_sole_world":[left.x,left.y,left.z],"right_sole_world":[right.x,right.y,right.z]}

func penetrates_seat_structure() -> bool:
	var solids: Array[CollisionShape3D] = []
	for shape: CollisionShape3D in target.find_children("*", "CollisionShape3D", true, false):
		if shape.shape is BoxShape3D and shape.get_parent() is StaticBody3D and (shape.get_parent().collision_layer & 1) != 0: solids.append(shape)
	for mesh: MeshInstance3D in body.visual.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.skin == null: continue
		for surface in mesh.mesh.get_surface_count():
			var vertices := deformed_vertices(mesh,surface)
			for vertex_index in vertices.size():
				var vertex := vertices[vertex_index]
				var world: Vector3 = mesh.global_transform * vertex
				for shape in solids:
					var local: Vector3 = shape.global_transform.affine_inverse() * world
					var inside: Vector3 = (shape.shape as BoxShape3D).size * 0.5 - Vector3.ONE * 0.008
					if absf(local.x) < inside.x and absf(local.y) < inside.y and absf(local.z) < inside.z:
						var arrays: Array=source_arrays(mesh,surface)
						var joints=arrays[Mesh.ARRAY_BONES]
						var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
						var count:=int(joints.size()/vertices.size())
						var bindings: Array=[]
						for slot in count:
							var weight:=weights[vertex_index*count+slot]
							if weight>0: bindings.append({"bone":str(mesh.skin.get_bind_name(joints[vertex_index*count+slot])),"weight":weight})
						body.set_meta("seat_penetration",{"shape":str(shape.get_path()),"point":[world.x,world.y,world.z],"local":[local.x,local.y,local.z],"size":[shape.shape.size.x,shape.shape.size.y,shape.shape.size.z],"bindings":bindings})
						return true
	return false
