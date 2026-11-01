class_name WaterManager
extends MeshInstance3D

@export var splash_particles_scene: PackedScene
# Oleaje suave y calmado para máxima visibilidad y transparencia del dinosaurio
@export var wave_a: Vector4 = Vector4(1.0, 0.2, 0.05, 18.0)
@export var wave_b: Vector4 = Vector4(0.3, 0.8, 0.03, 12.0)

var _mat: ShaderMaterial
var _impacts: Array[Vector4] = [
	Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO
]
var _current_impact_idx: int = 0
var _time: float = 0.0

func _ready() -> void:
	add_to_group("water_manager")
	_mat = get_active_material(0) as ShaderMaterial
	if not _mat:
		_mat = material_override as ShaderMaterial
	if _mat:
		_mat.set_shader_parameter("wave_a", wave_a)
		_mat.set_shader_parameter("wave_b", wave_b)

func _process(_delta: float) -> void:
	_time = Time.get_ticks_msec() / 1000.0

func register_splash(global_point: Vector3, strength: float = 1.2) -> void:
	var shader_time: float = Time.get_ticks_msec() / 1000.0
	_impacts[_current_impact_idx] = Vector4(
		global_point.x,
		shader_time,
		global_point.z,
		clamp(strength, 0.1, 3.0)
	)
	_current_impact_idx = (_current_impact_idx + 1) % 4
	
	if _mat:
		_mat.set_shader_parameter("impacts", _impacts)
	
	if splash_particles_scene:
		var splash: GPUParticles3D = splash_particles_scene.instantiate()
		get_tree().current_scene.add_child(splash)
		splash.global_position = Vector3(global_point.x, global_position.y, global_point.z)
		splash.emitting = true
		splash.finished.connect(splash.queue_free)

func get_water_height_at(global_xz: Vector2) -> float:
	var y_offset: float = 0.0
	y_offset += _calc_gerstner_y(wave_a, global_xz)
	y_offset += _calc_gerstner_y(wave_b, global_xz)
	return global_position.y + y_offset

func _calc_gerstner_y(wave: Vector4, p_xz: Vector2) -> float:
	var steepness: float = wave.z
	var wavelength: float = wave.w
	var k: float = 2.0 * PI / wavelength
	var c: float = sqrt(9.8 / k)
	var d: Vector2 = Vector2(wave.x, wave.y).normalized()
	var f: float = k * (d.dot(p_xz) - c * _time)
	var a: float = steepness / k
	return a * sin(f)
