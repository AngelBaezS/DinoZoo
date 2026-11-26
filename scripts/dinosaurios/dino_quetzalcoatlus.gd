class_name DinoQuetzalcoatlus
extends CharacterBody3D

# ==============================================================================
# QUETZALCOATLUS — CEREBRO AUTÓNOMO Y SISTEMA PROCEDURAL AZDÁRQUIDO
# ==============================================================================
# Pterosaurio gigante que combina caminata terrestre y vuelo en planeo majestuoso.
# - Caminata cuadrúpeda terrestre usando alas plegadas y patas traseras.
# - Transición a despegue, planeo en 3D (`Quetzal_Volar_loop`) por el aviario y aterrizaje.
# - Cuello largo de 3 vértebras con compensación de mirada horizontal y picoteo.
# - Evasión tridimensional de paredes de roca, red de aviario y obstáculos del suelo.
# ==============================================================================

@export var is_autonomous: bool = true

@export_group("Cinemática y Velocidades")
@export var walk_anim_speed: float = 1.45
@export var fly_anim_speed: float = 1.15
@export var stride_speed_ratio: float = 0.21
@export var flight_speed: float = 5.2
@export var turn_speed: float = 1.10
@export var gravity: float = 9.8

var walk_speed: float:
	get: return walk_anim_speed * stride_speed_ratio

@export_group("Color y Plumaje / Membrana")
@export var skin_color: Color = Color(0.65, 0.60, 0.54, 1.0)
@export var crest_color: Color = Color(0.85, 0.32, 0.22, 1.0)

@export_group("Animación Procedural de Cuello Largo y Pico")
@export var head_yaw_max: float = 24.0
@export var head_pitch_max: float = 20.0
@export var neck_yaw_max: float = 16.0
@export var neck_pitch_max: float = 14.0

@export_group("Animación Procedural de Espina y Pecho")
@export var chest_yaw_max: float = 7.0
@export var spine_yaw_max: float = 5.0
@export var bank_roll_max: float = 18.0

@export_group("Adaptación a Pendientes / Terreno (En Suelo)")
@export var slope_adaptation_enabled: bool = true
@export var slope_smooth_speed: float = 5.5
@export var max_slope_pitch_deg: float = 28.0
@export var max_slope_roll_deg: float = 18.0
@export var probe_forward_dist: float = 2.2
@export var probe_side_dist: float = 1.0

@export_group("Cerebro Sensorial Autónomo")
@export var smell_radius: float = 30.0
@export var vision_angle_deg: float = 140.0
@export var eat_distance: float = 3.2

@export_group("Límites de Hábitat Aviario")
@export var paddock_bounds_min: Vector3 = Vector3(-20.0, 0.5, -20.0)
@export var paddock_bounds_max: Vector3 = Vector3(20.0, 18.0, 20.0)

enum State {
	PATROL_WALK,
	IDLE_ROOST,
	ALERT_SCAN,
	PURSUE_FOOD,
	EAT_PECK,
	TAKE_OFF,
	SOARING_FLIGHT,
	LANDING
}

@onready var visual_model: Node3D = get_node_or_null("VisualModel")

var current_state: State = State.PATROL_WALK:
	set(value):
		if current_state != value:
			current_state = value
			if not has_meta("_managed_by_park_optimizer"):
				print("[Cerebro Quetzalcoatlus] Estado: ", get_brain_state_name())

var current_food_target: Node3D = null

var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _jaw_ctrl: DinoJawController = DinoJawController.new()
var _spectator_ctrl: DinoSpectatorController = DinoSpectatorController.new()
var _time_accum: float = 0.0
var _state_timer: float = 0.0
var _current_waypoint: Vector3 = Vector3.ZERO
var _observe_look_angle: float = 0.0

var _turn_factor: float = 0.0
var _pitch_factor: float = 0.0
var _current_slope_pitch: float = 0.0
var _current_slope_roll: float = 0.0

var _terrain_collision_cooldown: float = 0.0
var _obstacle_detour_waypoint: Vector3 = Vector3.ZERO
var _detour_timer: float = 0.0
var _stuck_timer: float = 0.0

var _bone_head: int = -1
var _bone_neck_1: int = -1
var _bone_neck_2: int = -1
var _bone_neck_3: int = -1
var _bone_chest: int = -1
var _bone_spine: int = -1

var _head_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_1_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_2_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_3_rest_q: Quaternion = Quaternion.IDENTITY
var _chest_rest_q: Quaternion = Quaternion.IDENTITY
var _spine_rest_q: Quaternion = Quaternion.IDENTITY

func _ready() -> void:
	add_to_group("dino_pterosaurs")
	add_to_group("quetzalcoatlus")
	add_to_group("dinosaurios")
	_time_accum = randf_range(0.0, 10.0)
	_apply_dino_material()
	_find_animation_player()
	_find_skeleton()
	_spectator_ctrl.setup("quetzalcoatlus", self)
	_pick_new_patrol_waypoint()

	if randf() < 0.35:
		current_state = State.IDLE_ROOST
		_state_timer = randf_range(3.0, 6.0)
		_play_anim("Quetzal_Idle", 0.0)
	else:
		_play_anim("Quetzal_Caminar", 0.0)

func _apply_dino_material() -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh and mesh.mesh.get_surface_count() > 0:
			var has_mat = false
			for s in range(mesh.mesh.get_surface_count()):
				if mesh.get_active_material(s) != null or mesh.mesh.surface_get_material(s) != null:
					has_mat = true
					break
			if has_mat: continue
		var mat = StandardMaterial3D.new()
		mat.albedo_color = skin_color
		mat.roughness = 0.72
		mesh.material_override = mat

func _find_animation_player() -> void:
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not _anim_player and visual_model:
		_anim_player = visual_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		for aname in _anim_player.get_animation_list():
			if "Caminar" in aname or "Idle" in aname or "Volar" in aname:
				var anim := _anim_player.get_animation(aname)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
		if _anim_player.has_signal("mixer_applied") and not _anim_player.mixer_applied.is_connected(_apply_procedural_overlay):
			_anim_player.mixer_applied.connect(_apply_procedural_overlay)

func _find_skeleton() -> void:
	_skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	if not _skeleton and visual_model:
		_skeleton = visual_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton:
		_bone_head = _skeleton.find_bone("Head")
		_bone_neck_1 = _skeleton.find_bone("Neck.001")
		_bone_neck_2 = _skeleton.find_bone("Neck.002")
		_bone_neck_3 = _skeleton.find_bone("Neck.003")
		_bone_chest = _skeleton.find_bone("Chest")
		_bone_spine = _skeleton.find_bone("Spine")

		if _bone_head >= 0: _head_rest_q = _skeleton.get_bone_rest(_bone_head).basis.get_rotation_quaternion()
		if _bone_neck_1 >= 0: _neck_1_rest_q = _skeleton.get_bone_rest(_bone_neck_1).basis.get_rotation_quaternion()
		if _bone_neck_2 >= 0: _neck_2_rest_q = _skeleton.get_bone_rest(_bone_neck_2).basis.get_rotation_quaternion()
		if _bone_neck_3 >= 0: _neck_3_rest_q = _skeleton.get_bone_rest(_bone_neck_3).basis.get_rotation_quaternion()
		if _bone_chest >= 0: _chest_rest_q = _skeleton.get_bone_rest(_bone_chest).basis.get_rotation_quaternion()
		if _bone_spine >= 0: _spine_rest_q = _skeleton.get_bone_rest(_bone_spine).basis.get_rotation_quaternion()
		_jaw_ctrl.setup(_skeleton, "quetzalcoatlus", _anim_player)

func _play_anim(anim_name: String, blend: float = 0.3, custom_speed: float = -1.0) -> void:
	if not _anim_player:
		_find_animation_player()
		if not _anim_player: return

	var target_anim = ""
	var clean_name = anim_name.replace("_loop", "")
	if _anim_player.has_animation(anim_name):
		target_anim = anim_name
	elif _anim_player.has_animation(clean_name):
		target_anim = clean_name
	else:
		for a in _anim_player.get_animation_list():
			if a.ends_with(clean_name) or clean_name in a:
				target_anim = a
				break

	if target_anim != "":
		if custom_speed > 0.0:
			_anim_player.speed_scale = custom_speed
		elif "Volar" in target_anim:
			_anim_player.speed_scale = fly_anim_speed
		elif "Caminar" in target_anim:
			_anim_player.speed_scale = walk_anim_speed
		elif "Comer" in target_anim:
			_anim_player.speed_scale = 1.0
		else:
			_anim_player.speed_scale = 0.9

		if _anim_player.current_animation != target_anim or not _anim_player.is_playing():
			if "Caminar" in target_anim:
				# Quetzal_Caminar fue exportada con el ciclo de apoyo invertido; reproducir en reversa corrige el apoyo de patas y alas
				_anim_player.play(target_anim, blend, -1.0, true)
			else:
				_anim_player.play(target_anim, blend)

func _physics_process(delta: float) -> void:
	var is_flying = (current_state == State.TAKE_OFF or current_state == State.SOARING_FLIGHT or current_state == State.LANDING)

	if not is_flying:
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = -1.0

		if slope_adaptation_enabled:
			_update_surface_slope(delta)
	else:
		# En vuelo la gravedad es compensada por sustentación
		velocity.y = move_toward(velocity.y, 0.0, 2.0 * delta)

	_state_timer = max(0.0, _state_timer - delta)
	_terrain_collision_cooldown = max(0.0, _terrain_collision_cooldown - delta)
	_detour_timer = max(0.0, _detour_timer - delta)

	if not is_flying:
		_sensory_scan_food()

	var commands = _update_brain_state(delta)
	var desired_turn: float = commands.turn
	var desired_forward: float = commands.forward
	var current_move_speed: float = commands.speed

	var cur_turn_speed = turn_speed
	if _detour_timer > 0.0: cur_turn_speed = turn_speed * 1.5
	if desired_turn != 0.0:
		rotate_y(desired_turn * cur_turn_speed * delta)

	var forward_dir = -global_transform.basis.z
	var target_vel = Vector3.ZERO

	if is_flying:
		var pitch_rad = _pitch_factor * deg_to_rad(22.0)
		var fly_dir = (forward_dir + Vector3.UP * sin(pitch_rad)).normalized()
		target_vel = fly_dir * current_move_speed
		velocity = velocity.move_toward(target_vel, 6.0 * delta)
	else:
		var fwd_h = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
		if desired_forward > 0.0:
			target_vel = forward_dir * (desired_forward * current_move_speed)
		velocity.x = move_toward(velocity.x, target_vel.x, 8.5 * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, 8.5 * delta)

	move_and_slide()

	# Reacción a obstáculos
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if not collider or collider == self: continue

		var col_normal = col.get_normal()
		if col_normal.y < 0.65 and _terrain_collision_cooldown <= 0.0:
			_trigger_terrain_obstacle_turn(col_normal, col.get_position())
			break

	_handle_animation_clips()

func _sensory_scan_food() -> void:
	var closest_food := DinoFood.find_nearest_for(self, DinoFood.DIET_MEAT, smell_radius, _get_habitat_node(), paddock_bounds_min, paddock_bounds_max)
	current_food_target = closest_food

	if closest_food:
		var to_f = (closest_food.global_position - global_position).normalized()
		var fwd = -global_transform.basis.z
		var angle_to_food = rad_to_deg(fwd.angle_to(to_f))
		if current_state == State.SOARING_FLIGHT:
			current_state = State.LANDING
			_state_timer = 3.0
			_current_waypoint = closest_food.global_position
		elif angle_to_food <= vision_angle_deg * 0.5:
			if current_state != State.PURSUE_FOOD and current_state != State.EAT_PECK and current_state != State.LANDING:
				current_state = State.PURSUE_FOOD
		else:
			if current_state != State.ALERT_SCAN and current_state != State.PURSUE_FOOD:
				current_state = State.ALERT_SCAN
				_state_timer = 3.0

func _update_brain_state(delta: float) -> Dictionary:
	var turn: float = 0.0
	var forward: float = 0.0
	var speed: float = walk_speed

	var busy_with_food := is_instance_valid(current_food_target) or (current_state in [State.ALERT_SCAN, State.PURSUE_FOOD, State.EAT_PECK])
	_spectator_ctrl.update(delta, self, _get_habitat_node(), paddock_bounds_min, paddock_bounds_max, busy_with_food)

	if _spectator_ctrl.is_controlling() and current_state != State.TAKE_OFF and current_state != State.LANDING:
		if current_state == State.SOARING_FLIGHT:
			speed = flight_speed * 0.85
			forward = 1.0
			if _spectator_ctrl.get_phase() == DinoSpectatorController.Phase.RETREATING:
				_current_waypoint = _spectator_ctrl.get_aerial_retreat_waypoint()
				if global_position.distance_to(_current_waypoint) < 4.5:
					current_state = State.LANDING
					_state_timer = 4.0
					_current_waypoint = _spectator_ctrl.get_move_target(self)
			else:
				_current_waypoint = _spectator_ctrl.get_aerial_flyby_waypoint()
			turn = _steer_towards(_current_waypoint)
			var dy_fly = _current_waypoint.y - global_position.y
			_pitch_factor = clampf(dy_fly / 5.0, -0.6, 0.6)
			velocity.y = move_toward(velocity.y, dy_fly * 0.8, 4.0 * delta)
			var fly_fence = _compute_fence_avoidance()
			if abs(fly_fence) > 0.05:
				turn = fly_fence
			return {"turn": clamp(turn, -1.0, 1.0), "forward": clamp(forward, -1.0, 1.0), "speed": speed}
		elif _spectator_ctrl.is_moving_phase():
			current_state = State.PATROL_WALK
			_current_waypoint = _spectator_ctrl.get_move_target(self)
			_current_waypoint.y = global_position.y
			var steer_target := _obstacle_detour_waypoint if _detour_timer > 0.0 else _current_waypoint
			turn = _steer_towards(steer_target)
			forward = 1.0
			speed = walk_speed * _spectator_ctrl.get_speed_multiplier()
			var spec_fence = _compute_fence_avoidance()
			if abs(spec_fence) > 0.05:
				turn = spec_fence
			return {"turn": clamp(turn, -1.0, 1.0), "forward": clamp(forward, -1.0, 1.0), "speed": speed}
		elif _spectator_ctrl.is_posing_phase():
			if _spectator_ctrl.consume_display_trigger():
				current_state = State.TAKE_OFF
				_state_timer = 1.8
				_current_waypoint = _spectator_ctrl.get_aerial_flyby_waypoint()
			else:
				current_state = State.IDLE_ROOST
				_state_timer = maxf(_state_timer, 0.5)
				_observe_look_angle = _spectator_ctrl.get_head_look_factor(self)
				turn = _spectator_ctrl.get_showcase_turn(self)
				return {"turn": clamp(turn, -1.0, 1.0), "forward": 0.0, "speed": walk_speed}

	match current_state:
		State.PATROL_WALK:
			speed = walk_speed
			var dist = Vector2(global_position.x - _current_waypoint.x, global_position.z - _current_waypoint.z).length()
			if dist < 2.5:
				var roll = randf()
				if roll < 0.25:
					current_state = State.TAKE_OFF
					_state_timer = 2.0
					_pick_flight_waypoint()
				elif roll < 0.60:
					current_state = State.IDLE_ROOST
					_state_timer = randf_range(3.0, 6.0)
				else:
					_pick_new_patrol_waypoint()
			else:
				turn = _steer_towards(_current_waypoint)
				forward = 1.0

		State.IDLE_ROOST:
			forward = 0.0
			turn = 0.0
			_observe_look_angle = sin(_time_accum * 0.7) * 0.65
			if _state_timer <= 0.0:
				current_state = State.PATROL_WALK
				_pick_new_patrol_waypoint()

		State.ALERT_SCAN:
			forward = 0.0
			turn = 0.0
			if is_instance_valid(current_food_target):
				turn = _steer_towards(current_food_target.global_position) * 1.3
			if _state_timer <= 0.0:
				current_state = State.PATROL_WALK
				_pick_new_patrol_waypoint()

		State.PURSUE_FOOD:
			if is_instance_valid(current_food_target):
				speed = walk_speed * 1.3
				var dist = Vector2(global_position.x - current_food_target.global_position.x, global_position.z - current_food_target.global_position.z).length()
				if dist <= eat_distance:
					current_state = State.EAT_PECK
					_state_timer = 3.5
					if current_food_target.has_method("consume"):
						current_food_target.consume()
					else:
						current_food_target.queue_free()
					current_food_target = null
				else:
					var target_pos = current_food_target.global_position
					if _detour_timer > 0.0: target_pos = _obstacle_detour_waypoint
					turn = _steer_towards(target_pos) * 1.4
					forward = 1.0
			else:
				current_state = State.IDLE_ROOST
				_state_timer = 2.0

		State.EAT_PECK:
			forward = 0.0
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_ROOST
				_state_timer = randf_range(2.5, 5.0)

		State.TAKE_OFF:
			speed = flight_speed * 0.7
			forward = 1.0
			_pitch_factor = 0.8
			velocity.y = 3.5
			turn = _steer_towards(_current_waypoint)
			if _state_timer <= 0.0:
				current_state = State.SOARING_FLIGHT
				_state_timer = randf_range(8.0, 16.0)

		State.SOARING_FLIGHT:
			speed = flight_speed
			forward = 1.0
			var dist = global_position.distance_to(_current_waypoint)
			if dist < 4.0:
				_pick_flight_waypoint()
			turn = _steer_towards(_current_waypoint)
			var dy = _current_waypoint.y - global_position.y
			_pitch_factor = clampf(dy / 5.0, -0.6, 0.6)
			velocity.y = move_toward(velocity.y, dy * 0.8, 4.0 * delta)
			if _state_timer <= 0.0:
				current_state = State.LANDING
				_state_timer = 4.0
				_pick_new_patrol_waypoint()

		State.LANDING:
			speed = flight_speed * 0.6
			forward = 1.0
			turn = _steer_towards(_current_waypoint)
			_pitch_factor = -0.5
			velocity.y = move_toward(velocity.y, -2.5, 3.0 * delta)
			if is_on_floor() or _to_habitat_local(global_position).y <= 1.0:
				current_state = State.IDLE_ROOST
				_state_timer = randf_range(3.0, 6.0)

	var fence_steer = _compute_fence_avoidance()
	if abs(fence_steer) > 0.05:
		turn = fence_steer

	return {"turn": clamp(turn, -1.0, 1.0), "forward": clamp(forward, -1.0, 1.0), "speed": speed}

func _handle_animation_clips() -> void:
	var real_h_speed := Vector2(velocity.x, velocity.z).length()
	match current_state:
		State.PATROL_WALK:
			if real_h_speed < 0.025:
				_play_anim("Quetzal_Idle", 0.35, 0.9)
			else:
				var synced := clampf(real_h_speed / maxf(stride_speed_ratio, 0.01), 0.45, walk_anim_speed * 1.3)
				_play_anim("Quetzal_Caminar", 0.3, synced)
		State.IDLE_ROOST:
			_play_anim("Quetzal_Idle", 0.4, 0.9)
		State.ALERT_SCAN:
			_play_anim("Quetzal_Buscar_Comida", 0.3, 1.0)
		State.PURSUE_FOOD:
			if real_h_speed < 0.025:
				_play_anim("Quetzal_Idle", 0.25, 0.9)
			else:
				var synced := clampf(real_h_speed / maxf(stride_speed_ratio, 0.01), 0.6, walk_anim_speed * 1.6)
				_play_anim("Quetzal_Caminar", 0.25, synced)
		State.EAT_PECK:
			_play_anim("Quetzal_Comer", 0.2, 1.0)
		State.TAKE_OFF:
			_play_anim("Quetzal_Volar", 0.25, fly_anim_speed * 1.25)
		State.SOARING_FLIGHT:
			var fly_synced := clampf((velocity.length() / maxf(flight_speed, 0.5)) * fly_anim_speed, 0.85, fly_anim_speed * 1.3)
			_play_anim("Quetzal_Volar", 0.35, fly_synced)
		State.LANDING:
			_play_anim("Quetzal_Volar", 0.3, fly_anim_speed * 1.15)

func _process(delta: float) -> void:
	_time_accum += delta

	var is_flying = (current_state == State.TAKE_OFF or current_state == State.SOARING_FLIGHT or current_state == State.LANDING)

	var target_turn = 0.0
	if current_state == State.PATROL_WALK or current_state == State.PURSUE_FOOD or is_flying:
		var to_wp = (_current_waypoint - global_position).normalized()
		var local_wp = global_transform.basis.inverse() * to_wp
		target_turn = clampf(-local_wp.x, -1.0, 1.0)
	elif current_state == State.IDLE_ROOST or current_state == State.ALERT_SCAN:
		target_turn = _observe_look_angle

	if _spectator_ctrl.wants_head_look() and current_state in [State.PATROL_WALK, State.IDLE_ROOST, State.SOARING_FLIGHT]:
		target_turn = _spectator_ctrl.get_head_look_factor(self)

	_turn_factor = lerpf(_turn_factor, target_turn, clampf(delta * 4.0, 0.0, 1.0))

	var jaw_mode: int = DinoJawController.Mode.EAT if current_state == State.EAT_PECK else DinoJawController.Mode.CLOSED
	_jaw_ctrl.update(delta, jaw_mode, _anim_player)

func _apply_procedural_overlay() -> void:
	if not _skeleton:
		return
	_jaw_ctrl.apply()
	var is_flying := (current_state == State.TAKE_OFF or current_state == State.SOARING_FLIGHT or current_state == State.LANDING)
	var is_action := (current_state in [State.EAT_PECK, State.ALERT_SCAN])
	var head_w := 0.15 if is_action else (0.35 if is_flying else 0.50)
	var body_w := 0.0 if is_action else (0.45 if is_flying else 0.40)

	var yaw_rad = _turn_factor * deg_to_rad(head_yaw_max) * head_w
	var slope_comp = (-_current_slope_pitch * 0.5 if not is_flying else -_pitch_factor * 0.3) * head_w
	_apply_bone_rotation(_bone_head, _head_rest_q, slope_comp, yaw_rad)
	_apply_bone_rotation(_bone_neck_3, _neck_3_rest_q, slope_comp * 0.8, yaw_rad * 0.8)
	_apply_bone_rotation(_bone_neck_2, _neck_2_rest_q, slope_comp * 0.6, yaw_rad * 0.6)
	_apply_bone_rotation(_bone_neck_1, _neck_1_rest_q, slope_comp * 0.3, yaw_rad * 0.3)

	if body_w > 0.01:
		var bank_roll = -_turn_factor * deg_to_rad(bank_roll_max if is_flying else 4.0) * body_w
		_apply_bone_rotation(_bone_chest, _chest_rest_q, 0.0, _turn_factor * deg_to_rad(chest_yaw_max) * body_w, bank_roll)
		_apply_bone_rotation(_bone_spine, _spine_rest_q, 0.0, _turn_factor * deg_to_rad(spine_yaw_max) * body_w, bank_roll * 0.5, false)
	elif _bone_spine >= 0:
		_skeleton.set_bone_pose_rotation(_bone_spine, _spine_rest_q)

func _apply_bone_rotation(bone_idx: int, rest_q: Quaternion, pitch_rad: float, yaw_rad: float, roll_rad: float = 0.0, additive: bool = true) -> void:
	if bone_idx < 0: return
	var base_q = _skeleton.get_bone_pose_rotation(bone_idx) if additive else rest_q
	var q_pitch = Quaternion(Vector3.RIGHT, pitch_rad)
	var q_yaw = Quaternion(Vector3.FORWARD, yaw_rad)
	var q_roll = Quaternion(Vector3.UP, roll_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, base_q * (q_pitch * q_roll * q_yaw))

func _update_surface_slope(delta: float) -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state: return

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

	if hit_front.has_hit and hit_rear.has_hit:
		var delta_y = hit_front.pos.y - hit_rear.pos.y
		target_pitch = atan2(delta_y, probe_forward_dist * 2.0)
	elif is_on_floor():
		var fn = get_floor_normal()
		var lfn = global_transform.basis.inverse() * fn
		target_pitch = atan2(lfn.z, lfn.y)

	if hit_left.has_hit and hit_right.has_hit:
		var delta_roll_y = hit_right.pos.y - hit_left.pos.y
		target_roll = -atan2(delta_roll_y, probe_side_dist * 2.0)
	elif is_on_floor():
		var fn = get_floor_normal()
		var lfn = global_transform.basis.inverse() * fn
		target_roll = atan2(-lfn.x, lfn.y)

	target_pitch = clampf(target_pitch, -deg_to_rad(max_slope_pitch_deg), deg_to_rad(max_slope_pitch_deg))
	target_roll = clampf(target_roll, -deg_to_rad(max_slope_roll_deg), deg_to_rad(max_slope_roll_deg))

	var blend = clampf(delta * slope_smooth_speed, 0.0, 1.0)
	_current_slope_pitch = lerp_angle(_current_slope_pitch, target_pitch, blend)
	_current_slope_roll = lerp_angle(_current_slope_roll, target_roll, blend)

func _cast_probe(space_state: PhysicsDirectSpaceState3D, pos: Vector3) -> Dictionary:
	var from = Vector3(pos.x, global_position.y + 2.0, pos.z)
	var to = Vector3(pos.x, global_position.y - 3.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var res = space_state.intersect_ray(query)
	if res.size() > 0:
		return {"has_hit": true, "pos": res.position, "normal": res.normal}
	return {"has_hit": false, "pos": pos, "normal": Vector3.UP}

func _trigger_terrain_obstacle_turn(col_normal: Vector3, _col_point: Vector3) -> void:
	if _terrain_collision_cooldown > 0.0: return
	_terrain_collision_cooldown = 1.4

	var fwd = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	var norm = col_normal
	norm.y = 0.0
	norm = norm.normalized()

	var turn_left = fwd.cross(norm).y > 0.0
	var detour_dir = norm.cross(Vector3.UP if turn_left else Vector3.DOWN).normalized()
	_obstacle_detour_waypoint = global_position + detour_dir * 5.0
	_detour_timer = 2.0

func _steer_towards(target_pos: Vector3) -> float:
	var to_target = (target_pos - global_position)
	to_target.y = 0.0
	var local_dir = global_transform.basis.inverse() * to_target.normalized()
	return clamp(-local_dir.x * 2.2, -1.0, 1.0)

func _compute_fence_avoidance() -> float:
	if current_state == State.PURSUE_FOOD or current_state == State.EAT_PECK:
		return 0.0
	var local_pos = _to_habitat_local(global_position)
	var fwd = -global_transform.basis.z
	var hab = _get_habitat_node()
	if hab:
		fwd = hab.global_transform.basis.inverse() * fwd
	var needs_avoid = false
	if (local_pos.x > paddock_bounds_max.x - 2.5 and fwd.x > 0.0) or (local_pos.x < paddock_bounds_min.x + 2.5 and fwd.x < 0.0):
		needs_avoid = true
	if (local_pos.z > paddock_bounds_max.z - 2.5 and fwd.z > 0.0) or (local_pos.z < paddock_bounds_min.z + 2.5 and fwd.z < 0.0):
		needs_avoid = true
	if needs_avoid:
		return _steer_towards(_get_habitat_center())
	return 0.0

func _to_habitat_local(pos: Vector3) -> Vector3:
	var hab = _get_habitat_node()
	return hab.to_local(pos) if hab else pos

func _get_habitat_center() -> Vector3:
	var hab = _get_habitat_node()
	return hab.global_position if hab else Vector3.ZERO

func _get_habitat_node() -> Node3D:
	var p = get_parent()
	while p:
		if p is Node3D and (p.name.begins_with("Habitat") or p == get_tree().current_scene):
			return p as Node3D
		p = p.get_parent()
	return null

func _pick_new_patrol_waypoint() -> void:
	var lx = randf_range(paddock_bounds_min.x + 2.5, paddock_bounds_max.x - 2.5)
	var lz = randf_range(paddock_bounds_min.z + 2.5, paddock_bounds_max.z - 2.5)
	var hab = _get_habitat_node()
	if hab:
		_current_waypoint = hab.to_global(Vector3(lx, 0.5, lz))
	else:
		_current_waypoint = Vector3(lx, 0.5, lz)

func _pick_flight_waypoint() -> void:
	var lx = randf_range(paddock_bounds_min.x + 4.0, paddock_bounds_max.x - 4.0)
	var ly = randf_range(7.0, 14.0)
	var lz = randf_range(paddock_bounds_min.z + 4.0, paddock_bounds_max.z - 4.0)
	var hab = _get_habitat_node()
	if hab:
		_current_waypoint = hab.to_global(Vector3(lx, ly, lz))
	else:
		_current_waypoint = Vector3(lx, ly, lz)

func get_brain_state_name() -> String:
	match current_state:
		State.PATROL_WALK: return "CAMINATA CUADRÚPEDA TERRESTRE"
		State.IDLE_ROOST: return "PERCHADO / REPOSO"
		State.ALERT_SCAN: return "ESCANEO VISUAL EN TIERRA"
		State.PURSUE_FOOD: return "ACERCÁNDOSE A ALIMENTO"
		State.EAT_PECK: return "PICOTEANDO / COMIENDO"
		State.TAKE_OFF: return "DESPEGUE Y ASCENSO"
		State.SOARING_FLIGHT: return "PLANEO EN VUELO POR AVIARIO"
		State.LANDING: return "DESCENSO Y ATERRIZAJE"
	return "DESCONOCIDO"
