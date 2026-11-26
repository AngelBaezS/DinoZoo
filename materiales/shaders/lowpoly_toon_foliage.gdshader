shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ============================================================================
// LOW-POLY TOON FOLIAGE SHADER (Doble cara + Brisa sutil) — DinoZoo VR
// ============================================================================
// Variante cull_disabled para hojas de palmera, helechos, arbustos y copas
// para que se vean sólidos y sombreados desde arriba y desde abajo en VR.
// ============================================================================

group_uniforms Base;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_vertex_color = false;
uniform vec3 emission_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 0.0;
uniform float color_vibrance : hint_range(0.8, 1.35) = 1.10;

group_uniforms CelShading;
uniform vec3 shadow_tint : source_color = vec3(0.46, 0.54, 0.60);
uniform vec3 mid_tint : source_color = vec3(0.78, 0.80, 0.76);
uniform vec3 highlight_tint : source_color = vec3(0.98, 0.96, 0.86);
uniform float shadow_threshold : hint_range(-0.4, 0.6) = -0.08;
uniform float highlight_threshold : hint_range(0.2, 0.95) = 0.52;
uniform float band_smoothness : hint_range(0.005, 0.15) = 0.045;

group_uniforms RimAndSpecular;
uniform vec3 rim_color : source_color = vec3(1.0, 0.96, 0.84);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.20;
uniform float rim_power : hint_range(1.5, 8.0) = 3.6;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.0;

group_uniforms WindAnimation;
uniform float wind_strength : hint_range(0.0, 0.5) = 0.075;
uniform float wind_speed : hint_range(0.2, 5.0) = 1.55;
uniform float wind_height_start : hint_range(0.0, 4.0) = 1.4;

void vertex() {
	if (wind_strength > 0.001) {
		float h = max(0.0, VERTEX.y - wind_height_start);
		if (h > 0.0) {
			vec3 w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
			vec2 cam_d = w_pos.xz - INV_VIEW_MATRIX[3].xz;
			if (dot(cam_d, cam_d) < 10000.0) {
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
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 col = albedo_color.rgb;
	if (use_albedo_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	if (use_vertex_color) {
		col *= COLOR.rgb;
	}
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
	float cast_shadow_mask = smoothstep(0.18, 0.55, ATTENUATION);
	float band_mid = smoothstep(shadow_threshold - band_smoothness, shadow_threshold + band_smoothness, ndotl) * cast_shadow_mask;
	float band_hi = smoothstep(highlight_threshold - band_smoothness, highlight_threshold + band_smoothness, ndotl * ATTENUATION);

	vec3 cel_factor = mix(shadow_tint, mid_tint, band_mid);
	cel_factor = mix(cel_factor, highlight_tint, band_hi);

	DIFFUSE_LIGHT += cel_factor * (LIGHT_COLOR * 0.31831);

	if (rim_strength > 0.001) {
		float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float f2 = f * f;
		float fresnel = mix(f2 * f, f2 * f2, clamp(rim_power - 3.0, 0.0, 1.0));
		float rim_mask = smoothstep(0.34, 0.50, fresnel * clamp(ndotl + 0.30, 0.0, 1.0)) * ATTENUATION;
		SPECULAR_LIGHT += rim_color * (rim_mask * rim_strength * 0.16) * (LIGHT_COLOR * 0.31831);
	}
}
