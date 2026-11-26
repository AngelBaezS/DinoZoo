class_name DinoSpectatorController
extends RefCounted

## ============================================================================
## DINO SPECTATOR CONTROLLER — Interacción Natural con Visitantes (15 Especies)
## ============================================================================
## Cuando el jugador / espectador se acerca (~30 m):
##   1. APPROACHING: El dinosaurio nota al visitante y se acerca con naturalidad
##      (sin velocidad de caza/depredación), siguiendo un arco orgánico hacia el
##      borde seguro de su hábitat más cercano al espectador.
##   2. SHOWCASING: Se exhibe con la conducta propia de su especie (pose 3/4,
##      perfil lateral para lucir velas/placas/maza, nado paralelo junto al
##      cristal del acuario, o planeo sobre el aviario) mirando con curiosidad.
##   3. RETREATING: Si el espectador está muy cerca o concluye la exhibición,
##      da media vuelta y camina / nada / vuela de regreso al interior del recinto.
##   4. COOLDOWN: Descansa / patrulla unos segundos y vuelve a acercarse si el
##      espectador continúa cerca (~30 m).
## ============================================================================

enum Phase {
	NONE,
	APPROACHING,
	SHOWCASING,
	RETREATING,
	COOLDOWN
}

enum ShowcaseStyle {
	CURIOUS_POSE,      # Pose 3/4 mirando al espectador + gesto ocasional
	BROADSIDE_PROFILE, # Se coloca de costado (~65-75°) para lucir vela/placas/cuerpo
	PARALLEL_GLIDE,    # Se desliza paralelo a la valla/cristal observando de lado
	AERIAL_OR_GROUND   # Pose terrestre elegante o sobrevuelo rasante (Quetzalcoatlus)
}

const SPECIES_PROFILES := {
	"aquilops": {
		"detect_radius": 30.0, "too_close_dist": 5.5, "arrive_dist": 1.5, "safe_margin": 1.6,
		"style": ShowcaseStyle.CURIOUS_POSE, "presentation_angle_deg": 28.0,
		"approach_speed_mult": 1.35, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.35,
		"showcase_min": 3.8, "showcase_max": 6.0, "min_close_glance": 1.1,
		"cooldown_min": 6.0, "cooldown_max": 10.5,
		"approach_timeout": 22.0, "retreat_timeout": 18.0,
		"lateral_spread": 1.6, "arc_width": 0.9, "glide_half_span": 0.0,
		"display_chance": 0.65, "display_duration": 2.6,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"velociraptor": {
		"detect_radius": 30.0, "too_close_dist": 6.5, "arrive_dist": 2.0, "safe_margin": 2.2,
		"style": ShowcaseStyle.PARALLEL_GLIDE, "presentation_angle_deg": 82.0,
		"approach_speed_mult": 0.95, "showcase_speed_mult": 0.78, "retreat_speed_mult": 1.05,
		"showcase_min": 5.0, "showcase_max": 7.5, "min_close_glance": 1.5,
		"cooldown_min": 7.5, "cooldown_max": 13.0,
		"approach_timeout": 18.0, "retreat_timeout": 15.0,
		"lateral_spread": 2.2, "arc_width": 1.4, "glide_half_span": 3.8,
		"display_chance": 0.45, "display_duration": 2.4,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"carnotaurus": {
		"detect_radius": 30.0, "too_close_dist": 8.5, "arrive_dist": 2.8, "safe_margin": 3.0,
		"style": ShowcaseStyle.BROADSIDE_PROFILE, "presentation_angle_deg": 65.0,
		"approach_speed_mult": 0.95, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.0,
		"showcase_min": 4.8, "showcase_max": 7.5, "min_close_glance": 1.8,
		"cooldown_min": 8.5, "cooldown_max": 14.5,
		"approach_timeout": 20.0, "retreat_timeout": 18.0,
		"lateral_spread": 3.2, "arc_width": 2.2, "glide_half_span": 0.0,
		"display_chance": 0.50, "display_duration": 3.2,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"espinosaurio": {
		"detect_radius": 34.0, "too_close_dist": 11.0, "arrive_dist": 3.5, "safe_margin": 3.6,
		"style": ShowcaseStyle.BROADSIDE_PROFILE, "presentation_angle_deg": 72.0,
		"approach_speed_mult": 0.95, "showcase_speed_mult": 1.0, "retreat_speed_mult": 0.95,
		"showcase_min": 5.5, "showcase_max": 8.5, "min_close_glance": 2.0,
		"cooldown_min": 9.5, "cooldown_max": 15.5,
		"approach_timeout": 26.0, "retreat_timeout": 22.0,
		"lateral_spread": 4.5, "arc_width": 3.0, "glide_half_span": 0.0,
		"display_chance": 0.40, "display_duration": 3.2,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"estegosaurio": {
		"detect_radius": 30.0, "too_close_dist": 8.5, "arrive_dist": 2.8, "safe_margin": 3.0,
		"style": ShowcaseStyle.BROADSIDE_PROFILE, "presentation_angle_deg": 75.0,
		"approach_speed_mult": 1.05, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.05,
		"showcase_min": 5.5, "showcase_max": 8.5, "min_close_glance": 2.0,
		"cooldown_min": 8.5, "cooldown_max": 14.0,
		"approach_timeout": 24.0, "retreat_timeout": 20.0,
		"lateral_spread": 3.2, "arc_width": 2.0, "glide_half_span": 0.0,
		"display_chance": 0.48, "display_duration": 3.2,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"euoplocephalus": {
		"detect_radius": 30.0, "too_close_dist": 7.0, "arrive_dist": 2.2, "safe_margin": 2.5,
		"style": ShowcaseStyle.BROADSIDE_PROFILE, "presentation_angle_deg": 62.0,
		"approach_speed_mult": 1.10, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.10,
		"showcase_min": 5.0, "showcase_max": 7.8, "min_close_glance": 1.8,
		"cooldown_min": 8.0, "cooldown_max": 13.5,
		"approach_timeout": 22.0, "retreat_timeout": 18.0,
		"lateral_spread": 2.2, "arc_width": 1.4, "glide_half_span": 0.0,
		"display_chance": 0.48, "display_duration": 3.2,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"erlikosaurus": {
		"detect_radius": 30.0, "too_close_dist": 7.0, "arrive_dist": 2.2, "safe_margin": 2.5,
		"style": ShowcaseStyle.CURIOUS_POSE, "presentation_angle_deg": 35.0,
		"approach_speed_mult": 1.0, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.0,
		"showcase_min": 4.8, "showcase_max": 7.5, "min_close_glance": 1.7,
		"cooldown_min": 7.5, "cooldown_max": 13.0,
		"approach_timeout": 20.0, "retreat_timeout": 17.0,
		"lateral_spread": 2.2, "arc_width": 1.5, "glide_half_span": 0.0,
		"display_chance": 0.48, "display_duration": 3.0,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"pachycephalosaurus": {
		"detect_radius": 30.0, "too_close_dist": 7.0, "arrive_dist": 2.2, "safe_margin": 2.5,
		"style": ShowcaseStyle.CURIOUS_POSE, "presentation_angle_deg": 25.0,
		"approach_speed_mult": 1.0, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.05,
		"showcase_min": 4.5, "showcase_max": 7.0, "min_close_glance": 1.6,
		"cooldown_min": 7.0, "cooldown_max": 12.0,
		"approach_timeout": 19.0, "retreat_timeout": 16.0,
		"lateral_spread": 2.2, "arc_width": 1.5, "glide_half_span": 0.0,
		"display_chance": 0.52, "display_duration": 2.8,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"triceratops": {
		"detect_radius": 32.0, "too_close_dist": 9.0, "arrive_dist": 3.0, "safe_margin": 4.2,
		"style": ShowcaseStyle.CURIOUS_POSE, "presentation_angle_deg": 32.0,
		"approach_speed_mult": 1.05, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.05,
		"showcase_min": 5.5, "showcase_max": 8.5, "min_close_glance": 2.0,
		"cooldown_min": 9.0, "cooldown_max": 15.0,
		"approach_timeout": 24.0, "retreat_timeout": 20.0,
		"lateral_spread": 3.8, "arc_width": 2.4, "glide_half_span": 0.0,
		"display_chance": 0.55, "display_duration": 3.5,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"titanosaurus": {
		"detect_radius": 40.0, "too_close_dist": 13.5, "arrive_dist": 5.5, "safe_margin": 6.2,
		"style": ShowcaseStyle.BROADSIDE_PROFILE, "presentation_angle_deg": 70.0,
		"approach_speed_mult": 1.25, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.20,
		"showcase_min": 6.5, "showcase_max": 9.5, "min_close_glance": 2.6,
		"cooldown_min": 11.0, "cooldown_max": 17.5,
		"approach_timeout": 32.0, "retreat_timeout": 28.0,
		"lateral_spread": 6.5, "arc_width": 4.0, "glide_half_span": 0.0,
		"display_chance": 0.55, "display_duration": 4.8,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"trex": {
		"detect_radius": 36.0, "too_close_dist": 11.5, "arrive_dist": 3.8, "safe_margin": 5.6,
		"style": ShowcaseStyle.CURIOUS_POSE, "presentation_angle_deg": 34.0,
		"approach_speed_mult": 1.0, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.0,
		"showcase_min": 5.5, "showcase_max": 8.5, "min_close_glance": 2.2,
		"cooldown_min": 10.5, "cooldown_max": 17.0,
		"approach_timeout": 28.0, "retreat_timeout": 24.0,
		"lateral_spread": 4.5, "arc_width": 3.2, "glide_half_span": 0.0,
		"display_chance": 0.65, "display_duration": 4.6,
		"is_3d": false, "showcase_y_pref": 0.0, "retreat_y_pref": 0.0
	},
	"quetzalcoatlus": {
		"detect_radius": 34.0, "too_close_dist": 9.0, "arrive_dist": 3.2, "safe_margin": 3.4,
		"style": ShowcaseStyle.AERIAL_OR_GROUND, "presentation_angle_deg": 40.0,
		"approach_speed_mult": 1.15, "showcase_speed_mult": 1.0, "retreat_speed_mult": 1.10,
		"showcase_min": 5.0, "showcase_max": 8.0, "min_close_glance": 1.8,
		"cooldown_min": 9.0, "cooldown_max": 15.0,
		"approach_timeout": 22.0, "retreat_timeout": 18.0,
		"lateral_spread": 4.0, "arc_width": 2.5, "glide_half_span": 9.0,
		"display_chance": 0.50, "display_duration": 6.5,
		"is_3d": true, "showcase_y_pref": 7.5, "retreat_y_pref": 10.5
	},
	"mosasaurus": {
		"detect_radius": 38.0, "too_close_dist": 15.0, "arrive_dist": 4.5, "safe_margin": 6.0,
		"style": ShowcaseStyle.PARALLEL_GLIDE, "presentation_angle_deg": 90.0,
		"approach_speed_mult": 1.0, "showcase_speed_mult": 0.78, "retreat_speed_mult": 1.05,
		"showcase_min": 6.5, "showcase_max": 10.0, "min_close_glance": 2.4,
		"cooldown_min": 8.0, "cooldown_max": 13.5,
		"approach_timeout": 26.0, "retreat_timeout": 24.0,
		"lateral_spread": 6.0, "arc_width": 4.0, "glide_half_span": 14.0,
		"display_chance": 0.0, "display_duration": 0.0,
		"is_3d": true, "showcase_y_pref": 10.0, "retreat_y_pref": 7.2
	},
	"elasmosaurus": {
		"detect_radius": 34.0, "too_close_dist": 12.0, "arrive_dist": 3.6, "safe_margin": 3.8,
		"style": ShowcaseStyle.PARALLEL_GLIDE, "presentation_angle_deg": 90.0,
		"approach_speed_mult": 0.95, "showcase_speed_mult": 0.70, "retreat_speed_mult": 1.0,
		"showcase_min": 6.0, "showcase_max": 9.0, "min_close_glance": 2.0,
		"cooldown_min": 7.5, "cooldown_max": 12.5,
		"approach_timeout": 22.0, "retreat_timeout": 20.0,
		"lateral_spread": 4.2, "arc_width": 3.0, "glide_half_span": 9.5,
		"display_chance": 0.42, "display_duration": 4.0,
		"is_3d": true, "showcase_y_pref": 8.2, "retreat_y_pref": 5.2
	},
	"liopleurodon": {
		"detect_radius": 32.0, "too_close_dist": 10.0, "arrive_dist": 3.2, "safe_margin": 3.5,
		"style": ShowcaseStyle.PARALLEL_GLIDE, "presentation_angle_deg": 90.0,
		"approach_speed_mult": 0.95, "showcase_speed_mult": 0.72, "retreat_speed_mult": 1.0,
		"showcase_min": 5.5, "showcase_max": 8.5, "min_close_glance": 1.8,
		"cooldown_min": 7.0, "cooldown_max": 12.0,
		"approach_timeout": 20.0, "retreat_timeout": 18.0,
		"lateral_spread": 3.4, "arc_width": 2.5, "glide_half_span": 7.5,
		"display_chance": 0.0, "display_duration": 0.0,
		"is_3d": true, "showcase_y_pref": 6.2, "retreat_y_pref": 3.8
	},
}

var _profile: Dictionary = {}
var _species_key: String = ""
var _phase: int = Phase.NONE
var _phase_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _showcase_duration: float = 6.0
var _time_accum: float = 0.0

var _spectator_pos: Vector3 = Vector3.ZERO
var _has_spectator: bool = false
var _dist_to_spectator: float = 9999.0

var _showcase_point: Vector3 = Vector3.ZERO
var _glide_end_point: Vector3 = Vector3.ZERO
var _retreat_point: Vector3 = Vector3.ZERO
var _aerial_flyby_point: Vector3 = Vector3.ZERO
var _aerial_retreat_point: Vector3 = Vector3.ZERO

var _lateral_sign: float = 1.0
var _lateral_jitter: float = 1.0
var _approach_arc_sign: float = 1.0
var _presentation_side: float = 1.0
var _initial_delay: float = 0.0

var _display_trigger_time: float = 2.0
var _display_rolled: bool = false
var _display_fired: bool = false
var _pending_display_trigger: bool = false
var _entered_too_close: bool = false


func setup(species_key: String, dino: Node3D) -> void:
	_species_key = species_key.to_lower().replace("dino_", "").replace("dino", "").replace("_", "").replace("-", "")
	if _species_key == "swimmer":
		_species_key = "mosasaurus"
	if SPECIES_PROFILES.has(_species_key):
		_profile = SPECIES_PROFILES[_species_key]
	else:
		_profile = SPECIES_PROFILES["triceratops"]

	var inst_id := absi(dino.get_instance_id()) if is_instance_valid(dino) else randi()
	_lateral_sign = 1.0 if (inst_id % 2 == 0) else -1.0
	_lateral_jitter = 0.55 + float((inst_id >> 3) % 10) * 0.06
	_presentation_side = _lateral_sign
	_approach_arc_sign = -_lateral_sign
	_initial_delay = float((inst_id >> 1) % 7) * 0.18
	_time_accum = float(inst_id % 17) * 0.37

	_phase = Phase.NONE
	_phase_timer = 0.0
	_cooldown_timer = 0.0
	_pending_display_trigger = false


func update(
	delta: float,
	dino: Node3D,
	hab: Node3D,
	bounds_min: Vector3,
	bounds_max: Vector3,
	busy_with_food: bool,
	max_y_world: float = 1e9
) -> void:
	_time_accum += delta

	if not is_instance_valid(dino):
		_phase = Phase.NONE
		_has_spectator = false
		return

	if busy_with_food:
		if _phase != Phase.NONE and _phase != Phase.COOLDOWN:
			_phase = Phase.NONE
		_pending_display_trigger = false
		return

	var spec_info := _resolve_spectator_pos(dino)
	_has_spectator = bool(spec_info["found"])
	if not _has_spectator:
		if _phase != Phase.NONE:
			_phase = Phase.NONE
		return

	_spectator_pos = spec_info["pos"] as Vector3
	var dino_pos := dino.global_position
	_dist_to_spectator = Vector2(dino_pos.x - _spectator_pos.x, dino_pos.z - _spectator_pos.z).length()

	var detect_r: float = float(_profile["detect_radius"])
	var exit_r: float = detect_r + 6.5
	var too_close: float = float(_profile["too_close_dist"])
	var arrive_d: float = float(_profile["arrive_dist"])
	var style: int = int(_profile["style"])

	# Retraso inicial escalonado entre individuos del mismo recinto
	if _initial_delay > 0.0 and _phase == Phase.NONE:
		if _dist_to_spectator <= detect_r:
			_initial_delay -= delta
		return

	match _phase:
		Phase.NONE:
			if _dist_to_spectator <= detect_r:
				_begin_approaching(dino, hab, bounds_min, bounds_max, max_y_world)

		Phase.APPROACHING:
			_phase_timer += delta
			if _dist_to_spectator > exit_r:
				_phase = Phase.NONE
				return

			var dist_target := _dist_to_point(dino_pos, _showcase_point, bool(_profile["is_3d"]))
			if dist_target <= arrive_d or _dist_to_spectator <= too_close or _phase_timer >= float(_profile["approach_timeout"]):
				_begin_showcasing(dino, hab, bounds_min, bounds_max, max_y_world, _dist_to_spectator <= too_close)

		Phase.SHOWCASING:
			_phase_timer += delta
			if _dist_to_spectator > exit_r:
				_phase = Phase.NONE
				return

			var min_glance: float = float(_profile["min_close_glance"])
			if _dist_to_spectator < too_close and _phase_timer >= min_glance:
				_begin_retreating(dino, hab, bounds_min, bounds_max, max_y_world)
				return

			if style == ShowcaseStyle.PARALLEL_GLIDE:
				var dist_glide := _dist_to_point(dino_pos, _glide_end_point, bool(_profile["is_3d"]))
				if dist_glide <= arrive_d:
					_begin_retreating(dino, hab, bounds_min, bounds_max, max_y_world)
					return

			# Disparar animación distintiva a mitad de la exhibición (solo si queda margen natural)
			if not _display_fired and _display_rolled and _phase_timer >= _display_trigger_time:
				if (_showcase_duration - _phase_timer) >= 1.2:
					_pending_display_trigger = true
				_display_fired = true

			if _phase_timer >= _showcase_duration:
				_begin_retreating(dino, hab, bounds_min, bounds_max, max_y_world)

		Phase.RETREATING:
			_phase_timer += delta
			var dist_ret := _dist_to_point(dino_pos, _retreat_point, bool(_profile["is_3d"]))
			if dist_ret <= arrive_d or _phase_timer >= float(_profile["retreat_timeout"]):
				_begin_cooldown()

		Phase.COOLDOWN:
			_cooldown_timer -= delta
			if _dist_to_spectator > exit_r and _cooldown_timer <= 0.0:
				_phase = Phase.NONE
			elif _cooldown_timer <= 0.0 and _dist_to_spectator <= detect_r:
				# Volver a acercarse para mostrarse de nuevo con ligera variación lateral
				_presentation_side = -_presentation_side
				_approach_arc_sign = -_approach_arc_sign
				_lateral_jitter = randf_range(0.55, 1.15)
				_begin_approaching(dino, hab, bounds_min, bounds_max, max_y_world)


func _begin_approaching(dino: Node3D, hab: Node3D, bounds_min: Vector3, bounds_max: Vector3, max_y_world: float) -> void:
	_phase = Phase.APPROACHING
	_phase_timer = 0.0
	_pending_display_trigger = false
	_entered_too_close = false
	_compute_showcase_waypoints(dino, hab, bounds_min, bounds_max, max_y_world)


func _begin_showcasing(dino: Node3D, hab: Node3D, bounds_min: Vector3, bounds_max: Vector3, max_y_world: float, too_close: bool) -> void:
	_phase = Phase.SHOWCASING
	_phase_timer = 0.0
	_entered_too_close = too_close
	_pending_display_trigger = false
	_display_fired = false

	if too_close:
		_showcase_duration = float(_profile["min_close_glance"]) + randf_range(0.0, 0.5)
		_display_rolled = false
	else:
		_showcase_duration = randf_range(float(_profile["showcase_min"]), float(_profile["showcase_max"]))
		_display_rolled = (randf() < float(_profile["display_chance"]))
		_display_trigger_time = randf_range(1.1, maxf(1.3, _showcase_duration * 0.45))

	_compute_showcase_waypoints(dino, hab, bounds_min, bounds_max, max_y_world)


func _begin_retreating(dino: Node3D, hab: Node3D, bounds_min: Vector3, bounds_max: Vector3, max_y_world: float) -> void:
	_phase = Phase.RETREATING
	_phase_timer = 0.0
	_pending_display_trigger = false
	_compute_retreat_waypoints(dino, hab, bounds_min, bounds_max, max_y_world)


func _begin_cooldown() -> void:
	_phase = Phase.COOLDOWN
	_phase_timer = 0.0
	_pending_display_trigger = false
	_cooldown_timer = randf_range(float(_profile["cooldown_min"]), float(_profile["cooldown_max"]))


func _compute_showcase_waypoints(dino: Node3D, hab: Node3D, bounds_min: Vector3, bounds_max: Vector3, max_y_world: float) -> void:
	var bmin := _shrink_bounds_xz(bounds_min, bounds_max, float(_profile["safe_margin"]), true)
	var bmax := _shrink_bounds_xz(bounds_min, bounds_max, float(_profile["safe_margin"]), false)
	var p_loc := hab.to_local(_spectator_pos) if hab else _spectator_pos

	var center_xz := Vector2((bmin.x + bmax.x) * 0.5, (bmin.z + bmax.z) * 0.5)
	var player_xz := Vector2(p_loc.x, p_loc.z)
	var to_p := (player_xz - center_xz)
	if to_p.length_squared() < 0.01:
		to_p = Vector2(0.0, 1.0)
	var dir_to_p := to_p.normalized()
	var tangent := Vector2(-dir_to_p.y, dir_to_p.x)

	# Punto base más cercano al espectador dentro del hábitat seguro
	var base_xz := Vector2(
		clampf(player_xz.x, bmin.x, bmax.x),
		clampf(player_xz.y, bmin.z, bmax.z)
	)
	base_xz += tangent * (_lateral_sign * float(_profile["lateral_spread"]) * _lateral_jitter)
	base_xz.x = clampf(base_xz.x, bmin.x, bmax.x)
	base_xz.y = clampf(base_xz.y, bmin.z, bmax.z)

	var y_loc: float = dino.global_position.y
	if bool(_profile["is_3d"]):
		y_loc = clampf(float(_profile["showcase_y_pref"]), bounds_min.y + 0.8, maxf(bounds_min.y + 0.9, bounds_max.y - 0.5))

	var style: int = int(_profile["style"])
	if style == ShowcaseStyle.PARALLEL_GLIDE:
		var span: float = float(_profile["glide_half_span"])
		var start_xz := base_xz - tangent * (_presentation_side * span * 0.6)
		var end_xz := base_xz + tangent * (_presentation_side * span)
		start_xz = Vector2(clampf(start_xz.x, bmin.x, bmax.x), clampf(start_xz.y, bmin.z, bmax.z))
		end_xz = Vector2(clampf(end_xz.x, bmin.x, bmax.x), clampf(end_xz.y, bmin.z, bmax.z))
		_showcase_point = _to_global_pos(hab, Vector3(start_xz.x, y_loc, start_xz.y), dino.global_position.y, bool(_profile["is_3d"]), max_y_world)
		_glide_end_point = _to_global_pos(hab, Vector3(end_xz.x, y_loc, end_xz.y), dino.global_position.y, bool(_profile["is_3d"]), max_y_world)
	else:
		_showcase_point = _to_global_pos(hab, Vector3(base_xz.x, y_loc, base_xz.y), dino.global_position.y, bool(_profile["is_3d"]), max_y_world)
		_glide_end_point = _showcase_point

	# Para Quetzalcoatlus: punto de sobrevuelo escénico ligeramente elevado frente al espectador
	var fly_y := clampf(float(_profile["showcase_y_pref"]), bounds_min.y + 3.0, maxf(bounds_min.y + 4.0, bounds_max.y - 2.5))
	var fly_xz := base_xz + tangent * (_presentation_side * float(_profile["glide_half_span"]) * 0.45)
	fly_xz = Vector2(clampf(fly_xz.x, bmin.x, bmax.x), clampf(fly_xz.y, bmin.z, bmax.z))
	_aerial_flyby_point = _to_global_pos(hab, Vector3(fly_xz.x, fly_y, fly_xz.y), dino.global_position.y, true, 1e9)


func _compute_retreat_waypoints(dino: Node3D, hab: Node3D, bounds_min: Vector3, bounds_max: Vector3, max_y_world: float) -> void:
	var bmin := _shrink_bounds_xz(bounds_min, bounds_max, float(_profile["safe_margin"]), true)
	var bmax := _shrink_bounds_xz(bounds_min, bounds_max, float(_profile["safe_margin"]), false)
	var p_loc := hab.to_local(_spectator_pos) if hab else _spectator_pos

	var center_xz := Vector2((bmin.x + bmax.x) * 0.5, (bmin.z + bmax.z) * 0.5)
	var half_ext := Vector2((bmax.x - bmin.x) * 0.5, (bmax.z - bmin.z) * 0.5)
	var player_xz := Vector2(p_loc.x, p_loc.z)

	var away_dir := (center_xz - player_xz)
	if away_dir.length_squared() < 0.04:
		var d_loc := hab.to_local(dino.global_position) if hab else dino.global_position
		away_dir = (center_xz - Vector2(d_loc.x, d_loc.z))
	if away_dir.length_squared() < 0.04:
		away_dir = Vector2(-_presentation_side, -0.6)
	away_dir = away_dir.normalized()

	var tangent := Vector2(-away_dir.y, away_dir.x)
	var depth_ratio := randf_range(0.58, 0.88)
	var lat_ratio := randf_range(-0.45, 0.45)

	var target_xz := Vector2(
		center_xz.x + away_dir.x * half_ext.x * depth_ratio + tangent.x * half_ext.x * lat_ratio,
		center_xz.y + away_dir.y * half_ext.y * depth_ratio + tangent.y * half_ext.y * lat_ratio
	)
	target_xz.x = clampf(target_xz.x, bmin.x, bmax.x)
	target_xz.y = clampf(target_xz.y, bmin.z, bmax.z)

	var y_loc: float = dino.global_position.y
	if bool(_profile["is_3d"]):
		y_loc = clampf(float(_profile["retreat_y_pref"]), bounds_min.y + 0.8, maxf(bounds_min.y + 0.9, bounds_max.y - 0.5))

	_retreat_point = _to_global_pos(hab, Vector3(target_xz.x, y_loc, target_xz.y), dino.global_position.y, bool(_profile["is_3d"]), max_y_world)

	var fly_ret_y := clampf(float(_profile["retreat_y_pref"]), bounds_min.y + 3.5, maxf(bounds_min.y + 4.5, bounds_max.y - 2.0))
	_aerial_retreat_point = _to_global_pos(hab, Vector3(target_xz.x, fly_ret_y, target_xz.y), dino.global_position.y, true, 1e9)


func _shrink_bounds_xz(bmin: Vector3, bmax: Vector3, margin: float, is_min: bool) -> Vector3:
	var half_x := (bmax.x - bmin.x) * 0.42
	var half_z := (bmax.z - bmin.z) * 0.42
	var mx := minf(margin, maxf(0.5, half_x))
	var mz := minf(margin, maxf(0.5, half_z))
	if is_min:
		return Vector3(bmin.x + mx, bmin.y, bmin.z + mz)
	return Vector3(bmax.x - mx, bmax.y, bmax.z - mz)


func _to_global_pos(hab: Node3D, local_pt: Vector3, fallback_y: float, use_3d_y: bool, max_y_world: float) -> Vector3:
	var world_pt := hab.to_global(local_pt) if hab else local_pt
	if not use_3d_y:
		world_pt.y = fallback_y
	elif max_y_world < 1e8:
		world_pt.y = minf(world_pt.y, max_y_world - 0.25)
	return world_pt


func _dist_to_point(a: Vector3, b: Vector3, use_3d: bool) -> float:
	if use_3d:
		var dx := a.x - b.x
		var dz := a.z - b.z
		var dy := (a.y - b.y) * 0.55
		return sqrt(dx * dx + dy * dy + dz * dz)
	return Vector2(a.x - b.x, a.z - b.z).length()


func _resolve_spectator_pos(dino: Node3D) -> Dictionary:
	var tree := dino.get_tree()
	if tree:
		var root := tree.root
		if root and root.has_meta("_test_spectator_pos"):
			var tpos = root.get_meta("_test_spectator_pos")
			if tpos is Vector3:
				return {"found": true, "pos": tpos}

	var vp := dino.get_viewport()
	if vp:
		var cam := vp.get_camera_3d()
		if is_instance_valid(cam):
			return {"found": true, "pos": cam.global_position}

	if tree:
		var p_node := tree.get_first_node_in_group("player") as Node3D
		if is_instance_valid(p_node):
			return {"found": true, "pos": p_node.global_position}
		if tree.current_scene:
			var pvr := tree.current_scene.find_child("PlayerVR", true, false) as Node3D
			if is_instance_valid(pvr):
				return {"found": true, "pos": pvr.global_position}

	return {"found": false, "pos": Vector3.ZERO}


func is_controlling() -> bool:
	return _phase == Phase.APPROACHING or _phase == Phase.SHOWCASING or _phase == Phase.RETREATING


func get_phase() -> int:
	return _phase


func get_phase_name() -> String:
	match _phase:
		Phase.NONE: return "NONE"
		Phase.APPROACHING: return "APPROACHING"
		Phase.SHOWCASING: return "SHOWCASING"
		Phase.RETREATING: return "RETREATING"
		Phase.COOLDOWN: return "COOLDOWN"
	return "UNKNOWN"


func is_moving_phase() -> bool:
	if _phase == Phase.APPROACHING or _phase == Phase.RETREATING:
		return true
	if _phase == Phase.SHOWCASING and int(_profile.get("style", 0)) == ShowcaseStyle.PARALLEL_GLIDE:
		return true
	return false


func is_posing_phase() -> bool:
	return _phase == Phase.SHOWCASING and int(_profile.get("style", 0)) != ShowcaseStyle.PARALLEL_GLIDE


func get_move_target(dino: Node3D) -> Vector3:
	if _phase == Phase.SHOWCASING:
		return _glide_end_point
	if _phase == Phase.RETREATING:
		return _retreat_point

	# APPROACHING: curva orgánica sutil hasta converger a ~3.5 m del destino
	if not is_instance_valid(dino):
		return _showcase_point

	var to_goal := _showcase_point - dino.global_position
	to_goal.y = 0.0
	var d := to_goal.length()
	var arc_w := float(_profile.get("arc_width", 0.0))
	if d > 4.2 and arc_w > 0.05:
		var dir := to_goal / d
		var right := Vector3(-dir.z, 0.0, dir.x)
		var arc_blend := clampf((d - 4.2) / 10.0, 0.0, 1.0)
		var mid := dino.global_position.lerp(_showcase_point, 0.48)
		mid += right * (_approach_arc_sign * arc_w * arc_blend)
		mid.y = _showcase_point.y
		return mid
	return _showcase_point


func get_speed_multiplier() -> float:
	match _phase:
		Phase.APPROACHING: return float(_profile.get("approach_speed_mult", 1.0))
		Phase.SHOWCASING: return float(_profile.get("showcase_speed_mult", 1.0))
		Phase.RETREATING: return float(_profile.get("retreat_speed_mult", 1.0))
	return 1.0


func get_showcase_turn(dino: Node3D) -> float:
	if not _has_spectator or not is_instance_valid(dino):
		return 0.0
	var to_spec := _spectator_pos - dino.global_position
	to_spec.y = 0.0
	if to_spec.length_squared() < 0.01:
		return 0.0

	var pres_angle := deg_to_rad(float(_profile.get("presentation_angle_deg", 35.0)))
	var desired_dir := to_spec.normalized().rotated(Vector3.UP, _presentation_side * pres_angle)
	var local_dir := dino.global_transform.basis.inverse() * desired_dir
	var yaw_err := atan2(-local_dir.x, -local_dir.z)
	if absf(yaw_err) < 0.09:
		return 0.0
	return clampf(yaw_err * 1.35, -0.85, 0.85)


func wants_head_look() -> bool:
	if not _has_spectator:
		return false
	if _phase == Phase.SHOWCASING:
		return true
	if _phase == Phase.APPROACHING:
		var detect_r := float(_profile.get("detect_radius", 30.0))
		return _dist_to_spectator <= detect_r * 0.78
	return false


func get_head_look_factor(dino: Node3D) -> float:
	if not _has_spectator or not is_instance_valid(dino):
		return 0.0
	var to_spec := _spectator_pos - dino.global_position
	to_spec.y = 0.0
	if to_spec.length_squared() < 0.01:
		return 0.0
	var local_dir := dino.global_transform.basis.inverse() * to_spec.normalized()
	var wave := sin(_time_accum * 0.95) * 0.14
	return clampf(-local_dir.x * 1.25 + wave, -0.92, 0.92)


func get_head_pitch_factor(dino: Node3D) -> float:
	if not _has_spectator or not is_instance_valid(dino):
		return 0.0
	var dy := (_spectator_pos.y + 1.1) - (dino.global_position.y + 2.4)
	var dxz := maxf(3.0, Vector2(_spectator_pos.x - dino.global_position.x, _spectator_pos.z - dino.global_position.z).length())
	var target_pitch := clampf(atan2(dy, dxz) * 1.35, -0.48, 0.42)
	return target_pitch + sin(_time_accum * 0.7) * 0.06


func consume_display_trigger() -> bool:
	if _pending_display_trigger:
		_pending_display_trigger = false
		return true
	return false


func get_display_duration() -> float:
	return float(_profile.get("display_duration", 3.2))


func get_aerial_flyby_waypoint() -> Vector3:
	return _aerial_flyby_point


func get_aerial_retreat_waypoint() -> Vector3:
	return _aerial_retreat_point
