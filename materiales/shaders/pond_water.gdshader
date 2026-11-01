shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Coloración estilizada de agua tropical de estanque
uniform vec3 shallow_color : source_color = vec3(0.26, 0.74, 0.88);
uniform vec3 deep_color : source_color = vec3(0.09, 0.40, 0.58);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);

// Nivel de semitransparencia (permite ver al dinosaurio sumergido caminando por el fondo)
uniform float water_transparency : hint_range(0.1, 1.0) = 0.52;

// Parámetros de oleaje y movimiento líquido
uniform float wave_speed : hint_range(0.1, 5.0) = 1.4;
uniform float wave_amplitude : hint_range(0.0, 0.2) = 0.026;
uniform float wave_frequency : hint_range(0.1, 4.0) = 1.2;

// Detalle de ondas y destellos superficiales
uniform float ripple_speed : hint_range(0.1, 5.0) = 1.8;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.22;

varying vec3 v_world_pos;
varying float v_wave_height;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Oleaje suave del estanque mediante ondas sinusoidales continuas
	float t = TIME * wave_speed;
	float w1 = sin(v_world_pos.x * wave_frequency + v_world_pos.z * (wave_frequency * 0.75) + t) * wave_amplitude;
	float w2 = cos(v_world_pos.x * (wave_frequency * 1.3) - v_world_pos.z * wave_frequency + t * 1.25) * (wave_amplitude * 0.65);
	float total_wave = w1 + w2;

	VERTEX.y += total_wave;
	v_wave_height = total_wave;
}

void fragment() {
	vec3 norm = NORMAL;
	if (!FRONT_FACING) {
		norm = -NORMAL;
	}

	// Perturbación de normales para oleaje detallado y destellos de luz solar
	float rt = TIME * ripple_speed;
	float r1 = sin(v_world_pos.x * 2.8 + v_world_pos.z * 1.9 + rt);
	float r2 = cos(-v_world_pos.x * 2.1 + v_world_pos.z * 3.2 + rt * 1.2);
	float r3 = sin(v_world_pos.x * 4.2 - v_world_pos.z * 3.8 + rt * 0.8);

	vec3 wave_normal_local = vec3(
		(cos(v_world_pos.x * 2.8 + rt) * 0.18 - sin(-v_world_pos.x * 2.1 + rt * 1.2) * 0.12) * ripple_strength,
		1.0,
		(cos(v_world_pos.z * 1.9 + rt) * 0.18 + sin(v_world_pos.z * 3.2 + rt * 1.2) * 0.12) * ripple_strength
	);
	vec3 perturbed_normal = normalize((VIEW_MATRIX * vec4(normalize(wave_normal_local), 0.0)).xyz);
	NORMAL = mix(norm, perturbed_normal, 0.75);

	// Efecto Fresnel para realismo de refracción y reflexión
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	// Gradiente de agua entre zonas someras y profundas
	float depth_blend = clamp((v_wave_height / max(wave_amplitude * 2.0, 0.001)) + 0.5, 0.0, 1.0);
	vec3 base_water = mix(deep_color, shallow_color, depth_blend);

	// Espuma suave en las crestas de ola
	float foam_mask = smoothstep(wave_amplitude * 0.45, wave_amplitude * 0.95, v_wave_height);
	vec3 final_color = mix(mix(base_water, shallow_color * 1.2, fresnel * 0.65), foam_color, foam_mask * 0.6);

	ALBEDO = final_color;
	ROUGHNESS = mix(0.08, 0.4, foam_mask);
	METALLIC = 0.04;
	SPECULAR = 0.65;

	// Semitransparente: permite ver claramente el cuerpo y las patas del dinosaurio sumergido
	ALPHA = mix(water_transparency, 0.92, foam_mask * 0.5);
}

