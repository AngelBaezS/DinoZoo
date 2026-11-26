extends Node

## Autoload ligero que asegura que incluso al ejecutar un hábitat individual
## directamente (sin pasar por EscenarioPrincipal), se aplique el shader estilizado
## low-poly animado de manera automática.

var _stylizer: LowPolyToonStylizer

func _ready() -> void:
	_stylizer = LowPolyToonStylizer.new()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_check_current_scene")

func _check_current_scene() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	# Si EscenarioPrincipal ya gestiona el estilo, no duplicar trabajo
	if scene.has_meta("_managed_toon_style") or scene.name == "EscenarioPrincipal":
		return
	var stats := _stylizer.apply_to_tree(scene)
	scene.set_meta("_managed_toon_style", true)
	print("[EstiloAnimadoGlobal] Aplicado a %s | Mallas=%d | Materiales toon=%d" % [
		scene.name, stats.get("meshes_visited", 0), stats.get("unique_toon_materials", 0)
	])

func _on_node_added(node: Node) -> void:
	# Detectar cambios de escena vía change_scene_to_*
	if node == get_tree().current_scene:
		call_deferred("_check_current_scene")
