extends RefCounted
## The front-facing triangle list is the sole solid source for the rotor.

static func radial(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))

static func band(r0: float, r1: float, y0: float, y1: float, angle: float, span: float, bevel: float = 0.0) -> ArrayMesh:
	var b := minf(bevel, minf((r1-r0)*0.4, (y1-y0)*0.4))
	var profile := PackedVector2Array([Vector2(r0+b,y0),Vector2(r1-b,y0)])
	if b > 0.0:
		profile.append(Vector2(r1,y0+b))
		profile.append(Vector2(r1,y1-b))
	profile.append(Vector2(r1-b,y1))
	profile.append(Vector2(r0+b,y1))
	if b > 0.0:
		profile.append(Vector2(r0,y1-b))
		profile.append(Vector2(r0,y0+b))
	var steps := maxi(1, ceili(span / TAU * 192.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var u := radial(angle + span * float(i)/steps)
		var v := radial(angle + span * float(i+1)/steps)
		for j in profile.size():
			var p := profile[j]
			var q := profile[(j+1) % profile.size()]
			var a := u*p.x + Vector3.UP*p.y
			var c := v*q.x + Vector3.UP*q.y
			tri(st, a, c, u*q.x + Vector3.UP*q.y)
			tri(st, a, v*p.x + Vector3.UP*p.y, c)
	if span < TAU-0.0001:
		var u := radial(angle)
		var v := radial(angle+span)
		for j in range(1, profile.size()-1):
			var p := profile[0]
			var q := profile[j]
			var s := profile[j+1]
			tri(st, u*p.x+Vector3.UP*p.y, u*q.x+Vector3.UP*q.y, u*s.x+Vector3.UP*s.y)
			tri(st, v*p.x+Vector3.UP*p.y, v*s.x+Vector3.UP*s.y, v*q.x+Vector3.UP*q.y)
	return st.commit()

static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c-a).cross(b-a).normalized() # Godot front faces are clockwise.
	for p in [a,b,c]:
		st.set_normal(n)
		st.add_vertex(p)

static func ramp(r0: float, r1: float, a: float, span: float, rise: float, steps: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var u := radial(a + span * float(i)/steps)
		var v := radial(a + span * float(i+1)/steps)
		var p := Vector3.UP * rise * float(i)/steps
		var q := Vector3.UP * rise * float(i+1)/steps
		tri(st,u*r0+p,v*r1+q,v*r0+q)
		tri(st,u*r0+p,u*r1+p,v*r1+q)
	return st.commit()
