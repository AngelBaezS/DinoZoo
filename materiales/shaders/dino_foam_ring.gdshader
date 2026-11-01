shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 1.0);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float water_base_y = 0.0;
uniform vec4 wave_a = vec4(1.0, 0.2, 0.25, 4.0);
uniform vec4 wave_b = vec4(0.3, 0.8, 0.18, 2.5);

// Parámetros de forma contorneada del dinosaurio (alargado en Z, adaptado a su anatomía)
uniform vec2 ring_shape_scale = vec2(2.2, 0.85);
uniform vec2 ring_offset = vec2(0.0, 0.0);

uniform float inner_radius : hint_range(0.0, 0.5) = 0.10;
uniform float outer_radius : hint_range(0.1, 0.6) = 0.46;
uniform float foam_intensity : hint_range(0.0, 1.0) = 1.0;

vec3 gerstner_offset(vec4 wave, vec3 p, float time) {
	float steepness = wave.z;
	float wavelength = wave.w;
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave.xy);
	float f = k * (dot(d, p.xz) - c * time);
	float a = steepness / k;
	return vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 grid_point = vec3(world_pos.x, water_base_y, world_pos.z);
	vec3 wave_offset = gerstner_offset(wave_a, grid_point, TIME) + gerstner_offset(wave_b, grid_point, TIME);
	world_pos.y = water_base_y + wave_offset.y + 0.03; // Previene Z-fighting
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
	// Deformación elíptica/alargada adaptada al contorno del cuerpo del mosasaurio
	vec2 centered_uv = (UV - vec2(0.5) - ring_offset) * ring_shape_scale;
	float dist = length(centered_uv);
	float angle = atan(centered_uv.y, centered_uv.x);
	
	vec2 polar_uv1 = vec2(angle / TAU * 3.0, dist * 3.5 - TIME * 0.45);
	vec2 polar_uv2 = vec2(angle / TAU * 5.0 + 0.3, dist * 5.0 - TIME * 0.25);
	
	float n1 = texture(noise_tex, polar_uv1).r;
	float n2 = texture(noise_tex, polar_uv2).r;
	float combined_noise = (n1 + n2) * 0.5;
	
	float inner_mask = smoothstep(inner_radius, inner_radius + 0.08, dist);
	float outer_mask = 1.0 - smoothstep(outer_radius - 0.16, outer_radius, dist);
	float ring_mask = inner_mask * outer_mask;
	
	float concentric_ripples = sin(dist * 26.0 - TIME * 4.5) * 0.15 + 0.85;
	float final_mask = ring_mask * combined_noise * concentric_ripples * foam_intensity;
	
	ALBEDO = foam_color;
	ALPHA = final_mask;
	ALPHA_SCISSOR_THRESHOLD = 0.35; // Recorte Alpha Scissor: Cero overdraw en Adreno GPU
}
