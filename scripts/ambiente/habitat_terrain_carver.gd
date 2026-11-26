@tool
class_name HabitatTerrainCarver
extends RefCounted

## ============================================================================
## HABITAT TERRAIN CARVER — DinoZoo (Editor @tool + Runtime VR)
## ============================================================================
## Detecta automáticamente todos los hábitats agregados a EscenarioPrincipal
## (incluso los arrastrados posteriormente por el usuario) y limpia el área
## exacta debajo de cada hábitat en el ambiente principal:
##   1. Recorte visual pixel-perfect por shader (OBB orientado, cualquier rotación Y)
##      en Terrain-col, Roads y plazas del bioma principal.
##   2. Recorte físico exacto (clipping 2D Sutherland-Hodgman de triángulos del
##      ConcavePolygonShape3D) para que estanques, ríos y acuarios no tengan
##      suelo invisible debajo.
##   3. Ocultamiento automático (y restauración si el hábitat se mueve o borra)
##      de árboles, rocas, arbustos, faroles o bancas del bioma principal dentro
##      del perímetro del hábitat.
## ============================================================================

const CUTOUT_SHADER_PATH := "res://materiales/shaders/terrain_habitat_cutout.gdshader"
const MAX_CUTOUTS := 32

## Margen hacia adentro del borde exterior del hábitat para que el faldón/bordillo
## del recinto encaje sin rendijas contra el terreno principal (0.18m).
var cutout_inset: float = 0.18
## Margen hacia adentro del terreno interior hundido para el recorte FÍSICO (0.65m):
## deja la colisión del terreno principal intacta bajo bordes, aceras y césped exterior
## para evitar grietas o caídas al vacío al caminar cerca de cualquier hábitat.
var physics_cutout_inset: float = 0.65
## Profundidad mínima local (< -0.22m) que debe tener un triángulo caminable (no vertical)
## del terreno interior de un hábitat (estanques, ríos, fosas) para justificar recortar
## la colisión física del terreno principal exactamente en esa depresión.
var physics_depression_threshold: float = -0.22
## Margen extra alrededor del hábitat para despejar árboles/rocas del ambiente principal
## y evitar que ramas o copas invadan las vallas.
var prop_clearance_margin: float = 2.5
## Rango vertical relativo al Y del hábitat donde se aplica el recorte del terreno principal.
var vertical_below_margin: float = 14.0
var vertical_above_margin: float = 18.0

var _cutout_shader: Shader
var _wrapped_meshes: Dictionary = {}        # instance_id -> { s: ShaderMaterial }
var _surface_sample_pts: Dictionary = {}    # instance_id -> Array[Dictionary { "aabb": AABB, "pts": PackedVector3Array }]
var _orig_collision_faces: Dictionary = {}  # instance_id -> { "shape": ConcavePolygonShape3D, "faces": PackedVector3Array, "body": StaticBody3D }
var _last_cutouts: Array[Dictionary] = []

const BASE_MESH_KEYWORDS := [
	"terrain", "lawn", "curb", "pit_floor", "foundation",
	"diorama_base", "main_perimeter", "access_road"
]

const DEPRESSED_INTERIOR_KEYWORDS := [
	"terrain_mesh", "enclosure_terrain", "trex_terrain",
	"pit_floor", "pond_bed", "river_bed", "basin"
]

const CARVABLE_SURFACE_NAMES := [
	"terrain-col", "terrain", "roads", "zoo_walkways", "park_central_plaza-col", "park_central_plaza",
	"marine_promenade-col", "marine_promenade"
]

const PROTECTED_ISLAND_NAMES := [
	"terrain-col", "terrain", "roads", "zoo_walkways", "water", "bridges-col", "bridges",
	"park_welcome_arch-col", "park_welcome_arch",
	"zoo_arch_", "marine_promenade",
	"park_central_plaza-col", "park_central_plaza",
	"desert_stone_arch", "waterfall"
]


static func is_habitat_node(node: Node) -> bool:
	if not (node is Node3D) or not is_instance_valid(node):
		return false
	var ln := node.name.to_lower()
	if ln.begins_with("habitat"):
		return true
	if node.scene_file_path != "" and "habitat_" in node.scene_file_path.to_lower():
		return true
	if node.is_in_group("habitats"):
		return true
	if node.has_node("Enclosure") or node.has_node("PaddockEnclosure") or node.has_node("EnclosureTRex"):
		return true
	return false


func find_all_habitats(scene_root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not is_instance_valid(scene_root):
		return result
	for child in scene_root.get_children():
		if is_habitat_node(child):
			result.append(child as Node3D)
		elif child is Node3D and not _is_island_root(child):
			# Permitir que el usuario agrupe hábitats dentro de un nodo carpeta (ej. "Habitats")
			for sub in child.get_children():
				if is_habitat_node(sub):
					result.append(sub as Node3D)
	return result


func find_island_root(scene_root: Node) -> Node3D:
	if not is_instance_valid(scene_root):
		return null
	var direct := scene_root.get_node_or_null("Escenario2km")
	if direct is Node3D:
		return direct as Node3D
	for child in scene_root.get_children():
		if child is Node3D and _is_island_root(child):
			return child as Node3D
	return null


func _is_island_root(node: Node) -> bool:
	var ln := node.name.to_lower()
	return "escenario2km" in ln or "bioma" in ln or ("escenario_2km" in node.scene_file_path.to_lower())


## Recalcula y aplica los recortes visuales, físicos (en runtime) y limpieza de props
## para todos los hábitats actuales bajo `scene_root`.
func refresh_cutouts(scene_root: Node3D, island_root: Node3D = null, carve_physics: bool = true) -> Dictionary:
	var stats := {
		"habitats": 0,
		"props_hidden": 0,
		"props_restored": 0,
		"collision_tris_before": 0,
		"collision_tris_after": 0
	}
	if not is_instance_valid(scene_root) or not scene_root.is_inside_tree():
		return stats
	if island_root == null:
		island_root = find_island_root(scene_root)
	if not is_instance_valid(island_root) or not island_root.is_inside_tree():
		return stats

	var habitats := find_all_habitats(scene_root)
	var cutouts: Array[Dictionary] = []
	var physics_cutouts: Array[Dictionary] = []
	for hab in habitats:
		if cutouts.size() >= MAX_CUTOUTS:
			break
		if not hab.is_inside_tree():
			continue
		var obb := compute_habitat_obb(hab)
		if not obb.is_empty():
			cutouts.append(obb)
		if carve_physics and not Engine.is_editor_hint():
			var phys_obb := compute_habitat_physics_obb(hab)
			if not phys_obb.is_empty():
				physics_cutouts.append(phys_obb)

	_last_cutouts = cutouts
	stats["habitats"] = cutouts.size()

	# 1. Recorte visual pixel-perfect por shader en Terrain-col y Roads
	_apply_visual_cutouts(island_root, cutouts)

	# 2. Limpieza automática de árboles, rocas, arbustos y props del bioma principal
	var prop_res := _clear_overlapping_island_props(island_root, cutouts)
	stats["props_hidden"] = prop_res["hidden"]
	stats["props_restored"] = prop_res["restored"]

	# 3. Recorte exacto de colisión trimesh (solo en interiores hundidos con colisión propia)
	if carve_physics and not Engine.is_editor_hint():
		var phys_res := _carve_terrain_collisions(island_root, physics_cutouts)
		stats["collision_tris_before"] = phys_res["before"]
		stats["collision_tris_after"] = phys_res["after"]

	return stats


func _get_enclosure_root(habitat: Node3D) -> Node3D:
	var enclosure_root: Node3D = habitat.get_node_or_null("Enclosure") as Node3D
	if not enclosure_root:
		enclosure_root = habitat.get_node_or_null("PaddockEnclosure") as Node3D
	if not enclosure_root:
		enclosure_root = habitat.get_node_or_null("EnclosureTRex") as Node3D
	if not enclosure_root:
		enclosure_root = habitat
	return enclosure_root


func _build_obb_dict(habitat: Node3D, mn: Vector3, mx: Vector3, inset: float) -> Dictionary:
	# Escala en XZ del nodo hábitat
	var bx := habitat.global_transform.basis.x
	var bz := habitat.global_transform.basis.z
	var scale_x := Vector2(bx.x, bx.z).length()
	var scale_z := Vector2(bz.x, bz.z).length()
	if scale_x < 0.001 or scale_z < 0.001:
		return {}

	var axis_x := Vector2(bx.x, bx.z).normalized()
	var axis_z := Vector2(-axis_x.y, axis_x.x)

	var local_center := Vector3((mn.x + mx.x) * 0.5, 0.0, (mn.z + mx.z) * 0.5)
	var world_center := habitat.global_transform * local_center

	var raw_half_x := (mx.x - mn.x) * 0.5 * scale_x
	var raw_half_z := (mx.z - mn.z) * 0.5 * scale_z
	var half_x := raw_half_x - inset
	var half_z := raw_half_z - inset
	if half_x < 1.0 or half_z < 1.0:
		return {}

	var hab_y := habitat.global_position.y
	var min_y := hab_y - vertical_below_margin
	var max_y := hab_y + vertical_above_margin

	# AABB mundial conservador en XZ para descarte O(1) rápido
	var wx_ext := absf(axis_x.x) * half_x + absf(axis_z.x) * half_z
	var wz_ext := absf(axis_x.y) * half_x + absf(axis_z.y) * half_z

	return {
		"name": habitat.name,
		"node": habitat,
		"center_xz": Vector2(world_center.x, world_center.z),
		"axis_x": axis_x,
		"axis_z": axis_z,
		"half_x": half_x,
		"half_z": half_z,
		"raw_half_x": raw_half_x,
		"raw_half_z": raw_half_z,
		"min_y": min_y,
		"max_y": max_y,
		"world_min_x": world_center.x - wx_ext,
		"world_max_x": world_center.x + wx_ext,
		"world_min_z": world_center.z - wz_ext,
		"world_max_z": world_center.z + wz_ext,
	}


func _mesh_has_physics_collider(mi: MeshInstance3D) -> bool:
	for child in mi.get_children():
		if child is StaticBody3D:
			for sub in child.get_children():
				if sub is CollisionShape3D and (sub as CollisionShape3D).shape != null and not (sub as CollisionShape3D).disabled:
					return true
	var parent := mi.get_parent()
	if parent is StaticBody3D:
		for sub in parent.get_children():
			if sub is CollisionShape3D and (sub as CollisionShape3D).shape != null and not (sub as CollisionShape3D).disabled:
				return true
	return false


## Calcula la caja orientada (OBB) exacta en mundo del perímetro base de un hábitat
## (usada para recorte visual por shader y limpieza de árboles/rocas).
func compute_habitat_obb(habitat: Node3D) -> Dictionary:
	if not is_instance_valid(habitat) or not habitat.is_inside_tree():
		return {}

	var enclosure_root := _get_enclosure_root(habitat)
	var inv_hab := habitat.global_transform.affine_inverse()
	var base_min := Vector3(1e9, 1e9, 1e9)
	var base_max := Vector3(-1e9, -1e9, -1e9)
	var found_base := false

	var fallback_min := Vector3(1e9, 1e9, 1e9)
	var fallback_max := Vector3(-1e9, -1e9, -1e9)
	var found_fallback := false

	for child in enclosure_root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if not is_instance_valid(mi) or not mi.mesh:
			continue
		if _is_inside_dynamic_node(mi, habitat):
			continue
		var ln := mi.name.to_lower()
		if "foam" in ln or "water" in ln:
			continue

		var ab := mi.get_aabb()
		if ab.size.length_squared() < 0.01:
			continue

		var xf := inv_hab * mi.global_transform
		var is_base := false
		for kw in BASE_MESH_KEYWORDS:
			if kw in ln:
				is_base = true
				break

		for x in [ab.position.x, ab.end.x]:
			for y in [ab.position.y, ab.end.y]:
				for z in [ab.position.z, ab.end.z]:
					var p := xf * Vector3(x, y, z)
					fallback_min = fallback_min.min(p)
					fallback_max = fallback_max.max(p)
					found_fallback = true
					if is_base:
						base_min = base_min.min(p)
						base_max = base_max.max(p)
						found_base = true

	if not found_base and not found_fallback:
		return {}

	var mn := base_min if found_base else fallback_min
	var mx := base_max if found_base else fallback_max
	return _build_obb_dict(habitat, mn, mx, cutout_inset)


## Calcula el OBB estricto para recorte de colisión FÍSICA:
## Solo recorta el terreno principal exactamente sobre los triángulos caminables hundidos
## (estanques, ríos o fosas con |normal.y| > 0.35 y centroide Y < physics_depression_threshold)
## dentro de mallas con StaticBody3D propio, siempre acotados hacia adentro del borde de la
## malla por `physics_cutout_inset`. Así, los bordes exteriores, esquinas redondeadas, aceras
## y hábitats planos conservan doble respaldo físico y jamás provocan caídas al vacío.
func compute_habitat_physics_obb(habitat: Node3D) -> Dictionary:
	if not is_instance_valid(habitat) or not habitat.is_inside_tree():
		return {}

	var enclosure_root := _get_enclosure_root(habitat)
	var inv_hab := habitat.global_transform.affine_inverse()
	var dep_min := Vector3(1e9, 1e9, 1e9)
	var dep_max := Vector3(-1e9, -1e9, -1e9)
	var found_depressed := false

	for child in enclosure_root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if not is_instance_valid(mi) or not mi.mesh:
			continue
		if _is_inside_dynamic_node(mi, habitat):
			continue
		var ln := mi.name.to_lower()
		if "foam" in ln or "water" in ln:
			continue

		var is_interior_ground := false
		for kw in DEPRESSED_INTERIOR_KEYWORDS:
			if kw in ln:
				is_interior_ground = true
				break
		if not is_interior_ground:
			continue

		# Nunca abrir hueco físico si la malla interior no posee colisión física propia
		if not _mesh_has_physics_collider(mi):
			continue

		var ab := mi.get_aabb()
		if ab.size.length_squared() < 0.01:
			continue

		var xf := inv_hab * mi.global_transform
		var mesh_min := Vector3(1e9, 1e9, 1e9)
		var mesh_max := Vector3(-1e9, -1e9, -1e9)
		for x in [ab.position.x, ab.end.x]:
			for y in [ab.position.y, ab.end.y]:
				for z in [ab.position.z, ab.end.z]:
					var p := xf * Vector3(x, y, z)
					mesh_min = mesh_min.min(p)
					mesh_max = mesh_max.max(p)

		# Descarte O(1): si la malla no baja del umbral, no necesita hueco físico
		if mesh_min.y >= physics_depression_threshold:
			continue

		# Recorrer únicamente triángulos caminables hundidos (ignora faldones verticales y bordes planos)
		var faces := mi.mesh.get_faces()
		var tri_min := Vector3(1e9, 1e9, 1e9)
		var tri_max := Vector3(-1e9, -1e9, -1e9)
		var has_dep_tris := false
		var fi := 0
		var fcount := faces.size()
		while fi + 2 < fcount:
			var p0 := xf * faces[fi]
			var p1 := xf * faces[fi + 1]
			var p2 := xf * faces[fi + 2]
			fi += 3
			var nrm := (p1 - p0).cross(p2 - p0)
			if nrm.length_squared() < 1e-8:
				continue
			nrm = nrm.normalized()
			var cy := (p0.y + p1.y + p2.y) / 3.0
			if absf(nrm.y) > 0.35 and cy < physics_depression_threshold:
				tri_min = tri_min.min(p0).min(p1).min(p2)
				tri_max = tri_max.max(p0).max(p1).max(p2)
				has_dep_tris = true

		if not has_dep_tris:
			continue

		# Acotar siempre dentro del perímetro seguro de la malla (margen physics_cutout_inset)
		# y contraer ligeramente hacia adentro del vaso hundido (0.35m) para evitar esquinas redondeadas
		var safe_min_x := maxf(tri_min.x + 0.35, mesh_min.x + physics_cutout_inset)
		var safe_max_x := minf(tri_max.x - 0.35, mesh_max.x - physics_cutout_inset)
		var safe_min_z := maxf(tri_min.z + 0.35, mesh_min.z + physics_cutout_inset)
		var safe_max_z := minf(tri_max.z - 0.35, mesh_max.z - physics_cutout_inset)
		if safe_max_x - safe_min_x < 1.0 or safe_max_z - safe_min_z < 1.0:
			continue

		dep_min = dep_min.min(Vector3(safe_min_x, tri_min.y, safe_min_z))
		dep_max = dep_max.max(Vector3(safe_max_x, tri_max.y, safe_max_z))
		found_depressed = true

	if not found_depressed:
		return {}

	return _build_obb_dict(habitat, dep_min, dep_max, 0.0)


func get_habitat_transform_signature(scene_root: Node) -> String:
	var parts: PackedStringArray = []
	for hab in find_all_habitats(scene_root):
		var p := hab.global_position
		var r := hab.global_rotation
		var s := hab.scale
		parts.append("%d:%.2f,%.2f,%.2f|%.3f|%.2f,%.2f" % [
			hab.get_instance_id(), p.x, p.y, p.z, r.y, s.x, s.z
		])
	return ";".join(parts)


func get_last_cutouts() -> Array[Dictionary]:
	return _last_cutouts


# ==============================================================================
# 1. RECORTE VISUAL PIXEL-PERFECT POR SHADER
# ==============================================================================
func _ensure_shader() -> Shader:
	if _cutout_shader == null:
		_cutout_shader = load(CUTOUT_SHADER_PATH) as Shader
	return _cutout_shader


func _apply_visual_cutouts(island_root: Node3D, cutouts: Array[Dictionary]) -> void:
	var shader := _ensure_shader()
	if not shader:
		push_warning("[HabitatTerrainCarver] No se encontró shader: " + CUTOUT_SHADER_PATH)
		return

	# Preparar arrays uniformes fijos de tamaño MAX_CUTOUTS
	var centers_rot: Array[Vector4] = []
	var extents_y: Array[Vector4] = []
	centers_rot.resize(MAX_CUTOUTS)
	extents_y.resize(MAX_CUTOUTS)

	var count := mini(cutouts.size(), MAX_CUTOUTS)
	var g_min_x := 1e9
	var g_max_x := -1e9
	var g_min_z := 1e9
	var g_max_z := -1e9
	for i in range(MAX_CUTOUTS):
		if i < count:
			var c: Dictionary = cutouts[i]
			var ctr: Vector2 = c["center_xz"]
			var ax: Vector2 = c["axis_x"]
			centers_rot[i] = Vector4(ctr.x, ctr.y, ax.x, ax.y)
			extents_y[i] = Vector4(c["half_x"], c["half_z"], c["min_y"], c["max_y"])
			g_min_x = minf(g_min_x, c["world_min_x"])
			g_max_x = maxf(g_max_x, c["world_max_x"])
			g_min_z = minf(g_min_z, c["world_min_z"])
			g_max_z = maxf(g_max_z, c["world_max_z"])
		else:
			centers_rot[i] = Vector4.ZERO
			extents_y[i] = Vector4.ZERO

	var global_bounds := Vector4(g_min_x, g_max_x, g_min_z, g_max_z) if count > 0 else Vector4(1.0, -1.0, 1.0, -1.0)

	# Buscar superficies recortables del ambiente principal (Terrain-col, Roads, etc.)
	for child in island_root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if not is_instance_valid(mi) or not mi.mesh:
			continue
		var ln := mi.name.to_lower()
		var carvable := false
		for cname in CARVABLE_SURFACE_NAMES:
			if ln == cname:
				carvable = true
				break
		if not carvable:
			continue

		var smats := _get_or_wrap_mesh_materials(mi, shader, cutouts)
		for smat in smats:
			smat.set_shader_parameter("cutout_count", count)
			smat.set_shader_parameter("all_cutouts_bounds", global_bounds)
			smat.set_shader_parameter("cutout_centers_rot", centers_rot)
			smat.set_shader_parameter("cutout_extents_y", extents_y)


func _get_surface_sample_data(mi: MeshInstance3D) -> Array[Dictionary]:
	var id := mi.get_instance_id()
	if _surface_sample_pts.has(id):
		return _surface_sample_pts[id]
	var data: Array[Dictionary] = []
	var xf := mi.global_transform
	var mesh := mi.mesh
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX else PackedVector3Array()
		if verts.is_empty():
			data.append({"aabb": AABB(), "pts": PackedVector3Array()})
			continue
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		var w_pts := PackedVector3Array()
		w_pts.resize(verts.size())
		for i in range(verts.size()):
			var w := xf * verts[i]
			w_pts[i] = w
			mn = mn.min(w)
			mx = mx.max(w)
		data.append({"aabb": AABB(mn, mx - mn), "pts": w_pts})
	_surface_sample_pts[id] = data
	return data


func _surface_overlaps_any_cutout(surf_info: Dictionary, cutouts: Array[Dictionary]) -> bool:
	var ab: AABB = surf_info["aabb"]
	if cutouts.is_empty() or ab.size == Vector3.ZERO:
		return false
	var any_aabb := false
	for c in cutouts:
		if ab.end.x >= c["world_min_x"] and ab.position.x <= c["world_max_x"] \
			and ab.end.z >= c["world_min_z"] and ab.position.z <= c["world_max_z"] \
			and ab.end.y >= c["min_y"] and ab.position.y <= c["max_y"]:
			any_aabb = true
			break
	if not any_aabb:
		return false

	# Comprobación precisa por vértice (con margen 16m de triángulo) para descartar montañas lejanas
	var pts: PackedVector3Array = surf_info["pts"]
	for v in pts:
		if _point_inside_any_obb(Vector2(v.x, v.z), v.y, cutouts, 18.0):
			return true
	return false


func _get_or_wrap_mesh_materials(mi: MeshInstance3D, shader: Shader, cutouts: Array[Dictionary]) -> Array[ShaderMaterial]:
	var id := mi.get_instance_id()
	var cache: Dictionary = _wrapped_meshes.get(id, {})
	var surf_data := _get_surface_sample_data(mi)
	var result: Array[ShaderMaterial] = []
	var surf_count := mi.mesh.get_surface_count()

	for s in range(surf_count):
		var overlaps := _surface_overlaps_any_cutout(surf_data[s], cutouts)
		if not overlaps:
			# Dejar la superficie sin shader discard para conservar Early-Z en GPU (montañas, desierto, pedestal)
			if cache.has(s) and mi.get_surface_override_material(s) == cache[s]:
				mi.set_surface_override_material(s, null)
			continue

		if cache.has(s):
			var cached_mat: ShaderMaterial = cache[s]
			if mi.get_surface_override_material(s) != cached_mat:
				mi.set_surface_override_material(s, cached_mat)
			result.append(cached_mat)
			continue

		var existing := mi.get_active_material(s)
		var smat := ShaderMaterial.new()
		smat.shader = shader
		if existing is BaseMaterial3D:
			var bm := existing as BaseMaterial3D
			smat.set_shader_parameter("albedo_color", bm.albedo_color)
			smat.set_shader_parameter("roughness_val", bm.roughness)
			smat.set_shader_parameter("metallic_val", bm.metallic)
			if bm.albedo_texture:
				smat.set_shader_parameter("use_albedo_tex", true)
				smat.set_shader_parameter("albedo_tex", bm.albedo_texture)
		elif existing is ShaderMaterial:
			var esm := existing as ShaderMaterial
			if esm.shader == shader:
				smat = esm
			else:
				var col_val = esm.get_shader_parameter("albedo_color")
				if col_val is Color:
					smat.set_shader_parameter("albedo_color", col_val)
		cache[s] = smat
		mi.set_surface_override_material(s, smat)
		result.append(smat)

	_wrapped_meshes[id] = cache
	return result


# ==============================================================================
# 2. LIMPIEZA AUTOMÁTICA DE ÁRBOLES, ROCAS Y PROPS DEL BIOMA PRINCIPAL
# ==============================================================================
func _clear_overlapping_island_props(island_root: Node3D, cutouts: Array[Dictionary]) -> Dictionary:
	var hidden_count := 0
	var restored_count := 0

	for child in island_root.get_children():
		if not (child is Node3D) or not is_instance_valid(child):
			continue
		var ln := child.name.to_lower()
		var protected := false
		for pname in PROTECTED_ISLAND_NAMES:
			if ln == pname or ln.begins_with(pname):
				protected = true
				break
		if protected:
			continue

		var prop := child as Node3D
		var pos := prop.global_position
		var inside := _point_inside_any_obb(Vector2(pos.x, pos.z), pos.y, cutouts, prop_clearance_margin)

		if inside:
			if not bool(prop.get_meta("_carved_by_habitat", false)):
				prop.visible = false
				prop.set_meta("_carved_by_habitat", true)
				_set_subtree_colliders_disabled(prop, true)
				hidden_count += 1
		else:
			if bool(prop.get_meta("_carved_by_habitat", false)):
				prop.visible = true
				prop.remove_meta("_carved_by_habitat")
				_set_subtree_colliders_disabled(prop, false)
				restored_count += 1

	return {"hidden": hidden_count, "restored": restored_count}


func _set_subtree_colliders_disabled(node: Node, disabled: bool) -> void:
	for cs in node.find_children("*", "CollisionShape3D", true, false):
		(cs as CollisionShape3D).disabled = disabled


func _point_inside_any_obb(pt_xz: Vector2, pt_y: float, cutouts: Array[Dictionary], extra_margin: float) -> bool:
	for c in cutouts:
		if pt_y < c["min_y"] or pt_y > c["max_y"]:
			continue
		var d := pt_xz - (c["center_xz"] as Vector2)
		var ax: Vector2 = c["axis_x"]
		var az: Vector2 = c["axis_z"]
		var lx := d.dot(ax)
		var lz := d.dot(az)
		if absf(lx) <= (c["raw_half_x"] + extra_margin) and absf(lz) <= (c["raw_half_z"] + extra_margin):
			return true
	return false


# ==============================================================================
# 3. RECORTE FÍSICO EXACTO DE COLISIONES TRIMESH (CLIPPING 2D POR OBB)
# ==============================================================================
func _carve_terrain_collisions(island_root: Node3D, cutouts: Array[Dictionary]) -> Dictionary:
	var tris_before := 0
	var tris_after := 0

	for node in island_root.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if not is_instance_valid(body):
			continue
		var parent_ln := body.get_parent().name.to_lower() if body.get_parent() else ""
		var body_ln := body.name.to_lower()
		var is_terrain := (parent_ln == "terrain-col" or parent_ln == "terrain" or body_ln == "terrain-col" or parent_ln == "roads")
		if not is_terrain:
			continue

		for child in body.get_children():
			if not (child is CollisionShape3D):
				continue
			var cs := child as CollisionShape3D
			if not (cs.shape is ConcavePolygonShape3D):
				continue

			var cs_id := cs.get_instance_id()
			var orig_faces: PackedVector3Array
			var working_shape: ConcavePolygonShape3D

			if _orig_collision_faces.has(cs_id):
				orig_faces = _orig_collision_faces[cs_id]["faces"]
				working_shape = _orig_collision_faces[cs_id]["shape"]
			else:
				var src_shape := cs.shape as ConcavePolygonShape3D
				orig_faces = src_shape.get_faces().duplicate()
				# Duplicar el recurso en memoria para no modificar el .scn importado
				working_shape = src_shape.duplicate() as ConcavePolygonShape3D
				cs.shape = working_shape
				_orig_collision_faces[cs_id] = {
					"shape": working_shape,
					"faces": orig_faces,
					"body": body
				}

			tris_before += orig_faces.size() / 3
			if cutouts.is_empty():
				working_shape.set_faces(orig_faces)
				tris_after += orig_faces.size() / 3
				continue

			var xf := cs.global_transform
			var inv_xf := xf.affine_inverse()
			var out_faces := _filter_and_clip_faces(orig_faces, xf, inv_xf, cutouts)
			working_shape.set_faces(out_faces)
			tris_after += out_faces.size() / 3

	return {"before": tris_before, "after": tris_after}


func _filter_and_clip_faces(orig_faces: PackedVector3Array, to_world: Transform3D, to_local: Transform3D, cutouts: Array[Dictionary]) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := orig_faces.size()
	var i := 0
	while i + 2 < n:
		var w0 := to_world * orig_faces[i]
		var w1 := to_world * orig_faces[i + 1]
		var w2 := to_world * orig_faces[i + 2]
		i += 3

		# Descarte AABB ultra rápido contra la unión de los OBBs
		var t_min_x := minf(w0.x, minf(w1.x, w2.x))
		var t_max_x := maxf(w0.x, maxf(w1.x, w2.x))
		var t_min_z := minf(w0.z, minf(w1.z, w2.z))
		var t_max_z := maxf(w0.z, maxf(w1.z, w2.z))
		var t_min_y := minf(w0.y, minf(w1.y, w2.y))
		var t_max_y := maxf(w0.y, maxf(w1.y, w2.y))

		var active_obbs: Array[Dictionary] = []
		for c in cutouts:
			if t_max_x < c["world_min_x"] or t_min_x > c["world_max_x"]:
				continue
			if t_max_z < c["world_min_z"] or t_min_z > c["world_max_z"]:
				continue
			if t_max_y < c["min_y"] or t_min_y > c["max_y"]:
				continue
			active_obbs.append(c)

		if active_obbs.is_empty():
			out.append(orig_faces[i - 3])
			out.append(orig_faces[i - 2])
			out.append(orig_faces[i - 1])
			continue

		# Recortar progresivamente el triángulo (o sub-triángulos) contra cada OBB que lo solapa
		var tris: Array = [[w0, w1, w2]]
		for c in active_obbs:
			var next_tris: Array = []
			for tri in tris:
				var pieces := _subtract_obb_from_triangle(tri[0], tri[1], tri[2], c)
				for piece in pieces:
					next_tris.append(piece)
			tris = next_tris
			if tris.is_empty():
				break

		for tri in tris:
			out.append(to_local * (tri[0] as Vector3))
			out.append(to_local * (tri[1] as Vector3))
			out.append(to_local * (tri[2] as Vector3))

	return out


func _subtract_obb_from_triangle(w0: Vector3, w1: Vector3, w2: Vector3, obb: Dictionary) -> Array:
	var ctr: Vector2 = obb["center_xz"]
	var ax: Vector2 = obb["axis_x"]
	var az: Vector2 = obb["axis_z"]
	var hx: float = obb["half_x"]
	var hz: float = obb["half_z"]

	# Transformar los 3 vértices al espacio local del OBB: (lx, world_y, lz)
	var p0 := _world_to_obb_local(w0, ctr, ax, az)
	var p1 := _world_to_obb_local(w1, ctr, ax, az)
	var p2 := _world_to_obb_local(w2, ctr, ax, az)

	# Si todos los vértices están completamente fuera por un mismo lado -> conservar íntegro
	if (p0.x <= -hx and p1.x <= -hx and p2.x <= -hx) or \
	   (p0.x >= hx and p1.x >= hx and p2.x >= hx) or \
	   (p0.z <= -hz and p1.z <= -hz and p2.z <= -hz) or \
	   (p0.z >= hz and p1.z >= hz and p2.z >= hz):
		return [[w0, w1, w2]]

	# Si todos los vértices están estrictamente dentro -> eliminar por completo
	if absf(p0.x) <= hx and absf(p0.z) <= hz and \
	   absf(p1.x) <= hx and absf(p1.z) <= hz and \
	   absf(p2.x) <= hx and absf(p2.z) <= hz:
		return []

	# Particionar el complemento exterior de [-hx, hx] x [-hz, hz] en 4 regiones convexas disjuntas
	var tri_poly: Array[Vector3] = [p0, p1, p2]
	var regions: Array = []

	# Región 1: x <= -hx
	var reg_l := _clip_poly_plane(tri_poly, 0, -hx, false)
	if reg_l.size() >= 3:
		regions.append(reg_l)

	# Región 2: x >= +hx
	var reg_r := _clip_poly_plane(tri_poly, 0, hx, true)
	if reg_r.size() >= 3:
		regions.append(reg_r)

	# Franja central: -hx <= x <= +hx
	var mid := _clip_poly_plane(_clip_poly_plane(tri_poly, 0, -hx, true), 0, hx, false)
	if mid.size() >= 3:
		# Región 3: z <= -hz
		var reg_b := _clip_poly_plane(mid, 2, -hz, false)
		if reg_b.size() >= 3:
			regions.append(reg_b)
		# Región 4: z >= +hz
		var reg_t := _clip_poly_plane(mid, 2, hz, true)
		if reg_t.size() >= 3:
			regions.append(reg_t)

	# Triangular polígonos exteriores resultantes y volver a espacio mundial
	var result: Array = []
	for poly in regions:
		var a := _obb_local_to_world(poly[0], ctr, ax, az)
		for k in range(1, poly.size() - 1):
			var b := _obb_local_to_world(poly[k], ctr, ax, az)
			var c_pt := _obb_local_to_world(poly[k + 1], ctr, ax, az)
			# Descartar triángulos degenerados de área casi cero
			if (b - a).cross(c_pt - a).length_squared() > 1e-4:
				result.append([a, b, c_pt])
	return result


func _world_to_obb_local(w: Vector3, ctr: Vector2, ax: Vector2, az: Vector2) -> Vector3:
	var d := Vector2(w.x - ctr.x, w.z - ctr.y)
	return Vector3(d.dot(ax), w.y, d.dot(az))


func _obb_local_to_world(p: Vector3, ctr: Vector2, ax: Vector2, az: Vector2) -> Vector3:
	var wx := ctr.x + ax.x * p.x + az.x * p.z
	var wz := ctr.y + ax.y * p.x + az.y * p.z
	return Vector3(wx, p.y, wz)


## Recorta un polígono convexo 3D (con Y interpolado) contra el semiplano axis >= val (keep_greater=true)
## o axis <= val (keep_greater=false), donde axis=0 es X y axis=2 es Z.
func _clip_poly_plane(poly: Array[Vector3], axis: int, val: float, keep_greater: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var count := poly.size()
	if count < 3:
		return out

	for i in range(count):
		var curr := poly[i]
		var prev := poly[(i + count - 1) % count]
		var cv := curr.x if axis == 0 else curr.z
		var pv := prev.x if axis == 0 else prev.z
		var curr_in := (cv >= val) if keep_greater else (cv <= val)
		var prev_in := (pv >= val) if keep_greater else (pv <= val)

		if curr_in:
			if not prev_in:
				var denom := cv - pv
				if absf(denom) > 1e-6:
					var t := clampf((val - pv) / denom, 0.0, 1.0)
					out.append(prev.lerp(curr, t))
			out.append(curr)
		elif prev_in:
			var denom := cv - pv
			if absf(denom) > 1e-6:
				var t := clampf((val - pv) / denom, 0.0, 1.0)
				out.append(prev.lerp(curr, t))
	return out


func _is_inside_dynamic_node(node: Node, stop_node: Node) -> bool:
	var p: Node = node.get_parent()
	while p and p != stop_node:
		if p is CharacterBody3D or p is Skeleton3D or p is RigidBody3D:
			return true
		p = p.get_parent()
	return false
