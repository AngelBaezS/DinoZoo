shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// ============================================================================
// AGUA CARICATURESCA ANIMADA — ESTANQUES Y RÍOS DE HÁBITATS (DinoZoo VR)
// Reemplaza las ondas en cuadrícula por red cáustica Voronoi orgánica,
// bandas cel-shaded por profundidad y espuma de orilla animada.
// ============================================================================

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec3 shallow_color : source_color = vec3(0.24, 0.84, 0.88);
uniform vec3 deep_color : source_color = vec3(0.08, 0.48, 0.72);
uniform vec3 caustic_color : source_color = vec3(0.80, 0.98, 1.0);
uniform vec3 foam_color : source_color = vec3(0.96, 0.99, 1.0);

uniform float water_transparency : hint_range(0.15, 0.95) = 0.58;
uniform float wave_speed : hint_range(0.1, 5.0) = 1.4;
uniform float wave_amplitude : hint_range(0.0, 0.15) = 0.025;
uniform float wave_frequency : hint_range(0.1, 4.0) = 0.9;
uniform float caustic_scale : hint_range(0.1, 3.0) = 0.42;

varying vec3 v_world_pos;
varying float v_wave_height;

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float w1 = sin(v_world_pos.x * wave_frequency + v_world_pos.z * (wave_frequency * 0.7) + t) * wave_amplitude;
	float w2 = cos(v_world_pos.x * (wave_frequency * 1.2) - v_world_pos.z * wave_frequency + t * 1.15) * (wave_amplitude * 0.6);
	float total_wave = w1 + w2;
	VERTEX.y += total_wave;
	v_wave_height = total_wave;
}

void fragment() {
	float t = TIME * 0.65;

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
#endif
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= max(abs(view_pos.w), 0.0001) * sign(view_pos.w + 0.00001);
	float water_depth = clamp((-view_pos.z) - (-VERTEX.z), 0.0, 20.0);

	vec2 w_uv = v_world_pos.xz * caustic_scale;
	vec2 warp = vec2(
		sin(w_uv.y * 1.8 + t * 1.2) + cos(w_uv.x * 1.1 - t * 0.8) * 0.4,
		cos(w_uv.x * 1.7 - t * 1.0) + sin(w_uv.y * 1.2 + t * 0.9) * 0.4
	) * 0.30;
	float web_a = voronoi_web(w_uv + warp + vec2(t * 0.25, -t * 0.16), t * 1.3);
	float web_b = voronoi_web(w_uv * 1.45 - warp * 0.7 + vec2(-t * 0.18, t * 0.22), t * 1.1);

	float caustics = clamp((1.0 - smoothstep(0.045, 0.125, web_a)) * 0.75 + (1.0 - smoothstep(0.035, 0.105, web_b)) * 0.35, 0.0, 1.0);

	float depth_band = smoothstep(0.45, 1.8, water_depth);
	vec3 base_col = mix(shallow_color, deep_color, depth_band);
	vec3 col = mix(base_col, caustic_color, caustics * 0.48);

	float wobble = (web_a - 0.5) * 0.25;
	float edge_foam = 1.0 - smoothstep(0.18, 0.48, water_depth + wobble);
	float shore_ring = (1.0 - smoothstep(0.25, 1.35, water_depth)) * smoothstep(0.12, 0.30, water_depth) * smoothstep(0.60, 0.80, sin(water_depth * 7.5 - TIME * 2.6));
	float foam = clamp(max(edge_foam, shore_ring * 0.65), 0.0, 1.0);

	ALBEDO = mix(col, foam_color, foam);
	ALPHA = mix(water_transparency * (0.78 + 0.22 * depth_band), 0.94, foam);
}
