shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// LOW-POLY TOON / ANIMATED SHADER — DinoZoo VR (Godot 4.7 GL Compatibility)
// ============================================================================
// Reemplaza el PBR pesado estándar (Burley + Schlick GGX) por iluminación
// estilizada tipo animación 3D (3 bandas cel-shaded cálido/frío + rim light
// nítido + brisa sutil opcional en vértices para follaje).
// Más ligero en GPU por píxel que StandardMaterial3D y 100% compatible con
// MultiMeshInstance3D y Skeleton3D (dinosaurios animados con pixel-art).
// ============================================================================

group_uniforms Base;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_vertex_color = false;
uniform vec3 emission_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 0.0;
uniform float color_vibrance : hint_range(0.8, 1.35) = 1.06;

group_uniforms CelShading;
uniform vec3 shadow_tint : source_color = vec3(0.34, 0.43, 0.56);
uniform vec3 mid_tint : source_color = vec3(0.76, 0.77, 0.78);
uniform vec3 highlight_tint : source_color = vec3(0.98, 0.96, 0.88);
uniform float shadow_threshold : hint_range(-0.4, 0.6) = -0.05;
uniform float highlight_threshold : hint_range(0.2, 0.95) = 0.52;
uniform float band_smoothness : hint_range(0.005, 0.15) = 0.04;

group_uniforms RimAndSpecular;
uniform vec3 rim_color : source_color = vec3(1.0, 0.96, 0.84);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;
uniform float rim_power : hint_range(1.5, 8.0) = 3.8;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.0;

group_uniforms WindAnimation;
// Solo > 0.0 en árboles, palmeras, arbustos y helechos (0.0 en rocas, edificios y dinos)
uniform float wind_strength : hint_range(0.0, 0.5) = 0.0;
uniform float wind_speed : hint_range(0.2, 5.0) = 1.65;
uniform float wind_height_start : hint_range(0.0, 4.0) = 0.35;

void vertex() {
	if (wind_strength > 0.001) {
		float h = max(0.0, VERTEX.y - wind_height_start);
		if (h > 0.0) {
			vec3 w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
			vec2 cam_d = w_pos.xz - INV_VIEW_MATRIX[3].xz;
			if (dot(cam_d, cam_d) < 13225.0) {
				// Fase única por instancia (compatible con MultiMeshInstance3D vía MODEL_MATRIX[3])
				vec2 inst_xz = MODEL_MATRIX[3].xz;
				float phase = TIME * wind_speed + inst_xz.x * 0.13 + inst_xz.y * 0.17 + VERTEX.y * 0.22;
				float bend = min(h * 0.18, 2.2) * wind_strength;
				VERTEX.x += sin(phase) * bend;
				VERTEX.z += cos(phase * 0.83) * bend * 0.72;
			}
		}
	}
}

void fragment() {
	vec3 col = albedo_color.rgb;
	if (use_albedo_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
	// Realce ligero de saturación/vivacidad tipo película animada low-poly
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = clamp(mix(vec3(luma), col, color_vibrance), vec3(0.0), vec3(1.0));

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;

	if (emission_strength > 0.001) {
		EMISSION = emission_color * emission_strength;
	}
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	// Combinar ángulo solar con sombras proyectadas (ATTENUATION) para que los árboles gigantes
	// proyecten sombras frescas y nítidas sobre todo el suelo y hábitats
	float cast_shadow_mask = smoothstep(0.18, 0.55, ATTENUATION);
	float band_mid = smoothstep(shadow_threshold - band_smoothness, shadow_threshold + band_smoothness, ndotl) * cast_shadow_mask;
	float band_hi = smoothstep(highlight_threshold - band_smoothness, highlight_threshold + band_smoothness, ndotl * ATTENUATION);

	vec3 cel_factor = mix(shadow_tint, mid_tint, band_mid);
	cel_factor = mix(cel_factor, highlight_tint, band_hi);

	// En Godot 4, DIFFUSE_LIGHT se multiplica automáticamente por ALBEDO (dividir por PI conserva energía correcta)
	DIFFUSE_LIGHT += cel_factor * (LIGHT_COLOR * 0.31831);

	// Contorno luminoso estilizado (Rim Light) en siluetas iluminadas
	if (rim_strength > 0.001) {
		float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float f2 = f * f;
		float fresnel = mix(f2 * f, f2 * f2, clamp(rim_power - 3.0, 0.0, 1.0));
		float rim_mask = smoothstep(0.34, 0.50, fresnel * clamp(ndotl + 0.30, 0.0, 1.0)) * ATTENUATION;
		SPECULAR_LIGHT += rim_color * (rim_mask * rim_strength * 0.18) * (LIGHT_COLOR * 0.31831);
	}

	// Destello especular cartoon nítido opcional (ojos, metales, detalles brillantes)
	if (specular_strength > 0.001) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float spec = smoothstep(0.91, 0.945, dot(NORMAL, half_vec)) * ATTENUATION;
		SPECULAR_LIGHT += (LIGHT_COLOR * 0.31831) * (spec * specular_strength * 0.35);
	}
}
