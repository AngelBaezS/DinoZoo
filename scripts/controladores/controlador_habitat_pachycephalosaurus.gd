extends Node3D

@onready var dino = get_node_or_null("DinoPachycephalosaurus")
@onready var camera: Camera3D = get_node_or_null("Camera3D")

const PRESET_OVERVIEW_POS = Vector3(32.0, 32.0, 34.0)
const PRESET_OVERVIEW_TARGET = Vector3(0.0, 0.5, 0.0)

var pond_water_shader: Shader = preload("res://materiales/shaders/pond_water.gdshader")

func _ready() -> void:
	_setup_enclosure_collisions()
	_setup_pond_water()

	if not camera or get_parent() != get_tree().root:
		set_process(false)
		set_process_unhandled_input(false)
		set_process_input(false)
		return

	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

func _setup_pond_water() -> void:
	var enclosure = get_node_or_null("Enclosure")
	if not enclosure:
		enclosure = get_node_or_null("PaddockEnclosure")
	if not enclosure:
		return

	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(self, meshes)

	for m in meshes:
		if m.name.begins_with("Water") or m.name.begins_with("Pond_Water"):
			for child in m.get_children():
				if child is CollisionShape3D or child is StaticBody3D:
					child.queue_free()

			var water_mat = ShaderMaterial.new()
			water_mat.shader = pond_water_shader
			m.material_override = water_mat

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
		"Catwalk_Stairs", 		"Stair_Ramp", 		"Terrain", "Enclosure_Terrain", "Fence", "Hill_Rock", "Lake_Rock",
		"Dirt_Rock", "Cave", "Deck", "Diorama_Base", "Trough_Planter", "Lawn_Outer", "Outer_Lawn_Border", "Road", "Access_Road", "Verge_Inner", "Curb", "Main_Gate", "Floodgate", "Observation_Skywalk",
		"Boulder", "Blast_Gate", "Entrance_Grating", "Watchtower"
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
