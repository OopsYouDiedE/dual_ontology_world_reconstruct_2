@tool
class_name GothicVault3D
extends GothicHallPiece3D
## Clear-span pointed vault over the nave: shell, transverse/diagonal/ridge ribs,
## clerestory lunette webs, keystone bosses. Local origin = inner west-north corner.

@export var size := Vector2(9.4, 20.0):
	set(v): size = v; shape_changed()
@export_range(1, 12) var bays := 5:
	set(v): bays = v; changed()

func shape_key() -> Array: return [size]
func plan_outline() -> PackedVector2Array: return _rect_outline(Rect2(Vector2.ZERO, size))

func _build() -> void:
	var min_x := 0.0
	var max_x := size.x
	var min_z := 0.0
	var max_z := size.y
	var bays_z := maxi(1, bays)
	var bay_len := size.y / float(bays_z)
	var cx := (min_x + max_x) * 0.5
	var hx := (max_x - min_x) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs_x := 20
	var segs_z := bays_z * segs_x
	var grid: Array = []
	for iz in range(segs_z + 1):
		var row: Array = []
		var wz := lerpf(min_z, max_z, float(iz) / float(segs_z))
		var nz := fmod(wz - min_z, bay_len) / bay_len * 2.0 - 1.0
		for ix in range(segs_x + 1):
			var nx := -1.0 + 2.0 * float(ix) / float(segs_x)
			row.append(Vector3(cx + nx * hx, vault_height(nx, nz), wz))
		grid.append(row)
	for iz in segs_z:
		for ix in segs_x:
			_add_quad(st, grid[iz][ix], grid[iz + 1][ix], grid[iz + 1][ix + 1], grid[iz][ix + 1])
	st.generate_normals()
	_commit_mesh(st, mat("vault"), "NaveVaultShell")
	var rib_st := SurfaceTool.new()
	rib_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in range(bays_z + 1):
		var wz := min_z + float(iz) * bay_len
		var pts := PackedVector3Array()
		for ix in range(segs_x + 1):
			var nx := -1.0 + 2.0 * float(ix) / float(segs_x)
			pts.append(Vector3(cx + nx * (hx - PIER_INSET), SPRING_H + pointed_arch_y(nx) - 0.04, wz))
		_sweep_rib(rib_st, pts, 0.13)
		for dz: float in [-0.12, 0.12]:
			var fillet := PackedVector3Array()
			for p in pts: fillet.append(p + Vector3(0, 0.03, dz))
			_sweep_rib(rib_st, fillet, 0.052)
	for bi in bays_z:
		var z0 := min_z + float(bi) * bay_len
		var z1 := z0 + bay_len
		for diag in 2:
			var pts := PackedVector3Array()
			for i in range(segs_x + 1):
				var frac := float(i) / float(segs_x)
				var nx := -1.0 + 2.0 * frac
				var wz := lerpf(z0, z1, frac) if diag == 0 else lerpf(z1, z0, frac)
				pts.append(Vector3(cx + nx * (hx - PIER_INSET), vault_height(nx, nx) - 0.09, wz))
			_sweep_rib(rib_st, pts, 0.085)
		for x: float in [min_x, max_x]:
			var arch := PackedVector3Array()
			var web := SurfaceTool.new(); web.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in range(segs_x + 1):
				var u := float(i) / segs_x
				var p := Vector3(x, vault_height(1, 2 * u - 1), lerpf(z0, z1, u))
				if i > 0:
					var q := arch[i - 1]
					var lo := Vector3(x, SPRING_H - 0.06, q.z)
					var hi := Vector3(x, lo.y, p.z)
					if x == max_x: _add_quad(web, q, p, hi, lo)
					else: _add_quad(web, lo, hi, p, q)
				arch.append(p)
			web.generate_normals(); _commit_mesh(web, mat("wall"), "ClerestoryWeb")
			for i in arch.size(): arch[i].x += 0.10 if x == min_x else -0.10
			_sweep_rib(rib_st, arch, 0.092)
		var boss := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.24; bm.bottom_radius = 0.18; bm.height = 0.18
		boss.mesh = bm
		boss.position = Vector3(cx, CROWN_H - 0.11, (z0 + z1) * 0.5)
		boss.material_override = mat("brass")
		add_child(boss)
	for iz in range(1, bays_z):
		var knot := MeshInstance3D.new()
		var km := SphereMesh.new()
		km.radius = 0.19; km.height = 0.24; km.radial_segments = 8; km.rings = 4
		knot.mesh = km
		knot.position = Vector3(cx, CROWN_H - 0.08, min_z + float(iz) * bay_len)
		knot.material_override = mat("rib")
		add_child(knot)
	_sweep_rib(rib_st, PackedVector3Array([Vector3(cx, CROWN_H + 0.02, min_z + 0.06), Vector3(cx, CROWN_H + 0.02, max_z - 0.06)]), 0.075)
	rib_st.generate_normals()
	_commit_mesh(rib_st, mat("rib"), "NaveVaultRibs")
