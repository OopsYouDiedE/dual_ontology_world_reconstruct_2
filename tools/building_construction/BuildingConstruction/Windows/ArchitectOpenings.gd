extends RefCounted
## Direct statement port of OpeningsKit.createOpeningMesh.
const Geo = preload("../Shared/ArchitectGeometry.gd")

static func build(type: String, width: float, height: float, _bottom: float, rise: float = 0.4, wallThick: float = 0.28) -> Node3D:
	var root = Node3D.new()
	var frameThick = wallThick + 0.05
	var frameW = min(0.12, width * 0.10)
	if type == 'arched_window':
		var sill = Geo.box(Vector3(width + 0.22, 0.09, frameThick + 0.12), "stone")
		sill.position = Vector3(0, 0.045, 0)
		root.add_child(sill)
		var apron = Geo.box(Vector3(width + 0.14, 0.07, frameThick + 0.04), "wood_dark")
		apron.position = Vector3(0, -0.035, 0)
		root.add_child(apron)
		var springY = height - rise
		var jambL = Geo.box(Vector3(frameW, springY, frameThick), "wood_dark")
		jambL.position = Vector3(-width * 0.5 + frameW * 0.5, springY * 0.5, 0)
		root.add_child(jambL)
		var jambR = Geo.box(Vector3(frameW, springY, frameThick), "wood_dark")
		jambR.position = Vector3(width * 0.5 - frameW * 0.5, springY * 0.5, 0)
		root.add_child(jambR)
		var archSegs = 14
		var r = (width - frameW * 2) * 0.5
		var arcPts = []
		for i in range(0, int(archSegs + 1)):
			var th = PI * (float(i) / archSegs)
			arcPts.append([-cos(th) * r, springY + sin(th) * (rise - frameW * 0.5)])
		for i in range(0, int(archSegs)):
			var pA = arcPts[i]
			var pB = arcPts[i + 1]
			var segLen = Vector2(pB[0] - pA[0], pB[1] - pA[1]).length() + 0.015
			var seg = Geo.box(Vector3(segLen, frameW * 0.9, frameThick * 0.95), "wood_dark")
			seg.position = Vector3((pA[0] + pB[0]) * 0.5, (pA[1] + pB[1]) * 0.5, 0)
			seg.rotation.z = atan2(pB[1] - pA[1], pB[0] - pA[0])
			root.add_child(seg)
		for j in range(1, int(3 + 1)):
			var th = PI * (float(j) / 4.0)
			var targetX = r * cos(th)
			var targetY = springY + (rise - frameW) * sin(th)
			var rayLen = Vector2(targetX, targetY - springY).length()
			var ray = Geo.box(Vector3(rayLen, 0.03, 0.035), "wood")
			ray.position = Vector3(targetX * 0.5, springY + (targetY - springY) * 0.5, 0)
			ray.rotation.z = atan2(targetY - springY, targetX)
			root.add_child(ray)
		var mullV1 = Geo.box(Vector3(0.035, springY, 0.035), "wood")
		mullV1.position = Vector3(-width * 0.18, springY * 0.5, 0)
		root.add_child(mullV1)
		var mullV2 = Geo.box(Vector3(0.035, springY, 0.035), "wood")
		mullV2.position = Vector3(width * 0.18, springY * 0.5, 0)
		root.add_child(mullV2)
		var transom1 = Geo.box(Vector3(width - frameW * 2, 0.04, 0.04), "wood")
		transom1.position = Vector3(0, springY * 0.5, 0)
		root.add_child(transom1)
		var springTransom = Geo.box(Vector3(width - frameW * 2, 0.05, frameThick * 0.6), "wood_dark")
		springTransom.position = Vector3(0, springY, 0)
		root.add_child(springTransom)
		var glass_vertices = []
		for i in range(archSegs):
			var a = arcPts[i]
			var b = arcPts[i+1]
			Geo.quad(glass_vertices,Vector3(a[0],0.07,0),Vector3(b[0],0.07,0),Vector3(b[0],b[1],0),Vector3(a[0],a[1],0))
		root.add_child(Geo.surface(glass_vertices,"glass"))
	elif type == 'rectangular_window':
		var sill = Geo.box(Vector3(width + 0.18, 0.08, frameThick + 0.08), "stone")
		sill.position = Vector3(0, 0.04, 0)
		root.add_child(sill)
		var top = Geo.box(Vector3(width - frameW * 2, frameW, frameThick), "wood_dark")
		top.position = Vector3(0, height - frameW * 0.5, 0)
		root.add_child(top)
		var jambL = Geo.box(Vector3(frameW, height - 0.08, frameThick), "wood_dark")
		jambL.position = Vector3(-width * 0.5 + frameW * 0.5, (height + 0.08) * 0.5, 0)
		root.add_child(jambL)
		var jambR = Geo.box(Vector3(frameW, height - 0.08, frameThick), "wood_dark")
		jambR.position = Vector3(width * 0.5 - frameW * 0.5, (height + 0.08) * 0.5, 0)
		root.add_child(jambR)
		var glass = Geo.box(Vector3(width - frameW * 2, height - frameW * 2 - 0.08, 0.015), "glass")
		glass.position = Vector3(0, (height + 0.08) * 0.5, 0)
		root.add_child(glass)
		var mullV = Geo.box(Vector3(0.035, height - frameW * 2 - 0.08, 0.035), "wood")
		mullV.position = Vector3(0, (height + 0.08) * 0.5, 0)
		root.add_child(mullV)
		var mullH = Geo.box(Vector3(width - frameW * 2, 0.035, 0.035), "wood")
		mullH.position = Vector3(0, (height + 0.08) * 0.5, 0)
		root.add_child(mullH)
	elif type == 'round_window':
		var r = min(width, height) * 0.46
		var segs = 16
		for i in range(0, int(segs)):
			var a0 = (float(i) / segs) * PI * 2
			var a1 = (float(i + 1) / segs) * PI * 2
			var pA = [cos(a0) * r, sin(a0) * r]
			var pB = [cos(a1) * r, sin(a1) * r]
			var seg = Geo.box(Vector3(frameW, 0.06, frameThick), "wood_dark")
			seg.position = Vector3((pA[0] + pB[0]) * 0.5, height * 0.5 + (pA[1] + pB[1]) * 0.5, 0)
			seg.rotation.z = atan2(pB[1] - pA[1], pB[0] - pA[0])
			root.add_child(seg)
		var glass = Geo.box(Vector3(r * 1.85, r * 1.85, 0.015), "glass")
		glass.position = Vector3(0, height * 0.5, 0)
		root.add_child(glass)
		var mullH = Geo.box(Vector3(r * 1.9, 0.03, 0.03), "wood")
		mullH.position = Vector3(0, height * 0.5, 0)
		root.add_child(mullH)
		var mullV = Geo.box(Vector3(0.03, r * 1.9, 0.03), "wood")
		mullV.position = Vector3(0, height * 0.5, 0)
		root.add_child(mullV)
	elif type == 'closed_door' or type == 'arched_closed_door':
		var headerH = frameW * 1.25
		var jambL = Geo.box(Vector3(frameW, height, frameThick + 0.02), "wood_dark")
		jambL.position = Vector3(-width * 0.5 + frameW * 0.5, height * 0.5, 0)
		root.add_child(jambL)
		var jambR = Geo.box(Vector3(frameW, height, frameThick + 0.02), "wood_dark")
		jambR.position = Vector3(width * 0.5 - frameW * 0.5, height * 0.5, 0)
		root.add_child(jambR)
		var lintel = Geo.box(Vector3(width + 0.14, headerH, frameThick + 0.04), "wood_dark")
		lintel.position = Vector3(0, height + headerH * 0.5, 0)
		root.add_child(lintel)
		var cornice = Geo.box(Vector3(width + 0.22, 0.08, frameThick + 0.08), "wood")
		cornice.position = Vector3(0, height + headerH + 0.04, 0)
		root.add_child(cornice)
		var leafW = width - frameW * 2 - 0.02
		var leafH = height - 0.02
		var leaf = Geo.box(Vector3(leafW, leafH, 0.06), "wood")
		leaf.position = Vector3(0, leafH * 0.5 + 0.01, 0)
		root.add_child(leaf)
		var panelW = leafW * 0.72
		var lowerH = leafH * 0.35
		var upperH = leafH * 0.45
		var panelL = Geo.box(Vector3(panelW, lowerH, 0.085), "wood_dark")
		panelL.position = Vector3(0, 0.12 + lowerH * 0.5, 0)
		root.add_child(panelL)
		var panelU = Geo.box(Vector3(panelW, upperH, 0.085), "wood_dark")
		panelU.position = Vector3(0, leafH - 0.08 - upperH * 0.5, 0)
		root.add_child(panelU)
		var hPlate = Geo.box(Vector3(0.045, 0.18, 0.095), "gold")
		hPlate.position = Vector3(width * 0.32, 1.05, 0)
		root.add_child(hPlate)
		var hLever = Geo.box(Vector3(0.12, 0.022, 0.11), "gold")
		hLever.position = Vector3(width * 0.32 - 0.04, 1.07, 0.01)
		root.add_child(hLever)
	elif type == 'double_door':
		var headerH = frameW * 1.35
		var jambL = Geo.box(Vector3(frameW, height, frameThick + 0.03), "wood_dark")
		jambL.position = Vector3(-width * 0.5 + frameW * 0.5, height * 0.5, 0)
		root.add_child(jambL)
		var jambR = Geo.box(Vector3(frameW, height, frameThick + 0.03), "wood_dark")
		jambR.position = Vector3(width * 0.5 - frameW * 0.5, height * 0.5, 0)
		root.add_child(jambR)
		var lintel = Geo.box(Vector3(width + 0.18, headerH, frameThick + 0.06), "wood_dark")
		lintel.position = Vector3(0, height + headerH * 0.5, 0)
		root.add_child(lintel)
		var cornice = Geo.box(Vector3(width + 0.28, 0.10, frameThick + 0.10), "wood")
		cornice.position = Vector3(0, height + headerH + 0.05, 0)
		root.add_child(cornice)
		var singleW = (width - frameW * 2 - 0.04) * 0.5
		var leafH = height - 0.02
		for sign in [-1, 1]:
			var cx = sign * (singleW * 0.5 + 0.01)
			var leaf = Geo.box(Vector3(singleW, leafH, 0.06), "wood")
			leaf.position = Vector3(cx, leafH * 0.5 + 0.01, 0)
			root.add_child(leaf)
			var pW = singleW * 0.72
			var lowerH = leafH * 0.35
			var upperH = leafH * 0.45
			var pL = Geo.box(Vector3(pW, lowerH, 0.085), "wood_dark")
			pL.position = Vector3(cx, 0.12 + lowerH * 0.5, 0)
			root.add_child(pL)
			var pU = Geo.box(Vector3(pW, upperH, 0.085), "wood_dark")
			pU.position = Vector3(cx, leafH - 0.08 - upperH * 0.5, 0)
			root.add_child(pU)
			var hPlate = Geo.box(Vector3(0.04, 0.18, 0.095), "gold")
			hPlate.position = Vector3(sign * 0.06, 1.05, 0)
			root.add_child(hPlate)
			var hLever = Geo.box(Vector3(0.10, 0.022, 0.11), "gold")
			hLever.position = Vector3(sign * 0.06 - sign * 0.03, 1.07, 0.01)
			root.add_child(hLever)
	elif type == 'portal_arch':
		var headerH = frameW * 1.4
		var jambL = Geo.box(Vector3(frameW * 1.2, height, frameThick * 1.1), "wood_dark")
		jambL.position = Vector3(-width * 0.5 + frameW * 0.6, height * 0.5, 0)
		root.add_child(jambL)
		var jambR = Geo.box(Vector3(frameW * 1.2, height, frameThick * 1.1), "wood_dark")
		jambR.position = Vector3(width * 0.5 - frameW * 0.6, height * 0.5, 0)
		root.add_child(jambR)
		var header = Geo.box(Vector3(width + 0.16, headerH, frameThick * 1.15), "wood_dark")
		header.position = Vector3(0, height + headerH * 0.5, 0)
		root.add_child(header)
	return root
