class_name DinoTRex
extends CharacterBody3D

# ==============================================================================
# TYRANNOSAURUS REX — CEREBRO AUTÓNOMO Y SISTEMA PROCEDURAL DE APEX PREDATOR
# ==============================================================================
# Diseñado para un superdepredador bípedo de ~10m de longitud y ~4.3m de altura:
# - Cinemática bípeda sincronizada milimétricamente con el ciclo de pisada para evitar deslizamiento (foot-skating).
# - Sistema de contrapeso therópodo: la cola de 9 vértebras contrarresta activamente el momento del cráneo masivo.
# - Ondulación serpentina de cola en 9 segmentos con propagación sinusoidal y arrastre inercial.
# - Articulación procedural de mandíbula (Jaw) y cabeza (Head) en persecución, desgarre de carne y rugido.
# - Flexión dinámica de torso y columna vertebral en curvas con peralte (banking roll).
# - Adaptación al terreno mediante 4 sondas físicas con amortiguación elástica de masa.
# ==============================================================================

@export var is_autonomous: bool = true

# Velocidades y cadencia sincronizada (medidas con cinemática real en Godot)
@export_group("Cinemática y Velocidades")
@export var walk_anim_speed: float = 0.90        # Cadencia imponente de patrulla territorial
@export var run_anim_speed: float = 1.25         # Cadencia de embestida / carga hacia la presa
@export var stride_speed_ratio: float = 0.4    # Factor medido: pisada a 0.952 m/s (0.90 * 0.952 = 0.857 m/s, deriva 0.025 m/s)
@export var run_stride_ratio: float = 0.5288      # Factor medido: carrera a 2.115 m/s (1.25 * 2.115 = 2.644 m/s)
@export var turn_speed: float = 0.55             # Velocidad angular (rad/s) con inercia de therópodo pesado
@export var gravity: float = 9.8

var walk_speed: float:
	get: return walk_anim_speed * stride_speed_ratio

var run_speed: float:
	get: return run_anim_speed * run_stride_ratio

# Flexión procedural de cabeza y mandíbula
@export_group("Animación Procedural de Cabeza y Mandíbula")
@export var head_yaw_max: float = 18.0           # Giro horizontal de cabeza (grados)
@export var head_pitch_max: float = 14.0         # Cabeceo vertical de cabeza (grados)
@export var jaw_open_max: float = 28.0           # Apertura máxima procedural de mandíbula en mordida/rugido

# Flexión procedural de columna y torso
@export_group("Animación Procedural de Espina y Pecho")
@export var chest_yaw_max: float = 5.0           # Curvatura lateral del pecho en giros
@export var spine_yaw_max: float = 3.5           # Curvatura lateral de columna
@export var bank_roll_max: float = 3.0           # Peralte dinámico hacia el interior del giro

# Oscilación procedural de la cola (9 vértebras articuladas: Tail.001 - Tail.009)
@export_group("Ondulación Procedural de Cola (9 Segmentos)")
@export var tail_sway_speed: float = 1.15        # Frecuencia de vaivén de cola al caminar
@export var tail_sway_deg: float = 5.2           # Amplitud base en grados
@export var tail_counterweight_deg: float = 9.0  # Contrapeso therópodo: cola gira al lado opuesto del cráneo
@export var tail_turn_lag_deg: float = 6.5       # Arrastre inercial elástico de las vértebras distales

# Adaptación a Pendientes y Desniveles del Terreno
@export_group("Adaptación a Pendientes / Terreno")
@export var slope_adaptation_enabled: bool = true
@export var slope_smooth_speed: float = 4.8           # Suavizado de inclinación corporal
@export var max_slope_pitch_deg: float = 22.0         # Límite de cabeceo en pendientes
@export var max_slope_roll_deg: float = 14.0          # Límite de balanceo lateral
@export var probe_forward_dist: float = 3.2           # Distancia longitudinal de sondas (~5.6m total)
@export var probe_side_dist: float = 1.4              # Distancia transversal de sondas
@export var slope_head_compensate_ratio: float = 0.55 # Cabeza mantiene mirada horizontal
@export var slope_tail_balance_ratio: float = 0.65    # Contrapeso vertical de cola contra gravedad

# Percepción Sensorial Autónoma
@export_group("Cerebro Sensorial Autónomo")
@export var smell_radius: float = 55.0       # Radio olfativo 360° en el gran recinto 100x100m
@export var vision_angle_deg: float = 140.0  # Cono de visión frontal
@export var eat_distance: float = 4.2        # Distancia de alcance para devorar carne

# Límites del recinto (Recinto 80x80m proporcional a T-Rex 12m)
@export_group("Límites de Hábitat")
@export var paddock_bounds_min: Vector2 = Vector2(-28.5, -28.5)
@export var paddock_bounds_max: Vector2 = Vector2(28.5, 28.5)

# Estados del Cerebro del T-Rex
enum State {
	PATROL_TERRITORY,  # Patrulla imponente y pesada por su territorio
	IDLE_STALKING,     # Acecho estático, olfateo del aire y escaneo del perímetro
	SNIFF_TRACKING,    # Rastreo con cabeza baja siguiendo olor de carne
	CHARGE_PREY,       # Carga veloz y agresiva hacia alimento lanzado o presa
	FEEDING_CARCASS,   # Devorando carne de la carcasa o comida lanzada
	TERRITORIAL_ROAR   # Rugido demoledor de superdepredador alfa
}

@onready var visual_model: Node3D = get_node_or_null("VisualModel")

## Optimización de Rendimiento y Culling de Animaciones en FOV
@export_group("Optimización FOV / Culling")
@export var fov_culling_enabled: bool = true
@export var max_animation_distance: float = 160.0

var is_in_view: bool = true
var _visibility_notifier: VisibleOnScreenNotifier3D
var _visibility_check_timer: float = 0.0
const VISIBILITY_CHECK_INTERVAL: float = 0.12
const CULL_LENGTH_HALF: float = 7.0
const CULL_HEIGHT: float = 6.0
const CULL_WIDTH_HALF: float = 2.5

var current_state: State = State.PATROL_TERRITORY:
	set(value):
		if current_state != value:
			current_state = value
			if not has_meta("_managed_by_park_optimizer"):
				print("[Cerebro T-Rex] Estado: ", get_brain_state_name())

var current_food_target: Node3D = null

var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _time_accum: float = 0.0
var _state_timer: float = 0.0
var _current_waypoint: Vector3 = Vector3.ZERO
var _observe_look_angle: float = 0.0
var _roar_cooldown: float = 18.0

# Factores de interpolación elástica
var _turn_factor: float = 0.0
var _pitch_factor: float = 0.0
var _jaw_open_factor: float = 0.0

# Estado dinámico de adaptación al terreno
var _current_slope_pitch: float = 0.0
var _current_slope_roll: float = 0.0
var _current_ground_y_offset: float = 0.0

# Sistema dinámico de evasión de obstáculos
var _terrain_collision_cooldown: float = 0.0
var _obstacle_detour_waypoint: Vector3 = Vector3.ZERO
var _detour_timer: float = 0.0
var _stuck_timer: float = 0.0

# Índices de huesos en Skeleton3D
var _bone_head: int = -1
var _bone_jaw: int = -1
var _jaw_ctrl: DinoJawController = DinoJawController.new()
var _spectator_ctrl: DinoSpectatorController = DinoSpectatorController.new()
var _bone_chest: int = -1
var _bone_spine: int = -1
var _bone_pelvis: int = -1
var _tail_bones: Array[int] = []

# Quaternions de reposo
var _head_rest_q: Quaternion
var _jaw_rest_q: Quaternion
var _chest_rest_q: Quaternion
var _spine_rest_q: Quaternion
var _tail_rest_q: Array[Quaternion] = []

# Puntos de interés del hábitat para patrullaje
const WAYPOINT_CARCASS = Vector3(18.5, 0.5, 8.5)
const WAYPOINT_CAVE = Vector3(-11.2, 0.5, -24.0)
const WAYPOINT_POND = Vector3(-16.6, 0.5, 18.0)
const WAYPOINT_BUNKER = Vector3(32.0, 0.5, 0.5)

func _ready() -> void:
	add_to_group("trexes")
	add_to_group("dinosaurios")
	_init_components()
	_init_skeleton_bones()
	_spectator_ctrl.setup("trex", self)
	_setup_visibility_culling()
	_select_new_patrol_waypoint()
	_state_timer = randf_range(10.0, 16.0)

func _init_components() -> void:
	if not visual_model:
		visual_model = get_node_or_null("VisualModel")
	if visual_model:
		_anim_player = _find_animation_player(visual_model)
		_skeleton = _find_skeleton(visual_model)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null

func _init_skeleton_bones() -> void:
	if not _skeleton:
		return

	_bone_head = _skeleton.find_bone("Head")
	_bone_jaw = _skeleton.find_bone("Jaw")
	_bone_chest = _skeleton.find_bone("Chest")
	_bone_spine = _skeleton.find_bone("Spine")
	_bone_pelvis = _skeleton.find_bone("Pelvis")

	if _bone_head >= 0:
		_head_rest_q = _skeleton.get_bone_rest(_bone_head).basis.get_rotation_quaternion()
	if _bone_jaw >= 0:
		_jaw_rest_q = _skeleton.get_bone_rest(_bone_jaw).basis.get_rotation_quaternion()
	_jaw_ctrl.setup(_skeleton, "trex", _anim_player)
	if _bone_chest >= 0:
		_chest_rest_q = _skeleton.get_bone_rest(_bone_chest).basis.get_rotation_quaternion()
	if _bone_spine >= 0:
		_spine_rest_q = _skeleton.get_bone_rest(_bone_spine).basis.get_rotation_quaternion()

	# Registrar las 9 vértebras de la cola
	_tail_bones.clear()
	_tail_rest_q.clear()
	for i in range(1, 10):
		var bname = "Tail.00%d" % i
		var idx = _skeleton.find_bone(bname)
		if idx >= 0:
			_tail_bones.append(idx)
			_tail_rest_q.append(_skeleton.get_bone_rest(idx).basis.get_rotation_quaternion())

	print("[T-Rex] Huesos registrados con éxito: Cabeza (%d), Mandíbula (%d), Cola (%d vértebras)" % [_bone_head, _bone_jaw, _tail_bones.size()])

# ==============================================================================
# BUCLE DE FÍSICAS Y TOMA DE DECISIONES AUTÓNOMA
# ==============================================================================
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Comprobación periódica de campo de visión para optimizar CPU
	if fov_culling_enabled:
		_visibility_check_timer -= delta
		if _visibility_check_timer <= 0.0:
			_visibility_check_timer = VISIBILITY_CHECK_INTERVAL
			_update_visibility_state()

	_time_accum += delta
	_state_timer -= delta
	_detour_timer = max(0.0, _detour_timer - delta)
	_terrain_collision_cooldown = max(0.0, _terrain_collision_cooldown - delta)
	_roar_cooldown = max(0.0, _roar_cooldown - delta)

	# Sensor predictivo frontal de obstáculos (paredes y vallas)
	if is_autonomous and (current_state in [State.PATROL_TERRITORY, State.CHARGE_PREY, State.SNIFF_TRACKING]) and _terrain_collision_cooldown <= 0.0:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var chest_y = global_position.y + 2.6
			var fwd_h = -global_transform.basis.z
			fwd_h.y = 0.0
			fwd_h = fwd_h.normalized()
			var ray_from = Vector3(global_position.x, chest_y, global_position.z)
			var ray_to = ray_from + fwd_h * 6.5
			var q_pred = PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			q_pred.exclude = [get_rid()]
			var res_pred = space_state.intersect_ray(q_pred)
			if res_pred.size() > 0:
				var hit_norm = res_pred.normal
				if hit_norm.y < 0.65:
					var hit_norm_h = Vector3(hit_norm.x, 0.0, hit_norm.z).normalized()
					if fwd_h.dot(hit_norm_h) < -0.25:
						_trigger_obstacle_turn(hit_norm)

	if is_autonomous:
		_brain_sensory_scan()
		_update_state_machine(delta)
		_execute_movement(delta)

	move_and_slide()

	_check_dynamic_collisions(delta)

	# Solo ejecutar raycasts de adaptación de terreno si el dinosaurio está en campo de visión
	if slope_adaptation_enabled and is_in_view:
		_update_surface_slope(delta)

# ==============================================================================
# PERCEPCIÓN SENSORIAL OLFATIVA Y VISUAL
# ==============================================================================
func _brain_sensory_scan() -> void:
	# Buscar carne disponible en el hábitat (solo dieta carnívora)
	var best_food := DinoFood.find_nearest_for(self, DinoFood.DIET_MEAT, smell_radius, _get_habitat_node(), paddock_bounds_min, paddock_bounds_max)
	var closest_dist: float = global_position.distance_to(best_food.global_position) if is_instance_valid(best_food) else smell_radius

	if best_food and current_state != State.FEEDING_CARCASS:
		if current_food_target != best_food:
			current_food_target = best_food
			if closest_dist < 22.0:
				current_state = State.CHARGE_PREY
			else:
				current_state = State.SNIFF_TRACKING
		return

	if not is_instance_valid(current_food_target):
		current_food_target = null
		if current_state in [State.CHARGE_PREY, State.SNIFF_TRACKING, State.FEEDING_CARCASS]:
			current_state = State.PATROL_TERRITORY
			_select_new_patrol_waypoint()

# ==============================================================================
# MÁQUINA DE ESTADOS Y CONDUCTA DE APEX PREDATOR
# ==============================================================================
func _update_state_machine(delta: float) -> void:
	var busy_with_food := is_instance_valid(current_food_target) or (current_state in [State.SNIFF_TRACKING, State.CHARGE_PREY, State.FEEDING_CARCASS])
	_spectator_ctrl.update(
		delta,
		self,
		_get_habitat_node(),
		Vector3(paddock_bounds_min.x, 0.0, paddock_bounds_min.y),
		Vector3(paddock_bounds_max.x, 0.0, paddock_bounds_max.y),
		busy_with_food
	)

	if _spectator_ctrl.is_controlling() and current_state != State.TERRITORIAL_ROAR:
		if _spectator_ctrl.is_moving_phase():
			current_state = State.PATROL_TERRITORY
			_current_waypoint = _spectator_ctrl.get_move_target(self)
			_state_timer = maxf(_state_timer, 1.0)
		elif _spectator_ctrl.is_posing_phase():
			if _spectator_ctrl.consume_display_trigger():
				current_state = State.TERRITORIAL_ROAR
				_state_timer = _spectator_ctrl.get_display_duration()
			else:
				current_state = State.IDLE_STALKING
				_state_timer = maxf(_state_timer, 0.6)
				_observe_look_angle = _spectator_ctrl.get_head_look_factor(self)
	else:
		match current_state:
			State.PATROL_TERRITORY:
				var dist_to_wp = global_position.distance_to(_current_waypoint)
				if dist_to_wp < 3.2 or _state_timer <= 0.0:
					# Decidir siguiente estado: acecho o rugido
					if _roar_cooldown <= 0.0 and randf() < 0.40:
						current_state = State.TERRITORIAL_ROAR
						_state_timer = 5.0
						_roar_cooldown = randf_range(25.0, 45.0)
					elif randf() < 0.50:
						current_state = State.IDLE_STALKING
						_state_timer = randf_range(4.0, 7.5)
						_observe_look_angle = randf_range(-0.7, 0.7)
					else:
						_select_new_patrol_waypoint()
						_state_timer = randf_range(12.0, 20.0)

			State.IDLE_STALKING:
				if _state_timer <= 0.0:
					if _roar_cooldown <= 0.0 and randf() < 0.35:
						current_state = State.TERRITORIAL_ROAR
						_state_timer = 5.0
						_roar_cooldown = randf_range(25.0, 40.0)
					else:
						current_state = State.PATROL_TERRITORY
						_select_new_patrol_waypoint()
						_state_timer = randf_range(12.0, 18.0)

			State.SNIFF_TRACKING:
				if is_instance_valid(current_food_target):
					var dist = global_position.distance_to(current_food_target.global_position)
					if dist < 12.0:
						current_state = State.CHARGE_PREY
					elif dist < eat_distance:
						current_state = State.FEEDING_CARCASS
						_state_timer = randf_range(5.5, 8.0)
				else:
					current_state = State.PATROL_TERRITORY

			State.CHARGE_PREY:
				if is_instance_valid(current_food_target):
					var dist = Vector2(global_position.x - current_food_target.global_position.x, global_position.z - current_food_target.global_position.z).length()
					if dist <= eat_distance:
						current_state = State.FEEDING_CARCASS
						_state_timer = randf_range(6.0, 9.0)
						velocity = Vector3.ZERO
				else:
					current_state = State.PATROL_TERRITORY

			State.FEEDING_CARCASS:
				velocity = Vector3.ZERO
				if _state_timer <= 0.0:
					if is_instance_valid(current_food_target):
						if current_food_target.has_method("consume"):
							current_food_target.consume()
						else:
							current_food_target.queue_free()
						current_food_target = null
					current_state = State.TERRITORIAL_ROAR
					_state_timer = 5.0

			State.TERRITORIAL_ROAR:
				velocity = Vector3.ZERO
				if _state_timer <= 0.0:
					current_state = State.PATROL_TERRITORY
					_select_new_patrol_waypoint()
					_state_timer = randf_range(14.0, 22.0)

	_handle_animation_playback()

# ==============================================================================
# SISTEMA DE COORDENADAS DEL HÁBITAT Y PUNTOS DE PATRULLAJE
# ==============================================================================
func _get_habitat_node() -> Node3D:
	var p = get_parent()
	while p:
		if p is Node3D and (p.name.begins_with("Habitat") or p == get_tree().current_scene or p.get_parent() == get_tree().root):
			return p as Node3D
		p = p.get_parent()
	if get_parent() is Node3D:
		return get_parent() as Node3D
	return null

func _to_habitat_local(world_pos: Vector3) -> Vector3:
	var hab = _get_habitat_node()
	return hab.to_local(world_pos) if hab else world_pos

func _to_habitat_global(local_pos: Vector3) -> Vector3:
	var hab = _get_habitat_node()
	return hab.to_global(local_pos) if hab else local_pos

func _get_habitat_center() -> Vector3:
	var hab = _get_habitat_node()
	if hab:
		return hab.global_position
	return Vector3.ZERO

func _clamp_to_habitat(world_pos: Vector3, margin: float = 3.5) -> Vector3:
	var hab = _get_habitat_node()
	if hab:
		var loc = hab.to_local(world_pos)
		loc.x = clamp(loc.x, paddock_bounds_min.x + margin, paddock_bounds_max.x - margin)
		loc.z = clamp(loc.z, paddock_bounds_min.y + margin, paddock_bounds_max.y - margin)
		return hab.to_global(loc)
	else:
		var clamped = world_pos
		clamped.x = clamp(clamped.x, paddock_bounds_min.x + margin, paddock_bounds_max.x - margin)
		clamped.z = clamp(clamped.z, paddock_bounds_min.y + margin, paddock_bounds_max.y - margin)
		return clamped

func _pick_random_habitat_waypoint(margin: float = 4.5) -> Vector3:
	var hab = _get_habitat_node()
	var lx = randf_range(paddock_bounds_min.x + margin, paddock_bounds_max.x - margin)
	var lz = randf_range(paddock_bounds_min.y + margin, paddock_bounds_max.y - margin)
	var local_wp = Vector3(lx, 0.5, lz)
	if hab:
		var gw = hab.to_global(local_wp)
		gw.y = global_position.y
		return gw
	local_wp.y = global_position.y
	return local_wp

func _select_new_patrol_waypoint() -> void:
	# El T-Rex patrulla con alta probabilidad hacia puntos emblemáticos del recinto:
	var roll = randf()
	if roll < 0.28:
		# Patrullar hacia la carcasa de dinosaurio
		var wp_loc = WAYPOINT_CARCASS + Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		_current_waypoint = _to_habitat_global(wp_loc)
	elif roll < 0.48:
		# Patrullar hacia la orilla del estanque de agua
		var wp_loc = WAYPOINT_POND + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		_current_waypoint = _to_habitat_global(wp_loc)
	elif roll < 0.68:
		# Patrullar hacia la entrada de la cueva / garganta rocosa
		var wp_loc = WAYPOINT_CAVE + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		_current_waypoint = _to_habitat_global(wp_loc)
	elif roll < 0.82:
		# Merodear frente al búnker de visitantes
		var wp_loc = WAYPOINT_BUNKER + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-5.0, 5.0))
		_current_waypoint = _to_habitat_global(wp_loc)
	else:
		# Patrulla aleatoria en la meseta central
		_current_waypoint = _pick_random_habitat_waypoint(4.0)

	_current_waypoint = _clamp_to_habitat(_current_waypoint, 3.5)
	_current_waypoint.y = global_position.y

# ==============================================================================
# NAVEGACIÓN Y EJECUCIÓN DE MOVIMIENTO BÍPEDO
# ==============================================================================
func _execute_movement(delta: float) -> void:
	var target_pos = _current_waypoint
	if _detour_timer > 0.0:
		target_pos = _obstacle_detour_waypoint
	elif is_instance_valid(current_food_target):
		target_pos = current_food_target.global_position

	var target_spd = 0.0
	match current_state:
		State.PATROL_TERRITORY:
			target_spd = walk_speed
		State.SNIFF_TRACKING:
			target_spd = walk_speed * 0.75
		State.CHARGE_PREY:
			target_spd = run_speed
		State.IDLE_STALKING, State.FEEDING_CARCASS, State.TERRITORIAL_ROAR:
			target_spd = 0.0

	if target_spd > 0.0:
		var to_target = (target_pos - global_position)
		to_target.y = 0.0
		if to_target.length_squared() > 0.1:
			var target_rot = atan2(-to_target.x, -to_target.z)
			var current_rot = global_rotation.y
			var turn_mult = 2.4 if _detour_timer > 0.0 else (1.3 if current_state == State.CHARGE_PREY else 1.0)
			global_rotation.y = lerp_angle(current_rot, target_rot, turn_speed * delta * turn_mult)

			var forward_dir = -global_transform.basis.z
			forward_dir.y = 0.0
			forward_dir = forward_dir.normalized()

			# Reducir velocidad si el ángulo con el objetivo es muy pronunciado
			var angle_diff = abs(wrapf(target_rot - global_rotation.y, -PI, PI))
			var angle_mult = clampf(1.0 - (angle_diff / PI) * 0.6, 0.4, 1.0)

			velocity.x = forward_dir.x * (target_spd * angle_mult)
			velocity.z = forward_dir.z * (target_spd * angle_mult)
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 5.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 5.0)
		if _spectator_ctrl.is_posing_phase() and current_state == State.IDLE_STALKING:
			var pose_turn := _spectator_ctrl.get_showcase_turn(self)
			if pose_turn != 0.0:
				global_rotation.y += pose_turn * turn_speed * delta
			return

	# Evasión preventiva de límites de valla
	_avoid_paddock_boundaries()

func _avoid_paddock_boundaries() -> void:
	if current_state in [State.CHARGE_PREY, State.SNIFF_TRACKING, State.FEEDING_CARCASS] and is_instance_valid(current_food_target):
		return
	var margin = 4.5
	var local_pos = _to_habitat_local(global_position)
	var needs_avoid = false
	if local_pos.x < paddock_bounds_min.x + margin:
		needs_avoid = true
	elif local_pos.x > paddock_bounds_max.x - margin:
		needs_avoid = true
	if local_pos.z < paddock_bounds_min.y + margin:
		needs_avoid = true
	elif local_pos.z > paddock_bounds_max.y - margin:
		needs_avoid = true

	if needs_avoid and _detour_timer <= 0.0:
		var center = _get_habitat_center()
		center.y = global_position.y
		var to_center = (center - global_position).normalized()
		_trigger_obstacle_turn(-to_center, false)

func _check_dynamic_collisions(delta: float) -> void:
	var fwd_h = -global_transform.basis.z
	fwd_h.y = 0.0
	fwd_h = fwd_h.normalized()

	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is StaticBody3D or collider is GridMap:
			var n = col.get_normal()
			if n.y < 0.65: # Pared o roca vertical
				var n_h = Vector3(n.x, 0.0, n.z).normalized()
				if fwd_h.dot(n_h) < -0.20 or _terrain_collision_cooldown <= 0.0:
					_trigger_obstacle_turn(n)
					break

	# Detección anti-atascamiento (especialmente esquinas o muros)
	var real_h_speed = Vector2(velocity.x, velocity.z).length()
	var is_trying_to_move = (current_state in [State.PATROL_TERRITORY, State.CHARGE_PREY, State.SNIFF_TRACKING])
	if is_trying_to_move and real_h_speed < 0.15 and is_on_floor():
		_stuck_timer += delta
		if _stuck_timer > 0.45:
			_stuck_timer = 0.0
			_terrain_collision_cooldown = 0.0 # Anular cooldown para escapar
			var center = _get_habitat_center()
			center.y = global_position.y
			var to_center = (center - global_position).normalized()
			if to_center.length_squared() < 0.01:
				to_center = -fwd_h
			_trigger_obstacle_turn(-to_center, true)
	else:
		_stuck_timer = max(0.0, _stuck_timer - delta * 2.0)

func _trigger_obstacle_turn(col_normal: Vector3, is_stuck: bool = false) -> void:
	if _terrain_collision_cooldown > 0.0 and not is_stuck:
		return
	_terrain_collision_cooldown = 1.6

	var fwd = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var norm = col_normal
	norm.y = 0.0
	if norm.length_squared() < 0.001:
		norm = -fwd
	norm = norm.normalized()

	# Tangentes a la pared
	var tangent_right = norm.cross(Vector3.UP).normalized()
	var tangent_left = -tangent_right

	# Probar flancos con 2 whiskers raycast a +/- 55°
	var space_state = get_world_3d().direct_space_state
	var probe_dist = 6.0
	var ray_y = global_position.y + 2.0

	var dir_left = fwd.rotated(Vector3.UP, deg_to_rad(55.0)).normalized()
	var dir_right = fwd.rotated(Vector3.UP, deg_to_rad(-55.0)).normalized()

	var left_blocked = false
	var right_blocked = false

	if space_state:
		var q_left = PhysicsRayQueryParameters3D.create(
			Vector3(global_position.x, ray_y, global_position.z),
			Vector3(global_position.x, ray_y, global_position.z) + dir_left * probe_dist,
			1
		)
		q_left.exclude = [get_rid()]
		var res_l = space_state.intersect_ray(q_left)
		if res_l.size() > 0 and res_l.normal.y < 0.65:
			left_blocked = true

		var q_right = PhysicsRayQueryParameters3D.create(
			Vector3(global_position.x, ray_y, global_position.z),
			Vector3(global_position.x, ray_y, global_position.z) + dir_right * probe_dist,
			1
		)
		q_right.exclude = [get_rid()]
		var res_r = space_state.intersect_ray(q_right)
		if res_r.size() > 0 and res_r.normal.y < 0.65:
			right_blocked = true

	# Vector hacia el centro del hábitat
	var center = _get_habitat_center()
	center.y = global_position.y
	var to_center = (center - global_position)
	to_center.y = 0.0
	var to_center_dir = to_center.normalized() if to_center.length_squared() > 0.01 else -fwd

	var turn_left: bool = false
	var turn_deg: float = randf_range(80.0, 110.0)
	var new_fwd = fwd

	# Si ambos están bloqueados o está atascado (caso típico de esquina a 90°):
	if (left_blocked and right_blocked) or is_stuck:
		var deflection = deg_to_rad(randf_range(-20.0, 20.0))
		new_fwd = to_center_dir.rotated(Vector3.UP, deflection).normalized()
		turn_left = (fwd.cross(Vector3.UP).dot(new_fwd) < 0.0)
		turn_deg = rad_to_deg(fwd.angle_to(new_fwd))
	elif left_blocked and not right_blocked:
		turn_left = false
		turn_deg = randf_range(80.0, 110.0)
		var angle_rad = deg_to_rad(-turn_deg)
		new_fwd = fwd.rotated(Vector3.UP, angle_rad).normalized()
	elif right_blocked and not left_blocked:
		turn_left = true
		turn_deg = randf_range(80.0, 110.0)
		var angle_rad = deg_to_rad(turn_deg)
		new_fwd = fwd.rotated(Vector3.UP, angle_rad).normalized()
	else:
		# Ambos lados despejados: elegir el que apunte mejor hacia el centro del hábitat
		var dot_l = dir_left.dot(to_center_dir)
		var dot_r = dir_right.dot(to_center_dir)
		if dot_l > dot_r + 0.1:
			turn_left = true
		elif dot_r > dot_l + 0.1:
			turn_left = false
		else:
			turn_left = (fwd.dot(tangent_left) > fwd.dot(tangent_right))
		turn_deg = randf_range(80.0, 110.0)
		var angle_rad = deg_to_rad(turn_deg) if turn_left else deg_to_rad(-turn_deg)
		new_fwd = fwd.rotated(Vector3.UP, angle_rad).normalized()

	# Asegurar que el nuevo rumbo siempre apunte hacia el interior del hábitat
	if new_fwd.dot(to_center_dir) < 0.25 or (left_blocked and right_blocked) or is_stuck:
		new_fwd = to_center_dir.rotated(Vector3.UP, deg_to_rad(randf_range(-30.0, 30.0))).normalized()
		turn_deg = rad_to_deg(fwd.angle_to(new_fwd))
		turn_left = (fwd.cross(Vector3.UP).dot(new_fwd) < 0.0)

	# Proyectar el desvío dentro del hábitat
	var dist_forward = randf_range(9.0, 16.0)
	var detour = global_position + new_fwd * dist_forward
	detour = _clamp_to_habitat(detour, 3.5)
	detour.y = global_position.y

	_current_waypoint = detour
	_obstacle_detour_waypoint = detour
	_detour_timer = 3.5
	_turn_factor = 1.0 if turn_left else -1.0

	# Giro reactivo inicial inmediato para no seguir estrellándose contra la pared
	var target_rot = atan2(-new_fwd.x, -new_fwd.z)
	var lerp_weight = 0.85 if is_stuck else 0.65
	global_rotation.y = lerp_angle(global_rotation.y, target_rot, lerp_weight)

	# Redirigir velocidad
	var cur_speed = Vector2(velocity.x, velocity.z).length()
	var exit_speed = max(cur_speed * 0.6, walk_speed * 0.5)
	velocity.x = new_fwd.x * exit_speed
	velocity.z = new_fwd.z * exit_speed

	if not has_meta("_managed_by_park_optimizer"):
		print("[Cerebro T-Rex] Muro evadido -> Girando hacia ", "IZQUIERDA" if turn_left else "DERECHA", " (", round(turn_deg), "°)")

# ==============================================================================
# REPRODUCCIÓN DE ANIMACIONES BASE
# ==============================================================================
func _handle_animation_playback() -> void:
	match current_state:
		State.PATROL_TERRITORY:
			_play_anim("TRex_Caminar", 0.35, walk_anim_speed)
		State.IDLE_STALKING:
			_play_anim("TRex_Idle", 0.40, 0.85)
		State.SNIFF_TRACKING:
			_play_anim("TRex_Buscar_Comida", 0.30, 0.95)
		State.CHARGE_PREY:
			_play_anim("TRex_Caminar_Correr_Tomar", 0.20, run_anim_speed)
		State.FEEDING_CARCASS:
			_play_anim("TRex_Comer", 0.25, 1.0)
		State.TERRITORIAL_ROAR:
			_play_anim("TRex_Rugir", 0.20, 1.0)

func _play_anim(anim_name: String, blend_time: float, spd: float) -> void:
	if not _anim_player:
		return
	if not _anim_player.has_animation(anim_name):
		return
	if not is_in_view:
		return
	if _anim_player.current_animation != anim_name:
		_anim_player.play(anim_name, blend_time)
	_anim_player.speed_scale = spd

# ==============================================================================
# ANIMACIÓN PROCEDURAL EN TIEMPO REAL (_process)
# ==============================================================================
func _process(delta: float) -> void:
	if not is_in_view:
		return
	# 1. Factores de orientación hacia el objetivo
	var target_turn: float = 0.0
	var target_pitch: float = 0.0
	var target_jaw_open: float = 0.0

	match current_state:
		State.PATROL_TERRITORY, State.SNIFF_TRACKING, State.CHARGE_PREY:
			var tpos = _current_waypoint
			if is_instance_valid(current_food_target):
				tpos = current_food_target.global_position
			target_turn = _steer_towards(tpos)
			if current_state == State.SNIFF_TRACKING:
				target_pitch = -0.6 # Cabeza baja olfateando el rastro
			elif current_state == State.CHARGE_PREY:
				target_pitch = -0.3 # Mirada fija en la presa
				target_jaw_open = 0.4 # Mandíbula entreabierta con dientes afilados listos
		State.IDLE_STALKING:
			target_turn = _observe_look_angle
			target_pitch = sin(_time_accum * 0.9) * 0.2
		State.FEEDING_CARCASS:
			target_pitch = -0.85 # Cabeza contra la presa
			target_jaw_open = 0.5 + sin(_time_accum * 7.0) * 0.45 # Mordidas rítmicas
		State.TERRITORIAL_ROAR:
			target_pitch = 0.45 # Cabeza alzada rugiendo al cielo
			target_jaw_open = 1.0 # Fauces abiertas al máximo

	if _spectator_ctrl.wants_head_look() and current_state in [State.PATROL_TERRITORY, State.IDLE_STALKING]:
		target_turn = _spectator_ctrl.get_head_look_factor(self)
		target_pitch = _spectator_ctrl.get_head_pitch_factor(self)

	_turn_factor = move_toward(_turn_factor, target_turn, delta * 3.2)
	_pitch_factor = move_toward(_pitch_factor, target_pitch, delta * 2.8)
	_jaw_open_factor = move_toward(_jaw_open_factor, target_jaw_open, delta * 4.5)

	var jaw_mode: int = DinoJawController.Mode.CLOSED
	if current_state == State.FEEDING_CARCASS:
		jaw_mode = DinoJawController.Mode.EAT
	elif current_state == State.TERRITORIAL_ROAR:
		jaw_mode = DinoJawController.Mode.ROAR
	_jaw_ctrl.update(delta, jaw_mode, _anim_player)

	# 2. Orientación visual del modelo según la pendiente del terreno
	if visual_model and slope_adaptation_enabled:
		var base_yaw = Basis(Vector3.UP, PI)
		var q_pitch = Quaternion(Vector3.RIGHT, _current_slope_pitch)
		var q_roll = Quaternion(Vector3.FORWARD, _current_slope_roll)
		var slope_rot = Basis(q_pitch * q_roll)
		visual_model.transform.basis = (slope_rot * base_yaw).scaled(Vector3(5.0, 5.0, 5.0))
		visual_model.position.y = _current_ground_y_offset

	if not _skeleton:
		return

	_apply_procedural_animations()

func _steer_towards(target_world_pos: Vector3) -> float:
	var to_tgt = (target_world_pos - global_position)
	to_tgt.y = 0.0
	if to_tgt.length_squared() < 0.01:
		return 0.0
	var fwd = -global_transform.basis.z
	fwd.y = 0.0
	var cross_y = fwd.cross(to_tgt.normalized()).y
	return clampf(cross_y * 1.6, -1.0, 1.0)

# ==============================================================================
# APLICACIÓN DE HUESOS PROCEDURALES
# ==============================================================================
func _apply_procedural_animations() -> void:
	# A. Cabeza y Cuello (Seguimiento horizontal y vertical)
	var yaw_head = _turn_factor * deg_to_rad(head_yaw_max)
	var pitch_head = _pitch_factor * deg_to_rad(head_pitch_max)
	var slope_comp_head = -_current_slope_pitch * slope_head_compensate_ratio

	_apply_bone_rotation(_bone_head, _head_rest_q, pitch_head + slope_comp_head, yaw_head)

	# B. Mandíbula (Cerrada en reposo/caminata; abre en mordidas, rugidos, caza o de vez en cuando)
	_jaw_ctrl.apply()

	# C. Flexión de Columna y Pecho (Curvatura en giros y peralte)
	var yaw_chest = _turn_factor * deg_to_rad(chest_yaw_max)
	var yaw_spine = _turn_factor * deg_to_rad(spine_yaw_max)
	var bank_roll = -_turn_factor * deg_to_rad(bank_roll_max)

	_apply_bone_rotation(_bone_chest, _chest_rest_q, -_current_slope_pitch * 0.15, yaw_chest, bank_roll)
	_apply_bone_rotation(_bone_spine, _spine_rest_q, -_current_slope_pitch * 0.10, yaw_spine, bank_roll * 0.6)

	# D. Sistema de Contrapeso y Ondulación de Cola (9 Vértebras)
	# En un therópodo bípedo: cuando el cráneo gira a la izquierda, la cola gira a la derecha como contrapeso!
	var is_moving = (velocity.length_squared() > 0.05)
	var sway_mult = 1.35 if is_moving else 0.70
	var counter_balance = -_turn_factor * deg_to_rad(tail_counterweight_deg)
	var slope_tail_pitch = -_current_slope_pitch * slope_tail_balance_ratio

	for i in range(_tail_bones.size()):
		var b_idx = _tail_bones[i]
		var rest_q = _tail_rest_q[i]
		var vertebra_ratio = float(i + 1) / float(_tail_bones.size())

		# Desfase de onda sinusoidal traveling-wave
		var phase = _time_accum * tail_sway_speed - (i * 0.35)
		var sway_yaw = sin(phase) * deg_to_rad(tail_sway_deg * (0.6 + vertebra_ratio * 0.9) * sway_mult)

		# Contrapeso therópodo acumulativo
		var yaw_final = sway_yaw + counter_balance * (0.4 + vertebra_ratio * 0.8)
		var pitch_final = slope_tail_pitch * (0.5 + vertebra_ratio * 0.7)

		_apply_tail_rotation(b_idx, rest_q, pitch_final, yaw_final)

func _apply_bone_rotation(bone_idx: int, rest_q: Quaternion, pitch_rad: float, yaw_rad: float, roll_rad: float = 0.0) -> void:
	if bone_idx < 0:
		return
	var q_pitch = Quaternion(Vector3.RIGHT, pitch_rad)
	var q_yaw = Quaternion(Vector3.FORWARD, yaw_rad)
	var q_roll = Quaternion(Vector3.UP, roll_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, rest_q * (q_pitch * q_roll * q_yaw))

func _apply_tail_rotation(bone_idx: int, rest_q: Quaternion, pitch_rad: float, yaw_rad: float) -> void:
	if bone_idx < 0:
		return
	var q_pitch = Quaternion(Vector3.RIGHT, pitch_rad)
	var q_yaw = Quaternion(Vector3.FORWARD, yaw_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, rest_q * (q_pitch * q_yaw))

# ==============================================================================
# ADAPTACIÓN A PENDIENTES DEL TERRENO
# ==============================================================================
func _update_surface_slope(delta: float) -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return

	var fwd = -global_transform.basis.z
	var right = global_transform.basis.x

	var p_center = global_position
	var p_front = p_center + fwd * probe_forward_dist
	var p_rear = p_center - fwd * probe_forward_dist
	var p_left = p_center - right * probe_side_dist
	var p_right = p_center + right * probe_side_dist

	var hit_front = _cast_probe(space_state, p_front)
	var hit_rear = _cast_probe(space_state, p_rear)
	var hit_left = _cast_probe(space_state, p_left)
	var hit_right = _cast_probe(space_state, p_right)

	var target_pitch = 0.0
	var target_roll = 0.0
	var target_y_offset = 0.0

	var has_front_rear = hit_front.has_hit and hit_rear.has_hit
	var has_left_right = hit_left.has_hit and hit_right.has_hit

	if has_front_rear:
		var delta_y = hit_front.pos.y - hit_rear.pos.y
		var dist_h = probe_forward_dist * 2.0
		target_pitch = atan2(delta_y, dist_h)
		target_y_offset = ((hit_front.pos.y + hit_rear.pos.y) * 0.5) - global_position.y
	elif is_on_floor():
		var fn = get_floor_normal()
		var local_fn = global_transform.basis.inverse() * fn
		target_pitch = atan2(local_fn.z, local_fn.y)

	if has_left_right:
		var delta_roll_y = hit_right.pos.y - hit_left.pos.y
		var dist_w = probe_side_dist * 2.0
		target_roll = -atan2(delta_roll_y, dist_w)
	elif is_on_floor():
		var fn = get_floor_normal()
		var local_fn = global_transform.basis.inverse() * fn
		target_roll = atan2(-local_fn.x, local_fn.y)

	target_pitch = clampf(target_pitch, -deg_to_rad(max_slope_pitch_deg), deg_to_rad(max_slope_pitch_deg))
	target_roll = clampf(target_roll, -deg_to_rad(max_slope_roll_deg), deg_to_rad(max_slope_roll_deg))
	target_y_offset = clampf(target_y_offset, -0.6, 0.6)

	var blend_factor = clampf(delta * slope_smooth_speed, 0.0, 1.0)
	_current_slope_pitch = lerp_angle(_current_slope_pitch, target_pitch, blend_factor)
	_current_slope_roll = lerp_angle(_current_slope_roll, target_roll, blend_factor)
	_current_ground_y_offset = lerpf(_current_ground_y_offset, target_y_offset, blend_factor)

func _cast_probe(space_state: PhysicsDirectSpaceState3D, origin_xz: Vector3) -> Dictionary:
	var ray_top = Vector3(origin_xz.x, global_position.y + 4.0, origin_xz.z)
	var ray_bottom = Vector3(origin_xz.x, global_position.y - 4.0, origin_xz.z)
	var query = PhysicsRayQueryParameters3D.create(ray_top, ray_bottom, 1)
	query.exclude = [get_rid()]

	var result = space_state.intersect_ray(query)
	if result.size() > 0:
		return {"has_hit": true, "pos": result.position, "normal": result.normal}
	return {"has_hit": false, "pos": origin_xz, "normal": Vector3.UP}

func get_brain_state_name() -> String:
	match current_state:
		State.PATROL_TERRITORY: return "Patrullando Territorio (Apex Predator)"
		State.IDLE_STALKING: return "Acecho Estático y Olfateo"
		State.SNIFF_TRACKING: return "Rastreando Presa / Olor de Carne"
		State.CHARGE_PREY: return "¡Carga y Persecución de Presa!"
		State.FEEDING_CARCASS: return "Devorando Carne de Carcasa"
		State.TERRITORIAL_ROAR: return "¡Rugido Territorial Alfa!"
	return "Desconocido"

# ==============================================================================
# SISTEMA DE CULLING DE ANIMACIONES (OPTIMIZACIÓN DE FPS Y PROCESADOR)
# ==============================================================================
func _setup_visibility_culling() -> void:
	if not fov_culling_enabled:
		return

	_visibility_notifier = get_node_or_null("VisibilityNotifier")
	if not _visibility_notifier:
		_visibility_notifier = VisibleOnScreenNotifier3D.new()
		_visibility_notifier.name = "VisibilityNotifier"
		_visibility_notifier.aabb = AABB(
			Vector3(-CULL_WIDTH_HALF, 0.0, -CULL_LENGTH_HALF),
			Vector3(CULL_WIDTH_HALF * 2.0, CULL_HEIGHT, CULL_LENGTH_HALF * 2.0)
		)
		add_child(_visibility_notifier)

	_visibility_notifier.screen_entered.connect(_on_screen_entered)
	_visibility_notifier.screen_exited.connect(_on_screen_exited)
	_update_visibility_state(true)

func _on_screen_entered() -> void:
	if has_meta("_managed_by_park_optimizer"):
		return
	_set_animation_active(true)

func _on_screen_exited() -> void:
	if has_meta("_managed_by_park_optimizer"):
		return
	_set_animation_active(false)

func _set_animation_active(active: bool) -> void:
	if has_meta("_managed_by_park_optimizer"):
		return
	if not fov_culling_enabled:
		active = true

	if is_in_view == active:
		return

	is_in_view = active
	set_process(is_in_view)

	if _skeleton:
		_skeleton.process_mode = Node.PROCESS_MODE_INHERIT if is_in_view else Node.PROCESS_MODE_DISABLED

	if _anim_player:
		_anim_player.active = is_in_view
		if is_in_view:
			_handle_animation_playback()

func _update_visibility_state(_force: bool = false) -> void:
	if has_meta("_managed_by_park_optimizer"):
		return
	if not fov_culling_enabled:
		if not is_in_view:
			_set_animation_active(true)
		return

	var cam = get_viewport().get_camera_3d()
	if not cam:
		return

	var cam_pos = cam.global_position
	var dist_sq = global_position.distance_squared_to(cam_pos)

	# Si está más lejos del límite visual, suspender animaciones para ahorrar ciclos
	if dist_sq > max_animation_distance * max_animation_distance:
		_set_animation_active(false)
		return

	# Si el notificador de pantalla en C++ confirma que está en pantalla
	if _visibility_notifier and _visibility_notifier.is_on_screen():
		_set_animation_active(true)
		return

	# Frustum culling directo en el campo de visión de la cámara activa
	if cam.is_position_in_frustum(global_position):
		_set_animation_active(true)
		return

	# Comprobación de extremos corporales para dinosaurios de gran tamaño
	var fwd = -global_transform.basis.z
	var up = global_transform.basis.y
	if cam.is_position_in_frustum(global_position + fwd * CULL_LENGTH_HALF):
		_set_animation_active(true)
		return
	if cam.is_position_in_frustum(global_position - fwd * CULL_LENGTH_HALF):
		_set_animation_active(true)
		return
	if cam.is_position_in_frustum(global_position + up * CULL_HEIGHT):
		_set_animation_active(true)
		return

	_set_animation_active(false)
