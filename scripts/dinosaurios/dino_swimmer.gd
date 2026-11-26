class_name DinoSwimmer
extends CharacterBody3D

@export var water_manager: WaterManager

# Modo autónomo activado por defecto (100% autónomo)
@export var is_autonomous: bool = true

# Velocidades de nado (adaptadas a depredador de 15 metros en recinto de 100x100)
@export var swim_speed: float = 0.9
@export var sprint_speed: float = 1.8
@export var reverse_speed: float = 1.4
@export var turn_speed: float = 0.95
@export var vertical_speed: float = 0.6
@export var water_drag: float = 3.5

# Límite de flotabilidad: evita que suba más de la mitad del cuerpo
@export var surface_submerged_offset: float = 1.25

# Color base de fallback (solo si la malla no trae materiales pintados)
@export var dark_gray_color: Color = Color(0.18, 0.20, 0.23, 1.0)

# Ángulos máximos de flexión procedural (en grados) para viraje lateral (Yaw)
@export var head_yaw_max: float = 18.0
@export var neck_yaw_max: float = 13.0
@export var chest_yaw_max: float = 8.0
@export var spine_yaw_max: float = 6.0

# Ángulos máximos de flexión procedural para sumergirse / subir (Pitch)
@export var head_pitch_max: float = 16.0
@export var neck_pitch_max: float = 11.0
@export var chest_pitch_max: float = 7.0
@export var spine_pitch_max: float = 5.0
@export var body_pitch_max: float = 12.0
@export var ascend_pitch_ratio: float = 0.5 # Reduce la curvatura del cuello al 50% al subir

# Ondulación procedural de la cola en reposo y nado
@export var idle_tail_wave_speed: float = 1.8
@export var idle_tail_wave_deg: float = 7.5

# Parámetros del Cerebro Sensorial Autónomo (Opción A: Depredador)
@export var smell_radius: float = 60.0       # Radio 360° de olfato
@export var vision_angle_deg: float = 130.0  # Cono de visión frontal (apertura total)
@export var eat_distance: float = 4.5        # Distancia para morder comida

# Límites del estanque para la navegación autónoma (Paddock 100x100 con foso de 87x87m y 13m de profundidad)
@export var pool_bounds_min: Vector3 = Vector3(-35.0, 5.0, -35.0)
@export var pool_bounds_max: Vector3 = Vector3(35.0, 13.5, 35.0)

# Estados del Cerebro
enum State {
	PATROL_WANDER,    # Nado majestuoso entre waypoints en el estanque
	IDLE_OBSERVE,     # Flotando en reposo, coleo sutil y mirando el entorno
	ALERT_SMELL,      # Siente olor a comida a su espalda/costado: gira la cabeza hacia la fuente
	PURSUE_FOOD,      # Presa visualizada: acelera, nada hacia ella y apunta con la cabeza
	EAT_BITE,         # Mordida y deglución con salpicaduras y masticado
	CURIOUS_VISITOR   # Pasa junto al cristal frontal y observa a los visitantes
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
const CULL_LENGTH_HALF: float = 9.0
const CULL_HEIGHT: float = 5.0
const CULL_WIDTH_HALF: float = 3.5

var current_state: State = State.PATROL_WANDER:
	set(value):
		if current_state != value:
			current_state = value
			if not has_meta("_managed_by_park_optimizer"):
				print("[Cerebro Mosasaurio] Estado: ", get_brain_state_name())
var current_food_target: Node3D = null

var _anim_player: AnimationPlayer
var _skeleton: Skeleton3D
var _was_submerged: bool = false
var _time_accum: float = 0.0
var _state_timer: float = 0.0
var _current_waypoint: Vector3 = Vector3.ZERO
var _observe_look_angle: float = 0.0

# Factores de interpolación elástica
var _turn_factor: float = 0.0   # De -1.0 (derecha) a +1.0 (izquierda)
var _pitch_factor: float = 0.0  # De -1.0 (sumergirse/bajar) a +1.0 (subir a superficie)

# Índices de huesos en Skeleton3D
var _bone_head: int = -1
var _bone_neck: int = -1
var _bone_chest: int = -1
var _bone_spine: int = -1
var _bone_jaw: int = -1
var _jaw_ctrl: DinoJawController = DinoJawController.new()
var _spectator_ctrl: DinoSpectatorController = DinoSpectatorController.new()
var _bone_tail_1: int = -1
var _bone_tail_2: int = -1
var _bone_tail_3: int = -1
var _bone_tail_4: int = -1
var _bone_flipper_front_l: int = -1
var _bone_flipper_front_r: int = -1
var _bone_flipper_hind_l: int = -1
var _bone_flipper_hind_r: int = -1

# Posturas de reposo (Rest Quaternions) capturadas del modelo
var _head_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_rest_q: Quaternion = Quaternion.IDENTITY
var _chest_rest_q: Quaternion = Quaternion.IDENTITY
var _spine_rest_q: Quaternion = Quaternion.IDENTITY
var _jaw_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_1_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_2_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_3_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_4_rest_q: Quaternion = Quaternion.IDENTITY
var _flipper_front_l_rest_q: Quaternion = Quaternion.IDENTITY
var _flipper_front_r_rest_q: Quaternion = Quaternion.IDENTITY
var _flipper_hind_l_rest_q: Quaternion = Quaternion.IDENTITY
var _flipper_hind_r_rest_q: Quaternion = Quaternion.IDENTITY

func _ready() -> void:
	add_to_group("dino_aquatic")
	add_to_group("mosasaurus")
	add_to_group("dinosaurios")
	if not water_manager:
		water_manager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	
	_apply_dino_material()
	_find_animation_player()
	_find_skeleton()
	_spectator_ctrl.setup("mosasaurus", self)
	_setup_visibility_culling()
	_pick_new_patrol_waypoint()
	_play_anim("Mosa_Nadar", 0.0)
	print("[Cerebro Mosasaurio] Inicializado con animación procedural completa | Estado inicial: ", get_brain_state_name())

func _apply_dino_material() -> void:
	# Respetar materiales originales de Blender (Skin, Tongue, Tooths, Eye, etc.)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.name == "FoamRing":
			continue
		if mesh.mesh and mesh.mesh.get_surface_count() > 0:
			var has_mat: bool = false
			for s in range(mesh.mesh.get_surface_count()):
				if mesh.get_active_material(s) != null or mesh.mesh.surface_get_material(s) != null:
					has_mat = true
					break
			if has_mat:
				continue # Conservar materiales originales de textura y ojos

		# Material fallback en caso de no tener
		var mat = StandardMaterial3D.new()
		mat.albedo_color = dark_gray_color
		mat.roughness = 0.45
		mat.metallic = 0.05
		mat.metallic_specular = 0.5
		mesh.material_override = mat

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
		_bone_neck = _skeleton.find_bone("Neck")
		_bone_chest = _skeleton.find_bone("Chest")
		_bone_spine = _skeleton.find_bone("Spine")
		_bone_jaw = _skeleton.find_bone("Jaw")
		_bone_tail_1 = _skeleton.find_bone("Tail.001")
		_bone_tail_2 = _skeleton.find_bone("Tail.002")
		_bone_tail_3 = _skeleton.find_bone("Tail.003")
		_bone_tail_4 = _skeleton.find_bone("Tail.004")
		_bone_flipper_front_l = _skeleton.find_bone("Flipper_Front_1.L")
		_bone_flipper_front_r = _skeleton.find_bone("Flipper_Front_1.R")
		_bone_flipper_hind_l = _skeleton.find_bone("Flipper_Hind_1.L")
		_bone_flipper_hind_r = _skeleton.find_bone("Flipper_Hind_1.R")

		if _bone_head >= 0:
			_head_rest_q = _skeleton.get_bone_rest(_bone_head).basis.get_rotation_quaternion()
		if _bone_neck >= 0:
			_neck_rest_q = _skeleton.get_bone_rest(_bone_neck).basis.get_rotation_quaternion()
		if _bone_chest >= 0:
			_chest_rest_q = _skeleton.get_bone_rest(_bone_chest).basis.get_rotation_quaternion()
		if _bone_spine >= 0:
			_spine_rest_q = _skeleton.get_bone_rest(_bone_spine).basis.get_rotation_quaternion()
		if _bone_jaw >= 0:
			_jaw_rest_q = _skeleton.get_bone_rest(_bone_jaw).basis.get_rotation_quaternion()
		_jaw_ctrl.setup(_skeleton, "mosasaurus", _anim_player)
		if _bone_tail_1 >= 0:
			_tail_1_rest_q = _skeleton.get_bone_rest(_bone_tail_1).basis.get_rotation_quaternion()
		if _bone_tail_2 >= 0:
			_tail_2_rest_q = _skeleton.get_bone_rest(_bone_tail_2).basis.get_rotation_quaternion()
		if _bone_tail_3 >= 0:
			_tail_3_rest_q = _skeleton.get_bone_rest(_bone_tail_3).basis.get_rotation_quaternion()
		if _bone_tail_4 >= 0:
			_tail_4_rest_q = _skeleton.get_bone_rest(_bone_tail_4).basis.get_rotation_quaternion()
		if _bone_flipper_front_l >= 0:
			_flipper_front_l_rest_q = _skeleton.get_bone_rest(_bone_flipper_front_l).basis.get_rotation_quaternion()
		if _bone_flipper_front_r >= 0:
			_flipper_front_r_rest_q = _skeleton.get_bone_rest(_bone_flipper_front_r).basis.get_rotation_quaternion()
		if _bone_flipper_hind_l >= 0:
			_flipper_hind_l_rest_q = _skeleton.get_bone_rest(_bone_flipper_hind_l).basis.get_rotation_quaternion()
		if _bone_flipper_hind_r >= 0:
			_flipper_hind_r_rest_q = _skeleton.get_bone_rest(_bone_flipper_hind_r).basis.get_rotation_quaternion()

func _play_anim(anim_name: String, blend: float = 0.3, custom_speed: float = -1.0) -> void:
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
		elif "Nadar" in target_anim:
			_anim_player.speed_scale = 0.65
		elif "Comer" in target_anim:
			_anim_player.speed_scale = 1.0
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
	if not water_manager:
		var hab = _get_habitat_node()
		if hab:
			water_manager = hab.get_node_or_null("WaterSurface") as WaterManager
		if not water_manager:
			water_manager = get_tree().get_first_node_in_group("water_manager") as WaterManager
		if not water_manager:
			return

	var water_y: float = water_manager.get_water_height_at(Vector2(global_position.x, global_position.z))
	var max_allowed_y: float = water_y - surface_submerged_offset
	var depth: float = water_y - global_position.y
	var is_submerged: bool = depth > 0.0

	# 1. Salpicaduras al romper superficie
	if is_submerged != _was_submerged:
		if abs(velocity.y) > 0.8:
			water_manager.register_splash(global_position, 0.9)
		_was_submerged = is_submerged

	# 2. Actualización de Temporizadores del Cerebro
	_state_timer = max(0.0, _state_timer - delta)

	# 3. Detección Sensorial de Comida (Olfato 360° + Visión Frontal)
	_sensory_scan_food()

	# 4. Decisión de Movimiento 100% Autónomo
	var commands = _update_brain_state(delta, max_allowed_y)
	var desired_turn: float = commands.turn
	var desired_forward: float = commands.forward
	var desired_vertical: float = commands.vertical
	var current_move_speed: float = commands.speed

	# 5. Rotación del cuerpo (Yaw)
	if desired_turn != 0.0:
		rotate_y(desired_turn * turn_speed * delta)

	# 6. Desplazamiento Horizontal (Adelante / Atrás)
	var forward_dir = -global_transform.basis.z
	var target_h_vel = Vector3.ZERO

	if desired_forward > 0.0:
		target_h_vel = forward_dir * (desired_forward * current_move_speed)
	elif desired_forward < 0.0:
		target_h_vel = forward_dir * (desired_forward * reverse_speed)

	velocity.x = move_toward(velocity.x, target_h_vel.x, water_drag * delta)
	velocity.z = move_toward(velocity.z, target_h_vel.z, water_drag * delta)

	# 7. Desplazamiento Vertical con Flotabilidad Neutra
	if desired_vertical > 0.0:
		if global_position.y < max_allowed_y:
			velocity.y = move_toward(velocity.y, vertical_speed * desired_vertical, 4.0 * delta)
		else:
			velocity.y = move_toward(velocity.y, 0.0, 6.0 * delta)
	elif desired_vertical < 0.0:
		velocity.y = move_toward(velocity.y, vertical_speed * desired_vertical, 4.0 * delta)
	else:
		if global_position.y > max_allowed_y:
			velocity.y = move_toward(velocity.y, -0.8, 3.0 * delta)
		else:
			velocity.y = move_toward(velocity.y, 0.0, 3.0 * delta)

	move_and_slide()

	# Cota superior estricta: nunca superar la mitad del cuerpo fuera del agua
	if global_position.y > max_allowed_y:
		global_position.y = max_allowed_y
		if velocity.y > 0.0:
			velocity.y = 0.0

	# 8. Reproducción de Clips de Animación Base
	_handle_autonomous_animation_clips()

func _sensory_scan_food() -> void:
	var closest_food := DinoFood.find_nearest_for(self, DinoFood.DIET_MEAT, smell_radius, _get_habitat_node(), pool_bounds_min, pool_bounds_max)
	current_food_target = closest_food

	# Transiciones de estado sensorial
	if is_instance_valid(current_food_target):
		var to_food = (current_food_target.global_position - global_position).normalized()
		var forward = -global_transform.basis.z
		var angle_to_food = rad_to_deg(forward.angle_to(to_food))

		if current_state != State.EAT_BITE:
			if angle_to_food <= (vision_angle_deg * 0.5):
				# A la vista: Cazar comida
				if current_state != State.PURSUE_FOOD:
					current_state = State.PURSUE_FOOD
			else:
				# Fuera de la vista pero huele comida: Alerta de olfato
				if current_state != State.ALERT_SMELL and current_state != State.PURSUE_FOOD:
					current_state = State.ALERT_SMELL
					_state_timer = 3.5
	else:
		# Si la comida desapareció o fue devorada
		if current_state == State.PURSUE_FOOD or current_state == State.ALERT_SMELL:
			current_state = State.IDLE_OBSERVE
			_state_timer = randf_range(3.0, 5.0)

func _update_brain_state(delta: float, max_allowed_y: float) -> Dictionary:
	var turn: float = 0.0
	var forward: float = 0.0
	var vertical: float = 0.0
	var speed: float = swim_speed

	var busy_with_food := is_instance_valid(current_food_target) or (current_state in [State.ALERT_SMELL, State.PURSUE_FOOD, State.EAT_BITE])
	_spectator_ctrl.update(delta, self, _get_habitat_node(), pool_bounds_min, pool_bounds_max, busy_with_food, max_allowed_y)

	if _spectator_ctrl.is_controlling():
		_current_waypoint = _spectator_ctrl.get_move_target(self)
		var steer = _steer_towards(_current_waypoint, max_allowed_y)
		if _spectator_ctrl.get_phase() == DinoSpectatorController.Phase.SHOWCASING:
			current_state = State.CURIOUS_VISITOR
			speed = swim_speed * _spectator_ctrl.get_speed_multiplier()
			forward = 0.9
			turn = steer.turn * 0.9
			vertical = steer.vertical
			_observe_look_angle = _spectator_ctrl.get_head_look_factor(self)
		else:
			current_state = State.PATROL_WANDER
			speed = swim_speed * _spectator_ctrl.get_speed_multiplier()
			forward = 1.0
			turn = steer.turn
			vertical = steer.vertical
		var spec_wall = _compute_wall_avoidance(max_allowed_y)
		if abs(spec_wall) > 0.05:
			turn = spec_wall
		return {
			"turn": clamp(turn, -1.0, 1.0),
			"forward": clamp(forward, -1.0, 1.0),
			"vertical": clamp(vertical, -1.0, 1.0),
			"speed": speed
		}

	match current_state:
		State.PATROL_WANDER:
			speed = swim_speed
			var dist_to_target = global_position.distance_to(_current_waypoint)
			if dist_to_target < 2.5:
				if global_position.z > 4.0 and randf() < 0.45:
					current_state = State.CURIOUS_VISITOR
					_state_timer = 5.5
				elif randf() < 0.4:
					current_state = State.IDLE_OBSERVE
					_state_timer = randf_range(3.5, 7.0)
				else:
					_pick_new_patrol_waypoint()
			else:
				var steer = _steer_towards(_current_waypoint, max_allowed_y)
				turn = steer.turn
				vertical = steer.vertical
				forward = 1.0

		State.IDLE_OBSERVE:
			forward = 0.0
			vertical = 0.0
			turn = 0.0
			_observe_look_angle = sin(_time_accum * 0.8) * 0.75
			if _state_timer <= 0.0:
				current_state = State.PATROL_WANDER
				_pick_new_patrol_waypoint()

		State.ALERT_SMELL:
			if is_instance_valid(current_food_target):
				var steer = _steer_towards(current_food_target.global_position, max_allowed_y)
				turn = steer.turn * 1.3
				forward = 0.25
				vertical = steer.vertical * 0.5
				speed = swim_speed * 0.6
			else:
				current_state = State.PATROL_WANDER
				_pick_new_patrol_waypoint()

		State.PURSUE_FOOD:
			if is_instance_valid(current_food_target):
				speed = sprint_speed
				var food_pos = current_food_target.global_position
				var dist = global_position.distance_to(food_pos)

				if dist <= eat_distance or (dist <= 3.8 and velocity.length() < 0.3):
					current_state = State.EAT_BITE
					_state_timer = 2.4
					if water_manager:
						water_manager.register_splash(global_position, 1.2)
					if current_food_target.has_method("consume"):
						current_food_target.consume()
					else:
						current_food_target.queue_free()
					current_food_target = null
				else:
					var steer = _steer_towards(food_pos, max_allowed_y)
					turn = steer.turn * 1.5
					vertical = steer.vertical * 1.3
					forward = 1.0
			else:
				current_state = State.IDLE_OBSERVE
				_state_timer = 3.0

		State.EAT_BITE:
			forward = 0.05
			vertical = 0.0
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_OBSERVE
				_state_timer = randf_range(3.0, 5.0)

		State.CURIOUS_VISITOR:
			speed = swim_speed * 0.85
			forward = 0.9
			# Deslizarse a lo largo del gran ventanal de observación subacuático (+X = 49.6)
			var glass_local = Vector3(34.0, 9.5, sign(velocity.z + 0.1) * 26.0)
			var glass_target = _to_habitat_global(glass_local)
			var steer = _steer_towards(glass_target, max_allowed_y)
			turn = steer.turn * 0.85
			vertical = steer.vertical
			_observe_look_angle = 0.85
			if _state_timer <= 0.0:
				current_state = State.PATROL_WANDER
				_pick_new_patrol_waypoint()

	var wall_steer = _compute_wall_avoidance(max_allowed_y)
	if abs(wall_steer) > 0.05:
		turn = wall_steer

	return {
		"turn": clamp(turn, -1.0, 1.0),
		"forward": clamp(forward, -1.0, 1.0),
		"vertical": clamp(vertical, -1.0, 1.0),
		"speed": speed
	}

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

func _steer_towards(target_pos: Vector3, max_allowed_y: float) -> Dictionary:
	var to_target = target_pos - global_position
	var local_dir = global_transform.basis.inverse() * to_target.normalized()
	var turn = -local_dir.x * 2.2

	var clamped_target_y = min(target_pos.y, max_allowed_y)
	var dy = clamped_target_y - global_position.y
	
	# Zona muerta vertical: si el desnivel es suave (< 1.2m), nivelar cuerpo horizontalmente
	if abs(dy) < 1.2:
		dy = 0.0

	# Al nadar alto (cerca de la superficie / cota máxima), mantener orientación 100% horizontal
	if global_position.y >= (max_allowed_y - 1.5) and target_pos.y >= (max_allowed_y - 2.0):
		dy = 0.0

	var vertical = clamp(dy * 1.0, -1.0, 1.0)
	return { "turn": turn, "vertical": vertical }

func _compute_wall_avoidance(max_allowed_y: float) -> float:
	if current_state == State.PURSUE_FOOD or current_state == State.EAT_BITE:
		return 0.0

	var fwd = -global_transform.basis.z
	var hab = _get_habitat_node()
	if hab:
		fwd = hab.global_transform.basis.inverse() * fwd
	var local_pos = _to_habitat_local(global_position)
	var needs_avoid = false

	if local_pos.x > (pool_bounds_max.x - 4.5) and fwd.x > 0.0:
		needs_avoid = true
	elif local_pos.x < (pool_bounds_min.x + 4.5) and fwd.x < 0.0:
		needs_avoid = true

	if local_pos.z > (pool_bounds_max.z - 4.5) and fwd.z > 0.0:
		needs_avoid = true
	elif local_pos.z < (pool_bounds_min.z + 4.5) and fwd.z < 0.0:
		needs_avoid = true

	if needs_avoid:
		var center = _get_habitat_center()
		center.y = global_position.y
		var steer = _steer_towards(center, max_allowed_y)
		return steer.turn

	return 0.0

func _pick_new_patrol_waypoint() -> void:
	var wx = randf_range(pool_bounds_min.x + 3.0, pool_bounds_max.x - 3.0)
	var wy = randf_range(pool_bounds_min.y + 1.0, pool_bounds_max.y - 0.5)
	var wz = randf_range(pool_bounds_min.z + 3.0, pool_bounds_max.z - 3.0)
	_current_waypoint = _to_habitat_global(Vector3(wx, wy, wz))

func _handle_autonomous_animation_clips() -> void:
	match current_state:
		State.PATROL_WANDER:
			_play_anim("Mosa_Nadar", 0.35, 0.65)
		State.IDLE_OBSERVE:
			_play_anim("Mosa_Idle", 0.4, 0.8)
		State.ALERT_SMELL:
			_play_anim("Mosa_Buscar_Comida", 0.3, 0.85)
		State.PURSUE_FOOD:
			_play_anim("Mosa_Nadar", 0.25, 1.15)
		State.EAT_BITE:
			_play_anim("Mosa_Comer", 0.15, 1.0)
		State.CURIOUS_VISITOR:
			_play_anim("Mosa_Nadar", 0.4, 0.5)

func _process(delta: float) -> void:
	if not is_in_view:
		return
	_time_accum += delta

	# Cota superior real del agua para evitar inclinaciones erróneas
	var water_y: float = _to_habitat_global(Vector3(0.0, 15.0, 0.0)).y
	if water_manager:
		water_y = water_manager.get_water_height_at(Vector2(global_position.x, global_position.z))
	var max_allowed_y: float = water_y - surface_submerged_offset

	# 9. Cálculo de Factores Suavizados para Animación Procedural
	var target_turn: float = 0.0
	var target_pitch: float = 0.0

	match current_state:
		State.PATROL_WANDER, State.PURSUE_FOOD, State.ALERT_SMELL:
			var target_pos = _current_waypoint
			if is_instance_valid(current_food_target):
				target_pos = current_food_target.global_position
			var steer = _steer_towards(target_pos, max_allowed_y)
			target_turn = clamp(steer.turn, -1.0, 1.0)
			target_pitch = clamp(steer.vertical, -1.0, 1.0)

			# Al nadar alto (cerca de la superficie), mantener el cuerpo perfectamente horizontal
			if global_position.y >= (max_allowed_y - 1.2):
				target_pitch = 0.0
		State.IDLE_OBSERVE:
			target_turn = _observe_look_angle
			target_pitch = 0.0
		State.CURIOUS_VISITOR:
			target_turn = _observe_look_angle
			target_pitch = 0.0
		State.EAT_BITE:
			target_turn = 0.0
			target_pitch = 0.0

	if _spectator_ctrl.wants_head_look() and current_state in [State.PATROL_WANDER, State.CURIOUS_VISITOR, State.IDLE_OBSERVE]:
		target_turn = _spectator_ctrl.get_head_look_factor(self)

	# Interpolación inercial elástica
	_turn_factor = move_toward(_turn_factor, target_turn, delta * 3.2)
	_pitch_factor = move_toward(_pitch_factor, target_pitch, delta * 2.8)

	# Inclinación orgánica del cuerpo completo (Banking lateral en Z, Cabeceo en X)
	if visual_model:
		var current_body_pitch_max = body_pitch_max * (ascend_pitch_ratio if _pitch_factor > 0.0 else 1.0)
		var target_body_pitch = -_pitch_factor * deg_to_rad(current_body_pitch_max)
		var target_body_roll = _turn_factor * deg_to_rad(6.5)
		visual_model.rotation.x = move_toward(visual_model.rotation.x, target_body_pitch, delta * 2.5)
		visual_model.rotation.z = move_toward(visual_model.rotation.z, target_body_roll, delta * 2.5)

	if not _skeleton:
		return

	# 10. Capa Procedural Biomecánica sobre los Huesos
	# A) Flexión Lateral (Yaw) y Cabeceo (Pitch) en Cabeza, Cuello, Pecho y Columna
	var yaw_head: float = _turn_factor * deg_to_rad(head_yaw_max)
	var yaw_neck: float = _turn_factor * deg_to_rad(neck_yaw_max)
	var yaw_chest: float = _turn_factor * deg_to_rad(chest_yaw_max)
	var yaw_spine: float = _turn_factor * deg_to_rad(spine_yaw_max)

	var up_mult: float = ascend_pitch_ratio if _pitch_factor > 0.0 else 1.0
	var pitch_head: float = -_pitch_factor * deg_to_rad(head_pitch_max * up_mult)
	var pitch_neck: float = -_pitch_factor * deg_to_rad(neck_pitch_max * up_mult)
	var pitch_chest: float = -_pitch_factor * deg_to_rad(chest_pitch_max * up_mult)
	var pitch_spine: float = -_pitch_factor * deg_to_rad(spine_pitch_max * up_mult)

	_apply_bone_rotation(_bone_head, _head_rest_q, pitch_head, yaw_head)
	_apply_bone_rotation(_bone_neck, _neck_rest_q, pitch_neck, yaw_neck)
	_apply_bone_rotation(_bone_chest, _chest_rest_q, pitch_chest, yaw_chest)
	_apply_bone_rotation(_bone_spine, _spine_rest_q, pitch_spine, yaw_spine)

	# B) Onda Caudal Continua y Arrastre Inercial en los 4 Segmentos de la Cola
	var is_idle_mode: bool = (_anim_player and "Idle" in _anim_player.current_animation) or current_state == State.IDLE_OBSERVE
	var wave_mult: float = 1.0 if is_idle_mode else 0.35 # En nado rápido el clip base ya bate la cola, aquí añadimos inercia
	var wave_speed: float = idle_tail_wave_speed if is_idle_mode else 2.8

	var wave_1: float = sin(_time_accum * wave_speed) * deg_to_rad(idle_tail_wave_deg * wave_mult)
	var wave_2: float = sin(_time_accum * wave_speed - 0.7) * deg_to_rad(idle_tail_wave_deg * 1.35 * wave_mult)
	var wave_3: float = sin(_time_accum * wave_speed - 1.4) * deg_to_rad(idle_tail_wave_deg * 1.7 * wave_mult)
	var wave_4: float = sin(_time_accum * wave_speed - 2.1) * deg_to_rad(idle_tail_wave_deg * 2.1 * wave_mult)

	# Arrastre inercial (Turn Drag): cuando gira a la izquierda (+_turn_factor), la cola se flexiona a la derecha (-yaw)
	var turn_drag_1: float = -_turn_factor * deg_to_rad(5.5)
	var turn_drag_2: float = -_turn_factor * deg_to_rad(8.5)
	var turn_drag_3: float = -_turn_factor * deg_to_rad(11.5)
	var turn_drag_4: float = -_turn_factor * deg_to_rad(14.0)

	_apply_tail_rotation(_bone_tail_1, _tail_1_rest_q, wave_1 + turn_drag_1)
	_apply_tail_rotation(_bone_tail_2, _tail_2_rest_q, wave_2 + turn_drag_2)
	_apply_tail_rotation(_bone_tail_3, _tail_3_rest_q, wave_3 + turn_drag_3)
	_apply_tail_rotation(_bone_tail_4, _tail_4_rest_q, wave_4 + turn_drag_4)

	# C) Timoneo Hidrodinámico de Aletas Pectorales (Roll & Dive Trim)
	if _bone_flipper_front_l >= 0 and _bone_flipper_front_r >= 0:
		var flipper_bank = _turn_factor * deg_to_rad(12.0)
		var flipper_pitch = -_pitch_factor * deg_to_rad(8.0)
		var q_fl = Quaternion(Vector3.FORWARD, flipper_bank) * Quaternion(Vector3.RIGHT, flipper_pitch)
		var q_fr = Quaternion(Vector3.FORWARD, flipper_bank) * Quaternion(Vector3.RIGHT, flipper_pitch)
		_skeleton.set_bone_pose_rotation(_bone_flipper_front_l, _flipper_front_l_rest_q * q_fl)
		_skeleton.set_bone_pose_rotation(_bone_flipper_front_r, _flipper_front_r_rest_q * q_fr)

	# D) Mecánica Procedural de la Mandíbula (Cerrada en nado/reposo; abre al morder, saltar o de vez en cuando)
	var jaw_mode: int = DinoJawController.Mode.EAT if current_state == State.EAT_BITE else DinoJawController.Mode.CLOSED
	_jaw_ctrl.update(delta, jaw_mode, _anim_player)
	_jaw_ctrl.apply()

func _apply_bone_rotation(bone_idx: int, rest_q: Quaternion, pitch_rad: float, yaw_rad: float) -> void:
	if bone_idx < 0:
		return
	var q_pitch = Quaternion(Vector3.RIGHT, pitch_rad)
	var q_yaw = Quaternion(Vector3.FORWARD, yaw_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, rest_q * (q_pitch * q_yaw))

func _apply_tail_rotation(bone_idx: int, rest_q: Quaternion, yaw_rad: float) -> void:
	if bone_idx < 0:
		return
	var q_yaw = Quaternion(Vector3.FORWARD, yaw_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, rest_q * q_yaw)

func get_brain_state_name() -> String:
	match current_state:
		State.PATROL_WANDER:
			return "PATRULLANDO (Nado majestuoso)"
		State.IDLE_OBSERVE:
			return "REPOSO / OBSERVANDO (Flotando con coleo)"
		State.ALERT_SMELL:
			return "¡ALERTA DE OLFATO! (Rastreando comida)"
		State.PURSUE_FOOD:
			return "¡CAZANDO COMIDA! (Aceleración hacia presa)"
		State.EAT_BITE:
			return "¡DEVORANDO COMIDA! (Masticando presa)"
		State.CURIOUS_VISITOR:
			return "OBSERVANDO VISITANTES (Frente al cristal)"
	return "DESCONOCIDO"

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
			Vector3(-CULL_WIDTH_HALF, -2.5, -CULL_LENGTH_HALF),
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
