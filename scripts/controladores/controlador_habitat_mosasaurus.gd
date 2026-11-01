extends Node3D

@onready var water_surface: WaterManager = $WaterSurface
@onready var dino: DinoSwimmer = $DinoMosasaurus
@onready var camera: Camera3D = $Camera3D
@onready var cam_label: Label = get_node_or_null("UI/Panel/VBox/CamLabel")
@onready var brain_label: Label = get_node_or_null("UI/Panel/VBox/BrainLabel")

var food_scene: PackedScene = preload("res://entidades/dinosaurios/dino_food.tscn")

# Configuración de Cámara Sandbox / Espectador
@export var fly_speed: float = 18.0
@export var mouse_sensitivity: float = 0.0028

var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _is_right_mouse_down: bool = false

# Coordenadas preestablecidas de acceso rápido ([1], [2] y [3])
# 1. Vista Panorámica Aérea Isométrica del Paddock 100x100
const PRESET_ISO_POS = Vector3(88.0, 76.0, 88.0)
const PRESET_ISO_TARGET = Vector3(0.0, 11.0, 0.0)

# 2. Gran Ventanal de Observación Acuario (+X = 49.6m, Z = 0)
const PRESET_AQUARIUM_POS = Vector3(58.0, 11.0, 0.0)
const PRESET_AQUARIUM_TARGET = Vector3(0.0, 11.0, 0.0)

# 3. Pasarela Superior / Catwalk junto a la grúa de alimentación
const PRESET_CATWALK_POS = Vector3(-42.0, 24.5, 38.0)
const PRESET_CATWALK_TARGET = Vector3(0.0, 14.0, 0.0)

func _ready() -> void:
	# Soporte OpenXR si está disponible
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

	_setup_enclosure_collisions()
	if camera:
		_set_camera_view(PRESET_ISO_POS, PRESET_ISO_TARGET)
	_update_cam_label("Modo Sandbox Libre (WASD + Espacio/Shift)")

func _setup_enclosure_collisions() -> void:
	var enclosure = get_node_or_null("PaddockEnclosure")
	if not enclosure:
		return
	var solid_prefixes = [
		"Pit_Floor", "Main_Perimeter_Walls", "Quarry_Rock", "Boulder",
		"Observation_Glass", "Catwalk", "Foundation", "Interior_Access_Tower",
		"Containment_Blast_Gate", "Exterior_Buttresses", "Feeding_Jib_Crane"
	]
	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(enclosure, meshes)
	for m in meshes:
		for prefix in solid_prefixes:
			if m.name.begins_with(prefix):
				m.create_trimesh_collision()
				break

func _gather_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child)
		_gather_meshes(child, result)

func _set_camera_view(pos: Vector3, target: Vector3) -> void:
	camera.global_position = pos
	camera.look_at(target, Vector3.UP)
	_cam_yaw = camera.rotation.y
	_cam_pitch = camera.rotation.x

func _process(delta: float) -> void:
	if not camera:
		return

	# Movimiento Sandbox Tipo Vuelo Libre (WASD + Espacio / Shift)
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
		move_dir.y += 1.0 # Subir
	if Input.is_key_pressed(KEY_SHIFT):
		move_dir.y -= 1.0 # Bajar

	if move_dir.length_squared() > 0.001:
		camera.global_position += move_dir.normalized() * (fly_speed * delta)

	_update_brain_label()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F1:
			get_tree().change_scene_to_file("res://niveles/habitat_mosasaurus.tscn")
		elif event.keycode == KEY_F2:
			get_tree().change_scene_to_file("res://niveles/habitat_triceratops.tscn")
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://niveles/main.tscn")
		elif event.keycode == KEY_1:
			_set_camera_view(PRESET_ISO_POS, PRESET_ISO_TARGET)
			_update_cam_label("Vista Rápida: [1] Isométrica Aérea Paddock 100x100")
		elif event.keycode == KEY_2:
			_set_camera_view(PRESET_AQUARIUM_POS, PRESET_AQUARIUM_TARGET)
			_update_cam_label("Vista Rápida: [2] Gran Ventanal Subacuático")
		elif event.keycode == KEY_3:
			_set_camera_view(PRESET_CATWALK_POS, PRESET_CATWALK_TARGET)
			_update_cam_label("Vista Rápida: [3] Pasarela Superior y Grúa")
		elif event.keycode == KEY_H:
			var ui_node = get_node_or_null("UI")
			if ui_node:
				ui_node.visible = not ui_node.visible
		elif event.keycode == KEY_R:
			if dino:
				dino.global_position = Vector3(0.0, 10.0, 0.0)
				dino.velocity = Vector3.ZERO
				dino.current_state = DinoSwimmer.State.PATROL_WANDER

	# Control de Ratón (Clic Derecho = Rotar Cámara | Clic Izquierdo = Lanzar Comida)
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
			fly_speed = clamp(fly_speed + 2.0, 3.0, 35.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = clamp(fly_speed - 2.0, 3.0, 35.0)

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
	if not brain_label or not dino:
		return

	var txt = "Cerebro IA: 🟢 100% Autónomo | " + dino.get_brain_state_name()
	if is_instance_valid(dino.current_food_target):
		var dist = dino.global_position.distance_to(dino.current_food_target.global_position)
		txt += " (Distancia a presa: %.1fm)" % dist
	brain_label.text = txt
	brain_label.modulate = Color(0.4, 1.0, 0.5)

func _throw_food_at_cursor(screen_pos: Vector2) -> void:
	if not camera or not food_scene:
		return

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var water_y = 15.0
	if water_surface:
		water_y = water_surface.global_position.y

	var hit_pos = Vector3.ZERO
	if abs(ray_dir.y) > 0.001:
		var t = (water_y - ray_origin.y) / ray_dir.y
		if t > 0:
			hit_pos = ray_origin + ray_dir * t

	hit_pos.x = clamp(hit_pos.x, -35.0, 35.0)
	hit_pos.z = clamp(hit_pos.z, -35.0, 35.0)
	hit_pos.y = water_y

	var food = food_scene.instantiate() as RigidBody3D
	add_child(food)

	var start_pos = camera.global_position + ray_dir * 1.5
	food.global_position = start_pos

	var to_hit = (hit_pos - start_pos)
	var throw_vel = to_hit.normalized() * 24.0 + Vector3(0, 5.0, 0)
	food.linear_velocity = throw_vel

	if water_surface and hit_pos.length() > 0.1:
		water_surface.register_splash(hit_pos, 1.8)
