extends CharacterBody3D
class_name PlayerVRDesktop

## ====================================================================
## CONTROLES DEL JUGADOR - MODO TERRESTRE, VUELO CREATIVO Y ALIMENTACIÓN
## ====================================================================

const FOOD_MEAT_SCENE: PackedScene = preload("res://entidades/dinosaurios/dino_food.tscn")
const FOOD_GRASS_SCENE: PackedScene = preload("res://entidades/dinosaurios/dino_food_grass.tscn")

## Parámetros Terrestres (Cero resbalamiento en el suelo + subida automática de escalones)
@export_group("Movimiento Terrestre")
@export var walk_speed: float = 8.0
@export var sprint_speed: float = 16.0
@export var jump_velocity: float = 8.5
@export var acceleration: float = 60.0
@export var friction: float = 80.0  # Deceleración inmediata al soltar teclas
@export var gravity: float = 24.0
@export var max_step_height: float = 0.48
@export var max_slope_deg: float = 52.0

## Parámetros Vuelo Creativo / Sandbox (Minecraft Style)
@export_group("Vuelo Creativo / Sandbox")
@export var fly_speed: float = 14.0
@export var fly_sprint_speed: float = 35.0
@export var fly_vertical_speed: float = 10.0
@export var fly_vertical_sprint_speed: float = 22.0
@export var fly_acceleration: float = 50.0
@export var fly_friction: float = 40.0

## Parámetros de Alimentación (Teclas 1 = Carne, 2 = Pasto, F = Lanzar)
@export_group("Lanzamiento de Comida")
@export var throw_speed: float = 18.0
@export var throw_arc_up: float = 5.4
@export var throw_cooldown: float = 0.22
@export var max_active_thrown_food: int = 24

## Controles de mouse / Vista
@export_group("Cámara")
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = -1.5   # Permite mirar casi vertical hacia abajo al volar sobre hábitats
@export var max_pitch: float = 1.5

## Nodos
@onready var xr_origin: XROrigin3D = get_node_or_null("XROrigin3D")
@onready var camera: Camera3D = get_node_or_null("XROrigin3D/XRCamera3D")
@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
@onready var left_hand: XRController3D = get_node_or_null("XROrigin3D/LeftHand")
@onready var right_hand: XRController3D = get_node_or_null("XROrigin3D/RightHand")

## UI / HUD
@onready var hud: CanvasLayer = get_node_or_null("HUD")
@onready var status_label: Label = get_node_or_null("HUD/MarginContainer/Panel/VBox/Status")
@onready var speed_label: Label = get_node_or_null("HUD/MarginContainer/Panel/VBox/Ctrl7")
@onready var perf_label: Label = get_node_or_null("HUD/MarginContainer/Panel/VBox/PerfLabel")
@onready var crosshair: ColorRect = get_node_or_null("HUD/Crosshair")
@onready var slot_meat: PanelContainer = get_node_or_null("HUD/FoodHotbarAnchor/HotbarPanel/HotbarVBox/SlotsHBox/SlotMeat")
@onready var slot_grass: PanelContainer = get_node_or_null("HUD/FoodHotbarAnchor/HotbarPanel/HotbarVBox/SlotsHBox/SlotGrass")
@onready var throw_hint_label: Label = get_node_or_null("HUD/FoodHotbarAnchor/HotbarPanel/HotbarVBox/ThrowHint")
var _perf_timer: float = 0.0

## Estados
var is_mouse_captured: bool = false
var is_vr_active: bool = false
var is_flying: bool = false
var is_noclip: bool = false

## Estado de comida seleccionada ("meat" = tecla 1, "grass" = tecla 2)
var selected_food_type: String = DinoFood.DIET_MEAT
var _throw_cd_timer: float = 0.0
var _throw_feedback_timer: float = 0.0
var _thrown_food_queue: Array[DinoFood] = []

var _style_meat_active: StyleBoxFlat
var _style_grass_active: StyleBoxFlat
var _style_slot_inactive: StyleBoxFlat

## Detección de doble toque de espacio (Minecraft)
const DOUBLE_TAP_TIME: float = 0.35
var _last_space_press_time: float = -1.0
var _original_collision_mask: int = 1

func _ready() -> void:
	_original_collision_mask = collision_mask

	# Asegurar que la cámara de primera persona esté activa
	if camera:
		camera.current = true
		camera.make_current()

	# Configuración de física del suelo para máxima adherencia y rampas/escaleras fluidas
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(max_slope_deg)
	floor_snap_length = 0.55
	up_direction = Vector3.UP

	# Estilos dinámicos de la barra de comida
	_init_hotbar_styles()

	# Intentar inicializar OpenXR si hay hardware VR disponible
	_init_openxr()

	# Conectar botones de controladores VR si existen
	_setup_vr_controllers()

	_update_hud()
	_update_food_hotbar()

func _init_hotbar_styles() -> void:
	_style_meat_active = StyleBoxFlat.new()
	_style_meat_active.content_margin_left = 14.0
	_style_meat_active.content_margin_right = 14.0
	_style_meat_active.content_margin_top = 8.0
	_style_meat_active.content_margin_bottom = 8.0
	_style_meat_active.bg_color = Color(0.48, 0.13, 0.12, 0.94)
	_style_meat_active.border_color = Color(1.0, 0.48, 0.35, 1.0)
	_style_meat_active.set_border_width_all(2)
	_style_meat_active.set_corner_radius_all(8)

	_style_grass_active = StyleBoxFlat.new()
	_style_grass_active.content_margin_left = 14.0
	_style_grass_active.content_margin_right = 14.0
	_style_grass_active.content_margin_top = 8.0
	_style_grass_active.content_margin_bottom = 8.0
	_style_grass_active.bg_color = Color(0.14, 0.42, 0.16, 0.94)
	_style_grass_active.border_color = Color(0.45, 0.96, 0.42, 1.0)
	_style_grass_active.set_border_width_all(2)
	_style_grass_active.set_corner_radius_all(8)

	_style_slot_inactive = StyleBoxFlat.new()
	_style_slot_inactive.content_margin_left = 14.0
	_style_slot_inactive.content_margin_right = 14.0
	_style_slot_inactive.content_margin_top = 8.0
	_style_slot_inactive.content_margin_bottom = 8.0
	_style_slot_inactive.bg_color = Color(0.11, 0.14, 0.19, 0.72)
	_style_slot_inactive.border_color = Color(0.4, 0.48, 0.58, 0.4)
	_style_slot_inactive.set_border_width_all(1)
	_style_slot_inactive.set_corner_radius_all(8)

func _init_openxr() -> void:
	var xr_interface: XRInterface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		is_vr_active = true
		get_viewport().use_xr = true
		print("[PlayerVR] Sesión OpenXR activa.")
	else:
		is_vr_active = false
		print("[PlayerVR] Modo Escritorio activo (WASD + Mouse). [1] Carne | [2] Pasto | [F] Lanzar comida | [Doble Espacio/G] Volar.")

func _setup_vr_controllers() -> void:
	if left_hand:
		left_hand.button_pressed.connect(_on_vr_left_button_pressed)
	if right_hand:
		right_hand.button_pressed.connect(_on_vr_right_button_pressed)

func _on_vr_left_button_pressed(button_name: String) -> void:
	if button_name in ["by_button", "primary_click"]:
		toggle_fly()
	elif button_name == "ax_button":
		select_food(DinoFood.DIET_GRASS if selected_food_type == DinoFood.DIET_MEAT else DinoFood.DIET_MEAT)

func _on_vr_right_button_pressed(button_name: String) -> void:
	if button_name in ["trigger_click", "grip_click"]:
		throw_selected_food()
	elif button_name in ["by_button", "ax_button", "primary_click"]:
		toggle_fly()

func _unhandled_input(event: InputEvent) -> void:
	# Clic con el mouse para capturar el cursor
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_capture_mouse()

	# Tecla ESC para liberar el cursor
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_release_mouse()

	# Tecla H para alternar visibilidad del HUD
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		toggle_hud()

	# Selección de comida: [1] Carne (Carnívoros), [2] Manojo de pasto (Herbívoros)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 or event.keycode == KEY_KP_1:
			select_food(DinoFood.DIET_MEAT)
		elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
			select_food(DinoFood.DIET_GRASS)
		elif event.keycode == KEY_F:
			throw_selected_food()
		elif event.keycode == KEY_G:
			toggle_fly()

	# Tecla V para alternar noclip (atravesar barreras / vallas)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		toggle_noclip()

	# Doble pulsación de Espacio tipo Minecraft para alternar vuelo
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - _last_space_press_time <= DOUBLE_TAP_TIME:
			toggle_fly()
			_last_space_press_time = -1.0
		else:
			_last_space_press_time = current_time

	# Rueda del ratón para ajustar velocidad de vuelo al estar volando
	if event is InputEventMouseButton and event.pressed and is_flying:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed = clamp(fly_speed + 2.0, 6.0, 60.0)
			fly_sprint_speed = fly_speed * 2.5
			_update_hud()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed = clamp(fly_speed - 2.0, 6.0, 60.0)
			fly_sprint_speed = fly_speed * 2.5
			_update_hud()

	# Movimiento de cámara con el mouse cuando está capturado
	if is_mouse_captured and event is InputEventMouseMotion:
		# Rotación horizontal (Yaw) sobre el cuerpo del jugador
		rotate_y(-event.relative.x * mouse_sensitivity)

		# Rotación vertical (Pitch) sobre la cámara
		if camera:
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(camera.rotation.x, min_pitch, max_pitch)

## ====================================================================
## SISTEMA DE SELECCIÓN Y LANZAMIENTO DE COMIDA
## ====================================================================

func select_food(food_type: String) -> void:
	if food_type != DinoFood.DIET_MEAT and food_type != DinoFood.DIET_GRASS:
		return
	selected_food_type = food_type
	_throw_feedback_timer = 0.0
	_update_food_hotbar()

func throw_selected_food() -> DinoFood:
	if _throw_cd_timer > 0.0:
		return null
	_throw_cd_timer = throw_cooldown

	var scene: PackedScene = FOOD_MEAT_SCENE if selected_food_type == DinoFood.DIET_MEAT else FOOD_GRASS_SCENE
	if scene == null:
		return null

	var food := scene.instantiate() as DinoFood
	if food == null:
		return null

	food.food_type = selected_food_type

	# Determinar punto de lanzamiento y dirección desde la cámara (o mano derecha en VR)
	var origin_basis: Basis = global_transform.basis
	var spawn_pos: Vector3 = global_position + Vector3(0.0, 1.55, 0.0)
	if is_vr_active and is_instance_valid(right_hand):
		origin_basis = right_hand.global_transform.basis
		spawn_pos = right_hand.global_position
	elif is_instance_valid(camera):
		origin_basis = camera.global_transform.basis
		spawn_pos = camera.global_position

	var aim_forward: Vector3 = (-origin_basis.z).normalized()
	var aim_up: Vector3 = origin_basis.y.normalized()
	var aim_right: Vector3 = origin_basis.x.normalized()

	var parent_node: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
	if parent_node == null:
		parent_node = get_tree().root
	parent_node.add_child(food)

	# Posición ligeramente al frente y a la derecha para sensación natural de lanzamiento
	food.global_position = spawn_pos + aim_forward * 1.15 - aim_up * 0.14 + aim_right * 0.18

	# Impulso parabólico limpio para cruzar fácilmente las vallas hacia los recintos
	var player_vel_bonus: Vector3 = Vector3(velocity.x, maxf(0.0, velocity.y), velocity.z) * 0.35
	food.linear_velocity = aim_forward * throw_speed + Vector3.UP * throw_arc_up + player_vel_bonus
	food.angular_velocity = Vector3(
		randf_range(-5.5, 5.5),
		randf_range(-4.0, 4.0),
		randf_range(-5.5, 5.5)
	)

	# Limitar cantidad máxima de comida activa simultánea para cuidar FPS
	_cleanup_thrown_food_queue()
	_thrown_food_queue.append(food)
	while _thrown_food_queue.size() > max_active_thrown_food:
		var oldest: DinoFood = _thrown_food_queue.pop_front()
		if is_instance_valid(oldest):
			oldest.fade_out_and_free()

	_throw_feedback_timer = 0.85
	_update_food_hotbar(true)
	return food

func _cleanup_thrown_food_queue() -> void:
	var valid_items: Array[DinoFood] = []
	for item in _thrown_food_queue:
		if is_instance_valid(item) and item.is_inside_tree():
			valid_items.append(item)
	_thrown_food_queue = valid_items

func _update_food_hotbar(just_threw: bool = false) -> void:
	var is_meat := (selected_food_type == DinoFood.DIET_MEAT)
	if slot_meat:
		slot_meat.add_theme_stylebox_override("panel", _style_meat_active if is_meat else _style_slot_inactive)
		slot_meat.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_meat else Color(0.72, 0.76, 0.82, 0.85)
	if slot_grass:
		slot_grass.add_theme_stylebox_override("panel", _style_grass_active if not is_meat else _style_slot_inactive)
		slot_grass.modulate = Color(1.0, 1.0, 1.0, 1.0) if not is_meat else Color(0.72, 0.76, 0.82, 0.85)

	if throw_hint_label:
		if just_threw:
			if is_meat:
				throw_hint_label.text = "🥩 ¡Lanzaste Carne! (Atrae carnívoros)"
				throw_hint_label.modulate = Color(1.0, 0.72, 0.55)
			else:
				throw_hint_label.text = "🌿 ¡Lanzaste Manojo de pasto! (Atrae herbívoros)"
				throw_hint_label.modulate = Color(0.55, 1.0, 0.58)
		else:
			if is_meat:
				throw_hint_label.text = "Pulsa [F] para lanzar 🥩 Carne (Carnívoros)"
			else:
				throw_hint_label.text = "Pulsa [F] para lanzar 🌿 Manojo de pasto (Herbívoros)"
			throw_hint_label.modulate = Color(0.88, 0.94, 1.0)

func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	is_mouse_captured = true

func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_mouse_captured = false

## Alterna entre modo caminar normal y modo vuelo creativo
func toggle_fly() -> void:
	is_flying = not is_flying
	if is_flying:
		velocity.y = 0.0
		floor_snap_length = 0.0
		print("[PlayerVR] 🕊️ Modo Vuelo Creativo ACTIVADO. Usa [Espacio/E] para subir, [Ctrl/C] para bajar y [Shift] para Turbo.")
	else:
		floor_snap_length = 0.5
		if is_noclip:
			set_noclip(false)
		print("[PlayerVR] 🚶 Modo Terrestre restaurado.")
	_update_hud()

## Alterna modo fantasma (Noclip)
func toggle_noclip() -> void:
	set_noclip(not is_noclip)

func set_noclip(active: bool) -> void:
	is_noclip = active
	if is_noclip:
		if not is_flying:
			is_flying = true
			floor_snap_length = 0.0
		collision_mask = 0
		if collision_shape:
			collision_shape.disabled = true
		print("[PlayerVR] 👻 Modo Fantasma (Noclip) ACTIVADO. Atraviesa muros y vallas libremente.")
	else:
		collision_mask = _original_collision_mask
		if collision_shape:
			collision_shape.disabled = false
		print("[PlayerVR] 👻 Modo Fantasma desactivado (Colisiones activas).")
	_update_hud()

## Alterna la visibilidad del panel de ayuda HUD
func toggle_hud() -> void:
	if hud:
		hud.visible = not hud.visible

func _update_hud() -> void:
	if not status_label:
		return

	if is_noclip:
		status_label.text = "Modo: 👻 FANTASMA / NOCLIP (%.0f m/s)" % fly_speed
		status_label.modulate = Color(1.0, 0.85, 0.2)
	elif is_flying:
		status_label.text = "Modo: 🕊️ VUELO CREATIVO (%.0f m/s)" % fly_speed
		status_label.modulate = Color(0.2, 1.0, 0.7)
	else:
		status_label.text = "Modo: 🚶 TERRESTRE (Caminando)"
		status_label.modulate = Color(0.75, 0.85, 0.95)

	if speed_label:
		speed_label.text = "• Rueda Mouse: Vel. vuelo (%d m/s) | H: HUD" % int(fly_speed)

func _physics_process(delta: float) -> void:
	if _throw_cd_timer > 0.0:
		_throw_cd_timer = maxf(0.0, _throw_cd_timer - delta)
	if _throw_feedback_timer > 0.0:
		_throw_feedback_timer -= delta
		if _throw_feedback_timer <= 0.0:
			_update_food_hotbar(false)

	# Monitor de rendimiento y optimización de animaciones en FOV
	_perf_timer -= delta
	if _perf_timer <= 0.0:
		_perf_timer = 0.20
		_update_perf_label()

	if is_flying:
		_process_flying_physics(delta)
	else:
		_process_ground_physics(delta)

func _update_perf_label() -> void:
	if not perf_label:
		return
	var fps = Engine.get_frames_per_second()
	var dinos = get_tree().get_nodes_in_group("dinosaurios")
	var total_dinos = dinos.size()
	var active_dinos = 0
	for d in dinos:
		if not is_instance_valid(d):
			continue
		if d.has_meta("_perf_active"):
			if d.get_meta("_perf_active"):
				active_dinos += 1
		elif d.is_physics_processing():
			active_dinos += 1
	var draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	perf_label.text = "⚡ FPS: %d | Dinos: %d/%d activos | DrawCalls: %d" % [fps, active_dinos, total_dinos, draws]
	if fps >= 55:
		perf_label.modulate = Color(0.3, 1.0, 0.5)
	elif fps >= 30:
		perf_label.modulate = Color(1.0, 0.9, 0.3)
	else:
		perf_label.modulate = Color(1.0, 0.4, 0.3)

## Lógica física de vuelo creativo estilo Minecraft
func _process_flying_physics(delta: float) -> void:
	var is_sprinting: bool = Input.is_key_pressed(KEY_SHIFT)
	var current_horiz_speed: float = fly_sprint_speed if is_sprinting else fly_speed
	var current_vert_speed: float = fly_vertical_sprint_speed if is_sprinting else fly_vertical_speed

	# 1. Movimiento horizontal (WASD / Flechas)
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0

	# Soporte VR stick izquierdo
	if is_vr_active and left_hand:
		var vr_vec = left_hand.get_vector2("primary")
		if vr_vec.length_squared() > 0.04:
			input_dir = Vector2(vr_vec.x, -vr_vec.y)

	input_dir = input_dir.normalized()

	# Dirección horizontal relativa a la orientación del jugador
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * current_horiz_speed, fly_acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_horiz_speed, fly_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fly_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, fly_friction * delta)

	# 2. Movimiento vertical (Espacio/E para Subir, Ctrl/C/Q para Bajar)
	var vert_input: float = 0.0
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E):
		vert_input += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_Q):
		vert_input -= 1.0

	# Soporte VR stick derecho para eje vertical
	if is_vr_active and right_hand:
		var r_vec = right_hand.get_vector2("primary")
		if abs(r_vec.y) > 0.2:
			vert_input += r_vec.y

	if vert_input != 0.0:
		velocity.y = move_toward(velocity.y, vert_input * current_vert_speed, fly_acceleration * delta)
	else:
		velocity.y = move_toward(velocity.y, 0.0, fly_friction * delta)

	move_and_slide()

## Lógica física terrestre (Caminar, Correr, Saltar)
func _process_ground_physics(delta: float) -> void:
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Salto con Espacio
	if is_on_floor() and (Input.is_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("ui_accept")):
		velocity.y = jump_velocity

	# Velocidad objetivo (Sprint con Shift)
	var is_sprinting: bool = Input.is_key_pressed(KEY_SHIFT)
	var current_speed: float = sprint_speed if is_sprinting else walk_speed

	# Leer entrada de movimiento (WASD y flechas)
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0

	# Soporte VR stick izquierdo
	if is_vr_active and left_hand:
		var vr_vec = left_hand.get_vector2("primary")
		if vr_vec.length_squared() > 0.04:
			input_dir = Vector2(vr_vec.x, -vr_vec.y)

	input_dir = input_dir.normalized()

	# Dirección de movimiento relativa a la orientación del jugador
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	step_ground_motion(direction, current_speed, delta)

## Ejecuta un paso físico terrestre con subida automática de escalones/bordillos (sin saltar)
func step_ground_motion(direction: Vector3, current_speed: float, delta: float) -> void:
	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horiz_vel.length_squared() > 0.01 and velocity.y <= 0.6 and (is_on_floor() or test_move(global_transform, Vector3(0.0, -0.18, 0.0))):
		_try_auto_step_up(horiz_vel * delta)

	move_and_slide()

func _try_auto_step_up(horiz_motion: Vector3) -> void:
	var h_dir := Vector3(horiz_motion.x, 0.0, horiz_motion.z)
	var step_dist := h_dir.length()
	if step_dist < 0.001:
		return
	h_dir /= step_dist
	var probe_dist := maxf(step_dist, 0.18)

	# Solo activar si el movimiento horizontal choca contra un escalón/bordillo vertical
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, h_dir * probe_dist, col):
		return
	if col.get_normal().y >= 0.62:
		# Es una rampa caminable normal: move_and_slide la sube de forma natural
		return

	# Probar elevar hasta max_step_height, avanzar y descender sobre la superficie del escalón
	var up_xf := global_transform
	var up_col := KinematicCollision3D.new()
	var lift := max_step_height
	if test_move(up_xf, Vector3(0.0, max_step_height, 0.0), up_col):
		lift = maxf(0.0, up_col.get_travel().y - 0.02)
	if lift < 0.04:
		return
	up_xf.origin.y += lift

	# Confirmar que al frente a esa altura hay paso libre (no es un muro alto o vidrio)
	var fwd_col := KinematicCollision3D.new()
	var advance := probe_dist
	if test_move(up_xf, h_dir * probe_dist, fwd_col):
		advance = fwd_col.get_travel().length()
		if advance < 0.04:
			return
	up_xf.origin += h_dir * advance

	# Bajar hasta apoyar en la huella del escalón
	var down_col := KinematicCollision3D.new()
	if test_move(up_xf, Vector3(0.0, -lift, 0.0), down_col):
		if down_col.get_normal().y >= 0.70:
			var new_y := up_xf.origin.y + down_col.get_travel().y
			var gain := new_y - global_position.y
			if gain > 0.015 and gain <= max_step_height + 0.02:
				global_position.y = new_y
				velocity.y = maxf(0.0, velocity.y)
