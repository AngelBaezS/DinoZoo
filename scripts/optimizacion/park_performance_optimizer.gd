class_name ParkPerformanceOptimizer
extends Node

## ============================================================================
## PARK PERFORMANCE OPTIMIZER — DinoZoo (Godot 4.7 GL Compatibility)
## ============================================================================
## 1. Frustum + Distance Culling unificado (3 niveles) para los 36 dinosaurios:
##    - <= near_always_active_dist (34m): siempre activo + sombras (sin pop-in y reacción temprana a 30m).
##    - <= shadow_cull_distance (62m) en frustum: activo + sombras.
##    - <= max_dist (100m normal / 135m colosales) en frustum: activo sin sombras.
##    - Fuera de vista o > max_dist (+8m histéresis): oculta VisualModel/FoamRing,
##      pausa AnimationPlayer, Skeleton3D, _physics_process, _process y CollisionShape3D.
## 2. Batching espacial automático a MultiMeshInstance3D por chunks (280m isla / 130m hábitats),
##    conservando intactos los StaticBody3D originales para colisiones y fricción.
## 3. Optimización de cast_shadow y visibility_range_end en mallas planas/vidrio/follaje/props.
## ============================================================================

@export_group("Culling de Dinosaurios")
@export var dino_culling_enabled: bool = true
@export var dino_cull_distance: float = 88.0
@export var colossal_cull_distance: float = 125.0
@export var shadow_cull_distance: float = 48.0
@export var near_always_active_dist: float = 34.0
@export var cull_hysteresis: float = 8.0
@export var update_interval: float = 0.10

@export_group("MultiMesh GPU Instancing (Chunks & LOD)")
@export var multimesh_batching_enabled: bool = true
@export var island_chunk_size: float = 360.0
@export var island_lod0_chunk_size: float = 280.0
@export var island_lod1_chunk_size: float = 420.0
@export var habitat_chunk_size: float = 130.0
@export var tree_lod_switch_distance: float = 245.0
@export var merge_habitat_static_meshes: bool = true

@export_group("Sombras y Distancia de Detalles")
@export var optimize_shadows_and_ranges: bool = true
@export var small_prop_visibility_range: float = 100.0
@export var habitat_prop_visibility_range: float = 175.0
@export var habitat_tree_visibility_range: float = 225.0
@export var island_forest_visibility_range: float = 1350.0

enum DinoState { UNSET, ACTIVE_SHADOWS, ACTIVE_NO_SHADOWS, CULLED }

var _dino_entries: Array[Dictionary] = []
var _registered_dinos: Dictionary = {} # instance_id -> true
var _check_timer: float = 0.0
var _mm_container: Node3D
var _initialized: bool = false
var _lod_mesh_map: Dictionary = {} # base_mesh_name (lowercase) -> Mesh

## Estadísticas públicas para depuración / verificación
var batched_mesh_count: int = 0
var multimesh_node_count: int = 0
var shadow_disabled_count: int = 0
var active_dino_count: int = 0
var total_dino_count: int = 0

const COLOSSAL_KEYWORDS := ["titanosaurus", "mosasaurus", "trex", "t_rex", "espinosaurio"]

const SHADOW_OFF_KEYWORDS := [
	"water", "glass", "lawn", "road", "verge", "curb", "mud",
	"fern", "giantfern", "horsetail", "cycad", "bush", "grating",
	"railing", "deck_rail", "mullion", "fence_foundation", "helecho",
	"foam", "waterfall", "plaza", "bench", "lantern", "rock_",
	"cliff", "desert_rock", "boulder", "fallenlog", "trough",
	"feeder", "lod_"
]

const SMALL_PROP_KEYWORDS := [
	"fern", "cycad", "bush", "mud", "trough", "feeder",
	"boulder", "fallenlog", "roca", "tronco", "comedero",
	"carcasa", "helecho", "dirt_rock", "lake_rock", "hill_rock",
	"cave_boulder"
]

const HABITAT_MID_PROP_KEYWORDS := [
	"cave", "watchtower", "deck", "railing", "mullion",
	"post", "pillar", "platform"
]

const HABITAT_TREE_KEYWORDS := [
	"pino", "palmera", "arbol", "pine_front", "pine_back",
	"palm_front", "palm_back", "pine", "palm"
]

func _ready() -> void:
	call_deferred("_initialize_optimizations")

func _initialize_optimizations() -> void:
	if _initialized:
		return
	_initialized = true

	var scene_root := get_parent()
	if not scene_root:
		return

	if optimize_shadows_and_ranges:
		_apply_shadow_and_range_optimizations(scene_root)

	if multimesh_batching_enabled:
		_batch_static_meshes_to_multimesh(scene_root)
		if merge_habitat_static_meshes:
			_merge_static_habitat_meshes(scene_root)

	if dino_culling_enabled:
		_register_all_dinos(scene_root)
		_evaluate_all_dinos(true)

	print("[ParkPerformanceOptimizer] Activo | Dinos=%d | MultiMesh=%d (de %d mallas) | Sombras OFF=%d" % [
		total_dino_count, multimesh_node_count, batched_mesh_count, shadow_disabled_count
	])

## Llamado por ControladorEscenarioPrincipal si el usuario arrastra nuevos hábitats dinámicamente
func register_dynamic_subtree(node: Node) -> void:
	if not _initialized or not is_instance_valid(node):
		return
	if optimize_shadows_and_ranges:
		_apply_shadow_and_range_optimizations(node)
	if multimesh_batching_enabled:
		_batch_static_meshes_to_multimesh(node)
		if merge_habitat_static_meshes:
			_merge_static_habitat_meshes(node)
	if dino_culling_enabled:
		_register_all_dinos(node)
		_evaluate_all_dinos(false)

func _process(delta: float) -> void:
	if not dino_culling_enabled or not _initialized:
		return
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = update_interval
	_evaluate_all_dinos(false)

# ==============================================================================
# 1. CULLING UNIFICADO DE DINOSAURIOS (FRUSTUM + DISTANCIA + HISTÉRESIS)
# ==============================================================================
func _register_all_dinos(root_node: Node) -> void:
	var candidates: Array[Node] = []
	if root_node is CharacterBody3D and root_node.is_in_group("dinosaurios"):
		candidates.append(root_node)
	for child in root_node.find_children("*", "CharacterBody3D", true, false):
		if child.is_in_group("dinosaurios"):
			candidates.append(child)

	for node in candidates:
		var id := node.get_instance_id()
		if _registered_dinos.has(id):
			continue
		_registered_dinos[id] = true
		_register_single_dino(node as CharacterBody3D)

	total_dino_count = _dino_entries.size()

func _register_single_dino(dino: CharacterBody3D) -> void:
	# Ceder el control al optimizador central en los 4 scripts que tenían culling parcial previo
	dino.set_meta("_managed_by_park_optimizer", true)
	dino.set_meta("_perf_active", true)
	if "fov_culling_enabled" in dino:
		dino.set("fov_culling_enabled", false)

	# Recopilar nodos visuales y componentes del dinosaurio
	var visual_model := dino.get_node_or_null("VisualModel") as Node3D
	var visual_nodes: Array[Node3D] = []
	var dino_meshes: Array[MeshInstance3D] = []
	var foam_rings: Array[Node3D] = []
	var colliders: Array[CollisionShape3D] = []

	if visual_model:
		visual_nodes.append(visual_model)
		for m in visual_model.find_children("*", "MeshInstance3D", true, false):
			dino_meshes.append(m as MeshInstance3D)
	else:
		for m in dino.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			visual_nodes.append(mi)
			dino_meshes.append(mi)

	for child in dino.get_children():
		if child is CollisionShape3D:
			colliders.append(child as CollisionShape3D)
		elif child is MeshInstance3D and child != visual_model:
			visual_nodes.append(child as Node3D)
			if child is FoamRingController or "foam" in child.name.to_lower():
				foam_rings.append(child as Node3D)
			else:
				dino_meshes.append(child as MeshInstance3D)

	var anim_players: Array[AnimationPlayer] = []
	for ap in dino.find_children("*", "AnimationPlayer", true, false):
		anim_players.append(ap as AnimationPlayer)

	var skeletons: Array[Skeleton3D] = []
	for sk in dino.find_children("*", "Skeleton3D", true, false):
		skeletons.append(sk as Skeleton3D)

	# Calcular AABB local real (en espacio del CharacterBody3D) para frustum preciso
	var local_aabb := _compute_local_dino_aabb(dino, dino_meshes)
	var max_dim := maxf(local_aabb.size.x, maxf(local_aabb.size.y, local_aabb.size.z))

	# Determinar distancia máxima (gigantes/colosales tienen margen extra de visibilidad)
	var lname := dino.name.to_lower()
	var is_colossal := max_dim >= 12.0
	if not is_colossal:
		for kw in COLOSSAL_KEYWORDS:
			if kw in lname:
				is_colossal = true
				break
	var max_dist := colossal_cull_distance if is_colossal else dino_cull_distance

	# Reutilizar o crear VisibleOnScreenNotifier3D directamente bajo `dino`
	# IMPORTANTE: `dino.visible` permanece SIEMPRE true; solo ocultamos `visual_nodes`
	# para que el VisibleOnScreenNotifier3D siga funcionando en el BVH de C++.
	var old_notifier := dino.get_node_or_null("VisibilityNotifier")
	if old_notifier:
		old_notifier.queue_free()

	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.name = "ParkCullNotifier"
	notifier.aabb = local_aabb.grow(maxf(1.5, max_dim * 0.20))
	dino.add_child(notifier)

	var entry := {
		"dino": dino,
		"notifier": notifier,
		"visual_nodes": visual_nodes,
		"meshes": dino_meshes,
		"foam_rings": foam_rings,
		"colliders": colliders,
		"anim_players": anim_players,
		"skeletons": skeletons,
		"max_dist": max_dist,
		"half_extent": maxf(2.0, max_dim * 0.5),
		"height": maxf(2.0, local_aabb.size.y),
		"orig_process": dino.is_processing() or ("fov_culling_enabled" in dino),
		"state": DinoState.UNSET
	}
	_dino_entries.append(entry)

func _compute_local_dino_aabb(dino: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var inv_dino := dino.global_transform.affine_inverse()
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var found := false
	for mi in meshes:
		if not is_instance_valid(mi) or not mi.mesh:
			continue
		var ab := mi.get_aabb()
		var xf := inv_dino * mi.global_transform
		for x in [ab.position.x, ab.end.x]:
			for y in [ab.position.y, ab.end.y]:
				for z in [ab.position.z, ab.end.z]:
					var p := xf * Vector3(x, y, z)
					mn = mn.min(p)
					mx = mx.max(p)
					found = true
	if not found:
		return AABB(Vector3(-3.0, 0.0, -4.0), Vector3(6.0, 5.0, 8.0))
	return AABB(mn, (mx - mn).max(Vector3(1.5, 1.5, 1.5)))

func _evaluate_all_dinos(force: bool) -> void:
	var vp := get_viewport()
	if not vp:
		return
	var cam := vp.get_camera_3d()
	if not cam:
		return

	var cam_pos := cam.global_position
	var active := 0

	for i in range(_dino_entries.size() - 1, -1, -1):
		var entry: Dictionary = _dino_entries[i]
		var dino_ref = entry["dino"]
		if not is_instance_valid(dino_ref):
			_dino_entries.remove_at(i)
			continue
		var dino: CharacterBody3D = dino_ref as CharacterBody3D

		var pos := dino.global_position
		var dist_sq := pos.distance_squared_to(cam_pos)
		var cur_state: int = entry["state"]
		var is_currently_active := (cur_state == DinoState.ACTIVE_SHADOWS or cur_state == DinoState.ACTIVE_NO_SHADOWS)

		var base_max_dist: float = entry["max_dist"]
		var eff_max_dist := base_max_dist + (cull_hysteresis if is_currently_active else 0.0)
		var eff_shadow_dist := shadow_cull_distance + (cull_hysteresis * 0.5 if cur_state == DinoState.ACTIVE_SHADOWS else 0.0)

		var target_state := DinoState.CULLED

		if dist_sq <= near_always_active_dist * near_always_active_dist:
			# Margen de seguridad inmediato alrededor del jugador
			target_state = DinoState.ACTIVE_SHADOWS
		elif dist_sq <= eff_max_dist * eff_max_dist:
			var notifier: VisibleOnScreenNotifier3D = entry["notifier"]
			var on_screen := false
			if is_instance_valid(notifier) and notifier.is_on_screen():
				on_screen = true
			elif _is_dino_in_frustum_fallback(cam, dino, entry):
				on_screen = true

			if on_screen:
				if dist_sq <= eff_shadow_dist * eff_shadow_dist:
					target_state = DinoState.ACTIVE_SHADOWS
				else:
					target_state = DinoState.ACTIVE_NO_SHADOWS

		if force or target_state != cur_state:
			_apply_dino_state(entry, target_state)

		if entry["state"] != DinoState.CULLED:
			active += 1

	active_dino_count = active
	total_dino_count = _dino_entries.size()

func _is_dino_in_frustum_fallback(cam: Camera3D, dino: Node3D, entry: Dictionary) -> bool:
	var pos := dino.global_position
	if cam.is_position_in_frustum(pos):
		return true
	var h: float = entry["height"]
	if cam.is_position_in_frustum(pos + Vector3(0.0, h * 0.65, 0.0)):
		return true
	var ext: float = entry["half_extent"]
	var fwd := -dino.global_transform.basis.z
	if cam.is_position_in_frustum(pos + fwd * ext):
		return true
	if cam.is_position_in_frustum(pos - fwd * ext):
		return true
	return false

func _apply_dino_state(entry: Dictionary, new_state: int) -> void:
	entry["state"] = new_state
	var dino: CharacterBody3D = entry["dino"]
	var is_active := (new_state != DinoState.CULLED)
	var cast_sh := (new_state == DinoState.ACTIVE_SHADOWS)

	dino.set_meta("_perf_active", is_active)
	if "is_in_view" in dino:
		dino.set("is_in_view", is_active)

	for vn in entry["visual_nodes"]:
		if is_instance_valid(vn):
			(vn as Node3D).visible = is_active

	var shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in entry["meshes"]:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).cast_shadow = shadow_mode

	for fr in entry["foam_rings"]:
		if is_instance_valid(fr):
			(fr as Node3D).set_process(is_active)
			if not is_active:
				(fr as Node3D).visible = false

	for cs in entry["colliders"]:
		if is_instance_valid(cs):
			(cs as CollisionShape3D).set_deferred("disabled", not is_active)

	for sk in entry["skeletons"]:
		if is_instance_valid(sk):
			(sk as Skeleton3D).process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED

	for ap in entry["anim_players"]:
		if is_instance_valid(ap):
			(ap as AnimationPlayer).active = is_active

	dino.set_physics_process(is_active)
	var orig_proc: bool = entry["orig_process"]
	dino.set_process(is_active and orig_proc)

func _discover_lod_templates(root_node: Node) -> void:
	for n in root_node.find_children("LOD_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.visible = false
		mi.set_meta("_is_lod_template", true)
		if mi.mesh:
			var base_key := mi.name.substr(4).to_lower()
			_lod_mesh_map[base_key] = mi.mesh


func _get_lod_mesh_for(mi: MeshInstance3D) -> Mesh:
	if not mi.mesh or _lod_mesh_map.is_empty():
		return null
	var mname := mi.mesh.resource_name.to_lower()
	if _lod_mesh_map.has(mname):
		return _lod_mesh_map[mname] as Mesh
	# Respaldo por sufijo si Godot agregó prefijo al resource_name
	for key in _lod_mesh_map.keys():
		if mname.ends_with(key):
			return _lod_mesh_map[key] as Mesh
	# Respaldo por nombre de nodo
	var ln := mi.name.to_lower()
	if ln.begins_with("araucaria_") and _lod_mesh_map.has("asset_pine"):
		return _lod_mesh_map["asset_pine"] as Mesh
	if ln.begins_with("sequoia_") and _lod_mesh_map.has("asset_pine_light"):
		return _lod_mesh_map["asset_pine_light"] as Mesh
	if (ln.begins_with("dicksonia_") or ln.begins_with("palm_")) and _lod_mesh_map.has("asset_palm"):
		return _lod_mesh_map["asset_palm"] as Mesh
	return null


# ==============================================================================
# 2. OPTIMIZACIÓN DE SOMBRAS Y VISIBILITY RANGES EN MALLAS ESTÁTICAS
# ==============================================================================
func _apply_shadow_and_range_optimizations(root_node: Node) -> void:
	_discover_lod_templates(root_node)

	for m in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.mesh or mi.get_meta("_is_lod_template", false) or _is_inside_dynamic_entity(mi, root_node):
			continue

		var ln := mi.name.to_lower()
		var parent_name := mi.get_parent().name.to_lower() if mi.get_parent() else ""
		var in_island := (parent_name == "escenario2km")

		# A) Desactivar sombras en superficies planas, agua, cristales, terreno lejano, rocas y follaje bajo
		var disable_shadow := (in_island and ln == "terrain")
		if not disable_shadow:
			for kw in SHADOW_OFF_KEYWORDS:
				if kw in ln:
					disable_shadow = true
					break
		if not disable_shadow and not in_island:
			var ab := mi.get_aabb()
			if ab.size.y < 0.25 and not ("terrain" in ln or "pit_floor" in ln):
				disable_shadow = true

		if disable_shadow and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			shadow_disabled_count += 1

		# B) Distancias máximas de renderizado (visibility_range_end) y LOD para detalles menores
		if mi.visibility_range_end > 0.0:
			continue

		if in_island:
			if ln.begins_with("pine_") or ln.begins_with("palm_") or ln.begins_with("decid_") or ln.begins_with("araucaria_") or ln.begins_with("sequoia_") or ln.begins_with("ginkgo_") or ln.begins_with("dicksonia_") or ln.begins_with("giantsequoia_") or ln.begins_with("giantaraucaria_") or ln.begins_with("giantcanopy_") or ln.begins_with("gianttreefern_"):
				if _get_lod_mesh_for(mi) != null:
					mi.visibility_range_end = tree_lod_switch_distance
				else:
					mi.visibility_range_end = island_forest_visibility_range
			elif ln.begins_with("rock_"):
				mi.visibility_range_end = 900.0
			elif ln.begins_with("cycad_") or ln.begins_with("horsetail_"):
				mi.visibility_range_end = 360.0
			elif ln.begins_with("giantfern_"):
				mi.visibility_range_end = 260.0
			elif ln.begins_with("bush_") or ln.begins_with("fern_"):
				mi.visibility_range_end = 210.0
			elif ln.begins_with("lantern_") or ln.begins_with("bench_"):
				mi.visibility_range_end = 230.0
		else:
			var assigned := false
			for kw in SMALL_PROP_KEYWORDS:
				if kw in ln or kw in parent_name:
					mi.visibility_range_end = small_prop_visibility_range
					assigned = true
					break
			if not assigned:
				for kw in HABITAT_TREE_KEYWORDS:
					if kw in ln or kw in parent_name:
						mi.visibility_range_end = habitat_tree_visibility_range
						assigned = true
						break
			if not assigned and not ("outer" in ln or "perimeter" in ln or "diorama" in ln or "curb" in ln or "terrain" in ln or "pit_floor" in ln or "glass" in ln):
				for kw in HABITAT_MID_PROP_KEYWORDS:
					if kw in ln:
						mi.visibility_range_end = habitat_prop_visibility_range
						break

## Reconstruye únicamente los MultiMesh de la isla principal si un hábitat dinámico
## ocultó o restauró árboles/rocas del bioma después de la inicialización.
func rebuild_island_multimeshes(island_root: Node3D) -> void:
	if not _initialized or not multimesh_batching_enabled or not is_instance_valid(island_root):
		return
	if is_instance_valid(_mm_container):
		for child in _mm_container.get_children():
			if child.has_meta("_is_island_mm") and child.get_meta("_is_island_mm"):
				child.queue_free()
	# Restaurar visibilidad de mallas de isla que habían sido agrupadas y no fueron recortadas por un hábitat
	for m in island_root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.has_meta("_batched_island_mm"):
			mi.remove_meta("_batched_island_mm")
			var p := mi.get_parent()
			var carved: bool = bool(mi.get_meta("_carved_by_habitat", false)) \
				or (p != null and bool(p.get_meta("_carved_by_habitat", false)))
			if not carved:
				mi.visible = true
	_batch_static_meshes_to_multimesh(island_root, true)

# ==============================================================================
# 3. BATCHER AUTOMÁTICO A MULTIMESHINSTANCE3D POR CHUNKS ESPACIALES + LOD1
# ==============================================================================
func _batch_static_meshes_to_multimesh(root_node: Node, island_only: bool = false) -> void:
	if not _mm_container:
		_mm_container = Node3D.new()
		_mm_container.name = "OptimizedMultiMeshes"
		var parent_root := get_parent() if get_parent() else root_node
		parent_root.add_child(_mm_container)

	_discover_lod_templates(root_node)
	var groups := {}     # sig -> Array[MeshInstance3D]
	var lod1_groups := {} # sig -> { "mesh": Mesh, "list": Array[MeshInstance3D] }

	for m in root_node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.mesh or not mi.visible or mi.get_meta("_is_lod_template", false):
			continue
		if mi.has_meta("_carved_by_habitat") and mi.get_meta("_carved_by_habitat"):
			continue
		if _is_inside_dynamic_entity(mi, root_node):
			continue
		var m_lower := mi.name.to_lower()
		if mi.name == "WaterSurface" or mi.name == "FoamRing" or "water" in m_lower:
			continue
		# Evitar batching si usa surface_material_override distinto al material del mesh
		if _has_custom_surface_override(mi):
			continue
		# Evitar transformaciones reflejadas (determinante negativo invierte normales)
		if mi.global_transform.basis.determinant() <= 0.0:
			continue

		var pos := mi.global_position
		var is_island := (mi.get_parent() != null and mi.get_parent().name == "Escenario2km")
		if island_only and not is_island:
			continue

		var lod_mesh: Mesh = _get_lod_mesh_for(mi) if is_island else null
		var csz := island_lod0_chunk_size if lod_mesh != null else (island_chunk_size if is_island else habitat_chunk_size)
		var cx := int(floor(pos.x / csz))
		var cz := int(floor(pos.z / csz))

		var ov_id := mi.material_override.get_rid().get_id() if mi.material_override else 0
		var sig := "%d|%d,%d|%d|%d|%d|%d" % [
			1 if is_island else 0,
			cx, cz,
			mi.mesh.get_rid().get_id(),
			mi.cast_shadow,
			int(round(mi.visibility_range_end)),
			ov_id
		]

		if not groups.has(sig):
			groups[sig] = []
		groups[sig].append(mi)

		# Registrar también en chunk amplio LOD1 para horizonte (> tree_lod_switch_distance)
		if lod_mesh != null:
			var lx := int(floor(pos.x / island_lod1_chunk_size))
			var lz := int(floor(pos.z / island_lod1_chunk_size))
			var lsig := "%d,%d|%d" % [lx, lz, lod_mesh.get_rid().get_id()]
			if not lod1_groups.has(lsig):
				lod1_groups[lsig] = {"mesh": lod_mesh, "list": []}
			lod1_groups[lsig]["list"].append(mi)

	for sig in groups.keys():
		var arr: Array = groups[sig]
		var first := arr[0] as MeshInstance3D
		var is_island_group := (first.get_parent() != null and first.get_parent().name == "Escenario2km")
		if arr.size() < 2:
			# Para mallas de isla con chunk pequeño, permitir singleton solo si reduce árboles sueltos no cubiertos por LOD1
			continue
		var centroid := _compute_group_centroid(arr)
		var inv_chunk_xf := Transform3D(Basis.IDENTITY, -centroid)

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = first.mesh
		mm.instance_count = arr.size()

		for idx in range(arr.size()):
			var mi := arr[idx] as MeshInstance3D
			mm.set_instance_transform(idx, inv_chunk_xf * mi.global_transform)
			# Ocultamos solo el MeshInstance3D visual: sus hijos StaticBody3D siguen activos
			mi.visible = false
			if is_island_group:
				mi.set_meta("_batched_island_mm", true)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s_x%d" % [first.name.get_slice("_", 0), arr.size()]
		mmi.position = centroid
		mmi.multimesh = mm
		mmi.cast_shadow = first.cast_shadow
		mmi.material_override = first.material_override
		mmi.visibility_range_end = first.visibility_range_end
		if is_island_group:
			mmi.set_meta("_is_island_mm", true)
		_mm_container.add_child(mmi)

		multimesh_node_count += 1
		batched_mesh_count += arr.size()

	# Instanciar MultiMeshes LOD1 (siluetas 22-50 tris hasta 1400m sin sombras ni viento)
	for lsig in lod1_groups.keys():
		var rec: Dictionary = lod1_groups[lsig]
		var arr: Array = rec["list"]
		if arr.is_empty():
			continue
		var centroid := _compute_group_centroid(arr)
		var inv_chunk_xf := Transform3D(Basis.IDENTITY, -centroid)

		var lod_mm := MultiMesh.new()
		lod_mm.transform_format = MultiMesh.TRANSFORM_3D
		lod_mm.mesh = rec["mesh"] as Mesh
		lod_mm.instance_count = arr.size()
		for idx in range(arr.size()):
			lod_mm.set_instance_transform(idx, inv_chunk_xf * (arr[idx] as MeshInstance3D).global_transform)
		var lod_mmi := MultiMeshInstance3D.new()
		lod_mmi.name = "MM_LOD1_%s_x%d" % [(arr[0] as MeshInstance3D).name.get_slice("_", 0), arr.size()]
		lod_mmi.position = centroid
		lod_mmi.multimesh = lod_mm
		lod_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lod_mmi.visibility_range_begin = maxf(10.0, tree_lod_switch_distance - 45.0)
		lod_mmi.visibility_range_end = island_forest_visibility_range
		lod_mmi.set_meta("_is_island_mm", true)
		_mm_container.add_child(lod_mmi)
		multimesh_node_count += 1


func _compute_group_centroid(arr: Array) -> Vector3:
	var sum := Vector3.ZERO
	for m in arr:
		sum += (m as MeshInstance3D).global_position
	return sum / maxf(1.0, float(arr.size()))


# ==============================================================================
# 4. FUSIÓN DE MALLAS ESTÁTICAS ÚNICAS POR HÁBITAT (DRAG-AND-DROP FRIENDLY)
# ==============================================================================
func _merge_static_habitat_meshes(root_node: Node) -> void:
	var habitats := HabitatTerrainCarver.new().find_all_habitats(root_node)
	for hab in habitats:
		_merge_single_habitat(hab)


func _merge_single_habitat(hab: Node3D) -> void:
	if not is_instance_valid(hab) or hab.has_meta("_merged_static_done"):
		return
	hab.set_meta("_merged_static_done", true)

	var inv_hab := hab.global_transform.affine_inverse()
	var buckets := {} # sig -> { "mat": Material, "sh": int, "vr": float, "items": Array[Dictionary] }
	var source_meshes: Dictionary = {} # instance_id -> { "mi": MeshInstance3D, "total": int, "merged": int }

	for n in hab.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or not mi.mesh:
			continue
		if _is_inside_dynamic_entity(mi, hab):
			continue
		var ln := mi.name.to_lower()
		if "water" in ln or "foam" in ln or "glass" in ln or "window" in ln:
			continue
		if mi.material_override != null:
			continue
		if mi.global_transform.basis.determinant() <= 0.0:
			continue

		var sc := mi.mesh.get_surface_count()
		if sc == 0:
			continue
		# Validar primero que TODAS las superficies sean fusionables (evita duplicados en mallas parciales)
		var can_merge_all := true
		var surf_entries: Array[Dictionary] = []
		for s in range(sc):
			if mi.get_surface_override_material(s) != null or mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				can_merge_all = false
				break
			var mat := mi.mesh.surface_get_material(s)
			if mat == null or (mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
				can_merge_all = false
				break
			surf_entries.append({"surf": s, "mat": mat})
		if not can_merge_all:
			continue

		var rel_xf := inv_hab * mi.global_transform
		var mi_id := mi.get_instance_id()
		source_meshes[mi_id] = {"mi": mi, "total": sc, "merged": 0}

		for se in surf_entries:
			var s: int = se["surf"]
			var mat: Material = se["mat"]
			var sig := "%d|%d|%d" % [mat.get_rid().get_id(), mi.cast_shadow, int(round(mi.visibility_range_end))]
			if not buckets.has(sig):
				buckets[sig] = {"mat": mat, "sh": mi.cast_shadow, "vr": mi.visibility_range_end, "items": []}
			buckets[sig]["items"].append({"mi": mi, "mi_id": mi_id, "surf": s, "xf": rel_xf})

	var merged_container := Node3D.new()
	merged_container.name = "MergedStaticBatches"
	var created_any := false

	for sig in buckets.keys():
		var b: Dictionary = buckets[sig]
		var items: Array = b["items"]
		if items.size() < 2:
			continue

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vert_sum := 0
		var added_items: Array = []

		for it in items:
			var src_mi: MeshInstance3D = it["mi"]
			var s_idx: int = it["surf"]
			var arrs := src_mi.mesh.surface_get_arrays(s_idx)
			var vc: int = (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if arrs.size() > Mesh.ARRAY_VERTEX and arrs[Mesh.ARRAY_VERTEX] != null else 0
			if vc == 0:
				continue
			st.append_from(src_mi.mesh, s_idx, it["xf"])
			vert_sum += vc
			added_items.append(it)

		if added_items.size() < 2 or vert_sum == 0:
			continue

		var out_mesh := st.commit()
		if out_mesh and out_mesh.get_surface_count() > 0:
			out_mesh.surface_set_material(0, b["mat"] as Material)
			var batch_mi := MeshInstance3D.new()
			batch_mi.name = "HabBatch_x%d" % added_items.size()
			batch_mi.mesh = out_mesh
			batch_mi.cast_shadow = b["sh"]
			batch_mi.visibility_range_end = b["vr"]
			merged_container.add_child(batch_mi)
			created_any = true
			multimesh_node_count += 1
			for it in added_items:
				source_meshes[it["mi_id"]]["merged"] += 1

	if not created_any:
		merged_container.free()
		return

	# Ocultar solo los MeshInstance3D cuyas superficies fueron 100% fusionadas (StaticBody3D hijos siguen intactos)
	for mid in source_meshes.keys():
		var rec: Dictionary = source_meshes[mid]
		if rec["merged"] == rec["total"]:
			(rec["mi"] as MeshInstance3D).visible = false
			batched_mesh_count += 1

	hab.add_child(merged_container)

func _is_inside_dynamic_entity(node: Node, stop_node: Node) -> bool:
	var p: Node = node.get_parent()
	while p and p != stop_node:
		if p is CharacterBody3D or p is Skeleton3D or p is RigidBody3D:
			return true
		p = p.get_parent()
	return false

func _has_custom_surface_override(mi: MeshInstance3D) -> bool:
	if not mi.mesh:
		return false
	for s in range(mi.mesh.get_surface_count()):
		if mi.get_surface_override_material(s) != null:
			return true
	return false
