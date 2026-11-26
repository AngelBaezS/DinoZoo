shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// ============================================================================
// AGUA CARICATURESCA ANIMADA — HÁBITATS ACUÁTICOS (DinoZoo VR / Low-Poly Toon)
// Estilo Wind Waker / Pixar: bandas cel-shaded por profundidad, red cáustica
// Voronoi animada sin cuadrícula, espuma ondulante en orillas/rocas/dinos y
// destellos solares estilizados. Optimizado para GL Compatibility + VR.
// ============================================================================

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// Paleta tropical estilizada (3 bandas de profundidad)
uniform vec3 shallow_color : source_color = vec3(0.20, 0.86, 0.90);
uniform vec3 mid_color : source_color = vec3(0.10, 0.62, 0.88);
uniform vec3 deep_color : source_color = vec3(0.05, 0.36, 0.68);
uniform vec3 caustic_color : source_color = vec3(0.76, 0.98, 1.0);
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 1.0);

// Transparencia equilibrada: color vibrante + dinosaurios claramente visibles
uniform float water_transparency : hint_range(0.15, 0.95) = 0.56;
uniform float shallow_transparency : hint_range(0.10, 0.90) = 0.38;

// Profundidad y espuma de contacto (muros, islas de roca, escaleras, dinosaurios)
uniform float depth_fade_distance : hint_range(1.0, 25.0) = 10.5;
uniform float edge_foam_width : hint_range(0.1, 3.0) = 1.15;
uniform float shore_ripple_width : hint_range(0.2, 6.0) = 3.2;

// Red cáustica Voronoi en coordenadas de mundo (escala consistente en todos los hábitats)
uniform float caustic_scale : hint_range(0.05, 2.0) = 0.24;
uniform float caustic_speed : hint_range(0.05, 3.0) = 0.55;
uniform float caustic_intensity : hint_range(0.0, 1.0) = 0.55;

// Oleaje estilizado suave (compatible con WaterManager.get_water_height_at)
uniform vec4 wave_a = vec4(1.0, 0.2, 0.06, 16.0);
uniform vec4 wave_b = vec4(0.3, 0.8, 0.04, 11.0);
uniform float wave_speed_scale : hint_range(0.2, 3.0) = 1.0;

// Dirección del sol para destellos cel-shaded
uniform vec3 sun_direction = vec3(0.42, 0.78, 0.46);

// Sistema de Impacto de Dinosaurios / Comida (x, z = pos global, y = tiempo, w = fuerza)
uniform vec4 impacts[4];
uniform float ripple_speed = 6.0;
uniform float ripple_frequency = 2.4;
uniform float ripple_decay = 0.35;
uniform float sync_time = -1.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_wave_height;
varying float v_impact_foam;

// Hash rápido 2D sin texturas para Voronoi orgánico
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Voronoi con distancia al borde de celda (F2 - F1) -> red cáustica líquida orgánica sin lunares
float voronoi_web(vec2 x, float t) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			o = 0.5 + 0.42 * sin(t + 6.2831 * o);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return sqrt(f2) - sqrt(f1);
}

vec3 gerstner_wave(vec4 wave, vec3 p, float t, inout vec3 tangent, inout vec3 binormal) {
	float steepness = wave.z;
	float wavelength = max(wave.w, 0.5);
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave.xy + vec2(0.0001, 0.0));
	float f = k * (dot(d, p.xz) - c * t);
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
	float t = (sync_time >= 0.0 ? sync_time : TIME) * wave_speed_scale;
	vec3 orig_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 p = orig_world;

	// 1. Olas estilizadas suaves
	p += gerstner_wave(wave_a, orig_world, t, tangent, binormal);
	p += gerstner_wave(wave_b, orig_world, t, tangent, binormal);

	// 2. Ondas interactivas de salpicadura / impacto
	float total_ripple = 0.0;
	float ripple_foam = 0.0;
	float impact_clock = (sync_time >= 0.0 ? sync_time : TIME);
	for (int i = 0; i < 4; i++) {
		float start_time = impacts[i].y;
		float strength = impacts[i].w;
		if (strength > 0.001 && impact_clock > start_time) {
			float elapsed = impact_clock - start_time;
			if (elapsed < 6.0) {
				float dist = distance(orig_world.xz, impacts[i].xz);
				float wave_front = elapsed * ripple_speed;
				float dist_from_front = abs(dist - wave_front);
				float envelope = exp(-dist_from_front * 0.75) * exp(-elapsed * 0.9) * exp(-dist * ripple_decay * 0.25);
				float phase = sin(dist * ripple_frequency - elapsed * ripple_speed * 2.0);

				float ripple_offset = phase * envelope * strength * 0.45;
				total_ripple += ripple_offset;
				ripple_foam += clamp(envelope * strength * 1.4, 0.0, 1.0);

				vec2 dir_c = normalize(orig_world.xz - impacts[i].xz + vec2(0.0001));
				tangent.y += dir_c.x * ripple_offset * 1.2;
				binormal.y += dir_c.y * ripple_offset * 1.2;
			}
		}
	}

	p.y += total_ripple;

	// Transformar posición y normal correctamente al espacio local (respeta escalas 0.7x / 0.5x)
	mat4 inv_m = inverse(MODEL_MATRIX);
	VERTEX = (inv_m * vec4(p, 1.0)).xyz;
	vec3 w_norm = normalize(cross(binormal, tangent));
	NORMAL = normalize((inv_m * vec4(w_norm, 0.0)).xyz);

	v_world_pos = p;
	v_world_normal = w_norm;
	v_wave_height = p.y - orig_world.y;
	v_impact_foam = clamp(ripple_foam, 0.0, 1.0);
}

void fragment() {
	float t = TIME * caustic_speed;
	vec3 w_norm = normalize(v_world_normal);
	if (!FRONT_FACING) {
		w_norm = -w_norm;
	}

	// 1. Reconstrucción de profundidad real de escena (para bandas toon y espuma en muros/rocas/dinos)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
#endif
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= max(abs(view_pos.w), 0.0001) * sign(view_pos.w + 0.00001);
	float scene_depth = -view_pos.z;
	float frag_depth = -VERTEX.z;
	float water_depth = clamp(scene_depth - frag_depth, 0.0, 40.0);

	// 2. Red cáustica Voronoi animada de doble capa con curvatura fluida caricaturesca
	vec2 w_uv = v_world_pos.xz * caustic_scale;
	vec2 warp = vec2(
		sin(w_uv.y * 1.85 + t * 1.35) + cos(w_uv.x * 1.1 - t * 0.85) * 0.45,
		cos(w_uv.x * 1.75 - t * 1.15) + sin(w_uv.y * 1.2 + t * 0.95) * 0.45
	) * 0.32;

	float web_a = voronoi_web(w_uv + warp + vec2(t * 0.28, -t * 0.18), t * 1.35);
	float web_b = voronoi_web(w_uv * 1.48 - warp * 0.75 + vec2(-t * 0.22, t * 0.26), t * 1.15);

	// Líneas cáusticas curvas, nítidas y caricaturescas (estilo película animada / Wind Waker)
	float line_a = 1.0 - smoothstep(0.045, 0.125, web_a);
	float line_b = 1.0 - smoothstep(0.035, 0.105, web_b);
	float caustics = clamp(line_a * 0.78 + line_b * 0.34, 0.0, 1.0);

	// 3. Bandas de color cel-shaded según profundidad real del agua
	float depth_t = clamp(water_depth / depth_fade_distance, 0.0, 1.0);
	// Transiciones estilizadas por escalones suaves
	float band_mid = smoothstep(0.15, 0.28, depth_t);
	float band_deep = smoothstep(0.52, 0.72, depth_t);
	vec3 base_col = mix(shallow_color, mid_color, band_mid);
	base_col = mix(base_col, deep_color, band_deep);

	// Relieve toon sobre las crestas de ola + espuma sutil en picos más altos
	float wave_crest = smoothstep(0.04, 0.16, v_wave_height);
	float crest_foam = smoothstep(0.145, 0.21, v_wave_height) * line_a * 0.65;
	base_col = mix(base_col, shallow_color * 1.08, wave_crest * 0.36);

	// Mezclar red cáustica luminosa
	vec3 col = mix(base_col, caustic_color, caustics * caustic_intensity * (1.0 - band_deep * 0.20));

	// 4. Espuma caricaturesca animada en orillas, rocas, escaleras y dinosaurios emergiendo
	float foam_wobble = (web_a - 0.5) * 0.62 + sin(v_world_pos.x * 0.75 + v_world_pos.z * 0.65 + TIME * 2.4) * 0.18;
	float edge_foam = 1.0 - smoothstep(edge_foam_width * 0.58, edge_foam_width, water_depth + foam_wobble);

	// Segunda onda concéntrica estilizada pulsando suavemente desde las orillas/rocas
	float ripple_zone = (1.0 - smoothstep(edge_foam_width * 0.65, shore_ripple_width, water_depth)) * smoothstep(0.22, 0.58, water_depth);
	float ripple_ring = smoothstep(0.55, 0.76, sin(water_depth * 4.2 - TIME * 2.5 + foam_wobble * 2.8));
	float shore_ripple = ripple_zone * ripple_ring * 0.78;

	// Espuma de salpicaduras e impactos
	float impact_foam = smoothstep(0.20, 0.48, v_impact_foam);

	float total_foam = clamp(max(max(max(edge_foam, shore_ripple), impact_foam), crest_foam), 0.0, 1.0);

	// 5. Destellos solares toon y brillo Fresnel estilizado
	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 sun_dir = normalize(sun_direction);
	vec3 half_vec = normalize(sun_dir + view_world);

	// Perturbar ligeramente la normal con el patrón líquido para destellos chispeantes
	vec3 spark_n = normalize(w_norm + vec3((web_a - 0.5) * 0.42, 0.0, (web_b - 0.5) * 0.42));
	float ndh = max(dot(spark_n, half_vec), 0.0);
	float toon_spec = smoothstep(0.955, 0.980, ndh);
	float fresnel = pow(1.0 - clamp(dot(w_norm, view_world), 0.0, 1.0), 3.0);

	if (FRONT_FACING) {
		col = mix(col, shallow_color * 1.18, fresnel * 0.36);
		col = mix(col, foam_color, clamp(total_foam + toon_spec * 0.85, 0.0, 1.0));
		ALBEDO = col;
		float base_alpha = mix(shallow_transparency, water_transparency, band_mid);
		ALPHA = clamp(mix(base_alpha, 0.95, max(total_foam, toon_spec * 0.70)) + fresnel * 0.12, 0.0, 0.97);
	} else {
		// Vista desde debajo de la superficie (a través del gran ventanal del acuario):
		// Techo líquido turquesa luminoso con cáusticas danzantes y alta claridad
		vec3 under_col = mix(mid_color * 1.12, shallow_color * 1.18, 0.55);
		under_col = mix(under_col, caustic_color, caustics * 0.58);
		under_col = mix(under_col, foam_color, edge_foam * 0.72);
		ALBEDO = under_col;
		ALPHA = mix(0.24, 0.72, max(edge_foam, caustics * 0.32));
	}
}
