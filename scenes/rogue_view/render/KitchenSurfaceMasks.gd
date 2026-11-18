extends RefCounted
## Periodic data texture: soot, drips, wear and damp. Seeded, cached and mipmapped.
const SIZE := 128
const KITCHEN_SEED := 0x32C1A
static var _kitchen_texture: ImageTexture

static func kitchen_texture() -> ImageTexture:
	if _kitchen_texture == null: _kitchen_texture = ImageTexture.create_from_image(bake(KITCHEN_SEED))
	return _kitchen_texture

static func bake(seed_value: int) -> Image:
	var patch := FastNoiseLite.new()
	patch.seed = seed_value
	patch.frequency = 0.042
	patch.fractal_octaves = 3
	var fine := FastNoiseLite.new()
	fine.seed = seed_value ^ 0x61DF
	fine.frequency = 0.17
	fine.fractal_octaves = 2
	var bytes := PackedByteArray()
	bytes.resize(SIZE*SIZE*4)
	for y in SIZE:
		for x in SIZE:
			var broad := _periodic(patch,x,y)
			var detail := _periodic(fine,x,y)
			var streak := _periodic(patch,(x*4)%SIZE,y)*0.76+detail*0.24
			var i := (y*SIZE+x)*4
			bytes[i] = roundi(smoothstep(-0.10,0.36,broad+0.24*detail)*255.0)
			bytes[i+1] = roundi(smoothstep(0.04,0.33,streak)*255.0)
			bytes[i+2] = roundi(smoothstep(0.10,0.53,detail+0.35*broad)*255.0)
			bytes[i+3] = roundi(smoothstep(-0.15,0.29,broad-0.22*detail)*255.0)
	var image := Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGBA8,bytes)
	image.generate_mipmaps()
	return image

static func _periodic(noise: FastNoiseLite, x: int, y: int) -> float:
	var tx := smoothstep(0.0,float(SIZE),float(x))
	var ty := smoothstep(0.0,float(SIZE),float(y))
	return lerpf(
		lerpf(noise.get_noise_2d(x,y),noise.get_noise_2d(x-SIZE,y),tx),
		lerpf(noise.get_noise_2d(x,y-SIZE),noise.get_noise_2d(x-SIZE,y-SIZE),tx),ty)
