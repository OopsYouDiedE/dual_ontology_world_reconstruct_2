shader_type canvas_item;
render_mode unshaded;

// Each 2x2 output block corresponds to one 3D pixel at the workbench's 50% scale.
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	ivec2 cell = ivec2(floor(UV * vec2(textureSize(TEXTURE, 0)) * 0.5));
	float threshold = (BAYER[(cell.y % 4) * 4 + cell.x % 4] + 0.5) / 16.0 - 0.5;
	vec3 quantized = floor(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)) * 31.0 + 0.5 + threshold * 0.35) / 31.0;
	COLOR.rgb = quantized;
}
