extends Node3D

@onready var water_surface: WaterManager = get_node_or_null("WaterSurface")
@onready var dino = get_node_or_null("DinoLiopleurodon")
@onready var camera: Camera3D = get_node_or_null("Camera3D")

const PRESET_OVERVIEW_POS = Vector3(32.0, 24.0, 34.0)
const PRESET_OVERVIEW_TARGET = Vector3(0.0, 6.0, 0.0)

func _ready() -> void:
	_setup_enclosure_collisions()
	_setup_aquatic_visuals()

	if not camera or get_parent() != get_tree().root:
		set_process(false)
		set_process_unhandled_input(false)
		set_process_input(false)
		return

	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

func _setup_aquatic_visuals() -> void:
	# Preservar el shader caricaturesco animado de WaterSurface (WaterManager) con paleta azul costero vibrante
	if water_surface:
		water_surface.apply_palette(
			Color(0.20, 0.84, 0.94),
			Color(0.10, 0.54, 0.86),
			Color(0.05, 0.28, 0.58),
			Color(0.76, 0.97, 1.0),
			0.90
		)
	var enclosure = get_node_or_null("Enclosure")
	if not enclosure:
		enclosure = get_node_or_null("PaddockEnclosure")
	if not enclosure:
		return
	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(enclosure, meshes)
	for m in meshes:
		if "Observation_Glass" in m.name:
			var glass_mat := StandardMaterial3D.new()
			glass_mat.albedo_color = Color(0.66, 0.90, 0.98, 0.14)
			glass_mat.roughness = 0.06
			glass_mat.metallic = 0.05
			glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			glass_mat.render_priority = 2
			m.material_override = glass_mat

func _setup_enclosure_collisions() -> void:
	var enclosure = get_node_or_null("Enclosure")
	if not enclosure:
		enclosure = get_node_or_null("PaddockEnclosure")
	if not enclosure:
		return

	var mat_fisico := PhysicsMaterial.new()
	mat_fisico.friction = 1.0
	mat_fisico.rough = true
	mat_fisico.bounce = 0.0

	var solid_prefixes = [
		"Catwalk_Stairs", 		"Deck", 		"Stair_Ramp", 		"Pit_Floor", "Main_Perimeter_Walls", "Quarry_Rock", "Boulder",
		"Observation_Glass", "Catwalk", "Foundation", "Interior_Access_Tower",
		"Containment_Blast_Gate", "Exterior_Buttresses", "Feeding_Jib_Crane",
		"Entrance_Grating", "Window_Steel_Mullions", "Tower_Railings"
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
	if not node: return
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_gather_meshes(child, result)
