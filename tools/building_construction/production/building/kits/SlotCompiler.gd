extends RefCounted
## Resolve a semantic slot only after topology and finish layout are complete.
static func emit(s,q:Dictionary,style)->Dictionary:
	var id:String=q.id
	var choice=style.select(q)
	if choice.is_empty():s.notes.append(id+" · missing compatible recipe");return q
	q.recipe_key=choice.key
	var path=s.layout.overrides.get(id,{}).get("scene","")
	if path!="" and s.scene_ok(path):q.scene=path
	var origin:Vector3=q.p
	match q.kind:
		"CeilingSlot":origin+=Vector3.UP*q.height
		"BeamSlot":origin+=Vector3.UP*(q.height-.15)
		"CeilingLightSlot":origin+=Vector3.UP*(q.height-(.5 if q.variant=="pendant" else .13))
		"WindowSlot":origin+=Vector3.UP*q.low
	q.origin=origin
	if q.has("scene") and q.kind!="DoorSlot":s.socket(id,"custom",origin,{"scene":path,"yaw":q.yaw,"slot":q});return q
	var begin=s.pieces.size();choice.recipe.emit(s,q)
	if q.kind=="WallFinishSlot" and not s.host.volumes.is_empty():
		for i in range(s.pieces.size()-1,begin-1,-1):
			var r=s.pieces[i];var bounds=Transform3D(Basis(Vector3.UP,r.yaw),r.p)*AABB(-r.size*.5,r.size)
			if s.host.blocked(bounds):s.pieces.remove_at(i)
	return q
