shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.12, 0.58, 0.72);
uniform vec3 deep_color : source_color = vec3(0.03, 0.18, 0.32);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
// Agua transparente para ver al Mosasaurio con total claridad
uniform float water_transparency : hint_range(0.1, 1.0) = 0.38;

// Parámetros de Olas de Gerstner suaves y de gran longitud de onda (sin oleaje brusco)
uniform vec4 wave_a = vec4(1.0, 0.2, 0.05, 18.0); // dir.x, dir.y, steepness, wavelength
uniform vec4 wave_b = vec4(0.3, 0.8, 0.03, 12.0);

// Sistema de Impacto de Dinosaurios (x, z = posición global, y = tiempo de inicio, w = fuerza)
uniform vec4 impacts[4];
uniform float ripple_speed = 6.0;
uniform float ripple_frequency = 2.5;
uniform float ripple_decay = 0.45;

varying float v_height;
varying float v_foam;
varying vec3 world_pos;

vec3 gerstner_wave(vec4 wave, vec3 p, inout vec3 tangent, inout vec3 binormal) {
	float steepness = wave.z;
	float wavelength = wave.w;
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave.xy);
	float f = k * (dot(d, p.xz) - c * TIME);
	float a = steepness / k;

	tangent += vec3(
		-d.x * d.x * (steepness * sin(f)),
		d.x * (steepness * cos(f)),
		-d.x * d.y * (steepness * sin(f))
	);
	binormal += vec3(
		-d.x * d.y * (steepness * sin(f)),
		d.y * (steepness * cos(f)),
		-d.y * d.y * (steepness * sin(f))
	);
	return vec3(
		d.x * (a * cos(f)),
		a * sin(f),
		d.y * (a * cos(f))
	);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 grid_point = world_pos;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 p = grid_point;

	// 1. Olas de Gerstner base
	p += gerstner_wave(wave_a, grid_point, tangent, binormal);
	p += gerstner_wave(wave_b, grid_point, tangent, binormal);

	// 2. Ondas analíticas de impacto
	float total_ripple = 0.0;
	float ripple_foam = 0.0;
	for (int i = 0; i < 4; i++) {
		float start_time = impacts[i].y;
		float strength = impacts[i].w;
		if (strength > 0.001 && TIME > start_time) {
			float elapsed = TIME - start_time;
			float dist = distance(world_pos.xz, impacts[i].xz);
			float wave_front = elapsed * ripple_speed;
			
			float dist_from_front = abs(dist - wave_front);
			float envelope = exp(-dist_from_front * 0.8) * exp(-elapsed * 1.2) * exp(-dist * ripple_decay);
			float phase = sin(dist * ripple_frequency - elapsed * ripple_speed * 2.5);
			
			float ripple_offset = phase * envelope * strength;
			total_ripple += ripple_offset;
			ripple_foam += clamp(envelope * strength * 1.5, 0.0, 1.0);
			
			vec2 dir_to_center = normalize(world_pos.xz - impacts[i].xz + vec2(0.0001));
			tangent.y += dir_to_center.x * ripple_offset * 1.5;
			binormal.y += dir_to_center.y * ripple_offset * 1.5;
		}
	}

	p.y += total_ripple;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(p, 1.0)).xyz;
	NORMAL = normalize(cross(binormal, tangent));
	
	v_height = p.y - world_pos.y;
	v_foam = clamp((v_height * 1.2) + ripple_foam, 0.0, 1.0);
}

void fragment() {
	vec3 norm = NORMAL;
	if (!FRONT_FACING) {
		norm = -NORMAL;
	}

	float fresnel = pow(1.0 - clamp(dot(norm, VIEW), 0.0, 1.0), 3.0);
	vec3 base_water = mix(deep_color, shallow_color, clamp(v_height + 0.5, 0.0, 1.0));
	
	if (!FRONT_FACING) {
		// Cara inferior vista desde dentro del estanque / acuario
		base_water = mix(deep_color * 1.3, shallow_color * 1.1, 0.5);
	}
	
	vec3 water_col = mix(base_water, shallow_color * 1.3, fresnel);
	float foam_mask = smoothstep(0.35, 0.65, v_foam);
	
	ALBEDO = mix(water_col, foam_color, foam_mask);
	ROUGHNESS = mix(0.06, 0.5, foam_mask);
	METALLIC = 0.05;
	
	// Transparencia que permite ver al dinosaurio nadando por debajo como en un acuario
	ALPHA = mix(water_transparency, 0.98, foam_mask);
}
