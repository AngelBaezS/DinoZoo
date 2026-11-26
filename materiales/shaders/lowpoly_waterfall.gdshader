shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// ============================================================================
// CASCADA ESTILIZADA ANIMADA LOW-POLY — Ultra ligera (0 texturas, unshaded)
// ============================================================================

uniform vec3 water_deep : source_color = vec3(0.14, 0.56, 0.86);
uniform vec3 water_bright : source_color = vec3(0.36, 0.78, 0.96);
uniform vec3 foam_color : source_color = vec3(0.92, 0.98, 1.0);
uniform float flow_speed : hint_range(0.5, 16.0) = 6.5;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Franjas verticales descendentes estilizadas tipo animación 2D/3D
	float y_flow = v_world_pos.y * 0.14 + TIME * flow_speed;
	float x_coord = (v_world_pos.x + v_world_pos.z) * 0.28;

	float streak_a = sin(x_coord * 2.2 + sin(y_flow * 0.75) * 0.9);
	float streak_b = sin(y_flow * 1.45 + cos(x_coord * 1.5) * 1.1);
	float pattern = streak_a * 0.55 + streak_b * 0.45;

	// Bandas discretas cel-shaded (agua profunda -> agua brillante -> espuma blanca)
	vec3 col = mix(water_deep, water_bright, smoothstep(-0.1, 0.05, pattern));
	float foam_band = smoothstep(0.56, 0.68, pattern);
	col = mix(col, foam_color, foam_band);

	ALBEDO = col;
}
