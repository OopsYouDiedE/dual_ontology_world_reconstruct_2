extends RefCounted
## 昼夜光照：时间 → 太阳方位与色温、天光、环境光、灯具亮度、窗外天色。
## 3D 实机、2D 地图与编辑器共用同一条曲线（2D 的暗幕见 RoomGeometry.darkness）。

static func lighting(hour: float) -> Dictionary:
	var day := clampf((hour - 5.0) / 2.5, 0.0, 1.0) * clampf((20.0 - hour) / 2.5, 0.0, 1.0)
	var dusk := (hour - 17.0) / 3.0 if hour >= 17.0 and hour < 20.0 else 0.0
	var sun_color := Color("#ffe9c4")
	if day < 0.35: sun_color = Color("#ffb46a")
	elif dusk > 0.4: sun_color = Color("#ff9c5b")
	var sky := Color("#14121c")
	if day > 0.5: sky = Color("#6b7d8c")
	elif day > 0.15: sky = Color("#3d3540")
	return {
		"day": day, "sun_color": sun_color, "sky": sky,
		"sun_energy": 0.35 + day * 1.65,
		"ambient_energy": 0.55 + day * 0.65,
		"lamp_on": clampf(1.0 - day * 1.25, 0.0, 1.0),
		"fog": Color("#2a2430") if day > 0.4 else Color("#100e16"),
	}


## 太阳高度角（度）与方位角（度）；夜间退化为从另一侧照入的低亮度月光。
static func sun_angles(hour: float) -> Vector2:
	var t := clampf((hour - 6.0) / 14.0, 0.0, 1.0)  # 06:00 → 20:00
	var elevation := lerpf(8.0, 68.0, sin(t * PI)) if hour >= 5.0 and hour <= 20.5 else 28.0
	var azimuth := lerpf(-70.0, 70.0, t) if hour >= 5.0 and hour <= 20.5 else 160.0
	return Vector2(elevation, azimuth)


## 应用到场景：sun / environment / 灯列表（OmniLight3D）/ 自发光材质列表。
static func apply(hour: float, sun: DirectionalLight3D, env: Environment, lamps: Array, glow_materials: Array) -> void:
	var L := lighting(hour)
	var a := sun_angles(hour)
	if sun != null:
		sun.rotation_degrees = Vector3(-a.x, a.y, 0.0)
		sun.light_color = L.sun_color if L.day > 0.05 else Color("#5b6c9a")  # 夜间冷色月光
		sun.light_energy = L.sun_energy
	if env != null:
		env.background_mode = Environment.BG_COLOR
		env.background_color = L.sky if L.day > 0.35 else Color("#15121a")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = L.sky.lerp(Color("#2a1d12"), 0.35)
		env.ambient_light_energy = L.ambient_energy * 0.95
		env.fog_enabled = true
		env.fog_light_color = L.fog
		env.fog_density = 0.004
	for lamp in lamps:
		if is_instance_valid(lamp):
			lamp.light_energy = 0.35 + float(L.lamp_on) * 1.9
	for m in glow_materials:
		if m is StandardMaterial3D:
			m.emission_energy_multiplier = 0.25 + float(L.lamp_on) * 1.1


static func label(hour: float) -> String:
	if hour < 5.0 or hour >= 20.0: return "夜"
	if hour < 7.0: return "拂晓"
	if hour < 11.0: return "上午"
	if hour < 13.5: return "正午"
	if hour < 17.0: return "午后"
	if hour < 20.0: return "黄昏"
	return "夜"
