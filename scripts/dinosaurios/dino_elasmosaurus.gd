class_name DinoElasmosaurus
extends CharacterBody3D

# ==============================================================================
# ELASMOSAURUS — CEREBRO AUTÓNOMO Y SISTEMA PROCEDURAL PLESIOSAÚRIDO
# ==============================================================================
# Reptil marino con cuello extraordinariamente largo (5 vértebras articuladas).
# - Navegación 3D en estanque/laguna con nado hidrodinámico.
# - Cuello serpentino procedural que arquea y ondea anticipando giros.
# - Estado de respiración en superficie (`Elasmo_Respirar`) donde alza la cabeza sobre el agua.
# - Aletas sincronizadas con propulsión por aleteo submarino.
# - Evasión predictiva 3D de rocas, fondos y cristales del acuario.
# ==============================================================================

@export var is_autonomous: bool = true

@export_group("Cinemática y Velocidades Acuáticas")
@export var swim_anim_speed: float = 1.10
@export var sprint_anim_speed: float = 1.70
@export var swim_speed: float = 1.60
@export var sprint_speed: float = 2.75
@export var turn_speed: float = 1.05
@export var vertical_speed: float = 0.55
@export var water_drag: float = 3.2

@export_group("Color y Piel Acuática")
@export var skin_color: Color = Color(0.22, 0.45, 0.55, 1.0)
@export var belly_color: Color = Color(0.75, 0.82, 0.85, 1.0)

@export_group("Ondulación Procedural de Cuello Serpentino (5 Vértebras)")
@export var head_yaw_max: float = 25.0
@export var head_pitch_max: float = 20.0
@export var neck_yaw_max: float = 18.0
@export var neck_pitch_max: float = 15.0

@export_group("Oscilación de Aletas y Cola")
@export var tail_sway_speed: float = 1.30
@export var tail_sway_deg: float = 6.0
@export var flipper_roll_deg: float = 14.0

@export_group("Cerebro Sensorial Autónomo")
@export var smell_radius: float = 35.0
@export var vision_angle_deg: float = 135.0
@export var eat_distance: float = 3.5

@export_group("Límites del Estanque / Acuario")
@export var pool_bounds_min: Vector3 = Vector3(-23.5, 3.2, -23.5)
@export var pool_bounds_max: Vector3 = Vector3(23.5, 10.5, 23.5)
@export var surface_y: float = 11.2

enum State {
	PATROL_SWIM,
	IDLE_FLOAT,
	ALERT_SCENT,
	PURSUE_FISH,
	EAT_FISH,
	SURFACE_BREATHE
}

@onready var visual_model: Node3D = get_node_or_null("VisualModel")

var current_state: State = State.PATROL_SWIM:
	set(value):
		if current_state != value:
			current_state = value
			if not has_meta("_managed_by_park_optimizer"):
				print("[Cerebro Elasmosaurus] Estado: ", get_brain_state_name())

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

var _terrain_collision_cooldown: float = 0.0
var _obstacle_detour_waypoint: Vector3 = Vector3.ZERO
var _detour_timer: float = 0.0

var _bone_head: int = -1
var _bone_neck_1: int = -1
var _bone_neck_2: int = -1
var _bone_neck_3: int = -1
var _bone_neck_4: int = -1
var _bone_neck_5: int = -1
var _bone_chest: int = -1
var _bone_spine: int = -1
var _bone_tail_1: int = -1
var _bone_tail_2: int = -1
var _bone_tail_3: int = -1

var _head_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_1_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_2_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_3_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_4_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_5_rest_q: Quaternion = Quaternion.IDENTITY
var _chest_rest_q: Quaternion = Quaternion.IDENTITY
var _spine_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_1_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_2_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_3_rest_q: Quaternion = Quaternion.IDENTITY

func _ready() -> void:
	add_to_group("dino_swimmers")
	add_to_group("elasmosaurus")
	add_to_group("dinosaurios")
	_time_accum = randf_range(0.0, 10.0)
	_apply_dino_material()
	_find_animation_player()
	_find_skeleton()
	_spectator_ctrl.setup("elasmosaurus", self)
	_pick_new_swim_waypoint()

	if randf() < 0.4:
		current_state = State.IDLE_FLOAT
		_state_timer = randf_range(3.0, 6.0)
		_play_anim("Elasmo_Idle", 0.0)
	else:
		_play_anim("Elasmo_Nadar", 0.0)

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
		mat.roughness = 0.45
		mesh.material_override = mat

func _find_animation_player() -> void:
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not _anim_player and visual_model:
		_anim_player = visual_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player:
		_anim_player.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		for aname in _anim_player.get_animation_list():
			if "Nadar" in aname or "Idle" in aname:
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
		_bone_neck_4 = _skeleton.find_bone("Neck.004")
		_bone_neck_5 = _skeleton.find_bone("Neck.005")
		_bone_chest = _skeleton.find_bone("Chest")
		_bone_spine = _skeleton.find_bone("Spine")
		_bone_tail_1 = _skeleton.find_bone("Tail.001")
		_bone_tail_2 = _skeleton.find_bone("Tail.002")
		_bone_tail_3 = _skeleton.find_bone("Tail.003")

		if _bone_head >= 0: _head_rest_q = _skeleton.get_bone_rest(_bone_head).basis.get_rotation_quaternion()
		if _bone_neck_1 >= 0: _neck_1_rest_q = _skeleton.get_bone_rest(_bone_neck_1).basis.get_rotation_quaternion()
		if _bone_neck_2 >= 0: _neck_2_rest_q = _skeleton.get_bone_rest(_bone_neck_2).basis.get_rotation_quaternion()
		if _bone_neck_3 >= 0: _neck_3_rest_q = _skeleton.get_bone_rest(_bone_neck_3).basis.get_rotation_quaternion()
		if _bone_neck_4 >= 0: _neck_4_rest_q = _skeleton.get_bone_rest(_bone_neck_4).basis.get_rotation_quaternion()
		if _bone_neck_5 >= 0: _neck_5_rest_q = _skeleton.get_bone_rest(_bone_neck_5).basis.get_rotation_quaternion()
		if _bone_chest >= 0: _chest_rest_q = _skeleton.get_bone_rest(_bone_chest).basis.get_rotation_quaternion()
		if _bone_spine >= 0: _spine_rest_q = _skeleton.get_bone_rest(_bone_spine).basis.get_rotation_quaternion()
		if _bone_tail_1 >= 0: _tail_1_rest_q = _skeleton.get_bone_rest(_bone_tail_1).basis.get_rotation_quaternion()
		if _bone_tail_2 >= 0: _tail_2_rest_q = _skeleton.get_bone_rest(_bone_tail_2).basis.get_rotation_quaternion()
		if _bone_tail_3 >= 0: _tail_3_rest_q = _skeleton.get_bone_rest(_bone_tail_3).basis.get_rotation_quaternion()
		_jaw_ctrl.setup(_skeleton, "elasmosaurus", _anim_player)

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
		elif "Nadar" in target_anim:
			_anim_player.speed_scale = swim_anim_speed
		elif "Respirar" in target_anim:
			_anim_player.speed_scale = 0.9
		elif "Comer" in target_anim:
			_anim_player.speed_scale = 1.0
		else:
			_anim_player.speed_scale = 0.85

		if _anim_player.current_animation != target_anim or not _anim_player.is_playing():
			_anim_player.play(target_anim, blend)

func _physics_process(delta: float) -> void:
	_state_timer = max(0.0, _state_timer - delta)
	_terrain_collision_cooldown = max(0.0, _terrain_collision_cooldown - delta)
	_detour_timer = max(0.0, _detour_timer - delta)

	_sensory_scan_food()

	var commands = _update_brain_state(delta)
	var desired_turn: float = commands.turn
	var current_move_speed: float = commands.speed

	var cur_turn_speed = turn_speed
	if _detour_timer > 0.0: cur_turn_speed = turn_speed * 1.55
	if desired_turn != 0.0:
		rotate_y(desired_turn * cur_turn_speed * delta)

	var forward_dir = -global_transform.basis.z
	var pitch_rad = _pitch_factor * deg_to_rad(20.0)
	var move_dir = (Vector3(forward_dir.x, sin(pitch_rad), forward_dir.z)).normalized()

	var target_vel = move_dir * current_move_speed
	velocity = velocity.move_toward(target_vel, water_drag * delta * 2.0)

	move_and_slide()

	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if not collider or collider == self: continue
		var col_normal = col.get_normal()
		if _terrain_collision_cooldown <= 0.0:
			_trigger_obstacle_turn(col_normal)
			break

	_handle_animation_clips()

func _sensory_scan_food() -> void:
	var closest_food := DinoFood.find_nearest_for(self, DinoFood.DIET_MEAT, smell_radius, _get_habitat_node(), pool_bounds_min, pool_bounds_max)
	current_food_target = closest_food

	if closest_food:
		var to_f = (closest_food.global_position - global_position).normalized()
		var fwd = -global_transform.basis.z
		var angle_to_food = rad_to_deg(fwd.angle_to(to_f))
		if angle_to_food <= vision_angle_deg * 0.5:
			if current_state != State.PURSUE_FISH and current_state != State.EAT_FISH:
				current_state = State.PURSUE_FISH
		else:
			if current_state != State.ALERT_SCENT and current_state != State.PURSUE_FISH:
				current_state = State.ALERT_SCENT
				_state_timer = 3.5

func _update_brain_state(delta: float) -> Dictionary:
	var turn: float = 0.0
	var speed: float = swim_speed

	var busy_with_food := is_instance_valid(current_food_target) or (current_state in [State.ALERT_SCENT, State.PURSUE_FISH, State.EAT_FISH])
	_spectator_ctrl.update(delta, self, _get_habitat_node(), pool_bounds_min, pool_bounds_max, busy_with_food)

	if _spectator_ctrl.is_controlling() and current_state != State.SURFACE_BREATHE:
		if _spectator_ctrl.get_phase() == DinoSpectatorController.Phase.SHOWCASING and _spectator_ctrl.consume_display_trigger():
			current_state = State.SURFACE_BREATHE
			_state_timer = _spectator_ctrl.get_display_duration()
		else:
			current_state = State.PATROL_SWIM
			_current_waypoint = _spectator_ctrl.get_move_target(self)
			var steer_target := _obstacle_detour_waypoint if _detour_timer > 0.0 else _current_waypoint
			turn = _steer_towards(steer_target)
			var dy_spec = _current_waypoint.y - global_position.y
			_pitch_factor = clampf(dy_spec / 3.0, -0.7, 0.7)
			speed = swim_speed * _spectator_ctrl.get_speed_multiplier()
			var spec_pool = _compute_pool_avoidance()
			if abs(spec_pool) > 0.05:
				turn = spec_pool
			return {"turn": clamp(turn, -1.0, 1.0), "speed": speed}

	match current_state:
		State.PATROL_SWIM:
			speed = swim_speed
			var dist = global_position.distance_to(_current_waypoint)
			if dist < 3.0:
				var roll = randf()
				if roll < 0.20:
					current_state = State.SURFACE_BREATHE
					_state_timer = 4.5
				elif roll < 0.60:
					current_state = State.IDLE_FLOAT
					_state_timer = randf_range(3.5, 7.0)
				else:
					_pick_new_swim_waypoint()
			else:
				turn = _steer_towards(_current_waypoint)
				var dy = _current_waypoint.y - global_position.y
				_pitch_factor = clampf(dy / 3.0, -0.7, 0.7)

		State.IDLE_FLOAT:
			speed = swim_speed * 0.25
			turn = sin(_time_accum * 0.5) * 0.3
			_pitch_factor = sin(_time_accum * 0.7) * 0.2
			if _state_timer <= 0.0:
				current_state = State.PATROL_SWIM
				_pick_new_swim_waypoint()

		State.ALERT_SCENT:
			speed = swim_speed * 0.6
			if is_instance_valid(current_food_target):
				turn = _steer_towards(current_food_target.global_position) * 1.3
			if _state_timer <= 0.0:
				current_state = State.PATROL_SWIM
				_pick_new_swim_waypoint()

		State.PURSUE_FISH:
			if is_instance_valid(current_food_target):
				speed = sprint_speed
				var dist = global_position.distance_to(current_food_target.global_position)
				if dist <= eat_distance:
					current_state = State.EAT_FISH
					_state_timer = 3.5
					if current_food_target.has_method("consume"):
						current_food_target.consume()
					else:
						current_food_target.queue_free()
					current_food_target = null
				else:
					var target_pos = current_food_target.global_position
					if _detour_timer > 0.0: target_pos = _obstacle_detour_waypoint
					turn = _steer_towards(target_pos) * 1.5
					var dy = target_pos.y - global_position.y
					_pitch_factor = clampf(dy / 2.5, -0.8, 0.8)
			else:
				current_state = State.IDLE_FLOAT
				_state_timer = 2.5

		State.EAT_FISH:
			speed = swim_speed * 0.3
			turn = 0.0
			_pitch_factor = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_FLOAT
				_state_timer = randf_range(3.0, 5.0)

		State.SURFACE_BREATHE:
			speed = swim_speed * 0.4
			var hab = _get_habitat_node()
			var target_y = (hab.to_global(Vector3(0.0, surface_y - 0.5, 0.0)).y if hab else surface_y - 0.5)
			var dy = target_y - global_position.y
			_pitch_factor = clampf(dy / 2.0, -0.5, 0.8)
			turn = sin(_time_accum * 0.4) * 0.2
			if _state_timer <= 0.0:
				current_state = State.PATROL_SWIM
				_pick_new_swim_waypoint()

	var fence_steer = _compute_pool_avoidance()
	if abs(fence_steer) > 0.05:
		turn = fence_steer

	return {"turn": clamp(turn, -1.0, 1.0), "speed": speed}

func _handle_animation_clips() -> void:
	var real_speed := velocity.length()
	match current_state:
		State.PATROL_SWIM:
			var synced := clampf((real_speed / maxf(swim_speed, 0.1)) * swim_anim_speed, 0.55, sprint_anim_speed * 1.15)
			_play_anim("Elasmo_Nadar", 0.35, synced)
		State.IDLE_FLOAT:
			_play_anim("Elasmo_Idle", 0.4, 0.9)
		State.ALERT_SCENT:
			_play_anim("Elasmo_Buscar_Comida", 0.3, 1.0)
		State.PURSUE_FISH:
			var synced := clampf((real_speed / maxf(swim_speed, 0.1)) * swim_anim_speed, 0.85, sprint_anim_speed * 1.2)
			_play_anim("Elasmo_Nadar", 0.25, synced)
		State.EAT_FISH:
			_play_anim("Elasmo_Comer", 0.2, 1.0)
		State.SURFACE_BREATHE:
			_play_anim("Elasmo_Respirar", 0.3, 0.95)

func _process(delta: float) -> void:
	_time_accum += delta

	var target_turn = 0.0
	if current_state == State.PATROL_SWIM or current_state == State.PURSUE_FISH:
		var to_wp = (_current_waypoint - global_position).normalized()
		var local_wp = global_transform.basis.inverse() * to_wp
		target_turn = clampf(-local_wp.x, -1.0, 1.0)
	else:
		target_turn = sin(_time_accum * 0.7) * 0.4

	if _spectator_ctrl.wants_head_look() and current_state in [State.PATROL_SWIM, State.IDLE_FLOAT]:
		target_turn = _spectator_ctrl.get_head_look_factor(self)

	_turn_factor = lerpf(_turn_factor, target_turn, clampf(delta * 3.5, 0.0, 1.0))

	var jaw_mode: int = DinoJawController.Mode.CLOSED
	if current_state == State.EAT_FISH:
		jaw_mode = DinoJawController.Mode.EAT
	elif current_state == State.SURFACE_BREATHE:
		jaw_mode = DinoJawController.Mode.ROAR
	_jaw_ctrl.update(delta, jaw_mode, _anim_player)

func _apply_procedural_overlay() -> void:
	if not _skeleton:
		return
	_jaw_ctrl.apply()
	var is_action := (current_state in [State.EAT_FISH, State.SURFACE_BREATHE, State.ALERT_SCENT])
	var head_w := 0.0 if current_state == State.SURFACE_BREATHE else (0.15 if is_action else 0.50)
	var tail_w := 0.15 if is_action else 0.45

	# Flexión serpentina aditiva del largo cuello (5 vértebras)
	if head_w > 0.01:
		var yaw_rad = _turn_factor * deg_to_rad(head_yaw_max) * head_w
		var pitch_rad = -_pitch_factor * deg_to_rad(head_pitch_max) * head_w
		_apply_bone_rotation(_bone_head, _head_rest_q, pitch_rad, yaw_rad)
		_apply_bone_rotation(_bone_neck_5, _neck_5_rest_q, pitch_rad * 0.85, yaw_rad * 0.85)
		_apply_bone_rotation(_bone_neck_4, _neck_4_rest_q, pitch_rad * 0.70, yaw_rad * 0.70)
		_apply_bone_rotation(_bone_neck_3, _neck_3_rest_q, pitch_rad * 0.55, yaw_rad * 0.55)
		_apply_bone_rotation(_bone_neck_2, _neck_2_rest_q, pitch_rad * 0.40, yaw_rad * 0.40)
		_apply_bone_rotation(_bone_neck_1, _neck_1_rest_q, pitch_rad * 0.25, yaw_rad * 0.25)

	if tail_w > 0.01:
		var wave_1 = sin(_time_accum * tail_sway_speed) * deg_to_rad(tail_sway_deg * tail_w)
		var wave_2 = sin(_time_accum * tail_sway_speed - 0.7) * deg_to_rad(tail_sway_deg * 1.2 * tail_w)
		var wave_3 = sin(_time_accum * tail_sway_speed - 1.4) * deg_to_rad(tail_sway_deg * 1.4 * tail_w)
		var turn_drag = -_turn_factor * deg_to_rad(8.0) * tail_w

		_apply_tail_rotation(_bone_tail_1, _tail_1_rest_q, 0.0, wave_1 + turn_drag * 0.5)
		_apply_tail_rotation(_bone_tail_2, _tail_2_rest_q, 0.0, wave_2 + turn_drag * 0.8)
		_apply_tail_rotation(_bone_tail_3, _tail_3_rest_q, 0.0, wave_3 + turn_drag * 1.2)

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

func _trigger_obstacle_turn(col_normal: Vector3) -> void:
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

func _compute_pool_avoidance() -> float:
	if current_state == State.PURSUE_FISH or current_state == State.EAT_FISH:
		return 0.0
	var local_pos = _to_habitat_local(global_position)
	var fwd = -global_transform.basis.z
	var hab = _get_habitat_node()
	if hab:
		fwd = hab.global_transform.basis.inverse() * fwd
	var needs_avoid = false
	if (local_pos.x > pool_bounds_max.x - 2.5 and fwd.x > 0.0) or (local_pos.x < pool_bounds_min.x + 2.5 and fwd.x < 0.0):
		needs_avoid = true
	if (local_pos.z > pool_bounds_max.z - 2.5 and fwd.z > 0.0) or (local_pos.z < pool_bounds_min.z + 2.5 and fwd.z < 0.0):
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

func _pick_new_swim_waypoint() -> void:
	var lx = randf_range(pool_bounds_min.x + 2.5, pool_bounds_max.x - 2.5)
	var ly = randf_range(pool_bounds_min.y + 1.0, pool_bounds_max.y - 1.0)
	var lz = randf_range(pool_bounds_min.z + 2.5, pool_bounds_max.z - 2.5)
	var hab = _get_habitat_node()
	if hab:
		_current_waypoint = hab.to_global(Vector3(lx, ly, lz))
	else:
		_current_waypoint = Vector3(lx, ly, lz)

func get_brain_state_name() -> String:
	match current_state:
		State.PATROL_SWIM: return "NADO PATRULLA EN LAGUNA"
		State.IDLE_FLOAT: return "FLOTANDO EN REPOSO"
		State.ALERT_SCENT: return "DETECCIÓN OLFATIVA ACUÁTICA"
		State.PURSUE_FISH: return "PERSECUCIÓN DE PECES"
		State.EAT_FISH: return "DEVORANDO PRESA ACUÁTICA"
		State.SURFACE_BREATHE: return "RESPIRANDO EN SUPERFICIE"
	return "DESCONOCIDO"
