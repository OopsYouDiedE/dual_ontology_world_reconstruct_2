extends Control
## All coordinates are on the 1280 x 720 design sheet, letterboxed as a unit.
const ART := "res://scenes/blue_prince_lab/reference/interface/"
const TITLES := ["Bedroom", "Storeroom", "Hallway"]
var root := Control.new()
var mode := ""
var lens: Control
var title: Label
var outline: ColorRect
var board_layer: Control
var picked := -1
var sheet_open := true
var lens_at := Vector2(457,353)
var zoom := 2.0
var bold := SystemFont.new()
var hand := SystemFont.new()
var serif := SystemFont.new()

func setup(kind: String) -> void:
	mode = kind
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(root)
	bold.font_names = PackedStringArray(["Bahnschrift", "DejaVu Sans"])
	bold.font_weight = 780
	hand.font_names = PackedStringArray(["Segoe Print", "URW Bookman", "DejaVu Serif"])
	hand.font_italic = true
	serif.font_names = PackedStringArray(["Georgia", "DejaVu Serif"])
	resized.connect(_fit)
	_fit()
	if kind=="Draft": _draft()
	else: _inspect()

func _fit() -> void:
	var s := minf(size.x/1280.,size.y/720.)
	root.position = (size-Vector2(1280,720)*s)*.5
	root.scale = Vector2.ONE*s

func block(parent: Control,p: Vector2,sz: Vector2,c: Color) -> ColorRect:
	var b := ColorRect.new()
	b.mouse_filter=MOUSE_FILTER_IGNORE
	b.color=c
	parent.add_child(b)
	b.position=p
	b.size=sz
	return b

func picture(parent: Control,key: String,p: Vector2,sz: Vector2,angle:=0.) -> TextureRect:
	var t := TextureRect.new()
	t.texture=load(ART+(key if key.ends_with(".png") else key+".svg"))
	t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter=MOUSE_FILTER_IGNORE
	parent.add_child(t)
	t.position=p
	t.size=sz
	t.rotation_degrees=angle
	return t

func text(parent: Control,words: String,p: Vector2,sz: Vector2,px: int,font: Font,tint: Color,stroke:=0) -> Label:
	var label := Label.new()
	label.mouse_filter=MOUSE_FILTER_IGNORE
	label.text=words
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",px)
	label.add_theme_color_override("font_color",tint)
	label.add_theme_color_override("font_outline_color",Color("27232e"))
	label.add_theme_constant_override("outline_size",stroke)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	label.position=p
	label.size=sz
	return label

func _counter(inspect: bool) -> void:
	block(root,Vector2(9,8),Vector2(102,46),Color("161a1c84"))
	# Separate sole and heel marks leave a recognisable pair of footprints.
	for i in 2:
		var foot := block(root,Vector2(21+i*12,20-i*5),Vector2(7,15),Color("e4e1dc"))
		foot.rotation_degrees=-15+i*25
		block(root,Vector2(24+i*11,36-i*5),Vector2(6,5),Color("c9c8c4"))
	text(root,"25" if inspect else "15",Vector2(43,2),Vector2(53,47),31,hand,Color.WHITE,2)
	var resources := [["Key", "1", "91ccee"],["Gem","18","e5b3cf"],["Coin","14","dfc276"]] if inspect else [["Coin","14","dfc276"]]
	for i in resources.size():
		var x := 1264-(resources.size()-i)*77
		block(root,Vector2(x,8),Vector2(76,44),Color("161a1c84"))
		picture(root,resources[i][0],Vector2(x+2,15),Vector2(25,25))
		text(root,resources[i][1],Vector2(x+28,4),Vector2(46,42),28,hand,Color.WHITE,2)

func _draft() -> void:
	block(root,Vector2.ZERO,Vector2(1280,720),Color("10161c62"))
	board_layer=Control.new()
	board_layer.mouse_filter=MOUSE_FILTER_IGNORE
	root.add_child(board_layer)
	picture(board_layer,"Board",Vector2(0,117),Vector2(1280,244))
	block(board_layer,Vector2(425,95),Vector2(606,1.6),Color("d3dfe6"))
	title=text(board_layer,"S E L E C T   A   R O O M   T O   D R A F T",Vector2(410,48),Vector2(640,46),19,bold,Color("e4eaec"),3)
	outline=block(board_layer,Vector2(-400,121),Vector2(227,229),Color("ffe0a1"))
	for i in 3:
		var x := 414+i*240
		picture(board_layer,TITLES[i],Vector2(x,126),Vector2(220,220))
		text(board_layer,TITLES[i].to_upper(),Vector2(x-2,173),Vector2(224,52),29,bold,Color("fff6dc"),6)
		if i==0: text(board_layer,"Whenever you enter\nthis room, gain 2 steps.",Vector2(x+10,249),Vector2(202,52),14,bold,Color.WHITE,4)
		elif i==1:
			for j in 3:
				text(board_layer,"1",Vector2(x+44+j*45,252),Vector2(15,44),18,bold,Color.WHITE,3)
				picture(board_layer,["Key","Gem","Coin"][j],Vector2(x+59+j*45,264),Vector2(19,19))
	picture(board_layer,"Square",Vector2(172,159),Vector2(218,309),-13)
	picture(board_layer,"Rule",Vector2(1263,74),Vector2(189,305),96)
	picture(board_layer,"Tsquare",Vector2(0,-20),Vector2(411,720))
	text(root,"[ Tab ]   Blueprint",Vector2(14,665),Vector2(160,39),16,serif,Color("d3e0e5"),2)
	_counter(false)

func _inspect() -> void:
	var paper := block(root,Vector2(296,161),Vector2(403,482),Color("2c242d"))
	paper.rotation_degrees=-14
	block(paper,Vector2(3,3),Vector2(397,476),Color("bc9693"))
	text(paper,"print notes",Vector2(145,19),Vector2(207,51),25,hand,Color("725357"))
	var lines := ["Exposure no. 6  /  garden", "A print for one of the", "West Wing rooms.", "to be enlarged", "before the next sitting.", "The edge was too dark", "on that last plate."]
	for i in lines.size():
		text(paper,lines[i],Vector2(18,87+i*47),Vector2(352,45),21,hand,Color("72575b"))
	picture(root,"ArchivePrint.png",Vector2(553,93),Vector2(386,535),-5.5).modulate=Color("efc2c2")
	var copy := BackBufferCopy.new()
	copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT
	root.add_child(copy)
	lens=Control.new()
	lens.mouse_filter=MOUSE_FILTER_IGNORE
	root.add_child(lens)
	picture(lens,"Handle",Vector2(-143,-142),Vector2(296,514))
	var optic := block(lens,Vector2(-141,-141),Vector2(282,282),Color.WHITE)
	var mat := ShaderMaterial.new()
	mat.shader = preload("Loupe.gdshader")
	optic.material=mat
	lens.set_meta("optic",mat)
	lens.position=lens_at
	_counter(true)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	var point := root.get_local_mouse_position()
	if event is InputEventMouse:
		point=(event.position-root.position)/root.scale
	if mode=="Inspect" and (event is InputEventMouseMotion or event is InputEventMouseButton):
		if point.y<98: return
		lens_at=point.clamp(Vector2(24,76),Vector2(1256,698))
		lens.position=lens_at
		if event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP: zoom=minf(3.5,zoom+.25)
			if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom=maxf(1.25,zoom-.25)
			(lens.get_meta("optic") as ShaderMaterial).set_shader_parameter("zoom",zoom)
	if mode!="Draft": return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_TAB:
		sheet_open=not sheet_open
		board_layer.visible=sheet_open
		get_viewport().set_input_as_handled()
	if not sheet_open: return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT):
		for i in 3:
			if Rect2(414+i*240,126,220,220).has_point(point):
				outline.position.x=410+i*240
				if event is InputEventMouseButton:
					picked=i
					title.text=TITLES[i].to_upper()+"   /   DRAFTED"
					get_viewport().set_input_as_handled()
				return
		outline.position.x=410+picked*240 if picked>=0 else -400
