class_name FoamRingController
extends MeshInstance3D

@export var water_manager: WaterManager
@export var dino_body: CharacterBody3D
@export var dino_half_height: float = 1.0

var _mat: ShaderMaterial

func _ready() -> void:
	if not dino_body and get_parent() is CharacterBody3D:
		dino_body = get_parent() as CharacterBody3D
	if not water_manager:
		water_manager = get_tree().get_first_node_in_group("water_manager") as WaterManager

	_mat = material_override as ShaderMaterial
	if not _mat:
		_mat = get_active_material(0) as ShaderMaterial
	_update_shader_params()

func _update_shader_params() -> void:
	if water_manager and _mat:
		_mat.set_shader_parameter("wave_a", water_manager.wave_a)
		_mat.set_shader_parameter("wave_b", water_manager.wave_b)

func _process(_delta: float) -> void:
	if not water_manager:
		water_manager = get_tree().get_first_node_in_group("water_manager") as WaterManager
		_update_shader_params()

	if not water_manager or not dino_body or not _mat:
		return

	# Mantener plano horizontalmente sin cabeceo
	global_rotation = Vector3(0.0, dino_body.global_rotation.y, 0.0)
	_mat.set_shader_parameter("water_base_y", water_manager.global_position.y)

	var water_y: float = water_manager.get_water_height_at(Vector2(global_position.x, global_position.z))
	# Punto de referencia: línea media del lomo del mosasaurio
	var dino_surface_y: float = dino_body.global_position.y + 0.85
	var dist_to_surface: float = abs(dino_surface_y - water_y)

	if dist_to_surface < dino_half_height:
		visible = true
		var surface_factor: float = 1.0 - (dist_to_surface / dino_half_height)
		var speed_boost: float = clamp(dino_body.velocity.length() * 0.5, 0.6, 1.2)
		var target_intensity: float = clamp(surface_factor * speed_boost, 0.0, 1.0)
		_mat.set_shader_parameter("foam_intensity", target_intensity)
	else:
		visible = false
