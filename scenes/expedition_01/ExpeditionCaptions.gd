extends VBoxContainer
## A live caption per speaker; different speakers and thoughts coexist.
var entries:={}
var typeface:Font

func setup(font:Font)->void:
	typeface=font
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left=56.;offset_right=-56.;offset_top=-245.;offset_bottom=-52.
	alignment=BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation",5)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(_resize_lines)

static func reading_time(text:String)->float:
	var units:=0.
	var in_word:=false
	for i in text.length():
		var c:=text.unicode_at(i)
		if c>=0x3400 and c<=0x9fff:
			units+=1.;in_word=false
		elif (c>=65 and c<=90) or (c>=97 and c<=122) or (c>=48 and c<=57):
			if not in_word:units+=1.8
			in_word=true
		else:
			if c in [0x3002,0xFF01,0xFF1F,0x2026,46,63,33]:units+=.55
			in_word=false
	return clampf(1.5+units/8.,2.35,9.)

func post(id:String,speaker:String,text:String)->void:
	remove_speaker(speaker)
	var line:=Label.new()
	line.text=text if speaker.is_empty() else "%s：%s"%[speaker,text]
	line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	line.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter=Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_override("font",typeface)
	line.add_theme_font_size_override("font_size",20)
	line.add_theme_color_override("font_color",Color("dbd1bb") if speaker.is_empty() else Color("fff3df"))
	var plate:=StyleBoxFlat.new();plate.bg_color=Color(.035,.029,.023,.89);plate.set_corner_radius_all(4)
	plate.content_margin_left=18.;plate.content_margin_right=18.;plate.content_margin_top=7.;plate.content_margin_bottom=7.
	line.add_theme_stylebox_override("normal",plate)
	add_child(line)
	entries[speaker]={"id":id,"label":line,"remaining":reading_time(text)}
	_fit(line)

func _fit(line:Label)->void:
	var text_width:=typeface.get_string_size(line.text,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
	line.custom_minimum_size.x=minf(maxf(size.x,100.),ceilf(text_width)+38.)

func _resize_lines()->void:
	for entry in entries.values():_fit(entry.label)

func remove_speaker(speaker:String)->void:
	if not entries.has(speaker):return
	var line:Label=entries[speaker].label
	remove_child(line);line.queue_free();entries.erase(speaker)

func clear()->void:
	for speaker in entries.keys():remove_speaker(speaker)

func advance(dt:float)->void:
	for speaker in entries.keys():
		var entry:Dictionary=entries[speaker]
		entry.remaining-=dt
		if entry.remaining<=0.:remove_speaker(speaker)
		else:entry.label.modulate.a=clampf(entry.remaining/.32,0.,1.)
