shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Atlas contract: TL wood, TR cloth, BL paper, BR brass. Surface details are
// fixed to the material coordinates, never overlaid on the screen.
uniform vec4 base_color : source_color = vec4(0.26, 0.12, 0.05, 1.0);
uniform sampler2D material_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool has_atlas = false;
uniform bool has_normal_texture = false;
uniform bool has_roughness_texture = false;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.7;
uniform float roughness_texture_mix : hint_range(0.0, 1.0) = 1.0;
uniform vec2 atlas_origin = vec2(0.0);
uniform float material_kind = 0.0; // 0 wood, 1 cloth/pigment, 2 paper, 3 brass, 4 polished wood
uniform float surface_roughness = 0.62;
uniform float surface_metallic = 0.0;
uniform float atlas_gain = 1.0;
uniform float coat_amount = 0.08;
uniform float micro_depth = 1.0;
varying vec3 world_point;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}

vec3 bump_normal(vec3 n, vec3 position, float height) {
    vec3 dx = dFdx(position), dy = dFdy(position);
    vec3 rx = cross(dy, n), ry = cross(n, dx);
    float determinant = dot(dx, rx);
    vec3 gradient = rx * dFdx(height) + ry * dFdy(height);
    return normalize(max(abs(determinant), 0.0000001) * n - sign(determinant) * gradient);
}
vec3 mapped_normal(vec3 n, vec3 position, vec2 uv_dx, vec2 uv_dy, vec2 encoded_xy, float strength) {
    // Derive the cotangent frame from the actual texture coordinates. This
    // also handles the desk's world-mapped grain without relying on mesh UVs.
    vec3 dx = dFdx(position), dy = dFdy(position);
    // Explicit mirrored derivatives flip the cotangent frame with each tile;
    // the same gradients also select mipmaps for all three atlas textures.
    vec2 tx = uv_dx, ty = uv_dy;
    vec3 px = cross(dy, n), py = cross(n, dx);
    vec3 tangent = px * tx.x + py * ty.x;
    vec3 bitangent = px * tx.y + py * ty.y;
    float frame_size = max(dot(tangent, tangent), dot(bitangent, bitangent));
    if (frame_size < 0.0000000001) return n;
    float inverse_scale = inversesqrt(frame_size);
    vec2 xy = encoded_xy * 2.0 - 1.0;
    // Reconstruct Z so RGB and normal-map RG compression behave identically.
    vec3 sample_normal = normalize(vec3(xy * strength, sqrt(max(1.0 - dot(xy, xy), 0.0))));
    return normalize(tangent * inverse_scale * sample_normal.x + bitangent * inverse_scale * sample_normal.y + n * sample_normal.z);
}

void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
    bool wood = material_kind < 0.5 || material_kind > 3.5;
    bool brass = material_kind > 2.5 && material_kind < 3.5;
    vec2 coords = UV;
    if (material_kind < 0.5) {
        vec2 p = world_point.xz;
        vec2 board = vec2(dot(p, vec2(.3746066, -.9271839)), dot(p, vec2(.9271839, .3746066)));
        // One whole wood quadrant per 6.25 by 7.69 world units.
        coords = board.yx * vec2(.16, .13) + vec2(.5);
    }
    if (material_kind > 3.5) coords = UV * vec2(1.7, 0.65);
    if (brass && dot(abs(dFdx(UV)) + abs(dFdy(UV)), vec2(1.0)) < .0000001) {
        // A few tiny custom nib/gear surfaces have no authored UV channel.
        coords = vec2(world_point.x + world_point.y * .37, world_point.z + world_point.y * .71) * .8;
    }
    vec2 tile_uv = fract(coords);
    vec2 tile_direction = vec2(1.0);
    if (wood) {
        // Adjacent tiles meet at the same image edge. The atlas does not need
        // matching opposite borders, and negative coordinates mirror equally.
        vec2 odd_tile = mod(floor(coords), vec2(2.0));
        tile_uv = mix(tile_uv, vec2(1.0) - tile_uv, odd_tile);
        tile_direction = vec2(1.0) - 2.0 * odd_tile;
    }
    vec2 atlas_uv = atlas_origin + vec2(.002) + tile_uv * .496;
    vec2 atlas_dx = dFdx(coords) * tile_direction * .496;
    vec2 atlas_dy = dFdy(coords) * tile_direction * .496;
    vec3 painted = base_color.rgb;
    if (has_atlas) {
        // Explicit gradients avoid a blurred line at tile folds or wrapping.
        painted = textureGrad(material_atlas, atlas_uv, atlas_dx, atlas_dy).rgb;
        painted *= atlas_gain;
        painted = mix(painted, painted * base_color.rgb * 1.8, brass ? .10 : .06);
    }
    float broad = noise(coords * vec2(7.0, 19.0));
    float fine = noise(coords * vec2(83.0, 251.0));
    float height = 0.0005 * (fine - 0.5);
    float roughness = surface_roughness + (broad - 0.5) * 0.12;
    if (wood) {
        float fiber = sin(coords.y * 460.0 + noise(coords * vec2(4.0, 21.0)) * 7.0);
        float fiber_visibility = 1.0 - smoothstep(0.6, 1.8, fwidth(coords.y * 460.0));
        float pores = noise(coords * vec2(34.0, 310.0));
        painted *= mix(0.96, 1.04, broad) * (1.0 + 0.025 * fiber * fiber_visibility);
        float pigment_height = dot(painted, vec3(.2126, .7152, .0722));
        height = pigment_height * 0.005 + fiber * fiber_visibility * .00035 + (pores - .5) * .0008;
        roughness += (pores - .5) * .10;
    } else if (brass) {
        float phase = coords.y * 600.0 + noise(coords * vec2(19.0, 5.0)) * 3.5;
        float line_width = max(fwidth(phase) * .7, .12);
        float scratch = 1.0 - smoothstep(0.0, line_width, abs(sin(phase)));
        scratch *= smoothstep(.46, .77, noise(coords * vec2(67.0, 11.0)));
        painted *= mix(.91, 1.045, broad) + scratch * .035;
        roughness += scratch * .17 + (fine - .5) * .055;
        height = (fine - .5) * .0007 - scratch * .0008;
    } else if (material_kind < 1.5) {
        painted *= mix(.98, 1.02, broad);
        height = (fine - .5) * .00065;
    } else {
        height = (fine - .5) * .00035;
        roughness = max(roughness, .88);
    }
    ALBEDO = clamp(painted, vec3(0.0), vec3(1.0));
    vec3 surface_normal = normalize(NORMAL);
    float material_normal_scale = wood ? .20 : 1.0;
    if (has_normal_texture) {
        vec2 encoded_xy = textureGrad(normal_texture, atlas_uv, atlas_dx, atlas_dy).rg;
        surface_normal = mapped_normal(surface_normal, VERTEX, atlas_dx, atlas_dy, encoded_xy, normal_strength * material_normal_scale);
    }
    NORMAL = bump_normal(surface_normal, VERTEX, height * micro_depth * material_normal_scale * (has_normal_texture ? .18 : 1.0));
    if (has_roughness_texture) {
        float mapped_roughness = textureGrad(roughness_texture, atlas_uv, atlas_dx, atlas_dy).r;
        roughness = mix(roughness, mapped_roughness, roughness_texture_mix);
    }
    if (wood) roughness = max(roughness, material_kind < .5 ? .64 : .48);
    ROUGHNESS = clamp(roughness, .18, .98);
    METALLIC = surface_metallic;
    SPECULAR = .5;
    CLEARCOAT = coat_amount;
    CLEARCOAT_ROUGHNESS = .28;
}
