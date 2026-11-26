shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// TERRAIN HABITAT CUTOUT + LOW-POLY TOON SHADER (Godot 4.7 GL Compatibility)
// ============================================================================
// Combina el recorte pixel-perfect OBB bajo hasta 32 hábitats con el mismo
// sombreado estilizado cel-shaded de 3 bandas del resto del parque low-poly.
// ============================================================================

uniform vec4 albedo_color : source_color = vec4(0.25, 0.45, 0.12, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.92;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform bool use_albedo_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

// Parámetros de estilo animado (idénticos a lowpoly_toon.gdshader, calibrados para GL Compatibility)
uniform bool toon_enabled = true;
uniform float color_vibrance : hint_range(0.8, 1.35) = 1.08;
uniform vec3 shadow_tint : source_color = vec3(0.34, 0.43, 0.56);
uniform vec3 mid_tint : source_color = vec3(0.74, 0.75, 0.76);
uniform vec3 highlight_tint : source_color = vec3(0.96, 0.94, 0.88);
uniform float shadow_threshold : hint_range(-0.4, 0.6) = -0.05;
uniform float highlight_threshold : hint_range(0.2, 0.95) = 0.54;
uniform float band_smoothness : hint_range(0.005, 0.15) = 0.045;
uniform vec3 rim_color : source_color = vec3(1.0, 0.96, 0.86);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.08;

// Hasta 32 hábitats con recorte OBB orientado (cualquier tamaño y rotación Y)
const int MAX_CUTOUTS = 32;
uniform int cutout_count = 0;
// AABB global de todos los recortes activos: (min_x, max_x, min_z, max_z) para descarte O(1)
uniform vec4 all_cutouts_bounds = vec4(1.0, -1.0, 1.0, -1.0);
// xy = centro mundial (X, Z), zw = eje X local normalizado en XZ (axis_x.x, axis_x.z)
uniform vec4 cutout_centers_rot[32];
// xy = half_extents (half_x, half_z), z = min_y, w = max_y
uniform vec4 cutout_extents_y[32];

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (cutout_count > 0 && v_world_pos.x >= all_cutouts_bounds.x && v_world_pos.x <= all_cutouts_bounds.y && v_world_pos.z >= all_cutouts_bounds.z && v_world_pos.z <= all_cutouts_bounds.w) {
		for (int i = 0; i < MAX_CUTOUTS; i++) {
			if (i >= cutout_count) {
				break;
			}
			vec4 ey = cutout_extents_y[i];
			if (v_world_pos.y >= ey.z && v_world_pos.y <= ey.w) {
				vec4 cr = cutout_centers_rot[i];
				vec2 d = v_world_pos.xz - cr.xy;
				float lx = d.x * cr.z + d.y * cr.w;
				float lz = -d.x * cr.w + d.y * cr.z;
				if (abs(lx) <= ey.x && abs(lz) <= ey.y) {
					discard;
				}
			}
		}
	}

	vec3 col = albedo_color.rgb;
	if (use_albedo_tex) {
		col *= texture(albedo_tex, UV).rgb;
	}
	if (toon_enabled) {
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = clamp(mix(vec3(luma), col, color_vibrance), vec3(0.0), vec3(1.0));
	}

	ALBEDO = col;
	ROUGHNESS = toon_enabled ? 1.0 : roughness_val;
	METALLIC = toon_enabled ? 0.0 : metallic_val;
	SPECULAR = 0.0;
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	if (toon_enabled) {
		float cast_shadow_mask = smoothstep(0.18, 0.55, ATTENUATION);
		float band_mid = smoothstep(shadow_threshold - band_smoothness, shadow_threshold + band_smoothness, ndotl) * cast_shadow_mask;
		float band_hi = smoothstep(highlight_threshold - band_smoothness, highlight_threshold + band_smoothness, ndotl * ATTENUATION);

		vec3 cel_factor = mix(shadow_tint, mid_tint, band_mid);
		cel_factor = mix(cel_factor, highlight_tint, band_hi);
		DIFFUSE_LIGHT += cel_factor * (LIGHT_COLOR * 0.31831);

		if (rim_strength > 0.001) {
			float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			float f2 = f * f;
			float fresnel = f2 * f2;
			float rim_mask = smoothstep(0.38, 0.54, fresnel * clamp(ndotl + 0.25, 0.0, 1.0)) * ATTENUATION;
			SPECULAR_LIGHT += rim_color * (rim_mask * rim_strength * 0.16) * (LIGHT_COLOR * 0.31831);
		}
	} else {
		DIFFUSE_LIGHT += clamp(ndotl, 0.0, 1.0) * ATTENUATION * (LIGHT_COLOR * 0.31831);
	}
}
