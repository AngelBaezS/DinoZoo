extends Node3D

@onready var dino: DinoTriceratops = get_node_or_null("DinoTriceratops")
@onready var camera: Camera3D = $Camera3D
@onready var cam_label: Label = get_node_or_null("UI/Panel/VBox/CamLabel")
@onready var brain_label: Label = get_node_or_null("UI/Panel/VBox/BrainLabel")

var food_scene: PackedScene = preload("res://entidades/dinosaurios/dino_food.tscn")

# Configuración de Cámara Sandbox / Espectador
@export var fly_speed: float = 14.0
@export var fast_fly_multiplier: float = 2.0
@export var mouse_sensitivity: float = 0.0028

var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _is_right_mouse_down: bool = false

# Coordenadas preestablecidas de acceso rápido ([1], [2] y [3])
# Vista Panorámica Isométrica Estilizada (Lente 36° sin distorsión)
const PRESET_OVERVIEW_POS = Vector3(33.0, 28.0, 35.0)
const PRESET_OVERVIEW_TARGET = Vector3(0.0, 0.5, 0.0)

# Terraza de Observación de Visitantes (Deck elevado a 4.5m con vista panorámica al recinto)
const PRESET_FENCE_POS = Vector3(-16.0, 4.5, 2.0)
const PRESET_FENCE_TARGET = Vector3(0.0, 1.0, 0.0)

# Vista Cercana de la Laguna / Estanque de Agua
const PRESET_POND_POS = Vector3(-3.0, 4.2, 15.0)
const PRESET_POND_TARGET = Vector3(-7.0, -0.2, 7.5)

var pond_water_shader: Shader = preload("res://materiales/shaders/pond_water.gdshader")

func _ready() -> void:
	# Soporte OpenXR si está disponible
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

	_setup_enclosure_collisions()
	_setup_pond_water()
	if camera:
		_set_camera_view(PRESET_OVERVIEW_POS, PRESET_OVERVIEW_TARGET)
	_update_cam_label("Modo Sandbox Libre (WASD + Espacio/Shift)")

func _setup_pond_water() -> void:
	var enclosure = get_node_or_null("Enclosure")
	if not enclosure:
		return

	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(enclosure, meshes)

	for m in meshes:
		if m.name.begins_with("Water"):
			# Asegurar que el plano de agua no tenga cuerpo físico (100% atravesable)
			for child in m.get_children():
				if child is CollisionShape3D or child is StaticBody3D:
					child.queue_free()

			# Asignar shader de agua líquida semitransparente con oleaje
			var water_mat = ShaderMaterial.new()
			water_mat.shader = pond_water_shader
			m.material_override = water_mat
			print("[Recinto Terrestre] Agua de estanque aplicada a: ", m.name, " (Semitransparente, oleaje activo, sin físicas, atravesable)")

func _setup_enclosure_collisions() -> void:
	var enclosure = get_node_or_null("Enclosure")
	if not enclosure:
		return
	var solid_prefixes = [
		"Terrain", "Fence", "Hill_Rock", "Lake_Rock",
		"Dirt_Rock", "Cave", "Deck", "Diorama_Base", "Trough_Planter"
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

	# 1. Movimiento Sandbox Tipo Vuelo Libre (WASD + Espacio / Shift)
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
		var current_speed = fly_speed
		camera.global_position += move_dir.normalized() * (current_speed * delta)

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
			_set_camera_view(PRESET_OVERVIEW_POS, PRESET_OVERVIEW_TARGET)
			_update_cam_label("Vista Rápida: [1] Panorámica Aérea")
		elif event.keycode == KEY_2:
			_set_camera_view(PRESET_FENCE_POS, PRESET_FENCE_TARGET)
			_update_cam_label("Vista Rápida: [2] Terraza Mirador de Visitantes")
		elif event.keycode == KEY_3:
			_set_camera_view(PRESET_POND_POS, PRESET_POND_TARGET)
			_update_cam_label("Vista Rápida: [3] Laguna / Estanque de Agua")
		elif event.keycode == KEY_H:
			var ui_node = get_node_or_null("UI")
			if ui_node:
				ui_node.visible = not ui_node.visible
		elif event.keycode == KEY_R:
			var herd = get_tree().get_nodes_in_group("dino_herd")
			var start_positions = [
				Vector3(0.0, 0.5, 0.0),
				Vector3(6.5, 0.5, 5.5),
				Vector3(-5.5, 0.5, -4.5),
				Vector3(-10.0, 0.5, 6.0),
				Vector3(4.0, 0.5, -6.0)
			]
			var idx = 0
			for d in herd:
				if is_instance_valid(d):
					d.global_position = start_positions[idx % start_positions.size()]
					d.velocity = Vector3.ZERO
					d.current_state = DinoTriceratops.State.PATROL_WANDER
					idx += 1

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
			fly_speed = clamp(fly_speed + 2.0, 4.0, 40.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = clamp(fly_speed - 2.0, 4.0, 40.0)

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

	var herd = get_tree().get_nodes_in_group("dino_herd")
	var count = herd.size()
	var txt = "Cerebro Manada: 🟢 %d Triceratops Autónomos | Colisión Activa" % count
	if dino and is_instance_valid(dino.current_food_target):
		var dist = dino.global_position.distance_to(dino.current_food_target.global_position)
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
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 300.0, 1)
		var res = space_state.intersect_ray(query)
		if res.size() > 0:
			hit_pos = res.position

	if hit_pos == Vector3.ZERO and abs(ray_dir.y) > 0.001:
		var t = -ray_origin.y / ray_dir.y
		if t > 0:
			hit_pos = ray_origin + ray_dir * t

	hit_pos.x = clamp(hit_pos.x, -15.5, 15.5)
	hit_pos.z = clamp(hit_pos.z, -15.5, 15.5)
	hit_pos.y = max(hit_pos.y, 0.2)

	var food = food_scene.instantiate() as RigidBody3D
	add_child(food)

	var start_pos = camera.global_position + ray_dir * 1.5
	food.global_position = start_pos

	var to_hit = (hit_pos - start_pos)
	var throw_vel = to_hit.normalized() * 14.0 + Vector3(0, 4.0, 0)
	food.linear_velocity = throw_vel
