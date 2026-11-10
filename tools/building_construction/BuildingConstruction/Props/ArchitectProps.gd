extends RefCounted
## Statement-for-statement native port of buildSingleProp3D.
const Geo = preload("../Shared/ArchitectGeometry.gd")
const Plant = preload("ArchitectPlant.gd")

static func build(pObj: Dictionary) -> Node3D:
	var type = pObj.kind
	var position_x = pObj.x
	var position_z = pObj.z
	var baseY = pObj.get("y",0)
	var yaw = pObj.get("yaw",0)
	var params = pObj.get("params",{})
	var root = Node3D.new()
	if type == "planter": root = Plant.build(params)
	elif type == "pedestal":
		var pw = params.get("width",0.52)
		var ph = params.get("height",0.75)
		var foot = Geo.box(Vector3(pw * 1.14, 0.12, pw * 1.14), "wood_light")
		foot.position.y = 0.06
		root.add_child(foot)
		var plinth = Geo.box(Vector3(pw, 0.14, pw), "wood")
		plinth.position.y = 0.19
		root.add_child(plinth)
		var shaft = Geo.box(Vector3(pw * 0.78, ph - 0.28, pw * 0.78), "wood")
		shaft.position.y = 0.26 + (ph - 0.28) * 0.5
		root.add_child(shaft)
		var panelF = Geo.box(Vector3(pw * 0.48, (ph - 0.34) * 0.75, 0.02), "wood_dark")
		panelF.position = Vector3(0, 0.26 + (ph - 0.28) * 0.5, pw * 0.39 + 0.01)
		root.add_child(panelF)
		var neck = Geo.box(Vector3(pw * 0.90, 0.08, pw * 0.90), "wood_dark")
		neck.position.y = ph - 0.08
		root.add_child(neck)
		var cap = Geo.box(Vector3(pw * 1.16, 0.10, pw * 1.16), "wood_light")
		cap.position.y = ph - 0.01
		root.add_child(cap)
	elif type == 'chest':
		var cw = params.get("chest_w",0.95)
		var cd = params.get("chest_d",0.55)
		var ch = params.get("chest_h",0.50)
		var body = Geo.box(Vector3(cw, ch * 0.88, cd), "wood")
		body.position.y = ch * 0.44
		root.add_child(body)
		var lid = Geo.box(Vector3(cw + 0.04, 0.08, cd + 0.04), "wood_light")
		lid.position.y = ch * 0.88 + 0.04
		root.add_child(lid)
		var band1 = Geo.box(Vector3(0.06, ch + 0.02, cd + 0.02), "stone_dark")
		band1.position = Vector3(-cw * 0.32, ch * 0.48, 0)
		root.add_child(band1)
		var band2 = Geo.box(Vector3(0.06, ch + 0.02, cd + 0.02), "stone_dark")
		band2.position = Vector3(cw * 0.32, ch * 0.48, 0)
		root.add_child(band2)
		var lock = Geo.box(Vector3(0.12, 0.10, 0.03), "gold")
		lock.position = Vector3(0, ch * 0.78, cd * 0.5 + 0.015)
		root.add_child(lock)
	elif type == 'table':
		var tw = params.get("table_w",1.8)
		var td = params.get("table_d",0.95)
		var th = params.get("table_h",0.75)
		var topH = 0.05
		var top = Geo.box(Vector3(tw, topH, td), "wood_light")
		top.position.y = th - topH * 0.5
		root.add_child(top)
		var undercut = Geo.box(Vector3(tw - 0.06, 0.02, td - 0.06), "wood_dark")
		undercut.position.y = th - topH - 0.01
		root.add_child(undercut)
		var apronH = 0.11
		var apronL = Geo.box(Vector3(0.03, apronH, td - 0.16), "wood")
		apronL.position = Vector3(-tw * 0.5 + 0.07, th - topH - 0.02 - apronH * 0.5, 0)
		root.add_child(apronL)
		var apronR = Geo.box(Vector3(0.03, apronH, td - 0.16), "wood")
		apronR.position = Vector3(tw * 0.5 - 0.07, th - topH - 0.02 - apronH * 0.5, 0)
		root.add_child(apronR)
		var apronB = Geo.box(Vector3(tw - 0.16, apronH, 0.03), "wood")
		apronB.position = Vector3(0, th - topH - 0.02 - apronH * 0.5, -td * 0.5 + 0.07)
		root.add_child(apronB)
		var drawer = Geo.box(Vector3(tw - 0.18, apronH - 0.01, 0.03), "wood_light")
		drawer.position = Vector3(0, th - topH - 0.02 - apronH * 0.5, td * 0.5 - 0.07)
		root.add_child(drawer)
		for kx in [-0.28, 0.28]:
			var knob = Geo.mesh(Geo.cylinder(0.018, 0.018, 0.03, 8), "gold")
			knob.rotation.x = PI * 0.5
			knob.position = Vector3(kx, th - topH - 0.02 - apronH * 0.5, td * 0.5 - 0.045)
			root.add_child(knob)
		var legW = 0.068
		var legH = th - topH - 0.02
		var lx = tw * 0.5 - legW * 0.5 - 0.03
		var lz = td * 0.5 - legW * 0.5 - 0.03
		for pair1 in [[-lx, -lz], [lx, -lz], [-lx, lz], [lx, lz]]:
			var sx = pair1[0]
			var sz = pair1[1]
			var leg = Geo.box(Vector3(legW, legH, legW), "wood")
			leg.position = Vector3(sx, legH * 0.5, sz)
			root.add_child(leg)
	elif type == 'chair':
		var sw = params.get("seat_w",0.48)
		var sd = params.get("seat_d",0.48)
		var seatH = 0.45
		var seat = Geo.box(Vector3(sw, 0.04, sd), "wood")
		seat.position.y = seatH
		root.add_child(seat)
		var cushion = Geo.box(Vector3(sw - 0.04, 0.03, sd - 0.04), "green")
		cushion.position.y = seatH + 0.03
		root.add_child(cushion)
		var legW = 0.042
		var lx = sw * 0.5 - legW * 0.5
		var lz = sd * 0.5 - legW * 0.5
		for sx in [-lx, lx]:
			var fleg = Geo.box(Vector3(legW, seatH, legW), "wood")
			fleg.position = Vector3(sx, seatH * 0.5, lz)
			root.add_child(fleg)
		var backH = 0.52
		for sx in [-lx, lx]:
			var bpost = Geo.box(Vector3(legW, seatH + backH, legW), "wood")
			bpost.position = Vector3(sx, (seatH + backH) * 0.5, -lz)
			root.add_child(bpost)
		var topRail = Geo.box(Vector3(sw, 0.06, 0.03), "wood_light")
		topRail.position = Vector3(0, seatH + backH - 0.03, -lz)
		root.add_child(topRail)
		for kx in [-sw * 0.22, 0, sw * 0.22]:
			var slat = Geo.box(Vector3(0.025, backH - 0.12, 0.015), "wood")
			slat.position = Vector3(kx, seatH + backH * 0.5, -lz)
			root.add_child(slat)
		var stY = seatH * 0.35
		var stL = Geo.box(Vector3(0.02, 0.02, sd - 0.08), "wood_dark")
		stL.position = Vector3(-lx, stY, 0)
		root.add_child(stL)
		var stR = Geo.box(Vector3(0.02, 0.02, sd - 0.08), "wood_dark")
		stR.position = Vector3(lx, stY, 0)
		root.add_child(stR)
	elif type == 'bench':
		var bl = params.get("bench_len",1.6)
		var bw = params.get("bench_w",0.50)
		var seatH = 0.44
		var backH = 0.48
		var seat = Geo.box(Vector3(bl, 0.04, bw), "wood")
		seat.position.y = seatH
		root.add_child(seat)
		var cushion = Geo.box(Vector3(bl - 0.06, 0.03, bw - 0.06), "green")
		cushion.position.y = seatH + 0.03
		root.add_child(cushion)
		var legW = 0.048
		var lx = bl * 0.5 - legW * 0.5
		var lz = bw * 0.5 - legW * 0.5
		for sx in [-lx, lx]:
			var fleg = Geo.box(Vector3(legW, seatH, legW), "wood")
			fleg.position = Vector3(sx, seatH * 0.5, lz)
			root.add_child(fleg)
			var bpost = Geo.box(Vector3(legW, seatH + backH, legW), "wood")
			bpost.position = Vector3(sx, (seatH + backH) * 0.5, -lz)
			root.add_child(bpost)
			var arm = Geo.box(Vector3(0.04, 0.03, bw), "wood_light")
			arm.position = Vector3(sx, seatH + 0.22, 0)
			root.add_child(arm)
		var crest = Geo.box(Vector3(bl, 0.06, 0.03), "wood_light")
		crest.position = Vector3(0, seatH + backH - 0.03, -lz)
		root.add_child(crest)
		for i in range(0, int(7)):
			var slatX = -bl * 0.42 + i * (bl * 0.84 / 6)
			var slat = Geo.box(Vector3(0.028, backH - 0.12, 0.016), "wood")
			slat.position = Vector3(slatX, seatH + backH * 0.5, -lz)
			root.add_child(slat)
	elif type == 'bed':
		var bw = params.get("bed_w",1.8)
		var bl = params.get("bed_l",2.1)
		var headH = params.get("head_h",1.35)
		var footH = 0.65
		var frameH = 0.32
		var headboard = Geo.box(Vector3(bw + 0.08, headH, 0.08), "wood")
		headboard.position = Vector3(0, headH * 0.5, -bl * 0.5 + 0.04)
		root.add_child(headboard)
		var headInset = Geo.box(Vector3(bw - 0.16, headH * 0.65, 0.02), "wood_dark")
		headInset.position = Vector3(0, headH * 0.52, -bl * 0.5 + 0.08)
		root.add_child(headInset)
		var footboard = Geo.box(Vector3(bw + 0.08, footH, 0.08), "wood")
		footboard.position = Vector3(0, footH * 0.5, bl * 0.5 - 0.04)
		root.add_child(footboard)
		for sx in [-bw * 0.5 + 0.02, bw * 0.5 - 0.02]:
			var rail = Geo.box(Vector3(0.04, 0.18, bl - 0.16), "wood")
			rail.position = Vector3(sx, frameH * 0.5, 0)
			root.add_child(rail)
		var mat = Geo.box(Vector3(bw - 0.06, 0.22, bl - 0.16), "fabric_bed")
		mat.position = Vector3(0, frameH + 0.11, 0)
		root.add_child(mat)
		var drape = Geo.box(Vector3(bw - 0.04, 0.04, (bl - 0.16) * 0.68), "green")
		drape.position = Vector3(0, frameH + 0.22, (bl - 0.16) * 0.16)
		root.add_child(drape)
		var fold = Geo.box(Vector3(bw - 0.04, 0.06, 0.25), "fabric_bed")
		fold.position = Vector3(0, frameH + 0.23, -((bl - 0.16) * 0.18))
		root.add_child(fold)
		for px in [-bw * 0.26, bw * 0.26]:
			var pillow = Geo.box(Vector3(0.55, 0.10, 0.38), "fabric_bed")
			pillow.rotation.x = -0.22
			pillow.position = Vector3(px, frameH + 0.26, -bl * 0.5 + 0.35)
			root.add_child(pillow)
	elif type == 'wash_table':
		var ww = params.get("wash_w",1.1)
		var wd = 0.58
		var wh = 0.82
		var mh = params.get("mirror_h",0.80)
		var top = Geo.box(Vector3(ww, 0.04, wd), "wood_light")
		top.position.y = wh - 0.02
		root.add_child(top)
		var shelf = Geo.box(Vector3(ww - 0.10, 0.025, wd - 0.10), "wood")
		shelf.position.y = 0.18
		root.add_child(shelf)
		var legW = 0.045
		var lx = ww * 0.5 - legW * 0.5 - 0.02
		var lz = wd * 0.5 - legW * 0.5 - 0.02
		for pair2 in [[-lx, -lz], [lx, -lz], [-lx, lz], [lx, lz]]:
			var sx = pair2[0]
			var sz = pair2[1]
			var leg = Geo.box(Vector3(legW, wh - 0.04, legW), "wood")
			leg.position = Vector3(sx, (wh - 0.04) * 0.5, sz)
			root.add_child(leg)
		var mirrorFrame = Geo.box(Vector3(ww * 0.62, mh, 0.03), "wood_light")
		mirrorFrame.position = Vector3(0, wh + mh * 0.5, -wd * 0.5 + 0.03)
		root.add_child(mirrorFrame)
		var mirrorGlass = Geo.box(Vector3(ww * 0.52, mh - 0.10, 0.01), "glass")
		mirrorGlass.position = Vector3(0, wh + mh * 0.5, -wd * 0.5 + 0.045)
		root.add_child(mirrorGlass)
		var basin = Geo.mesh(Geo.cylinder(0.18, 0.12, 0.10, 16), "cream")
		basin.position = Vector3(-ww * 0.15, wh + 0.05, 0.02)
		root.add_child(basin)
		var pitcher = Geo.mesh(Geo.cylinder(0.06, 0.08, 0.22, 12), "cream")
		pitcher.position = Vector3(ww * 0.22, wh + 0.11, -0.04)
		root.add_child(pitcher)
	elif type == 'bookshelf':
		var bw = params.get("shelf_w",1.5)
		var bh = params.get("shelf_h",2.2)
		var bd = 0.38
		var layers = params.get("shelf_layers",5)
		var plinth = Geo.box(Vector3(bw + 0.04, 0.10, bd + 0.04), "wood_dark")
		plinth.position.y = 0.05
		root.add_child(plinth)
		var cornice = Geo.box(Vector3(bw + 0.06, 0.08, bd + 0.06), "wood_light")
		cornice.position.y = bh - 0.04
		root.add_child(cornice)
		for sx in [-bw * 0.5 + 0.02, bw * 0.5 - 0.02]:
			var side = Geo.box(Vector3(0.04, bh - 0.18, bd), "wood")
			side.position = Vector3(sx, 0.10 + (bh - 0.18) * 0.5, 0)
			root.add_child(side)
		var back = Geo.box(Vector3(bw - 0.04, bh - 0.18, 0.02), "wood_dark")
		back.position = Vector3(0, 0.10 + (bh - 0.18) * 0.5, -bd * 0.5 + 0.01)
		root.add_child(back)
		var shelfSpacing = (bh - 0.22) / layers
		var bookMats = ["book_red", "book_blue", "book_green", "cream"]
		for l in range(0, int(layers + 1)):
			var sy = 0.10 + l * shelfSpacing
			var shelf = Geo.box(Vector3(bw - 0.04, 0.03, bd - 0.02), "wood")
			shelf.position.y = sy
			root.add_child(shelf)
			if l < layers:
				var bx = -bw * 0.42
				while bx < bw * 0.38:
					# Positive remainder keeps widths and loop progress positive at negative X.
					var bookW = 0.035 + fposmod(bx,0.04)
					var bookH = shelfSpacing * 0.72 + fposmod(bx,0.06)
					var bMat = bookMats[int(abs(floor(bx * 47))) % bookMats.size()]
					var book = Geo.box(Vector3(bookW, bookH, bd * 0.65), bMat)
					book.position = Vector3(bx + bookW * 0.5, sy + 0.015 + bookH * 0.5, 0.02)
					root.add_child(book)
					bx += bookW + 0.005
	elif type == 'reception_desk':
		var dw = params.get("desk_w",2.4)
		var dh = params.get("desk_h",1.05)
		var dd = 0.85
		var plinth = Geo.box(Vector3(dw, 0.08, dd), "wood_dark")
		plinth.position.y = 0.04
		root.add_child(plinth)
		var carcass = Geo.box(Vector3(dw - 0.04, dh - 0.14, dd - 0.04), "wood")
		carcass.position.y = 0.08 + (dh - 0.14) * 0.5
		root.add_child(carcass)
		var pW = (dw - 0.28) / 3
		for i in range(0, int(3)):
			var px = -(dw - 0.28) * 0.5 + pW * 0.5 + i * (pW + 0.05)
			var panel = Geo.box(Vector3(pW, (dh - 0.25) * 0.78, 0.02), "wood_dark")
			panel.position = Vector3(px, 0.12 + (dh - 0.25) * 0.5, dd * 0.5 - 0.01)
			root.add_child(panel)
		var counter = Geo.box(Vector3(dw + 0.08, 0.06, dd + 0.08), "wood_light")
		counter.position.y = dh - 0.03
		root.add_child(counter)
		var bell = Geo.mesh(Geo.cylinder(0.04, 0.055, 0.04, 8), "gold")
		bell.position = Vector3(dw * 0.32, dh + 0.02, 0)
		root.add_child(bell)
		var sign = Geo.box(Vector3(0.28, 0.09, 0.04), "gold")
		sign.position = Vector3(0, dh + 0.045, dd * 0.35)
		root.add_child(sign)
	elif type == 'wall_lantern':
		var mount = Geo.box(Vector3(0.12, 0.26, 0.03), "wood_dark")
		mount.position = Vector3(0, 0, 0.015)
		root.add_child(mount)
		var arm = Geo.box(Vector3(0.03, 0.03, 0.22), "gold")
		arm.position = Vector3(0, 0.06, 0.12)
		root.add_child(arm)
		var cage = Geo.mesh(Geo.cylinder(0.11, 0.08, 0.26, 6), "gold")
		cage.position = Vector3(0, -0.04, 0.22)
		root.add_child(cage)
		var capT = Geo.mesh(Geo.cone(0.13, 0.10, 6), "gold")
		capT.position = Vector3(0, 0.14, 0.22)
		root.add_child(capT)
		var bulb = Geo.mesh(Geo.ico(0.05, 1), "emission")
		bulb.position = Vector3(0, -0.04, 0.22)
		root.add_child(bulb)
		var pLight = Geo.light(0xffd58b, 1.2, 5.0, 1.5)
		pLight.position = Vector3(0, -0.04, 0.26)
		root.add_child(pLight)
	elif type == 'banker_lamp':
		var base = Geo.mesh(Geo.cylinder(0.09, 0.11, 0.03, 12), "gold")
		base.position.y = 0.015
		root.add_child(base)
		var stem = Geo.mesh(Geo.cylinder(0.015, 0.015, 0.28, 8), "gold")
		stem.position.y = 0.17
		root.add_child(stem)
		var hood = Geo.box(Vector3(0.24, 0.08, 0.12), "green")
		hood.position = Vector3(0, 0.32, 0)
		root.add_child(hood)
		var emissionCore = Geo.box(Vector3(0.20, 0.02, 0.09), "emission")
		emissionCore.position = Vector3(0, 0.29, 0)
		root.add_child(emissionCore)
		var deskLight = Geo.light(0xffe6a3, 1.0, 3.2, 1.6)
		deskLight.position = Vector3(0, 0.27, 0)
		root.add_child(deskLight)
	elif type == 'pendant_lamp':
		var drop = params.get("drop_length",1.4)
		var canopy = Geo.mesh(Geo.cylinder(0.16, 0.20, 0.06, 8), "gold")
		canopy.position.y = drop
		root.add_child(canopy)
		var rod = Geo.mesh(Geo.cylinder(0.018, 0.018, drop, 8), "gold")
		rod.position.y = drop * 0.5
		root.add_child(rod)
		var ring = Geo.mesh(Geo.torus(0.55, 0.03, 6, 12), "gold")
		ring.rotation.x = PI * 0.5
		ring.position.y = 0
		root.add_child(ring)
		for i in range(0, int(6)):
			var ang = i * PI / 3
			var bulb = Geo.mesh(Geo.ico(0.06, 1), "emission")
			bulb.position = Vector3(cos(ang) * 0.55, 0.05, sin(ang) * 0.55)
			root.add_child(bulb)
		var chLight = Geo.light(0xffeaad, 2.0, 9.0, 1.2)
		chLight.position.y = -0.1
		root.add_child(chLight)
	elif type == 'painting':
		var pw = params.get("frame_w",1.35)
		var ph = params.get("frame_h",0.95)
		var frame = Geo.box(Vector3(pw, ph, 0.04), "gold")
		frame.position.z = 0.02
		root.add_child(frame)
		var canvas = Geo.box(Vector3(pw - 0.16, ph - 0.16, 0.01), "wall")
		canvas.position.z = 0.04
		root.add_child(canvas)
		var art1 = Geo.box(Vector3((pw - 0.16) * 0.55, (ph - 0.16) * 0.50, 0.005), "green")
		art1.position = Vector3(-(pw - 0.16) * 0.15, -(ph - 0.16) * 0.12, 0.045)
		root.add_child(art1)
		var art2 = Geo.box(Vector3((pw - 0.16) * 0.42, (ph - 0.16) * 0.35, 0.005), "leaf")
		art2.position = Vector3((pw - 0.16) * 0.18, (ph - 0.16) * 0.15, 0.048)
		root.add_child(art2)
	elif type == 'rug':
		var rw = params.get("rug_w",2.6)
		var rd = params.get("rug_d",1.8)
		var rugBorder = Geo.box(Vector3(rw, 0.015, rd), "wood_dark")
		rugBorder.position.y = 0.008
		root.add_child(rugBorder)
		var rugField = Geo.box(Vector3(rw - 0.20, 0.018, rd - 0.20), "green")
		rugField.position.y = 0.009
		root.add_child(rugField)
		var medallion = Geo.box(Vector3(rw * 0.42, 0.020, rd * 0.42), "cream")
		medallion.position.y = 0.010
		root.add_child(medallion)
	elif type == 'cabinet':
		var cw = params.get("cab_w",1.2)
		var ch = params.get("cab_h",2.0)
		var cd = 0.55
		var plinth = Geo.box(Vector3(cw + 0.04, 0.10, cd + 0.04), "wood_dark")
		plinth.position.y = 0.05
		root.add_child(plinth)
		var body = Geo.box(Vector3(cw, ch - 0.18, cd), "wood")
		body.position.y = 0.10 + (ch - 0.18) * 0.5
		root.add_child(body)
		var cornice = Geo.box(Vector3(cw + 0.06, 0.08, cd + 0.06), "wood_light")
		cornice.position.y = ch - 0.04
		root.add_child(cornice)
		for sx in [-cw * 0.24, cw * 0.24]:
			var panel = Geo.box(Vector3(cw * 0.42, (ch - 0.32) * 0.85, 0.02), "wood_dark")
			panel.position = Vector3(sx, 0.14 + (ch - 0.32) * 0.5, cd * 0.5 + 0.01)
			root.add_child(panel)
		for kx in [-0.03, 0.03]:
			var handle = Geo.mesh(Geo.cylinder(0.012, 0.012, 0.14, 8), "gold")
			handle.position = Vector3(kx, ch * 0.5, cd * 0.5 + 0.03)
			root.add_child(handle)
	elif type == 'screen':
		var sw = params.get("screen_w",1.8)
		var sh = params.get("screen_h",1.7)
		var pW = sw / 3
		for i in range(0, int(3)):
			var px = -sw * 0.5 + pW * 0.5 + i * pW
			var pz = (-0.10 if i == 1 else 0.08)
			var frame = Geo.box(Vector3(pW - 0.02, sh, 0.03), "wood")
			frame.position = Vector3(px, sh * 0.5, pz)
			root.add_child(frame)
			var fabric = Geo.box(Vector3(pW - 0.08, sh - 0.12, 0.01), "cream")
			fabric.position = Vector3(px, sh * 0.5, pz)
			root.add_child(fabric)
	elif type == 'crates':
		var c1 = Geo.box(Vector3(0.70, 0.70, 0.70), "wood")
		c1.position = Vector3(0, 0.35, 0)
		root.add_child(c1)
		var c2 = Geo.box(Vector3(0.55, 0.55, 0.55), "wood_light")
		c2.position = Vector3(0.12, 0.70 + 0.275, -0.05)
		c2.rotation.y = 0.25
		root.add_child(c2)
	else:
		var box = Geo.box(Vector3(0.6, 0.6, 0.6), "wood")
		box.position.y = 0.3
		root.add_child(box)
	root.position = Vector3(position_x,baseY,position_z)
	root.rotation.y = deg_to_rad(yaw)
	return root
