class_name DinoTriceratops
extends CharacterBody3D

# Modo autónomo activado por defecto (100% autónomo)
@export var is_autonomous: bool = true

# Velocidades y cadencia sincronizada (Evita deslizamiento de pisadas / Foot sliding)
@export var walk_anim_speed: float = 1.6        # Cadencia de paso al caminar
@export var run_anim_speed: float = 2.6         # Cadencia de paso al trotar hacia comida
@export var stride_speed_ratio: float = 0.32    # Factor de avance por segundo respecto al paso
@export var turn_speed: float = 1.1
@export var gravity: float = 9.8

var walk_speed: float:
	get: return walk_anim_speed * stride_speed_ratio

var run_speed: float:
	get: return run_anim_speed * stride_speed_ratio

# Color base de escamas y piel de ceratópsido (acorde a referencia diorama estilizada)
@export var skin_color: Color = Color(0.54, 0.44, 0.35, 1.0)
@export var horns_color: Color = Color(0.88, 0.85, 0.76, 1.0)

# Ángulos máximos de flexión procedural (en grados) para viraje lateral (Yaw)
@export var head_yaw_max: float = 18.0
@export var neck_yaw_max: float = 13.0
@export var chest_yaw_max: float = 8.0
@export var spine_yaw_max: float = 6.0

# Ángulos de cabeceo (Pitch)
@export var head_pitch_max: float = 14.0
@export var neck_pitch_max: float = 9.0

# Oscilación procedural de la cola
@export var tail_sway_speed: float = 1.6
@export var tail_sway_deg: float = 6.5

# Adaptación Procedural a Pendientes y Superficies Inclinadas (Montículos / Colinas)
@export_group("Adaptación a Pendientes / Terreno")
@export var slope_adaptation_enabled: bool = true
@export var slope_smooth_speed: float = 6.5          # Velocidad de transición elástica al subir/bajar
@export var max_slope_pitch_deg: float = 38.0        # Límite máximo de cabeceo del cuerpo en pendientes
@export var max_slope_roll_deg: float = 24.0         # Límite máximo de balanceo lateral en pendientes
@export var probe_forward_dist: float = 1.8          # Distancia hacia adelante/atrás de las sondas de suelo
@export var probe_side_dist: float = 0.9             # Distancia lateral de las sondas de suelo
@export var slope_spine_flex_ratio: float = 0.20     # Flexión de columna al subir/bajar
@export var slope_head_compensate_ratio: float = 0.45# Compensación de cabeza para mantener mirada al frente
@export var slope_neck_compensate_ratio: float = 0.35# Compensación de cuello
@export var slope_tail_balance_ratio: float = 0.40   # Contrapeso vertical de la cola

# Parámetros del Cerebro Sensorial Autónomo (Opción A: Herbívoro Territorial)
@export var smell_radius: float = 26.0       # Radio 360° de olfato
@export var vision_angle_deg: float = 130.0  # Cono de visión frontal
@export var eat_distance: float = 3.2        # Distancia para comer (permite alcanzar comida en vallas)

# Límites del recinto terrestre para patrullaje (Enclosure 50x50 con valla interna de 35x35m)
@export var paddock_bounds_min: Vector2 = Vector2(-15.5, -15.5)
@export var paddock_bounds_max: Vector2 = Vector2(15.5, 15.5)

# Estados del Cerebro
enum State {
	PATROL_WANDER,       # Caminata y pastoreo majestuoso por el recinto
	IDLE_OBSERVE,        # Pausa en reposo, respiración pesada y observación
	ALERT_SMELL,         # Huele comida en 360°: olfatea y gira hacia la fuente
	PURSUE_FOOD,         # Comida visualizada: camina directo hacia ella
	EAT_BITE,            # Baja el escudo y cabeza, mastica la comida
	TERRITORIAL_DISPLAY  # Exhibición territorial: cornada y sacudida de escudo
}

@onready var visual_model: Node3D = get_node_or_null("VisualModel")

var current_state: State = State.PATROL_WANDER:
	set(value):
		if current_state != value:
			current_state = value
			print("[Cerebro Triceratops] Estado: ", get_brain_state_name())

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

# Estado dinámico de adaptación al terreno y pendientes
var _current_slope_pitch: float = 0.0
var _current_slope_roll: float = 0.0
var _current_ground_y_offset: float = 0.0

# Sistema dinámico de evasión de obstáculos del terreno
var _terrain_collision_cooldown: float = 0.0
var _obstacle_detour_waypoint: Vector3 = Vector3.ZERO
var _detour_timer: float = 0.0
var _stuck_timer: float = 0.0

# Índices de huesos en Skeleton3D
var _bone_head: int = -1
var _bone_neck: int = -1
var _bone_chest: int = -1
var _bone_spine: int = -1
var _bone_jaw: int = -1
var _bone_tail_1: int = -1
var _bone_tail_2: int = -1
var _bone_tail_3: int = -1

var _head_rest_q: Quaternion = Quaternion.IDENTITY
var _neck_rest_q: Quaternion = Quaternion.IDENTITY
var _chest_rest_q: Quaternion = Quaternion.IDENTITY
var _spine_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_1_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_2_rest_q: Quaternion = Quaternion.IDENTITY
var _tail_3_rest_q: Quaternion = Quaternion.IDENTITY

func _ready() -> void:
	add_to_group("dino_herd")
	_time_accum = randf_range(0.0, 10.0)
	_apply_dino_material()
	_find_animation_player()
	_find_skeleton()
	_pick_new_patrol_waypoint()
	
	# Desfasar ligeramente el estado inicial para que la manada actúe de forma orgánica
	if randf() < 0.45:
		current_state = State.IDLE_OBSERVE
		_state_timer = randf_range(2.0, 6.0)
		_play_anim("Tri_Idle", 0.0)
	else:
		_play_anim("Tri_Caminar", 0.0)
	print("[Cerebro Triceratops] Iniciado en Manada | Estado: ", get_brain_state_name(), " | Rumbo a: ", _current_waypoint)

func _apply_dino_material() -> void:
	# Si el modelo ya tiene materiales pintados desde Blender (Skin, Horns, Eye, etc.),
	# los respetamos y no los sobreescribimos.
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh and mesh.mesh.get_surface_count() > 0:
			var has_existing_material = false
			for s in range(mesh.mesh.get_surface_count()):
				if mesh.get_active_material(s) != null or mesh.mesh.surface_get_material(s) != null:
					has_existing_material = true
					break
			if has_existing_material:
				continue # Conservar pintura y materiales de Blender

		# Fallback por si alguna malla carece de material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = skin_color
		mat.roughness = 0.75
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

		if _bone_head >= 0:
			_head_rest_q = _skeleton.get_bone_rest(_bone_head).basis.get_rotation_quaternion()
		if _bone_neck >= 0:
			_neck_rest_q = _skeleton.get_bone_rest(_bone_neck).basis.get_rotation_quaternion()
		if _bone_chest >= 0:
			_chest_rest_q = _skeleton.get_bone_rest(_bone_chest).basis.get_rotation_quaternion()
		if _bone_spine >= 0:
			_spine_rest_q = _skeleton.get_bone_rest(_bone_spine).basis.get_rotation_quaternion()
		if _bone_tail_1 >= 0:
			_tail_1_rest_q = _skeleton.get_bone_rest(_bone_tail_1).basis.get_rotation_quaternion()
		if _bone_tail_2 >= 0:
			_tail_2_rest_q = _skeleton.get_bone_rest(_bone_tail_2).basis.get_rotation_quaternion()
		if _bone_tail_3 >= 0:
			_tail_3_rest_q = _skeleton.get_bone_rest(_bone_tail_3).basis.get_rotation_quaternion()

func _play_anim(anim_name: String, blend: float = 0.3, custom_speed: float = -1.0) -> void:
	if not _anim_player:
		_find_animation_player()
		if not _anim_player:
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
		elif "Caminar" in target_anim:
			_anim_player.speed_scale = walk_anim_speed
		elif "Comer" in target_anim or "Cornada" in target_anim:
			_anim_player.speed_scale = 1.0
		else:
			_anim_player.speed_scale = 0.8

		if _anim_player.current_animation != target_anim:
			_anim_player.play(target_anim, blend)

func _physics_process(delta: float) -> void:
	# 1. Gravedad terrestre y adaptación al terreno
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -1.0 # Fuerza ligera hacia abajo para mantener contacto con el terreno 3D

	# 1.1 Sondas de superficie y adaptación de pendiente
	if slope_adaptation_enabled:
		_update_surface_slope(delta)

	# 2. Temporizadores del Cerebro y Evasión
	_state_timer = max(0.0, _state_timer - delta)
	_encounter_cooldown = max(0.0, _encounter_cooldown - delta)
	_terrain_collision_cooldown = max(0.0, _terrain_collision_cooldown - delta)
	_detour_timer = max(0.0, _detour_timer - delta)

	# 3. Escaneo Sensorial de Comida (Olfato 360° + Cono de Visión)
	_sensory_scan_food()

	# 4. Decisión de Movimiento 100% Autónomo
	var commands = _update_brain_state(delta)
	var desired_turn: float = commands.turn
	var desired_forward: float = commands.forward
	var current_move_speed: float = commands.speed

	# Modulación de velocidad según pendiente (más esfuerzo cuesta arriba, cauto cuesta abajo)
	if slope_adaptation_enabled:
		if _current_slope_pitch > 0.05:
			current_move_speed *= clampf(1.0 - sin(_current_slope_pitch) * 0.35, 0.7, 1.0)
		elif _current_slope_pitch < -0.05:
			current_move_speed *= clampf(1.0 + sin(_current_slope_pitch) * 0.2, 0.8, 1.0)

	# 5. Rotación sobre el suelo (con agilidad mejorada al evadir obstáculos frontales)
	var current_turn_speed = turn_speed
	if _detour_timer > 0.0:
		current_turn_speed = turn_speed * 1.55
	if desired_turn != 0.0:
		rotate_y(desired_turn * current_turn_speed * delta)

	# 6. Desplazamiento sobre plano XZ
	var forward_dir = -global_transform.basis.z
	var fwd_h = Vector3(forward_dir.x, 0.0, forward_dir.z).normalized()
	var target_h_vel = Vector3.ZERO
	if desired_forward > 0.0:
		target_h_vel = forward_dir * (desired_forward * current_move_speed)
	elif desired_forward < 0.0:
		target_h_vel = forward_dir * (desired_forward * (walk_speed * 0.5))

	# 6.1 Sensor predictivo frontal de obstáculos del terreno (detecta rocas y muros antes de colisionar)
	if (current_state == State.PATROL_WANDER or current_state == State.PURSUE_FOOD) and _terrain_collision_cooldown <= 0.0:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var chest_y = global_position.y + 1.2
			var ray_from = Vector3(global_position.x, chest_y, global_position.z)
			var ray_to = ray_from + fwd_h * 2.5
			var q_pred = PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1) # Capa 1: Terreno y objetos
			q_pred.exclude = [get_rid()]
			var res_pred = space_state.intersect_ray(q_pred)
			if res_pred.size() > 0:
				var hit_norm = res_pred.normal
				if hit_norm.y < 0.65:
					var hit_norm_h = Vector3(hit_norm.x, 0.0, hit_norm.z).normalized()
					if fwd_h.dot(hit_norm_h) < -0.3:
						_trigger_terrain_obstacle_turn(hit_norm, res_pred.position)

	velocity.x = move_toward(velocity.x, target_h_vel.x, 8.0 * delta)
	velocity.z = move_toward(velocity.z, target_h_vel.z, 8.0 * delta)

	move_and_slide()

	# 7. Detección física de impactos frontales tras move_and_slide()
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if not collider or collider == self:
			continue

		# 7.1 Si choca con otro dinosaurio de la manada
		if collider.is_in_group("dino_herd"):
			if current_state == State.PATROL_WANDER and _encounter_cooldown <= 0.0:
				_trigger_90_degree_turn(collider)
				break

		# 7.2 Si choca de frente con un objeto del terreno (rocas, muros, cuevas, vallas)
		var col_normal = col.get_normal()
		if col_normal.y < 0.65 and _terrain_collision_cooldown <= 0.0:
			var col_norm_h = Vector3(col_normal.x, 0.0, col_normal.z).normalized()
			if fwd_h.dot(col_norm_h) < -0.3:
				_trigger_terrain_obstacle_turn(col_normal, col.get_position())
				break

	# 7.3 Detección anti-bloqueo (si intenta avanzar pero la velocidad horizontal real es nula)
	var real_h_speed = Vector2(velocity.x, velocity.z).length()
	if desired_forward > 0.3 and real_h_speed < 0.12 and is_on_floor():
		_stuck_timer += delta
		if _stuck_timer > 0.5 and _terrain_collision_cooldown <= 0.0:
			_stuck_timer = 0.0
			_trigger_terrain_obstacle_turn(-fwd_h, global_position + fwd_h * 1.5)
	else:
		_stuck_timer = max(0.0, _stuck_timer - delta * 2.0)

	# 8. Animaciones de clip autónomas
	_handle_autonomous_animation_clips()

func _sensory_scan_food() -> void:
	var food_items = get_tree().get_nodes_in_group("dino_food")
	var closest_food: Node3D = null
	var closest_dist: float = smell_radius

	for item in food_items:
		if is_instance_valid(item) and item is Node3D:
			var d = global_position.distance_to(item.global_position)
			if d < closest_dist:
				closest_dist = d
				closest_food = item

	current_food_target = closest_food

	if is_instance_valid(current_food_target):
		var to_food = (current_food_target.global_position - global_position).normalized()
		var forward = -global_transform.basis.z
		var angle_to_food = rad_to_deg(forward.angle_to(to_food))

		if current_state != State.EAT_BITE and current_state != State.TERRITORIAL_DISPLAY:
			if angle_to_food <= (vision_angle_deg * 0.5):
				if current_state != State.PURSUE_FOOD:
					current_state = State.PURSUE_FOOD
			else:
				if current_state != State.ALERT_SMELL and current_state != State.PURSUE_FOOD:
					current_state = State.ALERT_SMELL
					_state_timer = 3.5
	else:
		if current_state == State.PURSUE_FOOD or current_state == State.ALERT_SMELL:
			current_state = State.IDLE_OBSERVE
			_state_timer = randf_range(3.0, 5.0)

func _update_brain_state(_delta: float) -> Dictionary:
	var turn: float = 0.0
	var forward: float = 0.0
	var speed: float = walk_speed

	match current_state:
		State.PATROL_WANDER:
			speed = walk_speed
			var dist = Vector2(global_position.x - _current_waypoint.x, global_position.z - _current_waypoint.z).length()
			if dist < 2.8:
				# Llegó al punto: 35% observar, 15% exhibición de cuernos, o nuevo punto
				var roll = randf()
				if roll < 0.18:
					current_state = State.TERRITORIAL_DISPLAY
					_state_timer = 4.0
				elif roll < 0.55:
					current_state = State.IDLE_OBSERVE
					_state_timer = randf_range(4.0, 8.0)
				else:
					_pick_new_patrol_waypoint()
			else:
				turn = _steer_towards(_current_waypoint)
				forward = 1.0

		State.IDLE_OBSERVE:
			forward = 0.0
			turn = 0.0
			_observe_look_angle = sin(_time_accum * 0.7) * 0.75
			if _state_timer <= 0.0:
				current_state = State.PATROL_WANDER
				_pick_new_patrol_waypoint()

		State.ALERT_SMELL:
			if is_instance_valid(current_food_target):
				turn = _steer_towards(current_food_target.global_position) * 1.3
				forward = 0.2
				speed = walk_speed * 0.6
			else:
				current_state = State.PATROL_WANDER
				_pick_new_patrol_waypoint()

		State.PURSUE_FOOD:
			if is_instance_valid(current_food_target):
				speed = run_speed
				var dist = global_position.distance_to(current_food_target.global_position)
				# Comer si está a distancia o si ya llegó frente a la valla donde está la comida
				if dist <= eat_distance or (dist <= 4.0 and velocity.length() < 0.25 and _state_timer > 0.4):
					current_state = State.EAT_BITE
					_state_timer = 3.2
					if current_food_target.has_method("consume"):
						current_food_target.consume()
					else:
						current_food_target.queue_free()
					current_food_target = null
				else:
					var target_steer_pos = current_food_target.global_position
					if _detour_timer > 0.0:
						target_steer_pos = _obstacle_detour_waypoint
					turn = _steer_towards(target_steer_pos) * 1.4
					forward = 1.0
			else:
				current_state = State.IDLE_OBSERVE
				_state_timer = 3.0

		State.EAT_BITE:
			forward = 0.0
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_OBSERVE
				_state_timer = randf_range(3.5, 6.0)

		State.TERRITORIAL_DISPLAY:
			forward = 0.1
			turn = 0.0
			if _state_timer <= 0.0:
				current_state = State.IDLE_OBSERVE
				_state_timer = randf_range(3.0, 5.0)

	# Evasión inteligente de otros miembros de la manada (evita colisiones frontales)
	var herd_steer = _compute_herd_avoidance()
	if abs(herd_steer) > 0.05:
		turn += herd_steer

	# Evasión de vallas perimetrales inteligente (solo si no persigue comida y va hacia la valla)
	var fence_steer = _compute_fence_avoidance()
	if abs(fence_steer) > 0.05:
		turn = fence_steer

	return {
		"turn": clamp(turn, -1.0, 1.0),
		"forward": clamp(forward, -1.0, 1.0),
		"speed": speed
	}

func _compute_herd_avoidance() -> float:
	# Si está en plena mordida o display, no girar
	if current_state == State.EAT_BITE or current_state == State.TERRITORIAL_DISPLAY:
		return 0.0

	var avoid: float = 0.0
	var herd = get_tree().get_nodes_in_group("dino_herd")
	for other in herd:
		if other != self and is_instance_valid(other) and other is Node3D:
			var to_other = other.global_position - global_position
			to_other.y = 0.0
			var dist = to_other.length()
			# Si otro dinosaurio está a menos de 4.8 metros
			if dist < 4.8 and dist > 0.1:
				var local_dir = global_transform.basis.inverse() * to_other.normalized()
				# Si viene frontalmente en nuestro camino al patrullar, iniciar giro de 90° para buscar otro camino
				if current_state == State.PATROL_WANDER and dist < 4.2 and local_dir.z < -0.25 and _encounter_cooldown <= 0.0:
					_trigger_90_degree_turn(other)
					return _steer_towards(_current_waypoint)

				# Evasión de separación lateral suave
				if local_dir.z < -0.1:
					var strength = (4.8 - dist) / 4.8
					var side_turn = 1.0 if local_dir.x >= 0.0 else -1.0
					avoid += side_turn * strength * 1.3
	return clamp(avoid, -1.0, 1.0)

func _trigger_90_degree_turn(other: Node3D) -> void:
	if current_state != State.PATROL_WANDER:
		return
	if _encounter_cooldown > 0.0:
		return

	_encounter_cooldown = 3.5

	var to_other = other.global_position - global_position
	to_other.y = 0.0
	var local_dir = global_transform.basis.inverse() * to_other.normalized()

	# Determinar si girar a la izquierda (+90°) o a la derecha (-90°)
	# Si el otro dinosaurio está a nuestra derecha (x >= 0), giramos a la izquierda; si no, a la derecha
	var turn_left = (local_dir.x >= 0.0)
	if abs(local_dir.x) < 0.15:
		turn_left = (randf() < 0.5)

	var angle_offset = (PI * 0.5) if turn_left else (-PI * 0.5)
	var new_fwd = (-global_transform.basis.z).rotated(Vector3.UP, angle_offset).normalized()

	# Proyectar el nuevo camino a 6 - 10 metros en ese ángulo de 90°
	var dist_forward = randf_range(6.0, 10.0)
	var new_target = global_position + new_fwd * dist_forward

	# Si el nuevo camino de 90° apunta hacia la valla perimetral, invertir al ángulo de 90° opuesto
	if new_target.x > paddock_bounds_max.x - 3.0 or new_target.x < paddock_bounds_min.x + 3.0 \
	or new_target.z > paddock_bounds_max.y - 3.0 or new_target.z < paddock_bounds_min.y + 3.0:
		angle_offset = -angle_offset
		new_fwd = (-global_transform.basis.z).rotated(Vector3.UP, angle_offset).normalized()
		new_target = global_position + new_fwd * dist_forward

	new_target.x = clamp(new_target.x, paddock_bounds_min.x + 3.0, paddock_bounds_max.x - 3.0)
	new_target.z = clamp(new_target.z, paddock_bounds_min.y + 3.0, paddock_bounds_max.y - 3.0)
	new_target.y = 0.0

	_current_waypoint = new_target

func _trigger_terrain_obstacle_turn(col_normal: Vector3, _col_point: Vector3) -> void:
	if _terrain_collision_cooldown > 0.0:
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

	# Tangentes a la superficie del obstáculo
	var tangent_right = norm.cross(Vector3.UP).normalized()
	var tangent_left = -tangent_right

	# Analizar con 2 rayos comprobadores (whiskers a +/- 65°) cuál flanco tiene espacio libre para avanzar
	var space_state = get_world_3d().direct_space_state
	var probe_dist = 5.5
	var ray_y = global_position.y + 1.2

	var dir_left = fwd.rotated(Vector3.UP, deg_to_rad(65.0)).normalized()
	var dir_right = fwd.rotated(Vector3.UP, deg_to_rad(-65.0)).normalized()

	var check_pos_left = global_position + dir_left * probe_dist
	var check_pos_right = global_position + dir_right * probe_dist

	var left_blocked = false
	var right_blocked = false

	if space_state:
		var q_left = PhysicsRayQueryParameters3D.create(
			Vector3(global_position.x, ray_y, global_position.z),
			Vector3(check_pos_left.x, ray_y, check_pos_left.z),
			1 # Capa 1: Terreno y objetos
		)
		q_left.exclude = [get_rid()]
		var res_l = space_state.intersect_ray(q_left)
		if res_l.size() > 0:
			var n = res_l.normal
			if n.y < 0.65:
				left_blocked = true

		var q_right = PhysicsRayQueryParameters3D.create(
			Vector3(global_position.x, ray_y, global_position.z),
			Vector3(check_pos_right.x, ray_y, check_pos_right.z),
			1
		)
		q_right.exclude = [get_rid()]
		var res_r = space_state.intersect_ray(q_right)
		if res_r.size() > 0:
			var n = res_r.normal
			if n.y < 0.65:
				right_blocked = true

	# Decidir hacia qué lado girar para continuar avanzando
	var turn_left: bool = false
	if left_blocked and not right_blocked:
		turn_left = false
	elif right_blocked and not left_blocked:
		turn_left = true
	else:
		# Si ambos están despejados (o ambos bloqueados), girar hacia el centro del recinto
		var to_center = Vector3.ZERO - global_position
		to_center.y = 0.0
		var dot_l = dir_left.dot(to_center.normalized())
		var dot_r = dir_right.dot(to_center.normalized())
		if dot_l > dot_r + 0.1:
			turn_left = true
		elif dot_r > dot_l + 0.1:
			turn_left = false
		else:
			# Si son similares, alinear con la tangente del obstáculo que continúe el avance
			turn_left = (fwd.dot(tangent_left) > fwd.dot(tangent_right))

	# Ángulo de giro amplio (entre 75° y 110°) para esquivar el objeto frontal y seguir avanzando
	var turn_deg = randf_range(75.0, 110.0)
	var angle_rad = deg_to_rad(turn_deg) if turn_left else deg_to_rad(-turn_deg)
	var new_fwd = fwd.rotated(Vector3.UP, angle_rad).normalized()

	# Proyectar el nuevo camino a 7 - 11 metros en esa dirección
	var dist_forward = randf_range(7.0, 11.0)
	var new_target = global_position + new_fwd * dist_forward

	# Si el nuevo rumbo choca con la valla exterior, invertir al lado opuesto
	if new_target.x > paddock_bounds_max.x - 3.0 or new_target.x < paddock_bounds_min.x + 3.0 \
	or new_target.z > paddock_bounds_max.y - 3.0 or new_target.z < paddock_bounds_min.y + 3.0:
		new_fwd = fwd.rotated(Vector3.UP, -angle_rad).normalized()
		new_target = global_position + new_fwd * dist_forward

	new_target.x = clamp(new_target.x, paddock_bounds_min.x + 3.0, paddock_bounds_max.x - 3.0)
	new_target.z = clamp(new_target.z, paddock_bounds_min.y + 3.0, paddock_bounds_max.y - 3.0)
	new_target.y = global_position.y

	_current_waypoint = new_target
	_obstacle_detour_waypoint = new_target
	_detour_timer = 2.4

	# Impulso inicial elástico de viraje para iniciar la rotación de inmediato
	_turn_factor = 1.0 if turn_left else -1.0
	print("[Cerebro Triceratops] Choque frontal con obstáculo evadido -> Girando ", "IZQUIERDA" if turn_left else "DERECHA", " (", round(turn_deg), "°) buscando seguir avanzando.")

func _steer_towards(target_pos: Vector3) -> float:
	var to_target = (target_pos - global_position)
	to_target.y = 0.0
	var local_dir = global_transform.basis.inverse() * to_target.normalized()
	return clamp(-local_dir.x * 2.2, -1.0, 1.0)

func _compute_fence_avoidance() -> float:
	# Si está cazando comida o comiendo, NO evadir: la comida es la prioridad absoluta
	if current_state == State.PURSUE_FOOD or current_state == State.EAT_BITE:
		return 0.0

	var fwd = -global_transform.basis.z
	var needs_avoid = false

	# Solo corregir rumbo si se aproxima a los límites Y su vector de marcha apunta hacia la valla
	if global_position.x > (paddock_bounds_max.x - 3.5) and fwd.x > 0.0:
		needs_avoid = true
	elif global_position.x < (paddock_bounds_min.x + 3.5) and fwd.x < 0.0:
		needs_avoid = true

	if global_position.z > (paddock_bounds_max.y - 3.5) and fwd.z > 0.0:
		needs_avoid = true
	elif global_position.z < (paddock_bounds_min.y + 3.5) and fwd.z < 0.0:
		needs_avoid = true

	if needs_avoid:
		# Virar suavemente hacia el centro seguro del recinto
		return _steer_towards(Vector3(0.0, global_position.y, 0.0))

	return 0.0

func _pick_new_patrol_waypoint() -> void:
	var wx = randf_range(paddock_bounds_min.x + 3.0, paddock_bounds_max.x - 3.0)
	var wz = randf_range(paddock_bounds_min.y + 3.0, paddock_bounds_max.y - 3.0)
	_current_waypoint = Vector3(wx, 0.0, wz)

func _handle_autonomous_animation_clips() -> void:
	var slope_anim_mult: float = 1.0
	if slope_adaptation_enabled:
		if _current_slope_pitch > 0.05:
			slope_anim_mult = clampf(1.0 - sin(_current_slope_pitch) * 0.35, 0.7, 1.0)
		elif _current_slope_pitch < -0.05:
			slope_anim_mult = clampf(1.0 + sin(_current_slope_pitch) * 0.2, 0.8, 1.0)

	match current_state:
		State.PATROL_WANDER:
			_play_anim("Tri_Caminar", 0.35, walk_anim_speed * slope_anim_mult)
		State.IDLE_OBSERVE:
			_play_anim("Tri_Idle", 0.4, 0.8)
		State.ALERT_SMELL:
			_play_anim("Tri_Buscar_Comida", 0.3, 0.9)
		State.PURSUE_FOOD:
			_play_anim("Tri_Caminar", 0.25, run_anim_speed * slope_anim_mult)
		State.EAT_BITE:
			_play_anim("Tri_Comer", 0.2, 1.0)
		State.TERRITORIAL_DISPLAY:
			_play_anim("Tri_Cornada", 0.25, 1.0)

func _process(delta: float) -> void:
	_time_accum += delta

	# 8. Factores Suavizados para Animación Procedural
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
				target_pitch = -0.5 # Cabeza hacia el suelo para buscar alimento
		State.IDLE_OBSERVE:
			target_turn = _observe_look_angle
		State.EAT_BITE:
			target_pitch = -0.8 # Cabeza abajo comiendo
		State.TERRITORIAL_DISPLAY:
			target_turn = sin(_time_accum * 6.0) * 0.4

	_turn_factor = move_toward(_turn_factor, target_turn, delta * 3.0)
	_pitch_factor = move_toward(_pitch_factor, target_pitch, delta * 2.5)

	# Orientación visual adaptada a la pendiente del terreno (Pitch y Roll adaptativo)
	if visual_model and slope_adaptation_enabled:
		var base_yaw = Basis(Vector3.UP, PI)
		var q_pitch = Quaternion(Vector3.RIGHT, _current_slope_pitch)
		var q_roll = Quaternion(Vector3.FORWARD, _current_slope_roll)
		var slope_rot = Basis(q_pitch * q_roll)
		visual_model.transform.basis = (slope_rot * base_yaw).scaled(Vector3(3.2, 3.2, 3.2))
		visual_model.position.y = _current_ground_y_offset

	if not _skeleton:
		return

	# 9. Rotación Procedural de Huesos con Compensación de Pendiente
	# En el rig del Triceratops:
	#  - Eje Z local: Viraje lateral (Yaw)
	#  - Eje X local: Cabeceo vertical (Pitch)
	#  - Eje Y local: Balanceo lateral (Roll)
	var yaw_head = _turn_factor * deg_to_rad(head_yaw_max)
	var yaw_neck = _turn_factor * deg_to_rad(neck_yaw_max)
	var yaw_chest = _turn_factor * deg_to_rad(chest_yaw_max)
	var yaw_spine = _turn_factor * deg_to_rad(spine_yaw_max)

	var pitch_head = _pitch_factor * deg_to_rad(head_pitch_max)
	var pitch_neck = _pitch_factor * deg_to_rad(neck_pitch_max)

	# Compensación de cabeza y cuello para mantener la visión horizontal al subir o bajar
	var slope_comp_head = -_current_slope_pitch * slope_head_compensate_ratio
	var slope_comp_neck = -_current_slope_pitch * slope_neck_compensate_ratio
	var slope_pitch_spine = -_current_slope_pitch * slope_spine_flex_ratio
	var slope_pitch_chest = -_current_slope_pitch * slope_spine_flex_ratio
	var slope_roll_spine = _current_slope_roll * 0.20

	_apply_bone_rotation(_bone_head, _head_rest_q, pitch_head + slope_comp_head, yaw_head)
	_apply_bone_rotation(_bone_neck, _neck_rest_q, pitch_neck + slope_comp_neck, yaw_neck)
	_apply_bone_rotation(_bone_chest, _chest_rest_q, slope_pitch_chest, yaw_chest, slope_roll_spine * 0.5)
	_apply_bone_rotation(_bone_spine, _spine_rest_q, slope_pitch_spine, yaw_spine, slope_roll_spine)

	# 10. Oscilación viva de la cola (Tail sway) + Contrapeso vertical en pendientes
	var is_walking = (_anim_player and "Caminar" in _anim_player.current_animation)
	var sway_mult = 1.3 if is_walking else 0.8
	var wave_1 = sin(_time_accum * tail_sway_speed) * deg_to_rad(tail_sway_deg * sway_mult)
	var wave_2 = sin(_time_accum * tail_sway_speed - 0.7) * deg_to_rad(tail_sway_deg * 1.3 * sway_mult)
	var wave_3 = sin(_time_accum * tail_sway_speed - 1.4) * deg_to_rad(tail_sway_deg * 1.6 * sway_mult)
	var turn_drag = -_turn_factor * deg_to_rad(7.0)

	var slope_tail_pitch = -_current_slope_pitch * slope_tail_balance_ratio

	_apply_tail_rotation(_bone_tail_1, _tail_1_rest_q, slope_tail_pitch * 0.7, wave_1 + turn_drag)
	_apply_tail_rotation(_bone_tail_2, _tail_2_rest_q, slope_tail_pitch * 1.0, wave_2 + turn_drag * 1.3)
	_apply_tail_rotation(_bone_tail_3, _tail_3_rest_q, slope_tail_pitch * 1.3, wave_3 + turn_drag * 1.6)

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

	# 4 Sondas de muestreo físico en la superficie (frontal, trasera, izquierda, derecha)
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

	# Clampear a límites físicos seguros
	target_pitch = clampf(target_pitch, -deg_to_rad(max_slope_pitch_deg), deg_to_rad(max_slope_pitch_deg))
	target_roll = clampf(target_roll, -deg_to_rad(max_slope_roll_deg), deg_to_rad(max_slope_roll_deg))
	target_y_offset = clampf(target_y_offset, -0.6, 0.6)

	# Suavizado elástico continuo (elimina tirones bruscos y simula la suspensión muscular)
	var blend_factor = clampf(delta * slope_smooth_speed, 0.0, 1.0)
	_current_slope_pitch = lerp_angle(_current_slope_pitch, target_pitch, blend_factor)
	_current_slope_roll = lerp_angle(_current_slope_roll, target_roll, blend_factor)
	_current_ground_y_offset = lerpf(_current_ground_y_offset, target_y_offset, blend_factor)

func _cast_probe(space_state: PhysicsDirectSpaceState3D, pos: Vector3) -> Dictionary:
	var from = Vector3(pos.x, global_position.y + 2.2, pos.z)
	var to = Vector3(pos.x, global_position.y - 3.5, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to, 1) # Capa 1: Terreno y escenario
	query.exclude = [get_rid()]
	var res = space_state.intersect_ray(query)
	if res.size() > 0:
		return {"has_hit": true, "pos": res.position, "normal": res.normal}
	return {"has_hit": false, "pos": pos, "normal": Vector3.UP}

func get_brain_state_name() -> String:
	match current_state:
		State.PATROL_WANDER:
			return "PASTOREANDO / PATRULLANDO (Caminata pesada)"
		State.IDLE_OBSERVE:
			return "REPOSO / OBSERVANDO (Respirando y alerta)"
		State.ALERT_SMELL:
			return "¡ALERTA DE OLFATO! (Rastreando vegetación)"
		State.PURSUE_FOOD:
			return "¡APROXIMÁNDOSE A COMIDA! (Rumbo directo)"
		State.EAT_BITE:
			return "¡COMIENDO! (Masticando con pico y mandíbula)"
		State.TERRITORIAL_DISPLAY:
			return "¡EXHIBICIÓN DE CUERNOS! (Cornada defensiva)"
	return "DESCONOCIDO"
