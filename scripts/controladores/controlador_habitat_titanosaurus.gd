extends Node3D

@onready var titano: DinoTitanosaurus = get_node_or_null("DinoTitanosaurus")
@onready var camera: Camera3D = get_node_or_null("Camera3D")
@onready var cam_label: Label = get_node_or_null("UI/Panel/VBox/CamLabel")
@onready var brain_label: Label = get_node_or_null("UI/Panel/VBox/BrainLabel")

var food_scene: PackedScene = preload("res://entidades/dinosaurios/dino_food.tscn")

# Configuración de Cámara Sandbox / Espectador
@export var fly_speed: float = 22.0
@export var fast_fly_multiplier: float = 2.2
@export var mouse_sensitivity: float = 0.0028

var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _is_right_mouse_down: bool = false

# Coordenadas de vistas rápidas adaptadas al recinto de 100x100m ([1], [2] y [3])
# Vista 1: Panorámica Aérea Majestuosa (Lente 38° abarcando el valle completo)
const PRESET_OVERVIEW_POS = Vector3(68.0, 58.0, 72.0)
const PRESET_OVERVIEW_TARGET = Vector3(0.0, 3.0, 0.0)

# Vista 2: Skywalk Mirador de Visitantes (Plataforma elevada frente a los saurópodos)
const PRESET_SKYWALK_POS = Vector3(-2.4, 11.2, 22.0)
const PRESET_SKYWALK_TARGET = Vector3(2.0, 5.0, -6.0)

# Vista 3: Valle del Río y Torres de Alimentación Superior (13.6m)
const PRESET_RIVER_TOWER_POS = Vector3(20.0, 14.5, -8.0)
const PRESET_RIVER_TOWER_TARGET = Vector3(8.0, 6.0, -27.5)

var pond_water_shader: Shader = preload("res://materiales/shaders/pond_water.gdshader")

func _ready() -> void:
	_setup_enclosure_collisions()
	_setup_river_water()

	# Si no hay cámara o si este hábitat está instanciado dentro de otra escena (ej. escenario principal),
	# desactivar completamente cualquier procesamiento o control para no interferir con el jugador.
	if not camera or get_parent() != get_tree().root:
		set_process(false)
		set_process_unhandled_input(false)
		set_process_input(false)
		return

	# Soporte OpenXR si está disponible (solo ejecución aislada)
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

	_set_camera_view(PRESET_OVERVIEW_POS, PRESET_OVERVIEW_TARGET)
	_update_cam_label("Modo Sandbox Libre (WASD + Espacio/Shift)")

func _setup_river_water() -> void:
	var enclosure = get_node_or_null("Enclosure")
	if not enclosure:
		return

	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(self, meshes)

	for m in meshes:
		if m.name.begins_with("River_Water") or m.name.begins_with("Water"):
			# Quitar colisiones físicas para que sea un río natural atravesable por los saurópodos
			for child in m.get_children():
				if child is CollisionShape3D or child is StaticBody3D:
					child.queue_free()

			var water_mat = ShaderMaterial.new()
			water_mat.shader = pond_water_shader
			m.material_override = water_mat
			print("[Recinto Titanosaurus 100x100] Agua de río aplicada a: ", m.name, " (Transparente, oleaje activo, sin físicas)")

func _setup_enclosure_collisions() -> void:
	var enclosure = get_node_or_null("Enclosure")
	if not enclosure:
		return

	var mat_fisico := PhysicsMaterial.new()
	mat_fisico.friction = 1.0
	mat_fisico.rough = true
	mat_fisico.bounce = 0.0

	var solid_prefixes = [
		"Catwalk_Stairs", 		"Deck", 		"Stair_Ramp", 		"Enclosure_Terrain", "Fence", "Canyon_Cliff", "Cave",
		"Cliff_Talus", "Observation_Skywalk", "Watchtower",
		"Feeding_Tower", "Main_Gate", "Floodgate", "Diorama_Base", "Lawn_Outer", "Outer_Lawn_Border", "Road", "Access_Road", "Verge_Inner", "Curb"
	]
	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(enclosure, meshes)
	var has_stair_ramp := false
	for m in meshes:
		if m.name.begins_with("Stair_Ramp"):
			has_stair_ramp = true
			break
	for m in meshes:
		if has_stair_ramp and (m.name.begins_with("Deck_Stairs") or m.name.begins_with("Catwalk_Stairs")):
			continue
		for prefix in solid_prefixes:
			if m.name.begins_with(prefix):
				if m.name.begins_with("Stair_Ramp"):
					m.visible = false
					m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				m.create_trimesh_collision()
				for child in m.get_children():
					if child is StaticBody3D:
						child.physics_material_override = mat_fisico
				break

func _gather_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		_gather_meshes(child, result)

func _set_camera_view(pos: Vector3, target: Vector3) -> void:
	if not camera:
		return
	camera.global_position = pos
	camera.look_at(target, Vector3.UP)
	_cam_yaw = camera.rotation.y
	_cam_pitch = camera.rotation.x

func _process(delta: float) -> void:
	if not camera:
		return

	# Vuelo Libre Sandbox (WASD + Espacio/Shift)
	var move_dir = Vector3.ZERO
	var cam_basis = camera.global_transform.basis

	if Input.is_key_pressed(KEY_W):
		move_dir -= cam_basis.z
	if Input.is_key_pressed(KEY_S):
		move_dir += cam_basis.z
	if Input.is_key_pressed(KEY_A):
		move_dir -= cam_basis.x
	if Input.is_key_pressed(KEY_D):
		move_dir += cam_basis.x

	if Input.is_key_pressed(KEY_SPACE):
		move_dir.y += 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		move_dir.y -= 1.0

	if move_dir.length_squared() > 0.001:
		var current_speed = fly_speed
		camera.global_position += move_dir.normalized() * (current_speed * delta)

	_update_brain_label()

func _unhandled_input(event: InputEvent) -> void:
	if not camera:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F1:
			get_tree().change_scene_to_file("res://niveles/habitat_mosasaurus.tscn")
		elif event.keycode == KEY_F2:
			get_tree().change_scene_to_file("res://niveles/habitat_triceratops.tscn")
		elif event.keycode == KEY_F3:
			get_tree().change_scene_to_file("res://niveles/habitat_titanosaurus.tscn")
		elif event.keycode == KEY_F4:
			get_tree().change_scene_to_file("res://niveles/habitat_trex.tscn")
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://niveles/main.tscn")
		elif event.keycode == KEY_1:
			_set_camera_view(PRESET_OVERVIEW_POS, PRESET_OVERVIEW_TARGET)
			_update_cam_label("Vista Rápida: [1] Panorámica Aérea 100x100m")
		elif event.keycode == KEY_2:
			_set_camera_view(PRESET_SKYWALK_POS, PRESET_SKYWALK_TARGET)
			_update_cam_label("Vista Rápida: [2] Skywalk Mirador de Visitantes")
		elif event.keycode == KEY_3:
			_set_camera_view(PRESET_RIVER_TOWER_POS, PRESET_RIVER_TOWER_TARGET)
			_update_cam_label("Vista Rápida: [3] Valle del Río y Torres de Follaje")
		elif event.keycode == KEY_H:
			var ui_node = get_node_or_null("UI")
			if ui_node:
				ui_node.visible = not ui_node.visible
		elif event.keycode == KEY_R:
			var herd = get_tree().get_nodes_in_group("titanosaurs")
			var start_positions = [
				Vector3(-12.0, 1.0, -8.0),
				Vector3(12.0, 1.0, 8.0),
				Vector3(-4.0, 1.0, 16.0)
			]
			var idx = 0
			for d in herd:
				if is_instance_valid(d):
					d.global_position = start_positions[idx % start_positions.size()]
					d.velocity = Vector3.ZERO
					d.current_state = DinoTitanosaurus.State.PATROL_WANDER
					idx += 1

	# Control de Ratón (Clic Derecho = Rotar Cámara | Clic Izquierdo = Lanzar Alimento)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.is_pressed():
				_is_right_mouse_down = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_is_right_mouse_down = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		elif event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			if not _is_right_mouse_down:
				_throw_food_at_cursor(event.position)
			else:
				var viewport_center = get_viewport().get_visible_rect().size * 0.5
				_throw_food_at_cursor(viewport_center)

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = clamp(fly_speed + 3.0, 6.0, 60.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = clamp(fly_speed - 3.0, 6.0, 60.0)

	elif event is InputEventMouseMotion and _is_right_mouse_down:
		_cam_yaw -= event.relative.x * mouse_sensitivity
		_cam_pitch = clamp(_cam_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-88.0), deg_to_rad(88.0))

		var basis_yaw = Basis(Vector3.UP, _cam_yaw)
		var basis_pitch = Basis(Vector3.RIGHT, _cam_pitch)
		camera.basis = basis_yaw * basis_pitch

func _update_cam_label(msg: String) -> void:
	if cam_label:
		cam_label.text = "Cámara Sandbox: " + msg

func _update_brain_label() -> void:
	if not brain_label:
		return

	var herd = get_tree().get_nodes_in_group("titanosaurs")
	var count = herd.size()
	var txt = "Cerebro Manada: 🟢 %d Titanosaurus Autónomos | 19m Colosales" % count
	if titano and is_instance_valid(titano.current_food_target):
		var dist = titano.global_position.distance_to(titano.current_food_target.global_position)
		txt += " (Comida a: %.1fm)" % dist
	brain_label.text = txt
	brain_label.modulate = Color(0.4, 1.0, 0.5)

func _throw_food_at_cursor(screen_pos: Vector2) -> void:
	if not camera or not food_scene:
		return

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)

	var hit_pos = Vector3.ZERO
	var space_state = get_world_3d().direct_space_state
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0, 1)
		var res = space_state.intersect_ray(query)
		if res.size() > 0:
			hit_pos = res.position

	if hit_pos == Vector3.ZERO and abs(ray_dir.y) > 0.001:
		var t = -ray_origin.y / ray_dir.y
		if t > 0:
			hit_pos = ray_origin + ray_dir * t

	hit_pos.x = clamp(hit_pos.x, -31.0, 31.0)
	hit_pos.z = clamp(hit_pos.z, -31.0, 31.0)
	hit_pos.y = max(hit_pos.y, 0.4)

	var food = food_scene.instantiate() as RigidBody3D
	add_child(food)

	var start_pos = camera.global_position + ray_dir * 2.0
	food.global_position = start_pos

	var to_hit = (hit_pos - start_pos)
	var throw_vel = to_hit.normalized() * 22.0 + Vector3(0, 6.0, 0)
	food.linear_velocity = throw_vel
