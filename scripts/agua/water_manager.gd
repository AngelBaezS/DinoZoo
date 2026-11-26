class_name WaterManager
extends MeshInstance3D

@export var splash_particles_scene: PackedScene
# Oleaje estilizado suave (animado y armonioso para los 3 hábitats acuáticos)
@export var wave_a: Vector4 = Vector4(1.0, 0.2, 0.06, 16.0)
@export var wave_b: Vector4 = Vector4(0.3, 0.8, 0.04, 11.0)

var _mat: ShaderMaterial
var _impacts: Array[Vector4] = [
	Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO
]
var _current_impact_idx: int = 0
var _sim_time: float = 0.0

func _ready() -> void:
	add_to_group("water_manager")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base_mat := get_active_material(0) as ShaderMaterial
	if not base_mat:
		base_mat = material_override as ShaderMaterial
	if base_mat:
		# Garantizar instancia única por hábitat para que olas, tonos y salpicaduras sean independientes
		_mat = base_mat.duplicate() as ShaderMaterial
		_mat.render_priority = 0
		set_surface_override_material(0, _mat)
		material_override = null
		_mat.set_shader_parameter("wave_a", wave_a)
		_mat.set_shader_parameter("wave_b", wave_b)
		_mat.set_shader_parameter("sync_time", _sim_time)

func _process(delta: float) -> void:
	_sim_time += delta
	if _mat:
		_mat.set_shader_parameter("sync_time", _sim_time)

func apply_palette(shallow: Color, mid: Color, deep: Color, caustic: Color = Color(0.76, 0.98, 1.0), edge_foam: float = 1.15) -> void:
	if not _mat:
		return
	_mat.set_shader_parameter("shallow_color", shallow)
	_mat.set_shader_parameter("mid_color", mid)
	_mat.set_shader_parameter("deep_color", deep)
	_mat.set_shader_parameter("caustic_color", caustic)
	_mat.set_shader_parameter("edge_foam_width", edge_foam)

func register_splash(global_point: Vector3, strength: float = 1.2) -> void:
	_impacts[_current_impact_idx] = Vector4(
		global_point.x,
		_sim_time,
		global_point.z,
		clamp(strength, 0.1, 3.0)
	)
	_current_impact_idx = (_current_impact_idx + 1) % 4

	if _mat:
		_mat.set_shader_parameter("impacts", _impacts)

	if splash_particles_scene:
		var splash: GPUParticles3D = splash_particles_scene.instantiate()
		var target_parent: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
		target_parent.add_child(splash)
		splash.global_position = Vector3(global_point.x, global_position.y, global_point.z)
		splash.emitting = true
		splash.finished.connect(splash.queue_free)

func get_water_height_at(global_xz: Vector2) -> float:
	var y_offset: float = 0.0
	y_offset += _calc_gerstner_y(wave_a, global_xz, _sim_time)
	y_offset += _calc_gerstner_y(wave_b, global_xz, _sim_time)
	return global_position.y + y_offset

func _calc_gerstner_y(wave: Vector4, p_xz: Vector2, t: float) -> float:
	var steepness: float = wave.z
	var wavelength: float = max(wave.w, 0.5)
	var k: float = 2.0 * PI / wavelength
	var c: float = sqrt(9.8 / k)
	var d: Vector2 = Vector2(wave.x, wave.y).normalized()
	var f: float = k * (d.dot(p_xz) - c * t)
	var a: float = steepness / k
	return a * sin(f)
