class_name DinoTitanosaurus
extends CharacterBody3D

# ==============================================================================
# TITANOSAURUS — CEREBRO AUTÓNOMO Y SISTEMA PROCEDURAL DE SAURÓPODO COLOSAL
# ==============================================================================
# Diseñado específicamente para un saurópodo gigante de ~19m de largo y ~6.4m de alto:
# - Marcha lenta, majestuosa y pesada con gran inercia rotacional y traslacional.
# - Cinemática procedural de cuello largo (4 vértebras) que lidera los giros con curvas orgánicas.
# - Cola flexible multi-segmento (5 vértebras) con propagación de onda serpentina y contrapeso.
# - Adaptación articular al terreno mediante sondas físicas delanteras, traseras y laterales.
# - Detección sensorial 360° de alimento (lanzado o torres de forraje alto) y bramido de manada.
# ==============================================================================

@export var is_autonomous: bool = true

# Velocidades y cadencia sincronizada (adaptadas a su masa monumental)
@export_group("Cinemática y Velocidades")
@export var walk_anim_speed: float = 0.80        # Cadencia lenta, majestuosa y pesada de paso
@export var run_anim_speed: float = 1.10         # Cadencia al apresurarse hacia comida
@export var stride_speed_ratio: float = 0.3     # Factor calibrado para 0.20 m/s congruente con la pisada real (0.80 * 0.25 = 0.20 m/s)
@export var turn_speed: float = 0.32             # Velocidad angular lenta (inercia rotacional colosal)
@export var gravity: float = 9.8

var walk_speed: float:
	get: return walk_anim_speed * stride_speed_ratio

var run_speed: float:
	get: return run_anim_speed * stride_speed_ratio

# Flexión procedural de cuello y cabeza en giros (Yaw)
@export_group("Animación Procedural de Cuello (Yaw & Pitch)")
@export var head_yaw_max: float = 14.0
@export var neck_3_yaw_max: float = 10.0
@export var neck_2_yaw_max: float = 7.0
@export var neck_1_yaw_max: float = 4.0

@export var head_pitch_max: float = 16.0
@export var neck_pitch_max: float = 12.0

# Flexión procedural de columna y torso
@export_group("Animación Procedural de Espina")
@export var chest_yaw_max: float = 3.5
@export var spine_2_yaw_max: float = 2.5
@export var spine_1_yaw_max: float = 1.8

# Oscilación procedural de la cola (5 vértebras articuladas)
@export_group("Ondulación Procedural de Cola")
@export var tail_sway_speed: float = 0.90        # Frecuencia lenta y majestuosa
@export var tail_sway_deg: float = 4.8           # Amplitud base en grados
@export var tail_turn_lag_deg: float = 7.5       # Arrastre de inercia en giros contrarios

# Adaptación a Pendientes y Desniveles del Terreno
@export_group("Adaptación a Pendientes / Terreno")
@export var slope_adaptation_enabled: bool = true
@export var slope_smooth_speed: float = 4.2           # Transición elástica de gran masa
@export var max_slope_pitch_deg: float = 24.0         # Cabeceo máximo en laderas
@export var max_slope_roll_deg: float = 16.0          # Balanceo lateral máximo
@export var probe_forward_dist: float = 5.5           # Separación longitudinal de sondas (~8.4m total)
@export var probe_side_dist: float = 2.0              # Separación transversal de sondas
@export var slope_neck_compensate_ratio: float = 0.50 # Cuello mantiene mirada horizontal
@export var slope_tail_balance_ratio: float = 0.45    # Contrapeso vertical de cola

# Percepción Sensorial Autónoma
@export_group("Cerebro Sensorial Autónomo")
@export var smell_radius: float = 42.0       # Radio olfativo 360° en el gran recinto 100x100m
@export var vision_angle_deg: float = 135.0  # Cono de visión frontal
@export var eat_distance: float = 5.5        # Distancia de alcance con su largo cuello

# Límites del recinto (Recinto 100x100 con valla interior de ~76x76m)
@export_group("Límites de Hábitat")
@export var paddock_bounds_min: Vector2 = Vector2(-31.0, -31.0)
@export var paddock_bounds_max: Vector2 = Vector2(31.0, 31.0)

# Estados del Cerebro del Saurópodo
enum State {
	PATROL_WANDER,   # Caminata majestuosa pastando por el valle
	IDLE_OBSERVE,    # Reposo erguido, respiración profunda y exploración visual
	ALERT_SMELL,     # Olfatea / identifica comida en el aire con cuello elevado
	PURSUE_FOOD,     # Marcha deliberada hacia alimento o torre de forraje
	EAT_BITE,        # Desciende o estira el cuello y mastica pausadamente
	HERD_CALL        # Llamado profundo / bramido resonante a la manada
}

@onready var visual_model: Node3D = get_node_or_null("VisualModel")

## Optimización de Rendimiento y Culling de Animaciones en FOV
@export_group("Optimización FOV / Culling")
@export var fov_culling_enabled: bool = true
@export var max_animation_distance: float = 180.0

var is_in_view: bool = true
var _visibility_notifier: VisibleOnScreenNotifier3D
var _visibility_check_timer: float = 0.0
const VISIBILITY_CHECK_INTERVAL: float = 0.12
const CULL_LENGTH_HALF: float = 12.0
const CULL_HEIGHT: float = 14.0
const CULL_WIDTH_HALF: float = 4.5

var current_state: State = State.PATROL_WANDER:
	set(value):
		if current_state != value:
			current_state = value
			if not has_meta("_managed_by_park_optimizer"):
				print("[Cerebro Titanosaurus] Estado: ", get_brain_state_name())

var current_food_target: Node3D = null

var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _time_accum: float = 0.0
var _state_timer: float = 0.0
var _current_waypoint: Vector3 = Vector3.ZERO
var _observe_look_angle: float = 0.0
var _encounter_cooldown: float = 0.0

# Factores de interpolación elástica
var _turn_factor: float = 0.0
var _pitch_factor: float = 0.0

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
var _jaw_ctrl: DinoJawController = DinoJawController.new()
var _spectator_ctrl: DinoSpectatorController = DinoSpectatorController.new()
var _bone_neck_3: int = -1
var _bone_neck_2: int = -1
var _bone_neck_1: int = -1
var _bone_chest: int = -1
var _bone_spine_2: int = -1
var _bone_spine_1: int = -1
var _bone_pelvis: int = -1
var _bone_tail_1: int = -1
var _bone_tail_2: int = -1
var _bone_tail_3: int = -1
var _bone_tail_4: int = -1
var _bone_tail_5: int = -1

var _head_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_3_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_2_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_1_rest_q: Quaternion = Quaternion.IDENTITY
var _chest_rest_q: Quaternion = Quaternion.IDENTITY
var _spine_2_rest_q: Quaternion = Quaternion.IDENTITY
var _spine_1_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_1_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_2_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_3_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_4_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_5_rest_q: Quaternion = Quaternion.IDENTITY

func _ready() -> void:
	add_to_group("dino_herd")
	add_to_group("titano_herd")
	add_to_group("titanosaurs")
	add_to_group("titanosaurus")
	add_to_group("dinosaurios")
	_time_accum = randf_range(0.0, 10.0)
	_find_animation_player()
	_find_skeleton()
	_spectator_ctrl.setup("titanosaurus", self)
	_setup_visibility_culling()
	_pick_new_patrol_waypoint()

	# Desfase orgánico de estados en la manada
	if randf() < 0.4:
		current_state = State.IDLE_OBSERVE
		_state_timer = randf_range(3.0, 7.0)
		_play_anim("idle", 0.0)
	else:
		_play_anim("caminar", 0.0)

	print("[Cerebro Titanosaurus] Iniciado en Hábitat 100x100 | Estado: ", get_brain_state_name(), " | Rumbo: ", _current_waypoint)

func _find_animation_player() -> void:
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not _anim_player and visual_model:
		_anim_player = visual_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

func _find_skeleton() -> void:
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	if not _skeleton and visual_model:
		_skeleton = visual_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton:
		_bone_head = _skeleton.find_bone("Head")
		_bone_neck_3 = _skeleton.find_bone("Neck.003")
		_bone_neck_2 = _skeleton.find_bone("Neck.002")
		_bone_neck_1 = _skeleton.find_bone("Neck.001")
		_bone_chest = _skeleton.find_bone("Chest")
		_bone_spine_2 = _skeleton.find_bone("Spine.002")
		_bone_spine_1 = _skeleton.find_bone("Spine.001")
		_bone_pelvis = _skeleton.find_bone("Pelvis")
		_bone_tail_1 = _skeleton.find_bone("Tail.001")
		_bone_tail_2 = _skeleton.find_bone("Tail.002")
		_bone_tail_3 = _skeleton.find_bone("Tail.003")
		_bone_tail_4 = _skeleton.find_bone("Tail.004")
		_bone_tail_5 = _skeleton.find_bone("Tail.005")

		if _bone_head >= 0:
			_head_rest_q = _skeleton.get_bone_rest(_bone_head).basis.get_rotation_quaternion()
		if _bone_neck_3 >= 0:
			_neck_3_rest_q = _skeleton.get_bone_rest(_bone_neck_3).basis.get_rotation_quaternion()
		if _bone_neck_2 >= 0:
			_neck_2_rest_q = _skeleton.get_bone_rest(_bone_neck_2).basis.get_rotation_quaternion()
		if _bone_neck_1 >= 0:
			_neck_1_rest_q = _skeleton.get_bone_rest(_bone_neck_1).basis.get_rotation_quaternion()
		if _bone_chest >= 0:
			_chest_rest_q = _skeleton.get_bone_rest(_bone_chest).basis.get_rotation_quaternion()
		if _bone_spine_2 >= 0:
			_spine_2_rest_q = _skeleton.get_bone_rest(_bone_spine_2).basis.get_rotation_quaternion()
		if _bone_spine_1 >= 0:
			_spine_1_rest_q = _skeleton.get_bone_rest(_bone_spine_1).basis.get_rotation_quaternion()
		if _bone_tail_1 >= 0:
			_tail_1_rest_q = _skeleton.get_bone_rest(_bone_tail_1).basis.get_rotation_quaternion()
		if _bone_tail_2 >= 0:
			_tail_2_rest_q = _skeleton.get_bone_rest(_bone_tail_2).basis.get_rotation_quaternion()
		if _bone_tail_3 >= 0:
			_tail_3_rest_q = _skeleton.get_bone_rest(_bone_tail_3).basis.get_rotation_quaternion()
		if _bone_tail_4 >= 0:
			_tail_4_rest_q = _skeleton.get_bone_rest(_bone_tail_4).basis.get_rotation_quaternion()
		if _bone_tail_5 >= 0:
			_tail_5_rest_q = _skeleton.get_bone_rest(_bone_tail_5).basis.get_rotation_quaternion()
		_jaw_ctrl.setup(_skeleton, "titanosaurus", _anim_player)

func _play_anim(anim_name: String, blend: float = 0.4, custom_speed: float = -1.0) -> void:
	if not _anim_player:
		_find_animation_player()
		if not _anim_player:
			return

	if not is_in_view:
		return

	var target_anim = ""
	if _anim_player.has_animation(anim_name):
		target_anim = anim_name
	else:
		for a in _anim_player.get_animation_list():
			if a.ends_with(anim_name) or anim_name in a:
				target_anim = a
				break

	if target_anim != "":
		if custom_speed > 0.0:
			_anim_player.speed_scale = custom_speed
		elif "caminar" in target_anim:
			_anim_player.speed_scale = walk_anim_speed
		elif "comer" in target_anim or "llamado" in target_anim:
			_anim_player.speed_scale = 0.95
		else:
			_anim_player.speed_scale = 0.85

		if _anim_player.current_animation != target_anim:
			_anim_player.play(target_anim, blend)

func _physics_process(delta: float) -> void:
	# Comprobación periódica de campo de visión para optimizar CPU
	if fov_culling_enabled:
		_visibility_check_timer -= delta
		if _visibility_check_timer <= 0.0:
			_visibility_check_timer = VISIBILITY_CHECK_INTERVAL
			_update_visibility_state()

	# 1. Gravedad y fijación a terreno
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -1.5

	# 1.1 Sondas físicas de superficie y cálculo de pendiente (solo cuando es visible)
	if slope_adaptation_enabled and is_in_view:
		_update_surface_slope(delta)

	# 2. Temporizadores de estado y evasión
	_state_timer = max(0.0, _state_timer - delta)
	_encounter_cooldown = max(0.0, _encounter_cooldown - delta)
	_terrain_collision_cooldown = max(0.0, _terrain_collision_cooldown - delta)
	_detour_timer = max(0.0, _detour_timer - delta)

	# 3. Detección sensorial de alimento
	_sensory_scan_food()

	# 4. Decisión del cerebro autónomo
	var commands = _update_brain_state(delta)
	var desired_turn: float = commands.turn
	var desired_forward: float = commands.forward
	var current_move_speed: float = commands.speed

	# Modulación de velocidad según pendiente
	if slope_adaptation_enabled:
		if _current_slope_pitch > 0.05:
			current_move_speed *= clampf(1.0 - sin(_current_slope_pitch) * 0.40, 0.65, 1.0)
		elif _current_slope_pitch < -0.05:
			current_move_speed *= clampf(1.0 + sin(_current_slope_pitch) * 0.25, 0.75, 1.0)

	# 5. Rotación sobre el suelo (lenta, con aceleración angular suave)
	var current_turn_speed = turn_speed
	if _detour_timer > 0.0:
		current_turn_speed = turn_speed * 2.8
	if desired_turn != 0.0:
		rotate_y(desired_turn * current_turn_speed * delta)

	# 6. Desplazamiento horizontal XZ
	var forward_dir = -global_transform.basis.z
	var fwd_h = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
	var target_h_vel = Vector3.ZERO
	if desired_forward > 0.0:
		target_h_vel = forward_dir * (desired_forward * current_move_speed)
	elif desired_forward < 0.0:
		target_h_vel = forward_dir * (desired_forward * (walk_speed * 0.4))

	# 6.1 Sensor predictivo frontal de largo alcance (detecta montañas, muros y torres a tiempo)
	if (current_state == State.PATROL_WANDER or current_state == State.PURSUE_FOOD) and _terrain_collision_cooldown <= 0.0:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var chest_y = global_position.y + 2.8
			var ray_from = Vector3(global_position.x, chest_y, global_position.z)
			var ray_to = ray_from + fwd_h * 11.0
			var q_pred = PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			q_pred.exclude = [get_rid()]
			var res_pred = space_state.intersect_ray(q_pred)
			if res_pred.size() > 0:
				var hit_norm = res_pred.normal
				if hit_norm.y < 0.65:
					var hit_norm_h = Vector3(hit_norm.x, 0.0, hit_norm.z).normalized()
					if fwd_h.dot(hit_norm_h) < -0.20:
						_trigger_terrain_obstacle_turn(hit_norm, res_pred.position)

	# Inercia de traslación pesada (acelera y frena con peso colosal)
	velocity.x = move_toward(velocity.x, target_h_vel.x, 1.2 * delta)
	velocity.z = move_toward(velocity.z, target_h_vel.z, 1.2 * delta)

	move_and_slide()

	# 7. Colisiones físicas tras move_and_slide()
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if not collider or collider == self:
			continue

		if collider.is_in_group("dino_herd"):
			if current_state == State.PATROL_WANDER and _encounter_cooldown <= 0.0:
				_trigger_herd_turn(collider)
				break

		var col_normal = col.get_normal()
		if col_normal.y < 0.65 and _terrain_collision_cooldown <= 0.0:
			var col_norm_h = Vector3(col_normal.x, 0.0, col_normal.z).normalized()
			if fwd_h.dot(col_norm_h) < -0.20:
				_trigger_terrain_obstacle_turn(col_normal, col.get_position())
				break

	# 7.1 Anti-atascamiento (especialmente en esquinas de vallas)
	var real_h_speed = Vector2(velocity.x, velocity.z).length()
	if desired_forward > 0.2 and real_h_speed < 0.15 and is_on_floor():
		_stuck_timer += delta
		if _stuck_timer > 0.45:
			_stuck_timer = 0.0
			_terrain_collision_cooldown = 0.0
			var center = _get_habitat_center()
			center.y = global_position.y
			var to_center = (center - global_position).normalized()
			if to_center.length_squared() < 0.01:
				to_center = -fwd_h
			_trigger_terrain_obstacle_turn(-to_center, global_position + fwd_h * 3.0, true)
	else:
		_stuck_timer = max(0.0, _stuck_timer - delta * 2.0)

	# 8. Actualizar clips de animación acordes al estado
	_handle_autonomous_animation_clips()

func _sensory_scan_food() -> void:
	var closest_food := DinoFood.find_nearest_for(self, DinoFood.DIET_GRASS, smell_radius, _get_habitat_node(), paddock_bounds_min, paddock_bounds_max)
	current_food_target = closest_food

	if is_instance_valid(current_food_target):
		var to_food = (current_food_target.global_position - global_position).normalized()
		var forward = -global_transform.basis.z
		var angle_to_food = rad_to_deg(forward.angle_to(to_food))

		if current_state != State.EAT_BITE and current_state != State.HERD_CALL:
			if angle_to_food <= (vision_angle_deg * 0.5):
				if current_state != State.PURSUE_FOOD:
					current_state = State.PURSUE_FOOD
			else:
				if current_state != State.ALERT_SMELL and current_state != State.PURSUE_FOOD:
					current_state = State.ALERT_SMELL
					_state_timer = 4.0
	else:
		if current_state == State.PURSUE_FOOD or current_state == State.ALERT_SMELL:
			current_state = State.IDLE_OBSERVE
			_state_timer = randf_range(3.5, 6.0)

func _update_brain_state(delta: float) -> Dictionary:
	var turn: float = 0.0
	var forward: float = 0.0
	var speed: float = walk_speed

	var busy_with_food := is_instance_valid(current_food_target) or (current_state in [State.ALERT_SMELL, State.PURSUE_FOOD, State.EAT_BITE])
	_spectator_ctrl.update(
		delta,
		self,
		_get_habitat_node(),
		Vector3(paddock_bounds_min.x, 0.0, paddock_bounds_min.y),
		Vector3(paddock_bounds_max.x, 0.0, paddock_bounds_max.y),
		busy_with_food
	)

	if _spectator_ctrl.is_controlling() and current_state != State.HERD_CALL:
		if _spectator_ctrl.is_moving_phase():
			current_state = State.PATROL_WANDER
			_current_waypoint = _spectator_ctrl.get_move_target(self)
			var steer_target := _obstacle_detour_waypoint if _detour_timer > 0.0 else _current_waypoint
			turn = _steer_towards(steer_target)
			forward = 1.0
			speed = walk_speed * _spectator_ctrl.get_speed_multiplier()
			var spec_herd = _compute_herd_avoidance()
			if abs(spec_herd) > 0.05:
				turn += spec_herd
			var spec_fence = _compute_fence_avoidance()
			if abs(spec_fence) > 0.05:
				turn = spec_fence
			return {"turn": clamp(turn, -1.0, 1.0), "forward": clamp(forward, -1.0, 1.0), "speed": speed}
		elif _spectator_ctrl.is_posing_phase():
			if _spectator_ctrl.consume_display_trigger():
				current_state = State.HERD_CALL
				_state_timer = _spectator_ctrl.get_display_duration()
			else:
				current_state = State.IDLE_OBSERVE
				_state_timer = maxf(_state_timer, 0.5)
			_observe_look_angle = _spectator_ctrl.get_head_look_factor(self)
			turn = _spectator_ctrl.get_showcase_turn(self)
			return {"turn": clamp(turn, -1.0, 1.0), "forward": 0.0, "speed": walk_speed}

	match current_state:
		State.PATROL_WANDER:
			speed = walk_speed
			var dist = Vector2(global_position.x - _current_waypoint.x, global_position.z - _current_waypoint.z).length()
			if dist < 4.5:
				var roll = randf()
				if roll < 0.20:
					current_state = State.HERD_CALL
					_state_timer = 5.2
				elif roll < 0.60:
					current_state = State.IDLE_OBSERVE
					_state_timer = randf_range(5.0, 10.0)
				else:
					_pick_new_patrol_waypoint()
			else:
				turn = _steer_towards(_current_waypoint)
				forward = 1.0

		State.IDLE_OBSERVE:
			forward = 0.0
			turn = 0.0
			_observe_look_angle = sin(_time_accum * 0.45) * 0.70
			if _state_timer <= 0.0:
				current_state = State.PATROL_WANDER
				_pick_new_patrol_waypoint()

		State.ALERT_SMELL:
			if is_instance_valid(current_food_target):
				turn = _steer_towards(current_food_target.global_position) * 1.15
				forward = 0.15
				speed = walk_speed * 0.5
			else:
				current_state = State.PATROL_WANDER
				_pick_new_patrol_waypoint()

		State.PURSUE_FOOD:
			if is_instance_valid(current_food_target):
				speed = run_speed
				var dist = global_position.distance_to(current_food_target.global_position)
				if dist <= eat_distance or (dist <= 6.5 and velocity.length() < 0.05 and _state_timer > 0.5):
					current_state = State.EAT_BITE
					_state_timer = 5.8
					if current_food_target.has_method("consume"):
						current_food_target.consume()
					else:
						current_food_target.queue_free()
					current_food_target = null
				else:
					var target_steer_pos = current_food_target.global_position
					if _detour_timer > 0.0:
						target_steer_pos = _obstacle_detour_waypoint
					turn = _steer_towards(target_steer_pos) * 1.25
					forward = 1.0
			else:
				current_state = State.IDLE_OBSERVE
				_state_timer = 4.0

		State.EAT_BITE:
			forward = 0.0
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_OBSERVE
				_state_timer = randf_range(4.0, 7.0)

		State.HERD_CALL:
			forward = 0.05
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_OBSERVE
				_state_timer = randf_range(4.0, 6.0)

	# Evasión de otros titanosaurios (respetar distancia monumental de 9m)
	var herd_steer = _compute_herd_avoidance()
	if abs(herd_steer) > 0.05:
		turn += herd_steer

	# Evasión de vallas perimetrales
	var fence_steer = _compute_fence_avoidance()
	if abs(fence_steer) > 0.05:
		turn = fence_steer

	return {
		"turn": clamp(turn, -1.0, 1.0),
		"forward": clamp(forward, -1.0, 1.0),
		"speed": speed
	}

func _compute_herd_avoidance() -> float:
	if current_state == State.EAT_BITE or current_state == State.HERD_CALL:
		return 0.0

	var avoid: float = 0.0
	var herd = get_tree().get_nodes_in_group("dino_herd")
	for other in herd:
		if other != self and is_instance_valid(other) and other is Node3D:
			var to_other = other.global_position - global_position
			to_other.y = 0.0
			var dist = to_other.length()
			if dist < 9.5 and dist > 0.1:
				var local_dir = global_transform.basis.inverse() * to_other.normalized()
				if current_state == State.PATROL_WANDER and dist < 8.0 and local_dir.z < -0.20 and _encounter_cooldown <= 0.0:
					_trigger_herd_turn(other)
					return _steer_towards(_current_waypoint)

				if local_dir.z < -0.1:
					var strength = (9.5 - dist) / 9.5
					var side_turn = 1.0 if local_dir.x >= 0.0 else -1.0
					avoid += side_turn * strength * 1.2
	return clamp(avoid, -1.0, 1.0)

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

func _clamp_to_habitat(world_pos: Vector3, margin: float = 4.0) -> Vector3:
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

func _pick_random_habitat_waypoint(margin: float = 5.0) -> Vector3:
	var hab = _get_habitat_node()
	var lx = randf_range(paddock_bounds_min.x + margin, paddock_bounds_max.x - margin)
	var lz = randf_range(paddock_bounds_min.y + margin, paddock_bounds_max.y - margin)
	var local_wp = Vector3(lx, 0.0, lz)
	if hab:
		var gw = hab.to_global(local_wp)
		gw.y = global_position.y
		return gw
	local_wp.y = global_position.y
	return local_wp

func _trigger_herd_turn(other: Node3D) -> void:
	if current_state != State.PATROL_WANDER or _encounter_cooldown > 0.0:
		return

	_encounter_cooldown = 4.5
	var to_other = other.global_position - global_position
	to_other.y = 0.0
	var local_dir = global_transform.basis.inverse() * to_other.normalized()

	var turn_left = (local_dir.x >= 0.0)
	if abs(local_dir.x) < 0.15:
		turn_left = (randf() < 0.5)

	var angle_offset = (PI * 0.45) if turn_left else (-PI * 0.45)
	var new_fwd = (-global_transform.basis.z).rotated(Vector3.UP, angle_offset).normalized()
	var dist_forward = randf_range(12.0, 18.0)
	var new_target = global_position + new_fwd * dist_forward

	new_target = _clamp_to_habitat(new_target, 4.0)
	new_target.y = global_position.y

	_current_waypoint = new_target

func _trigger_terrain_obstacle_turn(col_normal: Vector3, _col_point: Vector3, is_stuck: bool = false) -> void:
	if _terrain_collision_cooldown > 0.0 and not is_stuck:
		return

	_terrain_collision_cooldown = 1.8

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

	var tangent_right = norm.cross(Vector3.UP).normalized()
	var tangent_left = -tangent_right

	var space_state = get_world_3d().direct_space_state
	var probe_dist = 11.0
	var ray_y = global_position.y + 2.5

	var dir_left = fwd.rotated(Vector3.UP, deg_to_rad(60.0)).normalized()
	var dir_right = fwd.rotated(Vector3.UP, deg_to_rad(-60.0)).normalized()

	var check_pos_left = global_position + dir_left * probe_dist
	var check_pos_right = global_position + dir_right * probe_dist

	var left_blocked = false
	var right_blocked = false

	if space_state:
		var q_left = PhysicsRayQueryParameters3D.create(
			Vector3(global_position.x, ray_y, global_position.z),
			Vector3(check_pos_left.x, ray_y, check_pos_left.z),
			1
		)
		q_left.exclude = [get_rid()]
		var res_l = space_state.intersect_ray(q_left)
		if res_l.size() > 0 and res_l.normal.y < 0.65:
			left_blocked = true

		var q_right = PhysicsRayQueryParameters3D.create(
			Vector3(global_position.x, ray_y, global_position.z),
			Vector3(check_pos_right.x, ray_y, check_pos_right.z),
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
	var turn_deg: float = randf_range(75.0, 105.0)
	var new_fwd = fwd

	# Si ambos están bloqueados o está atascado (caso típico de esquina):
	if (left_blocked and right_blocked) or is_stuck:
		var deflection = deg_to_rad(randf_range(-20.0, 20.0))
		new_fwd = to_center_dir.rotated(Vector3.UP, deflection).normalized()
		turn_left = (fwd.cross(Vector3.UP).dot(new_fwd) < 0.0)
		turn_deg = rad_to_deg(fwd.angle_to(new_fwd))
	elif left_blocked and not right_blocked:
		turn_left = false
		turn_deg = randf_range(75.0, 105.0)
		var angle_rad = deg_to_rad(-turn_deg)
		new_fwd = fwd.rotated(Vector3.UP, angle_rad).normalized()
	elif right_blocked and not left_blocked:
		turn_left = true
		turn_deg = randf_range(75.0, 105.0)
		var angle_rad = deg_to_rad(turn_deg)
		new_fwd = fwd.rotated(Vector3.UP, angle_rad).normalized()
	else:
		var dot_l = dir_left.dot(to_center_dir)
		var dot_r = dir_right.dot(to_center_dir)
		if dot_l > dot_r + 0.1:
			turn_left = true
		elif dot_r > dot_l + 0.1:
			turn_left = false
		else:
			turn_left = (fwd.dot(tangent_left) > fwd.dot(tangent_right))
		turn_deg = randf_range(75.0, 105.0)
		var angle_rad = deg_to_rad(turn_deg) if turn_left else deg_to_rad(-turn_deg)
		new_fwd = fwd.rotated(Vector3.UP, angle_rad).normalized()

	# Asegurar que el nuevo rumbo siempre apunte hacia el interior del hábitat
	if new_fwd.dot(to_center_dir) < 0.25 or (left_blocked and right_blocked) or is_stuck:
		new_fwd = to_center_dir.rotated(Vector3.UP, deg_to_rad(randf_range(-30.0, 30.0))).normalized()
		turn_deg = rad_to_deg(fwd.angle_to(new_fwd))
		turn_left = (fwd.cross(Vector3.UP).dot(new_fwd) < 0.0)

	var dist_forward = randf_range(14.0, 22.0)
	var new_target = global_position + new_fwd * dist_forward
	new_target = _clamp_to_habitat(new_target, 4.0)
	new_target.y = global_position.y

	_current_waypoint = new_target
	_obstacle_detour_waypoint = new_target
	_detour_timer = 3.5
	_turn_factor = 1.0 if turn_left else -1.0

	# Giro reactivo inicial inmediato para despegar el cuello y cuerpo de la pared
	var target_rot = atan2(-new_fwd.x, -new_fwd.z)
	var lerp_weight = 0.85 if is_stuck else 0.65
	global_rotation.y = lerp_angle(global_rotation.y, target_rot, lerp_weight)

	# Redirigir velocidad
	var cur_speed = Vector2(velocity.x, velocity.z).length()
	var exit_speed = max(cur_speed * 0.5, walk_speed * 0.4)
	velocity.x = new_fwd.x * exit_speed
	velocity.z = new_fwd.z * exit_speed

	if not has_meta("_managed_by_park_optimizer"):
		print("[Cerebro Titanosaurus] Obstáculo en ruta -> Desviando hacia ", "IZQUIERDA" if turn_left else "DERECHA", " (", round(turn_deg), "°)")

func _steer_towards(target_pos: Vector3) -> float:
	var to_target = (target_pos - global_position)
	to_target.y = 0.0
	var local_dir = global_transform.basis.inverse() * to_target.normalized()
	return clamp(-local_dir.x * 2.0, -1.0, 1.0)

func _compute_fence_avoidance() -> float:
	if current_state == State.PURSUE_FOOD or current_state == State.EAT_BITE:
		return 0.0

	var fwd = -global_transform.basis.z
	var hab = _get_habitat_node()
	if hab:
		fwd = hab.global_transform.basis.inverse() * fwd
	var local_pos = _to_habitat_local(global_position)
	var needs_avoid = false

	if local_pos.x > (paddock_bounds_max.x - 5.0) and fwd.x > 0.0:
		needs_avoid = true
	elif local_pos.x < (paddock_bounds_min.x + 5.0) and fwd.x < 0.0:
		needs_avoid = true

	if local_pos.z > (paddock_bounds_max.y - 5.0) and fwd.z > 0.0:
		needs_avoid = true
	elif local_pos.z < (paddock_bounds_min.y + 5.0) and fwd.z < 0.0:
		needs_avoid = true

	if needs_avoid:
		var center = _get_habitat_center()
		center.y = global_position.y
		return _steer_towards(center)

	return 0.0

func _pick_new_patrol_waypoint() -> void:
	# Ocasionalmente (25% de probabilidad), fijar una de las dos torres de forraje alto como destino
	var roll = randf()
	if roll < 0.14:
		_current_waypoint = _to_habitat_global(Vector3(32.5, 0.0, 2.5)) # Torre Este
	elif roll < 0.28:
		_current_waypoint = _to_habitat_global(Vector3(8.0, 0.0, -27.5)) # Torre Norte
	else:
		_current_waypoint = _pick_random_habitat_waypoint(5.0)
	_current_waypoint = _clamp_to_habitat(_current_waypoint, 4.0)

func _handle_autonomous_animation_clips() -> void:
	var slope_anim_mult: float = 1.0
	if slope_adaptation_enabled:
		if _current_slope_pitch > 0.05:
			slope_anim_mult = clampf(1.0 - sin(_current_slope_pitch) * 0.40, 0.65, 1.0)
		elif _current_slope_pitch < -0.05:
			slope_anim_mult = clampf(1.0 + sin(_current_slope_pitch) * 0.25, 0.75, 1.0)

	match current_state:
		State.PATROL_WANDER:
			var move_mult := _spectator_ctrl.get_speed_multiplier() if _spectator_ctrl.is_moving_phase() else 1.0
			_play_anim("caminar", 0.40, walk_anim_speed * slope_anim_mult * move_mult)
		State.IDLE_OBSERVE:
			_play_anim("idle", 0.45, 0.85)
		State.ALERT_SMELL:
			_play_anim("identificar_comida", 0.35, 0.90)
		State.PURSUE_FOOD:
			_play_anim("caminar", 0.30, run_anim_speed * slope_anim_mult)
		State.EAT_BITE:
			_play_anim("comer", 0.25, 0.95)
		State.HERD_CALL:
			_play_anim("llamado", 0.30, 0.90)

func _process(delta: float) -> void:
	if not is_in_view:
		return
	_time_accum += delta

	# Factores suavizados para cinemática procedural
	var target_turn: float = 0.0
	var target_pitch: float = 0.0

	match current_state:
		State.PATROL_WANDER, State.PURSUE_FOOD, State.ALERT_SMELL:
			var tpos = _current_waypoint
			if is_instance_valid(current_food_target):
				if _detour_timer > 0.0:
					tpos = _obstacle_detour_waypoint
				else:
					tpos = current_food_target.global_position
			target_turn = _steer_towards(tpos)
			if current_state == State.PURSUE_FOOD:
				target_pitch = -0.35
			elif current_state == State.ALERT_SMELL:
				target_pitch = 0.40 # Cabeza elevada venteando el aire
		State.IDLE_OBSERVE:
			target_turn = _observe_look_angle
			target_pitch = sin(_time_accum * 0.35) * 0.20
		State.EAT_BITE:
			target_pitch = -0.65 # Cuello y cabeza hacia el follaje
		State.HERD_CALL:
			target_turn = sin(_time_accum * 2.0) * 0.15
			target_pitch = 0.65 # Cuello elevado hacia el cielo para el bramido

	if _spectator_ctrl.wants_head_look() and current_state in [State.PATROL_WANDER, State.IDLE_OBSERVE]:
		target_turn = _spectator_ctrl.get_head_look_factor(self)
		target_pitch = _spectator_ctrl.get_head_pitch_factor(self)

	# Suavizado de inercia procedural (el cuello largo tiene retraso de masa)
	_turn_factor = move_toward(_turn_factor, target_turn, delta * 1.8)
	_pitch_factor = move_toward(_pitch_factor, target_pitch, delta * 1.5)

	# Orientación visual adaptada al terreno (Pitch y Roll)
	if visual_model and slope_adaptation_enabled:
		var base_yaw = Basis(Vector3.UP, PI)
		var q_pitch = Quaternion(Vector3.RIGHT, _current_slope_pitch)
		var q_roll = Quaternion(Vector3.FORWARD, _current_slope_roll)
		var slope_rot = Basis(q_pitch * q_roll)
		visual_model.transform.basis = slope_rot * base_yaw
		visual_model.position.y = _current_ground_y_offset

	if not _skeleton:
		return

	# ==========================================================================
	# 9. CINEMÁTICA PROCEDURAL DE CUELLO LARGO (4 Vértebras)
	# ==========================================================================
	# El cuello largo lidera los giros con una curvatura progresiva natural (S-Curve):
	var yaw_head = _turn_factor * deg_to_rad(head_yaw_max)
	var yaw_neck_3 = _turn_factor * deg_to_rad(neck_3_yaw_max)
	var yaw_neck_2 = _turn_factor * deg_to_rad(neck_2_yaw_max)
	var yaw_neck_1 = _turn_factor * deg_to_rad(neck_1_yaw_max)

	var pitch_head = _pitch_factor * deg_to_rad(head_pitch_max)
	var pitch_neck = _pitch_factor * deg_to_rad(neck_pitch_max)

	# Compensación de horizonte en pendientes
	var slope_comp_head = -_current_slope_pitch * slope_neck_compensate_ratio
	var slope_comp_neck = -_current_slope_pitch * (slope_neck_compensate_ratio * 0.5)

	# Inclinación lateral del cuello al virar (roll orgánico hacia el interior del giro)
	var neck_bank_roll = -_turn_factor * deg_to_rad(3.5)

	_apply_bone_rotation(_bone_head, _head_rest_q, pitch_head + slope_comp_head, yaw_head, neck_bank_roll)
	_apply_bone_rotation(_bone_neck_3, _neck_3_rest_q, pitch_neck * 0.4 + slope_comp_neck, yaw_neck_3, neck_bank_roll * 0.8)
	_apply_bone_rotation(_bone_neck_2, _neck_2_rest_q, pitch_neck * 0.3 + slope_comp_neck * 0.7, yaw_neck_2, neck_bank_roll * 0.5)
	_apply_bone_rotation(_bone_neck_1, _neck_1_rest_q, pitch_neck * 0.2 + slope_comp_neck * 0.4, yaw_neck_1, neck_bank_roll * 0.3)

	# ==========================================================================
	# 10. FLEXIÓN PROCEDURAL DE ESPINA Y PECHO
	# ==========================================================================
	var yaw_chest = _turn_factor * deg_to_rad(chest_yaw_max)
	var yaw_spine_2 = _turn_factor * deg_to_rad(spine_2_yaw_max)
	var yaw_spine_1 = _turn_factor * deg_to_rad(spine_1_yaw_max)

	var slope_pitch_spine = -_current_slope_pitch * 0.15
	var slope_roll_spine = _current_slope_roll * 0.20

	_apply_bone_rotation(_bone_chest, _chest_rest_q, slope_pitch_spine, yaw_chest, slope_roll_spine * 0.5)
	_apply_bone_rotation(_bone_spine_2, _spine_2_rest_q, slope_pitch_spine * 0.7, yaw_spine_2, slope_roll_spine * 0.7)
	_apply_bone_rotation(_bone_spine_1, _spine_1_rest_q, slope_pitch_spine * 0.4, yaw_spine_1, slope_roll_spine)

	# ==========================================================================
	# 11. ONDULACIÓN PROCEDURAL DE COLA (5 Vértebras Articuladas)
	# ==========================================================================
	# Simula una onda sinusoidal que se propaga a lo largo de la cola con desfase progresivo,
	# más un arrastre inercial opuesto al viraje (tail drag):
	var is_walking = (_anim_player and "caminar" in _anim_player.current_animation)
	var sway_mult = 1.35 if is_walking else 0.85
	var turn_drag = -_turn_factor * deg_to_rad(tail_turn_lag_deg)

	var w1 = sin(_time_accum * tail_sway_speed) * deg_to_rad(tail_sway_deg * 0.7 * sway_mult)
	var w2 = sin(_time_accum * tail_sway_speed - 0.50) * deg_to_rad(tail_sway_deg * 0.95 * sway_mult)
	var w3 = sin(_time_accum * tail_sway_speed - 1.05) * deg_to_rad(tail_sway_deg * 1.25 * sway_mult)
	var w4 = sin(_time_accum * tail_sway_speed - 1.60) * deg_to_rad(tail_sway_deg * 1.55 * sway_mult)
	var w5 = sin(_time_accum * tail_sway_speed - 2.15) * deg_to_rad(tail_sway_deg * 1.85 * sway_mult)

	var slope_tail_pitch = -_current_slope_pitch * slope_tail_balance_ratio

	_apply_tail_rotation(_bone_tail_1, _tail_1_rest_q, slope_tail_pitch * 0.6, w1 + turn_drag * 0.5)
	_apply_tail_rotation(_bone_tail_2, _tail_2_rest_q, slope_tail_pitch * 0.8, w2 + turn_drag * 0.7)
	_apply_tail_rotation(_bone_tail_3, _tail_3_rest_q, slope_tail_pitch * 1.0, w3 + turn_drag * 0.9)
	_apply_tail_rotation(_bone_tail_4, _tail_4_rest_q, slope_tail_pitch * 1.2, w4 + turn_drag * 1.1)
	_apply_tail_rotation(_bone_tail_5, _tail_5_rest_q, slope_tail_pitch * 1.4, w5 + turn_drag * 1.3)

	var jaw_mode: int = DinoJawController.Mode.CLOSED
	if current_state == State.EAT_BITE:
		jaw_mode = DinoJawController.Mode.EAT
	elif current_state == State.HERD_CALL:
		jaw_mode = DinoJawController.Mode.ROAR
	_jaw_ctrl.update(delta, jaw_mode, _anim_player)
	_jaw_ctrl.apply()

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
	target_y_offset = clampf(target_y_offset, -0.9, 0.9)

	var blend_factor = clampf(delta * slope_smooth_speed, 0.0, 1.0)
	_current_slope_pitch = lerp_angle(_current_slope_pitch, target_pitch, blend_factor)
	_current_slope_roll = lerp_angle(_current_slope_roll, target_roll, blend_factor)
	_current_ground_y_offset = lerpf(_current_ground_y_offset, target_y_offset, blend_factor)

func _cast_probe(space_state: PhysicsDirectSpaceState3D, origin_xz: Vector3) -> Dictionary:
	var ray_top = Vector3(origin_xz.x, global_position.y + 4.5, origin_xz.z)
	var ray_bottom = Vector3(origin_xz.x, global_position.y - 4.5, origin_xz.z)
	var query = PhysicsRayQueryParameters3D.create(ray_top, ray_bottom, 1)
	query.exclude = [get_rid()]

	var result = space_state.intersect_ray(query)
	if result.size() > 0:
		return {"has_hit": true, "pos": result.position, "normal": result.normal}
	return {"has_hit": false, "pos": origin_xz, "normal": Vector3.UP}

func get_brain_state_name() -> String:
	match current_state:
		State.PATROL_WANDER: return "Patrullaje / Pastoreo Majestuoso"
		State.IDLE_OBSERVE: return "Reposo / Observación Erguida"
		State.ALERT_SMELL: return "Alerta Olfativa / Búsqueda de Follaje"
		State.PURSUE_FOOD: return "Marcha hacia Alimento"
		State.EAT_BITE: return "Alimentándose"
		State.HERD_CALL: return "Llamado / Bramido a la Manada"
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
			_handle_autonomous_animation_clips()

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

	if dist_sq > max_animation_distance * max_animation_distance:
		_set_animation_active(false)
		return

	if _visibility_notifier and _visibility_notifier.is_on_screen():
		_set_animation_active(true)
		return

	if cam.is_position_in_frustum(global_position):
		_set_animation_active(true)
		return

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
