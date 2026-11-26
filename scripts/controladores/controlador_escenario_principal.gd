@tool
extends Node3D

## ============================================================================
## CONTROLADOR ESCENARIO PRINCIPAL 2KM x 2KM — DinoZoo VR
## ============================================================================
## Gestiona el bioma principal, la sanitización de hábitats, la fricción VR,
## la optimización MultiMesh/Culling y el RECORTE AUTOMÁTICO DEL TERRENO bajo
## cualquier hábitat existente o añadido dinámicamente (en Editor y en Runtime).
## ============================================================================

@export_group("Estilo Visual Animado (Low-Poly Toon)")
## Reemplaza los materiales PBR estándar por el shader ligero estilizado tipo animación 3D
## (cel-shading de 3 bandas + rim light + cascadas animadas), conservando 100% del batching MultiMesh.
@export var estilo_animado_activo: bool = true:
	set(value):
		estilo_animado_activo = value
		if is_inside_tree():
			aplicar_estilo_animado()
## Brisa sutil en vértices para árboles, palmeras, arbustos y helechos (casi 0 costo en GPU).
@export var animacion_viento_follaje: bool = true:
	set(value):
		animacion_viento_follaje = value
		if is_inside_tree() and estilo_animado_activo:
			aplicar_estilo_animado()

@export_group("Recorte Automático de Terreno bajo Hábitats")
## Si está activo, recorta automáticamente el terreno principal y oculta árboles/rocas
## debajo de cada hábitat para evitar solapamientos, z-fighting y hundimientos.
@export var auto_recortar_terreno_habitats: bool = true
## Altura exacta de la planicie central donde descansan los hábitats (38.0m).
@export var altura_planicie_principal: float = 38.0
## Margen interior del recorte respecto al borde exterior del hábitat (evita rendijas).
@export var margen_borde_recorte: float = 0.18
## Margen adicional alrededor de cada hábitat para despejar árboles y rocas del bioma.
@export var margen_despeje_props: float = 2.5
## Botón de Inspector (Editor): haz clic para forzar la actualización del recorte.
@export var actualizar_recorte_ahora: bool = false:
	set(value):
		actualizar_recorte_ahora = false
		if value and is_inside_tree():
			recortar_terreno_para_habitats()
## Botón de Inspector (Editor): nivela en Y todos los hábitats a la altura de la planicie (38.0m).
@export var nivelar_habitats_a_planicie: bool = false:
	set(value):
		nivelar_habitats_a_planicie = false
		if value and is_inside_tree():
			_nivelar_todos_los_habitats()
			recortar_terreno_para_habitats()

var player: CharacterBody3D
var sun: DirectionalLight3D
var world_env: WorldEnvironment

var _xr_active: bool = false
var _perf_optimizer: ParkPerformanceOptimizer
var _terrain_carver: HabitatTerrainCarver
var _toon_stylizer: LowPolyToonStylizer
var _editor_poll_timer: float = 0.0
var _last_habitat_sig: String = ""

func _ready() -> void:
	set_meta("_managed_toon_style", true)
	player = get_node_or_null("PlayerVR") as CharacterBody3D
	sun = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	world_env = get_node_or_null("WorldEnvironment") as WorldEnvironment

	_terrain_carver = HabitatTerrainCarver.new()
	_toon_stylizer = LowPolyToonStylizer.new()
	_sincronizar_parametros_carver()

	# Monitorear hábitats añadidos o eliminados tanto en Editor como en Runtime
	if not child_entered_tree.is_connected(_on_child_entered_tree):
		child_entered_tree.connect(_on_child_entered_tree)
	if not child_exiting_tree.is_connected(_on_child_exiting_tree):
		child_exiting_tree.connect(_on_child_exiting_tree)

	if Engine.is_editor_hint():
		# En modo Editor: vista previa visual en vivo (recorte + shader animado) sin tocar física ni VR
		set_process(true)
		if auto_recortar_terreno_habitats:
			call_deferred("recortar_terreno_para_habitats")
		if estilo_animado_activo:
			call_deferred("aplicar_estilo_animado")
		return

	# Modo ejecución real (Juego / VR): sin polling por frame
	set_process(false)

	print("==================================================")
	print("🌿 ESCENARIO PRINCIPAL 2KM x 2KM INICIALIZADO")
	print("• Dimensiones: 2000m x 2000m (Valle Plano 38m + Montañas/Cascadas)")
	print("• Shader Low-Poly Animado (Toon): ", "ACTIVO" if estilo_animado_activo else "DESACTIVADO")
	print("• Recorte automático bajo hábitats: ", "ACTIVO" if auto_recortar_terreno_habitats else "DESACTIVADO")
	print("• Fricción de terreno: Activa (Sin deslizamiento)")
	print("• Controles: WASD + Mouse (Clic para capturar)")
	print("==================================================")

	var xr_interface := XRServer.find_interface("OpenXR")
	_xr_active = (xr_interface != null and xr_interface.is_initialized())

	# 1. Recortar terreno principal (visual + colisión trimesh + props) ANTES de optimizar MultiMeshes
	if auto_recortar_terreno_habitats:
		recortar_terreno_para_habitats()

	# 2. Aplicar shader ligero estilizado tipo animación ANTES del batching MultiMesh
	if estilo_animado_activo:
		aplicar_estilo_animado()

	# 3. Sanitizar luces, cámaras o UIs duplicadas de cualquier hábitat
	_sanitizar_escena()

	# 4. Asegurar fricción en cualquier StaticBody3D del terreno o recintos
	_configurar_friccion_terreno()

	# 5. Activar optimizador central (culling + MultiMesh por chunks + sombras)
	_perf_optimizer = ParkPerformanceOptimizer.new()
	_perf_optimizer.name = "ParkPerformanceOptimizer"
	add_child(_perf_optimizer)

func _process(delta: float) -> void:
	# Solo activo dentro del Editor de Godot para seguir en vivo si mueves/rotas un hábitat
	if not Engine.is_editor_hint() or not auto_recortar_terreno_habitats:
		return
	_editor_poll_timer -= delta
	if _editor_poll_timer > 0.0:
		return
	_editor_poll_timer = 0.35
	if _terrain_carver == null:
		_terrain_carver = HabitatTerrainCarver.new()
	var sig := _terrain_carver.get_habitat_transform_signature(self)
	if sig != _last_habitat_sig:
		_last_habitat_sig = sig
		recortar_terreno_para_habitats()

## Función pública principal: limpia y desaparece la parte del ambiente principal
## (terreno visual, colisión física y árboles/rocas) exactamente debajo de todos los hábitats.
func recortar_terreno_para_habitats() -> Dictionary:
	if _terrain_carver == null:
		_terrain_carver = HabitatTerrainCarver.new()
	_sincronizar_parametros_carver()

	var island := _terrain_carver.find_island_root(self)
	if not island:
		return {}

	var carve_physics := not Engine.is_editor_hint()
	var stats := _terrain_carver.refresh_cutouts(self, island, carve_physics)
	_last_habitat_sig = _terrain_carver.get_habitat_transform_signature(self)

	if not Engine.is_editor_hint():
		print("[HabitatTerrainCarver] Recortados %d hábitats | Props ocultos=%d | Colisión tris: %d -> %d" % [
			stats.get("habitats", 0),
			stats.get("props_hidden", 0),
			stats.get("collision_tris_before", 0),
			stats.get("collision_tris_after", 0)
		])
		if is_instance_valid(_perf_optimizer):
			_perf_optimizer.rebuild_island_multimeshes(island)

	return stats

## Función pública para registrar y limpiar debajo de un hábitat específico añadido dinámicamente.
func registrar_y_recortar_habitat(habitat: Node3D, nivelar_a_planicie: bool = false) -> void:
	if not is_instance_valid(habitat):
		return
	if nivelar_a_planicie:
		habitat.global_position.y = altura_planicie_principal
	if auto_recortar_terreno_habitats:
		recortar_terreno_para_habitats()
	if not Engine.is_editor_hint():
		_sanitizar_nodo(habitat)
		_configurar_friccion_nodo(habitat)
		if is_instance_valid(_perf_optimizer):
			_perf_optimizer.call_deferred("register_dynamic_subtree", habitat)

func _sincronizar_parametros_carver() -> void:
	if _terrain_carver == null:
		return
	_terrain_carver.cutout_inset = margen_borde_recorte
	_terrain_carver.prop_clearance_margin = margen_despeje_props

func _nivelar_todos_los_habitats() -> void:
	if _terrain_carver == null:
		_terrain_carver = HabitatTerrainCarver.new()
	for hab in _terrain_carver.find_all_habitats(self):
		hab.position.y = altura_planicie_principal

## Aplica (o restaura si se desactiva) el shader estilizado low-poly animado a toda la escena.
func aplicar_estilo_animado(target_root: Node = null) -> Dictionary:
	if _toon_stylizer == null:
		_toon_stylizer = LowPolyToonStylizer.new()
	_toon_stylizer.wind_enabled = animacion_viento_follaje

	var root_node: Node = target_root if target_root != null else self
	if not estilo_animado_activo:
		_toon_stylizer.restore_originals(self)
		return {}

	var stats := _toon_stylizer.apply_to_tree(root_node)
	if not Engine.is_editor_hint() and target_root == null:
		print("[LowPolyToonStylizer] Estilo animado activo | Mallas=%d | Convertidos=%d | Materiales únicos=%d | Cascadas=%d" % [
			stats.get("meshes_visited", 0),
			stats.get("materials_converted", 0),
			stats.get("unique_toon_materials", 0),
			stats.get("waterfalls_styled", 0)
		])
	return stats

func _on_child_entered_tree(node: Node) -> void:
	if node == _perf_optimizer or node.name == "OptimizedMultiMeshes":
		return
	if HabitatTerrainCarver.is_habitat_node(node):
		if auto_recortar_terreno_habitats:
			call_deferred("recortar_terreno_para_habitats")
		if estilo_animado_activo:
			call_deferred("aplicar_estilo_animado", node)
	if Engine.is_editor_hint():
		return
	_sanitizar_nodo(node)
	_configurar_friccion_nodo(node)
	if is_instance_valid(_perf_optimizer):
		_perf_optimizer.call_deferred("register_dynamic_subtree", node)

func _on_child_exiting_tree(node: Node) -> void:
	if node == _perf_optimizer or node.name == "OptimizedMultiMeshes":
		return
	if HabitatTerrainCarver.is_habitat_node(node) and auto_recortar_terreno_habitats:
		call_deferred("recortar_terreno_para_habitats")

func _sanitizar_escena() -> void:
	for node in find_children("*", "", true, false):
		_sanitizar_nodo(node)

	# Asegurar que la cámara del jugador sea la activa y prioritaria
	if player and player.has_node("XROrigin3D/XRCamera3D"):
		var cam := player.get_node("XROrigin3D/XRCamera3D") as Camera3D
		if cam:
			cam.current = true
			cam.make_current()

func _sanitizar_nodo(node: Node) -> void:
	if not is_instance_valid(node):
		return

	# Eliminar soles secundarios para evitar sobreexposición de luz
	if node is DirectionalLight3D and node != sun:
		print("[Escenario] Sol secundario eliminado en: ", node.get_path())
		node.queue_free()
		return

	# Eliminar WorldEnvironment secundario
	if node is WorldEnvironment and node != world_env:
		print("[Escenario] WorldEnvironment secundario eliminado en: ", node.get_path())
		node.queue_free()
		return

	# Desactivar cámaras que no pertenezcan al jugador
	if node is Camera3D:
		if player and not player.is_ancestor_of(node):
			print("[Escenario] Cámara secundaria desactivada en: ", node.get_path())
			node.current = false

	# Ocultar o eliminar CanvasLayer secundario de UI de hábitats
	if node is CanvasLayer:
		if player and not player.is_ancestor_of(node):
			node.visible = false
			node.queue_free()

func _configurar_friccion_terreno() -> void:
	var mat_fisico := _crear_material_friccion()
	for node in find_children("*", "StaticBody3D", true, false):
		_aplicar_friccion_body(node as StaticBody3D, mat_fisico)

func _configurar_friccion_nodo(root: Node) -> void:
	var mat_fisico := _crear_material_friccion()
	if root is StaticBody3D:
		_aplicar_friccion_body(root as StaticBody3D, mat_fisico)
	for node in root.find_children("*", "StaticBody3D", true, false):
		_aplicar_friccion_body(node as StaticBody3D, mat_fisico)

func _crear_material_friccion() -> PhysicsMaterial:
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	mat.rough = true
	mat.bounce = 0.0
	return mat

func _aplicar_friccion_body(body: StaticBody3D, mat_fisico: PhysicsMaterial) -> void:
	if not is_instance_valid(body):
		return
	body.physics_material_override = mat_fisico

	# Solo instanciar nodos XRToolsGroundPhysics si OpenXR está activo (en escritorio evita ~690 nodos extra)
	if _xr_active and ClassDB.class_exists("XRToolsGroundPhysics") and ClassDB.class_exists("XRToolsGroundPhysicsSettings"):
		if not body.has_node("XRToolsGroundPhysics"):
			var xr_physics = ClassDB.instantiate("XRToolsGroundPhysics")
			var xr_settings = ClassDB.instantiate("XRToolsGroundPhysicsSettings")
			if xr_physics and xr_settings:
				xr_settings.move_drag = 30.0
				xr_settings.move_traction = 50.0
				xr_settings.stop_on_slope = true
				xr_settings.move_max_slope = 45.0
				xr_physics.physics = xr_settings
				body.add_child(xr_physics)
