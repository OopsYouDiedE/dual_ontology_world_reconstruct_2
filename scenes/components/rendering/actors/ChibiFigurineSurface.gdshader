shader_type spatial;
// Matte painted resin: broad diffuse response and a small, room-lit varnish lobe.
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

#include "res://scenes/components/rendering/actors/FigurinePaint.gdshaderinc"
