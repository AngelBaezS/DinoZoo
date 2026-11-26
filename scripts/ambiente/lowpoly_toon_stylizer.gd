@tool
class_name LowPolyToonStylizer
extends RefCounted

## ============================================================================
## LOW-POLY TOON STYLIZER — DinoZoo VR (Godot 4.7 GL Compatibility)
## ============================================================================
## Reemplaza los materiales PBR pesados por defecto de Godot (StandardMaterial3D)
## por un shader ligero estilizado tipo animación 3D (cel-shading de 3 bandas +
## rim light + brisa sutil en follaje + cascadas animadas).
##
## Diseñado para MÁXIMO rendimiento en VR:
##   - Reemplaza los materiales sobre los Mesh compartidos (mesh.surface_set_material)
##     y deduplica ShaderMaterials en caché por RID -> conserva al 100% el batching
##     GPU MultiMeshInstance3D de ParkPerformanceOptimizer (0 draw calls extra).
##   - Respeta automáticamente shaders de agua, recorte de terreno, cristales
##     transparentes y el rig XR del jugador.
##   - Reversible en vivo desde el Inspector (restaura materiales originales).
## ============================================================================

const TOON_SHADER_PATH := "res://materiales/shaders/lowpoly_toon.gdshader"
const TOON_FOLIAGE_SHADER_PATH := "res://materiales/shaders/lowpoly_toon_foliage.gdshader"
const WATERFALL_SHADER_PATH := "res://materiales/shaders/lowpoly_waterfall.gdshader"
const CUTOUT_SHADER_PATH := "res://materiales/shaders/terrain_habitat_cutout.gdshader"

var wind_enabled: bool = true

var _toon_shader: Shader
var _toon_foliage_shader: Shader
var _waterfall_shader: Shader
var _converted_cache: Dictionary = {}       # "mat_rid|profile" -> ShaderMaterial
var _orig_mesh_mats: Dictionary = {}        # mesh_rid -> { "mesh": Mesh, "slots": { s: Material } }
var _orig_override_mats: Dictionary = {}    # mi_id -> { "mi": MeshInstance3D, "mat_ov": Material, "surf_ov": { s: Material } }
var _waterfall_mat: ShaderMaterial

const SKIP_MESH_KEYWORDS := [
	"water", "foam", "glass", "window", "pointer", "laser", "ray", "teleport", "xr"
]

const TREE_DOUBLE_SIDED_KEYWORDS := [
	"palm", "dicksonia", "treefern", "gianttreefern"
]

const TREE_OPAQUE_KEYWORDS := [
	"pine", "decid", "araucaria", "sequoia", "ginkgo", "canopy", "giantcanopy", "arbol", "pino", "tree"
]

const LOW_FOLIAGE_DOUBLE_SIDED_KEYWORDS := [
	"fern", "giantfern", "cycad", "helecho", "flower", "foliage", "fodder", "greens", "cactus"
]

const LOW_FOLIAGE_OPAQUE_KEYWORDS := [
	"bush", "horsetail", "lycopod"
]


func apply_to_tree(root: Node) -> Dictionary:
	var stats := {
		"meshes_visited": 0,
		"materials_converted": 0,
		"unique_toon_materials": 0,
		"waterfalls_styled": 0,
		"skipped_special": 0
	}
	if not is_instance_valid(root):
		return stats
	if not _ensure_shaders():
		return stats

	var nodes: Array[Node] = []
	if root is MeshInstance3D:
		nodes.append(root)
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))

	for n in nodes:
		var mi := n as MeshInstance3D
		if not is_instance_valid(mi) or not mi.mesh:
			continue
		if _is_inside_player_rig(mi, root):
			stats["skipped_special"] += 1
			continue

		stats["meshes_visited"] += 1
		var ln := mi.name.to_lower()

		# 1. Cascadas -> shader animado de flujo cel-shaded
		if "waterfall" in ln:
			_apply_waterfall_style(mi)
			stats["waterfalls_styled"] += 1
			continue

		# 2. Omitir mallas de agua / cristal / espuma
		if _matches_any(ln, SKIP_MESH_KEYWORDS):
			stats["skipped_special"] += 1
			continue

		var profile := _detect_profile(mi, root)

		# 3. Convertir material_override si existe y es BaseMaterial3D opaco
		if mi.material_override != null:
			if mi.material_override is BaseMaterial3D and not _is_transparent_or_glass(mi.material_override as BaseMaterial3D, ln):
				_record_override_backup(mi, -1, mi.material_override)
				mi.material_override = _get_or_create_toon_mat(mi.material_override as BaseMaterial3D, profile)
				stats["materials_converted"] += 1
			continue

		# 4. Recorrer superficies de la malla
		var mesh := mi.mesh
		var surf_count := mesh.get_surface_count()
		for s in range(surf_count):
			var surf_ov := mi.get_surface_override_material(s)
			if surf_ov != null:
				if surf_ov is ShaderMaterial:
					var sm := surf_ov as ShaderMaterial
					if sm.shader and sm.shader.resource_path == CUTOUT_SHADER_PATH:
						sm.set_shader_parameter("toon_enabled", true)
					stats["skipped_special"] += 1
				elif surf_ov is BaseMaterial3D and not _is_transparent_or_glass(surf_ov as BaseMaterial3D, ln):
					_record_override_backup(mi, s, surf_ov)
					mi.set_surface_override_material(s, _get_or_create_toon_mat(surf_ov as BaseMaterial3D, profile))
					stats["materials_converted"] += 1
				continue

			var base_mat := mesh.surface_get_material(s)
			if base_mat == null:
				continue
			if base_mat is ShaderMaterial:
				# Ya convertido en otra instancia del mismo Mesh compartido o usa shader personalizado
				var sm := base_mat as ShaderMaterial
				if sm.shader == _toon_shader or sm.shader == _toon_foliage_shader:
					_update_wind_on_mat(sm, profile)
				continue
			if base_mat is BaseMaterial3D:
				var bm := base_mat as BaseMaterial3D
				if _is_transparent_or_glass(bm, ln):
					stats["skipped_special"] += 1
					continue
				# Reemplazar sobre el Mesh compartido preserva el batching MultiMeshInstance3D!
				_record_mesh_backup(mesh, s, bm)
				var toon_mat := _get_or_create_toon_mat(bm, profile)
				mesh.surface_set_material(s, toon_mat)
				stats["materials_converted"] += 1

	stats["unique_toon_materials"] = _converted_cache.size()
	return stats


## Restaura todos los materiales originales de Godot (útil para comparar o desactivar en vivo).
func restore_originals(root: Node = null) -> void:
	for mesh_id in _orig_mesh_mats.keys():
		var rec: Dictionary = _orig_mesh_mats[mesh_id]
		var mesh: Mesh = rec["mesh"]
		if not is_instance_valid(mesh):
			continue
		var slots: Dictionary = rec["slots"]
		for s in slots.keys():
			if s < mesh.get_surface_count():
				mesh.surface_set_material(s, slots[s])
	_orig_mesh_mats.clear()

	for mi_id in _orig_override_mats.keys():
		var rec: Dictionary = _orig_override_mats[mi_id]
		var mi: MeshInstance3D = rec["mi"]
		if not is_instance_valid(mi):
			continue
		if rec.has("mat_ov"):
			mi.material_override = rec["mat_ov"]
		var surf_ov: Dictionary = rec["surf_ov"]
		for s in surf_ov.keys():
			if mi.mesh and s < mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, surf_ov[s])
	_orig_override_mats.clear()
	_converted_cache.clear()

	# Desactivar toon_enabled en el shader de recorte de terreno
	if is_instance_valid(root):
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if not mi.mesh:
				continue
			for s in range(mi.mesh.get_surface_count()):
				var ov := mi.get_surface_override_material(s)
				if ov is ShaderMaterial:
					var sm := ov as ShaderMaterial
					if sm.shader and sm.shader.resource_path == CUTOUT_SHADER_PATH:
						sm.set_shader_parameter("toon_enabled", false)


func _ensure_shaders() -> bool:
	if _toon_shader == null:
		_toon_shader = load(TOON_SHADER_PATH) as Shader
	if _toon_foliage_shader == null:
		_toon_foliage_shader = load(TOON_FOLIAGE_SHADER_PATH) as Shader
	if _waterfall_shader == null:
		_waterfall_shader = load(WATERFALL_SHADER_PATH) as Shader
	return _toon_shader != null


func _apply_waterfall_style(mi: MeshInstance3D) -> void:
	if _waterfall_shader == null:
		return
	if _waterfall_mat == null:
		_waterfall_mat = ShaderMaterial.new()
		_waterfall_mat.shader = _waterfall_shader
	var mesh := mi.mesh
	if mesh.get_surface_count() > 0:
		var m0 := mesh.surface_get_material(0)
		if not (m0 is ShaderMaterial and (m0 as ShaderMaterial).shader == _waterfall_shader):
			_record_mesh_backup(mesh, 0, m0)
			mesh.surface_set_material(0, _waterfall_mat)
	# Superficie 1 es la espuma blanca de la cascada
	if mesh.get_surface_count() > 1:
		var m1 := mesh.surface_get_material(1)
		if m1 is BaseMaterial3D:
			_record_mesh_backup(mesh, 1, m1)
			mesh.surface_set_material(1, _get_or_create_toon_mat(m1 as BaseMaterial3D, "world"))


func _get_or_create_toon_mat(src: BaseMaterial3D, profile: String) -> ShaderMaterial:
	var key := "%d|%s|%d" % [src.get_rid().get_id(), profile, 1 if wind_enabled else 0]
	if _converted_cache.has(key):
		return _converted_cache[key] as ShaderMaterial

	var smat := ShaderMaterial.new()
	var is_double_sided := (profile == "foliage_tree" or profile == "foliage_low")
	smat.shader = _toon_foliage_shader if (is_double_sided and _toon_foliage_shader != null) else _toon_shader
	var use_vc := src.vertex_color_use_as_albedo or ("_vc" in src.resource_name.to_lower())
	smat.set_shader_parameter("albedo_color", src.albedo_color)
	smat.set_shader_parameter("use_vertex_color", use_vc)

	if src.albedo_texture != null:
		smat.set_shader_parameter("use_albedo_tex", true)
		smat.set_shader_parameter("albedo_tex", src.albedo_texture)
	else:
		smat.set_shader_parameter("use_albedo_tex", false)

	if src.emission_enabled and src.emission_energy_multiplier > 0.001:
		smat.set_shader_parameter("emission_color", Color(src.emission.r, src.emission.g, src.emission.b))
		smat.set_shader_parameter("emission_strength", src.emission_energy_multiplier)
	else:
		smat.set_shader_parameter("emission_strength", 0.0)

	# Ajuste estilizado por categoría (calibrado para Godot 4 GL Compatibility con sombras legibles en VR)
	match profile:
		"dinosaur":
			smat.set_shader_parameter("color_vibrance", 1.12)
			smat.set_shader_parameter("shadow_tint", Color(0.44, 0.50, 0.62))
			smat.set_shader_parameter("mid_tint", Color(0.76, 0.77, 0.78))
			smat.set_shader_parameter("highlight_tint", Color(0.98, 0.96, 0.88))
			smat.set_shader_parameter("shadow_threshold", -0.08)
			smat.set_shader_parameter("rim_strength", 0.34)
			smat.set_shader_parameter("rim_power", 3.1)
			smat.set_shader_parameter("specular_strength", 0.42 if src.roughness < 0.48 else 0.08)
		"foliage_tree", "foliage_tree_opaque":
			smat.set_shader_parameter("color_vibrance", 1.10)
			smat.set_shader_parameter("shadow_tint", Color(0.46, 0.54, 0.60))
			smat.set_shader_parameter("mid_tint", Color(0.78, 0.80, 0.76))
			smat.set_shader_parameter("highlight_tint", Color(0.98, 0.96, 0.86))
			smat.set_shader_parameter("shadow_threshold", -0.10)
			smat.set_shader_parameter("rim_strength", 0.18)
			smat.set_shader_parameter("rim_power", 3.6)
		"foliage_low", "foliage_low_opaque":
			smat.set_shader_parameter("color_vibrance", 1.12)
			smat.set_shader_parameter("shadow_tint", Color(0.46, 0.54, 0.60))
			smat.set_shader_parameter("mid_tint", Color(0.78, 0.80, 0.76))
			smat.set_shader_parameter("highlight_tint", Color(0.98, 0.96, 0.86))
			smat.set_shader_parameter("shadow_threshold", -0.08)
			smat.set_shader_parameter("rim_strength", 0.16)
		_:
			smat.set_shader_parameter("color_vibrance", 1.07)
			smat.set_shader_parameter("shadow_tint", Color(0.44, 0.50, 0.62))
			smat.set_shader_parameter("mid_tint", Color(0.74, 0.75, 0.76))
			smat.set_shader_parameter("highlight_tint", Color(0.96, 0.94, 0.88))
			smat.set_shader_parameter("shadow_threshold", -0.05)
			smat.set_shader_parameter("rim_strength", 0.12)
			smat.set_shader_parameter("specular_strength", 0.35 if (src.metallic > 0.35 or src.roughness < 0.38) else 0.0)

	_update_wind_on_mat(smat, profile)
	_converted_cache[key] = smat
	return smat


func _update_wind_on_mat(smat: ShaderMaterial, profile: String) -> void:
	if not wind_enabled:
		smat.set_shader_parameter("wind_strength", 0.0)
		return
	match profile:
		"foliage_tree", "foliage_tree_opaque":
			# Tronco y copa se doblan suavemente juntos arriba de Y=1.4m (sin separarse)
			smat.set_shader_parameter("wind_strength", 0.075)
			smat.set_shader_parameter("wind_speed", 1.45)
			smat.set_shader_parameter("wind_height_start", 1.4)
		"foliage_low", "foliage_low_opaque":
			smat.set_shader_parameter("wind_strength", 0.06)
			smat.set_shader_parameter("wind_speed", 2.05)
			smat.set_shader_parameter("wind_height_start", 0.20)
		_:
			smat.set_shader_parameter("wind_strength", 0.0)


func _detect_profile(mi: MeshInstance3D, stop_node: Node) -> String:
	var p: Node = mi.get_parent()
	while p and p != stop_node:
		if p is CharacterBody3D or p is Skeleton3D or p.is_in_group("dinosaurios"):
			return "dinosaur"
		p = p.get_parent()

	var ln := mi.name.to_lower()
	var pln := mi.get_parent().name.to_lower() if mi.get_parent() else ""
	var mname := mi.mesh.resource_name.to_lower() if mi.mesh else ""
	var combined := ln + " " + pln + " " + mname

	if ln.begins_with("lod_") or "static_vc" in mname:
		return "world"
	if _matches_any(combined, TREE_DOUBLE_SIDED_KEYWORDS):
		return "foliage_tree"
	if _matches_any(combined, LOW_FOLIAGE_DOUBLE_SIDED_KEYWORDS):
		return "foliage_low"
	if _matches_any(combined, LOW_FOLIAGE_OPAQUE_KEYWORDS):
		return "foliage_low_opaque"
	if _matches_any(combined, TREE_OPAQUE_KEYWORDS) and not ("tronco" in combined or "fallenlog" in combined or "bench" in combined):
		return "foliage_tree_opaque"
	return "world"


func _is_transparent_or_glass(bm: BaseMaterial3D, mesh_name_lower: String) -> bool:
	if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return true
	if bm.albedo_color.a < 0.98:
		return true
	var mn := bm.resource_name.to_lower()
	if "glass" in mn or "water" in mn or "crystal" in mn or "glass" in mesh_name_lower:
		return true
	return false


func _is_inside_player_rig(node: Node, stop_node: Node) -> bool:
	var p: Node = node
	while p and p != stop_node:
		var ln := p.name.to_lower()
		if "playervr" in ln or "xrorigin" in ln or "xrcontroller" in ln or "functionpointer" in ln:
			return true
		p = p.get_parent()
	return false


func _matches_any(text: String, keywords: Array) -> bool:
	for kw in keywords:
		if kw in text:
			return true
	return false


func _record_mesh_backup(mesh: Mesh, surface_idx: int, orig_mat: Material) -> void:
	var id := mesh.get_rid().get_id()
	if not _orig_mesh_mats.has(id):
		_orig_mesh_mats[id] = {"mesh": mesh, "slots": {}}
	var slots: Dictionary = _orig_mesh_mats[id]["slots"]
	if not slots.has(surface_idx):
		slots[surface_idx] = orig_mat


func _record_override_backup(mi: MeshInstance3D, surface_idx: int, orig_mat: Material) -> void:
	var id := mi.get_instance_id()
	if not _orig_override_mats.has(id):
		_orig_override_mats[id] = {"mi": mi, "surf_ov": {}}
	var rec: Dictionary = _orig_override_mats[id]
	if surface_idx == -1:
		if not rec.has("mat_ov"):
			rec["mat_ov"] = orig_mat
	else:
		var sov: Dictionary = rec["surf_ov"]
		if not sov.has(surface_idx):
			sov[surface_idx] = orig_mat
