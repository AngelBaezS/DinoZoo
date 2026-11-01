class_name DinoFood
extends RigidBody3D

@export var sink_speed: float = 0.6
@export var water_drag: float = 3.5
@export var float_depth_target: float = -1.2 # Se estabiliza flotando/hundiéndose suavemente
@export var lifetime: float = 45.0

var _water_manager: WaterManager
var _entered_water: bool = false
var _is_being_eaten: bool = false
var _life_timer: float = 0.0

func _ready() -> void:
	add_to_group("dino_food")
	_water_manager = get_tree().get_first_node_in_group("water_manager") as WaterManager

func _physics_process(delta: float) -> void:
	if _is_being_eaten:
		return

	_life_timer += delta
	if _life_timer >= lifetime:
		fade_out_and_free()
		return

	if not _water_manager:
		_water_manager = get_tree().get_first_node_in_group("water_manager") as WaterManager

	var water_y = 0.24
	if _water_manager:
		water_y = _water_manager.get_water_height_at(Vector2(global_position.x, global_position.z))

	# Verificar si entra al agua
	if global_position.y <= water_y:
		if not _entered_water:
			_entered_water = true
			if _water_manager:
				_water_manager.register_splash(global_position, 1.2)
			# Reducir velocidad de impacto al entrar al agua
			linear_velocity *= 0.35

		# Física acuática: flotabilidad y fricción
		gravity_scale = 0.05
		linear_damp = water_drag
		angular_damp = 2.0

		# Empuje hidrostático suave: tiende a flotar entre la superficie y float_depth_target
		var target_y = water_y + float_depth_target
		if global_position.y < target_y:
			apply_central_force(Vector3.UP * 4.0)
		else:
			apply_central_force(Vector3.DOWN * 2.0)
	else:
		_entered_water = false
		gravity_scale = 1.0
		linear_damp = 0.1

func consume() -> void:
	if _is_being_eaten:
		return
	_is_being_eaten = true
	remove_from_group("dino_food")

	if _water_manager:
		_water_manager.register_splash(global_position, 1.6)

	# Desvanecer o eliminar de inmediato
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func fade_out_and_free() -> void:
	_is_being_eaten = true
	remove_from_group("dino_food")
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
	tween.tween_callback(queue_free)

