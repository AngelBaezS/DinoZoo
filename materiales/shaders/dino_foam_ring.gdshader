shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Estela caricaturesca suave para dinosaurios acuáticos al romper la superficie
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float water_base_y = 0.0;
uniform vec4 wave_a = vec4(1.0, 0.2, 0.06, 16.0);
uniform vec4 wave_b = vec4(0.3, 0.8, 0.04, 11.0);

uniform vec2 ring_shape_scale = vec2(2.2, 0.85);
uniform vec2 ring_offset = vec2(0.0, 0.0);

uniform float inner_radius : hint_range(0.0, 0.5) = 0.14;
uniform float outer_radius : hint_range(0.1, 0.6) = 0.45;
uniform float foam_intensity : hint_range(0.0, 1.0) = 0.0;

vec3 gerstner_offset(vec4 wave, vec3 p, float time) {
	float steepness = wave.z;
	float wavelength = max(wave.w, 0.5);
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave.xy + vec2(0.0001, 0.0));
	float f = k * (dot(d, p.xz) - c * time);
	float a = steepness / k;
	return vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 grid_point = vec3(world_pos.x, water_base_y, world_pos.z);
	vec3 wave_offset = gerstner_offset(wave_a, grid_point, TIME) + gerstner_offset(wave_b, grid_point, TIME);
	world_pos.y = water_base_y + wave_offset.y + 0.04;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
	vec2 centered_uv = (UV - vec2(0.5) - ring_offset) * ring_shape_scale;
	float dist = length(centered_uv);
	float angle = atan(centered_uv.y, centered_uv.x);

	vec2 polar_uv1 = vec2(angle / TAU * 3.0, dist * 3.0 - TIME * 0.45);
	vec2 polar_uv2 = vec2(angle / TAU * 5.0 + 0.3, dist * 4.5 - TIME * 0.25);

	float n1 = texture(noise_tex, polar_uv1).r;
	float n2 = texture(noise_tex, polar_uv2).r;
	float combined_noise = (n1 + n2) * 0.5;

	float inner_mask = smoothstep(inner_radius, inner_radius + 0.10, dist);
	float outer_mask = 1.0 - smoothstep(outer_radius - 0.16, outer_radius, dist);
	float ring_mask = inner_mask * outer_mask;

	// Ondas concéntricas caricaturescas suaves (sin recorte duro tipo óvalo de plástico)
	float wave_band = smoothstep(0.35, 0.72, sin(dist * 24.0 - TIME * 4.2) * 0.5 + 0.5);
	float bubble_cut = smoothstep(0.38, 0.62, combined_noise * (0.65 + 0.35 * wave_band));
	float alpha = ring_mask * bubble_cut * foam_intensity * 0.85;

	ALBEDO = foam_color;
	ALPHA = alpha;
}
