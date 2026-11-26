class_name DinoCarnotaurus
extends CharacterBody3D

# ==============================================================================
# CARNOTAURUS — CEREBRO AUTÓNOMO Y SISTEMA PROCEDURAL DEPREDADOR
# ==============================================================================
# Therópodo carnívoro de tamaño mediano-grande, veloz y agresivo.
# - Movimiento bípedo con balanceo de torso y peralte dinámico.
# - Cola articulada de 4 vértebras como contrapeso.
# - Mandíbula articulada con mordida fuerte y micro-movimiento respiratorio.
# - Adaptación procedural a pendientes y desniveles del terreno.
# - Evasión predictiva y reactiva de obstáculos (rocas, muros, vallas).
# ==============================================================================

@export var is_autonomous: bool = true

@export_group("Cinemática y Velocidades")
@export var walk_anim_speed: float = 1.05
@export var run_anim_speed: float = 1.65
@export var stride_speed_ratio: float = 1.345
@export var run_stride_ratio: float = 1.345
@export var turn_speed: float = 0.85
@export var gravity: float = 9.8

var walk_speed: float:
	get: return walk_anim_speed * stride_speed_ratio

var run_speed: float:
	get: return run_anim_speed * run_stride_ratio

@export_group("Color y Textura")
@export var skin_color: Color = Color(0.68, 0.42, 0.30, 1.0)
@export var horn_color: Color = Color(0.25, 0.22, 0.20, 1.0)

@export_group("Animación Procedural de Cabeza y Mandíbula")
@export var head_yaw_max: float = 20.0
@export var head_pitch_max: float = 15.0
@export var jaw_open_max: float = 25.0

@export_group("Animación Procedural de Espina y Pecho")
@export var chest_yaw_max: float = 7.0
@export var spine_yaw_max: float = 5.0
@export var bank_roll_max: float = 4.0

@export_group("Ondulación Procedural de Cola (4 Segmentos)")
@export var tail_sway_speed: float = 1.35
@export var tail_sway_deg: float = 6.0
@export var tail_counterweight_deg: float = 8.5

@export_group("Adaptación a Pendientes / Terreno")
@export var slope_adaptation_enabled: bool = true
@export var slope_smooth_speed: float = 5.5
@export var max_slope_pitch_deg: float = 28.0
@export var max_slope_roll_deg: float = 18.0
@export var probe_forward_dist: float = 2.2
@export var probe_side_dist: float = 1.0
@export var slope_head_compensate_ratio: float = 0.50
@export var slope_tail_balance_ratio: float = 0.55

@export_group("Cerebro Sensorial Autónomo")
@export var smell_radius: float = 28.0
@export var vision_angle_deg: float = 135.0
@export var eat_distance: float = 3.2

@export_group("Límites de Hábitat")
@export var paddock_bounds_min: Vector2 = Vector2(-15.0, -15.0)
@export var paddock_bounds_max: Vector2 = Vector2(15.0, 15.0)

enum State {
	PATROL_TERRITORY,
	IDLE_STALKING,
	SNIFF_TRACKING,
	CHARGE_PREY,
	FEEDING_CARCASS,
	TAIL_WHIP_DISPLAY
}

@onready var visual_model: Node3D = get_node_or_null("VisualModel")

@export_group("Optimización FOV / Culling")
@export var fov_culling_enabled: bool = true
@export var max_animation_distance: float = 150.0

var is_in_view: bool = true
var _visibility_check_timer: float = 0.0
const VISIBILITY_CHECK_INTERVAL: float = 0.12

var current_state: State = State.PATROL_TERRITORY:
	set(value):
		if current_state != value:
			current_state = value
			if not has_meta("_managed_by_park_optimizer"):
				print("[Cerebro Carnotaurus] Estado: ", get_brain_state_name())

var current_food_target: Node3D = null

var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _jaw_ctrl: DinoJawController = DinoJawController.new()
var _spectator_ctrl: DinoSpectatorController = DinoSpectatorController.new()
var _time_accum: float = 0.0
var _state_timer: float = 0.0
var _current_waypoint: Vector3 = Vector3.ZERO
var _observe_look_angle: float = 0.0
var _encounter_cooldown: float = 0.0

var _turn_factor: float = 0.0
var _pitch_factor: float = 0.0

var _current_slope_pitch: float = 0.0
var _current_slope_roll: float = 0.0
var _current_ground_y_offset: float = 0.0

var _terrain_collision_cooldown: float = 0.0
var _obstacle_detour_waypoint: Vector3 = Vector3.ZERO
var _detour_timer: float = 0.0
var _stuck_timer: float = 0.0

var _bone_head: int = -1
var _bone_neck: int = -1
var _bone_chest: int = -1
var _bone_spine: int = -1
var _bone_jaw: int = -1
var _bone_ik_jaw: int = -1
var _bone_tail_1: int = -1
var _bone_tail_2: int = -1
var _bone_tail_3: int = -1
var _bone_tail_4: int = -1

var _head_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_rest_q: Quaternion = Quaternion.IDENTITY
var _chest_rest_q: Quaternion = Quaternion.IDENTITY
var _spine_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_1_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_2_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_3_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_4_rest_q: Quaternion = Quaternion.IDENTITY

func _ready() -> void:
	add_to_group("dino_carnivores")
	add_to_group("carnotaurus")
	add_to_group("dinosaurios")
	_time_accum = randf_range(0.0, 10.0)
	_apply_dino_material()
	_find_animation_player()
	_find_skeleton()
	_spectator_ctrl.setup("carnotaurus", self)
	_pick_new_patrol_waypoint()
	
	if randf() < 0.4:
		current_state = State.IDLE_STALKING
		_state_timer = randf_range(2.0, 5.0)
		_play_anim("Carno_Idle", 0.0)
	else:
		_play_anim("Carno_Caminar", 0.0)

func _apply_dino_material() -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh and mesh.mesh.get_surface_count() > 0:
			var has_mat = false
			for s in range(mesh.mesh.get_surface_count()):
				if mesh.get_active_material(s) != null or mesh.mesh.surface_get_material(s) != null:
					has_mat = true
					break
			if has_mat:
				continue
		var mat = StandardMaterial3D.new()
		mat.albedo_color = skin_color
		mat.roughness = 0.68
		mesh.material_override = mat

func _find_animation_player() -> void:
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not _anim_player and visual_model:
		_anim_player = visual_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		for aname in _anim_player.get_animation_list():
			if "Caminar" in aname or "Idle" in aname:
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
		_bone_neck = _skeleton.find_bone("Neck")
		_bone_chest = _skeleton.find_bone("Chest")
		_bone_spine = _skeleton.find_bone("Spine")
		_bone_jaw = _skeleton.find_bone("Jaw")
		_bone_ik_jaw = _skeleton.find_bone("IK_Jaw")
		_bone_tail_1 = _skeleton.find_bone("Tail.001")
		_bone_tail_2 = _skeleton.find_bone("Tail.002")
		_bone_tail_3 = _skeleton.find_bone("Tail.003")
		_bone_tail_4 = _skeleton.find_bone("Tail.004")

		if _bone_head >= 0: _head_rest_q = _skeleton.get_bone_rest(_bone_head).basis.get_rotation_quaternion()
		if _bone_neck >= 0: _neck_rest_q = _skeleton.get_bone_rest(_bone_neck).basis.get_rotation_quaternion()
		if _bone_chest >= 0: _chest_rest_q = _skeleton.get_bone_rest(_bone_chest).basis.get_rotation_quaternion()
		if _bone_spine >= 0: _spine_rest_q = _skeleton.get_bone_rest(_bone_spine).basis.get_rotation_quaternion()
		if _bone_tail_1 >= 0: _tail_1_rest_q = _skeleton.get_bone_rest(_bone_tail_1).basis.get_rotation_quaternion()
		if _bone_tail_2 >= 0: _tail_2_rest_q = _skeleton.get_bone_rest(_bone_tail_2).basis.get_rotation_quaternion()
		if _bone_tail_3 >= 0: _tail_3_rest_q = _skeleton.get_bone_rest(_bone_tail_3).basis.get_rotation_quaternion()
		if _bone_tail_4 >= 0: _tail_4_rest_q = _skeleton.get_bone_rest(_bone_tail_4).basis.get_rotation_quaternion()
		_jaw_ctrl.setup(_skeleton, "carnotaurus", _anim_player)

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
		elif "Caminar" in target_anim:
			_anim_player.speed_scale = walk_anim_speed
		elif "Coletear" in target_anim:
			_anim_player.speed_scale = 1.1
		elif "Comer" in target_anim:
			_anim_player.speed_scale = 1.0
		else:
			_anim_player.speed_scale = 0.9

		if _anim_player.current_animation != target_anim or not _anim_player.is_playing():
			_anim_player.play(target_anim, blend)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -1.0

	if slope_adaptation_enabled:
		_update_surface_slope(delta)

	_state_timer = max(0.0, _state_timer - delta)
	_encounter_cooldown = max(0.0, _encounter_cooldown - delta)
	_terrain_collision_cooldown = max(0.0, _terrain_collision_cooldown - delta)
	_detour_timer = max(0.0, _detour_timer - delta)

	_sensory_scan_food()

	var commands = _update_brain_state(delta)
	var desired_turn: float = commands.turn
	var desired_forward: float = commands.forward
	var current_move_speed: float = commands.speed

	if slope_adaptation_enabled:
		if _current_slope_pitch > 0.05:
			current_move_speed *= clampf(1.0 - sin(_current_slope_pitch) * 0.30, 0.75, 1.0)
		elif _current_slope_pitch < -0.05:
			current_move_speed *= clampf(1.0 + sin(_current_slope_pitch) * 0.18, 0.82, 1.0)

	var cur_turn_speed = turn_speed
	if _detour_timer > 0.0:
		cur_turn_speed = turn_speed * 1.6
	if desired_turn != 0.0:
		rotate_y(desired_turn * cur_turn_speed * delta)

	var forward_dir = -global_transform.basis.z
	var fwd_h = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
	var target_h_vel = Vector3.ZERO
	if desired_forward > 0.0:
		target_h_vel = forward_dir * (desired_forward * current_move_speed)

	# Detección frontal de obstáculos del terreno
	if (current_state == State.PATROL_TERRITORY or current_state == State.CHARGE_PREY) and _terrain_collision_cooldown <= 0.0:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var chest_y = global_position.y + 1.5
			var ray_from = Vector3(global_position.x, chest_y, global_position.z)
			var ray_to = ray_from + fwd_h * 4.2
			var q = PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			q.exclude = [get_rid()]
			var res = space_state.intersect_ray(q)
			if res.size() > 0 and res.normal.y < 0.65 and fwd_h.dot(res.normal) < -0.3:
				_trigger_terrain_obstacle_turn(res.normal, res.position)

	velocity.x = move_toward(velocity.x, target_h_vel.x, 9.0 * delta)
	velocity.z = move_toward(velocity.z, target_h_vel.z, 9.0 * delta)

	move_and_slide()

	# Reacción a colisiones físicas
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if not collider or collider == self: continue

		var col_normal = col.get_normal()
		if col_normal.y < 0.65 and _terrain_collision_cooldown <= 0.0:
			var col_norm_h = Vector3(col_normal.x, 0.0, col_normal.z).normalized()
			if fwd_h.dot(col_norm_h) < -0.3:
				_trigger_terrain_obstacle_turn(col_normal, col.get_position())
				break

	# Watchdog anti-atasco
	var real_h_speed = Vector2(velocity.x, velocity.z).length()
	if desired_forward > 0.2 and real_h_speed < 0.15 and is_on_floor():
		_stuck_timer += delta
		if _stuck_timer > 0.5:
			_stuck_timer = 0.0
			_terrain_collision_cooldown = 0.0
			var center = _get_habitat_center()
			center.y = global_position.y
			var to_center = (center - global_position).normalized()
			if to_center.length_squared() < 0.01: to_center = -fwd_h
			_trigger_terrain_obstacle_turn(-to_center, global_position + fwd_h * 1.5, true)
	else:
		_stuck_timer = max(0.0, _stuck_timer - delta * 2.0)

	_handle_animation_clips()

func _sensory_scan_food() -> void:
	var closest_food := DinoFood.find_nearest_for(self, DinoFood.DIET_MEAT, smell_radius, _get_habitat_node(), paddock_bounds_min, paddock_bounds_max)
	current_food_target = closest_food

	if closest_food:
		var to_f = (closest_food.global_position - global_position).normalized()
		var fwd = -global_transform.basis.z
		var angle_to_food = rad_to_deg(fwd.angle_to(to_f))
		if angle_to_food <= vision_angle_deg * 0.5:
			if current_state != State.CHARGE_PREY and current_state != State.FEEDING_CARCASS:
				current_state = State.CHARGE_PREY
		else:
			if current_state != State.SNIFF_TRACKING and current_state != State.CHARGE_PREY:
				current_state = State.SNIFF_TRACKING
				_state_timer = 3.5

func _update_brain_state(delta: float) -> Dictionary:
	var turn: float = 0.0
	var forward: float = 0.0
	var speed: float = walk_speed

	var busy_with_food := is_instance_valid(current_food_target) or (current_state in [State.SNIFF_TRACKING, State.CHARGE_PREY, State.FEEDING_CARCASS])
	_spectator_ctrl.update(
		delta,
		self,
		_get_habitat_node(),
		Vector3(paddock_bounds_min.x, 0.0, paddock_bounds_min.y),
		Vector3(paddock_bounds_max.x, 0.0, paddock_bounds_max.y),
		busy_with_food
	)

	if _spectator_ctrl.is_controlling() and current_state != State.TAIL_WHIP_DISPLAY:
		if _spectator_ctrl.is_moving_phase():
			current_state = State.PATROL_TERRITORY
			_current_waypoint = _spectator_ctrl.get_move_target(self)
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
				current_state = State.TAIL_WHIP_DISPLAY
				_state_timer = _spectator_ctrl.get_display_duration()
			else:
				current_state = State.IDLE_STALKING
				_state_timer = maxf(_state_timer, 0.5)
			_observe_look_angle = _spectator_ctrl.get_head_look_factor(self)
			turn = _spectator_ctrl.get_showcase_turn(self)
			return {"turn": clamp(turn, -1.0, 1.0), "forward": 0.0, "speed": walk_speed}

	match current_state:
		State.PATROL_TERRITORY:
			speed = walk_speed
			var dist = Vector2(global_position.x - _current_waypoint.x, global_position.z - _current_waypoint.z).length()
			if dist < 2.5:
				var roll = randf()
				if roll < 0.20:
					current_state = State.TAIL_WHIP_DISPLAY
					_state_timer = 3.5
				elif roll < 0.60:
					current_state = State.IDLE_STALKING
					_state_timer = randf_range(3.0, 7.0)
				else:
					_pick_new_patrol_waypoint()
			else:
				turn = _steer_towards(_current_waypoint)
				forward = 1.0

		State.IDLE_STALKING:
			forward = 0.0
			turn = 0.0
			_observe_look_angle = sin(_time_accum * 0.8) * 0.65
			if _state_timer <= 0.0:
				current_state = State.PATROL_TERRITORY
				_pick_new_patrol_waypoint()

		State.SNIFF_TRACKING:
			if is_instance_valid(current_food_target):
				turn = _steer_towards(current_food_target.global_position) * 1.3
				forward = 0.4
				speed = walk_speed * 0.7
			else:
				current_state = State.PATROL_TERRITORY
				_pick_new_patrol_waypoint()

		State.CHARGE_PREY:
			if is_instance_valid(current_food_target):
				speed = run_speed
				var dist = Vector2(global_position.x - current_food_target.global_position.x, global_position.z - current_food_target.global_position.z).length()
				if dist <= eat_distance:
					current_state = State.FEEDING_CARCASS
					_state_timer = 4.0
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
				current_state = State.IDLE_STALKING
				_state_timer = 2.5

		State.FEEDING_CARCASS:
			forward = 0.0
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_STALKING
				_state_timer = randf_range(3.0, 5.0)

		State.TAIL_WHIP_DISPLAY:
			forward = 0.05
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_STALKING
				_state_timer = randf_range(2.5, 4.0)

	var fence_steer = _compute_fence_avoidance()
	if abs(fence_steer) > 0.05:
		turn = fence_steer

	return {"turn": clamp(turn, -1.0, 1.0), "forward": clamp(forward, -1.0, 1.0), "speed": speed}

func _handle_animation_clips() -> void:
	var real_h_speed := Vector2(velocity.x, velocity.z).length()
	match current_state:
		State.PATROL_TERRITORY:
			if real_h_speed < 0.05:
				_play_anim("Carno_Idle", 0.3, 0.9)
			else:
				var synced := clampf(real_h_speed / maxf(stride_speed_ratio, 0.01), 0.4, walk_anim_speed * 1.25)
				_play_anim("Carno_Caminar", 0.3, synced)
		State.IDLE_STALKING:
			_play_anim("Carno_Idle", 0.4, 0.9)
		State.SNIFF_TRACKING:
			_play_anim("Carno_Buscar_Comida", 0.3, 1.0)
		State.CHARGE_PREY:
			if real_h_speed < 0.05:
				_play_anim("Carno_Idle", 0.25, 0.95)
			else:
				var synced := clampf(real_h_speed / maxf(run_stride_ratio, 0.01), 0.55, run_anim_speed * 1.25)
				_play_anim("Carno_Caminar", 0.25, synced)
		State.FEEDING_CARCASS:
			_play_anim("Carno_Comer", 0.2, 1.0)
		State.TAIL_WHIP_DISPLAY:
			_play_anim("Carno_Coletear", 0.25, 1.1)

func _process(delta: float) -> void:
	_time_accum += delta

	var target_turn = 0.0
	if current_state == State.PATROL_TERRITORY or current_state == State.CHARGE_PREY:
		var to_wp = (_current_waypoint - global_position).normalized()
		var local_wp = global_transform.basis.inverse() * to_wp
		target_turn = clampf(-local_wp.x, -1.0, 1.0)
	elif current_state == State.IDLE_STALKING:
		target_turn = _observe_look_angle

	if _spectator_ctrl.wants_head_look() and current_state in [State.PATROL_TERRITORY, State.IDLE_STALKING]:
		target_turn = _spectator_ctrl.get_head_look_factor(self)

	_turn_factor = lerpf(_turn_factor, target_turn, clampf(delta * 4.0, 0.0, 1.0))

	var jaw_mode: int = DinoJawController.Mode.CLOSED
	if current_state == State.FEEDING_CARCASS:
		jaw_mode = DinoJawController.Mode.EAT
	elif current_state == State.TAIL_WHIP_DISPLAY:
		jaw_mode = DinoJawController.Mode.ROAR
	_jaw_ctrl.update(delta, jaw_mode, _anim_player)

func _apply_procedural_overlay() -> void:
	if not _skeleton:
		return
	_jaw_ctrl.apply()
	var is_action := (current_state in [State.FEEDING_CARCASS, State.TAIL_WHIP_DISPLAY, State.SNIFF_TRACKING])
	var head_w := 0.15 if is_action else 0.55
	var body_w := 0.0 if is_action else 0.45
	var tail_w := 0.0 if current_state == State.TAIL_WHIP_DISPLAY else (0.15 if is_action else 0.45)

	# Flexión procedural aditiva de cabeza y cuello
	var yaw_rad = _turn_factor * deg_to_rad(head_yaw_max) * head_w
	var slope_comp = -_current_slope_pitch * slope_head_compensate_ratio * head_w
	_apply_bone_rotation(_bone_head, _head_rest_q, slope_comp, yaw_rad)
	_apply_bone_rotation(_bone_neck, _neck_rest_q, slope_comp * 0.6, yaw_rad * 0.6)

	# Flexión de columna y torso con peralte
	if body_w > 0.01:
		var bank_roll = -_turn_factor * deg_to_rad(bank_roll_max) * body_w
		_apply_bone_rotation(_bone_chest, _chest_rest_q, 0.0, _turn_factor * deg_to_rad(chest_yaw_max) * body_w, bank_roll)
		_apply_bone_rotation(_bone_spine, _spine_rest_q, 0.0, _turn_factor * deg_to_rad(spine_yaw_max) * body_w, bank_roll * 0.5)

	# Ondulación procedural aditiva de la cola (4 vértebras) + contrapeso
	if tail_w > 0.01:
		var is_walking = (_anim_player and "Caminar" in _anim_player.current_animation)
		var sway_mult = (1.1 if is_walking else 0.65) * tail_w
		var wave_1 = sin(_time_accum * tail_sway_speed) * deg_to_rad(tail_sway_deg * sway_mult)
		var wave_2 = sin(_time_accum * tail_sway_speed - 0.6) * deg_to_rad(tail_sway_deg * 1.2 * sway_mult)
		var wave_3 = sin(_time_accum * tail_sway_speed - 1.2) * deg_to_rad(tail_sway_deg * 1.4 * sway_mult)
		var wave_4 = sin(_time_accum * tail_sway_speed - 1.8) * deg_to_rad(tail_sway_deg * 1.6 * sway_mult)
		var turn_drag = -_turn_factor * deg_to_rad(tail_counterweight_deg) * tail_w

		var slope_tail_pitch = -_current_slope_pitch * slope_tail_balance_ratio * tail_w
		_apply_tail_rotation(_bone_tail_1, _tail_1_rest_q, slope_tail_pitch * 0.5, wave_1 + turn_drag * 0.5)
		_apply_tail_rotation(_bone_tail_2, _tail_2_rest_q, slope_tail_pitch * 0.8, wave_2 + turn_drag * 0.8)
		_apply_tail_rotation(_bone_tail_3, _tail_3_rest_q, slope_tail_pitch * 1.1, wave_3 + turn_drag * 1.1)
		_apply_tail_rotation(_bone_tail_4, _tail_4_rest_q, slope_tail_pitch * 1.4, wave_4 + turn_drag * 1.4)

func _apply_bone_rotation(bone_idx: int, _rest_q: Quaternion, pitch_rad: float, yaw_rad: float, roll_rad: float = 0.0) -> void:
	if bone_idx < 0: return
	var cur_q = _skeleton.get_bone_pose_rotation(bone_idx)
	var q_pitch = Quaternion(Vector3.RIGHT, pitch_rad)
	var q_yaw = Quaternion(Vector3.FORWARD, yaw_rad)
	var q_roll = Quaternion(Vector3.UP, roll_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, cur_q * (q_pitch * q_roll * q_yaw))

func _apply_tail_rotation(bone_idx: int, _rest_q: Quaternion, pitch_rad: float, yaw_rad: float) -> void:
	if bone_idx < 0: return
	var cur_q = _skeleton.get_bone_pose_rotation(bone_idx)
	var q_pitch = Quaternion(Vector3.RIGHT, pitch_rad)
	var q_yaw = Quaternion(Vector3.FORWARD, yaw_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, cur_q * (q_pitch * q_yaw))

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

func _trigger_terrain_obstacle_turn(col_normal: Vector3, _col_point: Vector3, is_stuck: bool = false) -> void:
	if _terrain_collision_cooldown > 0.0 and not is_stuck: return
	_terrain_collision_cooldown = 1.5

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
	if current_state == State.CHARGE_PREY or current_state == State.FEEDING_CARCASS:
		return 0.0
	var local_pos = _to_habitat_local(global_position)
	var fwd = -global_transform.basis.z
	var hab = _get_habitat_node()
	if hab:
		fwd = hab.global_transform.basis.inverse() * fwd
	var needs_avoid = false
	if (local_pos.x > paddock_bounds_max.x - 2.2 and fwd.x > 0.0) or (local_pos.x < paddock_bounds_min.x + 2.2 and fwd.x < 0.0):
		needs_avoid = true
	if (local_pos.z > paddock_bounds_max.y - 2.2 and fwd.z > 0.0) or (local_pos.z < paddock_bounds_min.y + 2.2 and fwd.z < 0.0):
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
	var lz = randf_range(paddock_bounds_min.y + 2.5, paddock_bounds_max.y - 2.5)
	var hab = _get_habitat_node()
	if hab:
		_current_waypoint = hab.to_global(Vector3(lx, 0.0, lz))
	else:
		_current_waypoint = Vector3(lx, 0.0, lz)
	_current_waypoint.y = global_position.y

func get_brain_state_name() -> String:
	match current_state:
		State.PATROL_TERRITORY: return "PATRULLA TERRITORIAL"
		State.IDLE_STALKING: return "ACECHO ESTÁTICO / OBSERVACIÓN"
		State.SNIFF_TRACKING: return "RASTREO OLFATIVO DE PRESA"
		State.CHARGE_PREY: return "EMBESTIDA HACIA ALIMENTO"
		State.FEEDING_CARCASS: return "DEVORANDO CARNE"
		State.TAIL_WHIP_DISPLAY: return "EXHIBICIÓN DE COLETAZO"
	return "DESCONOCIDO"
