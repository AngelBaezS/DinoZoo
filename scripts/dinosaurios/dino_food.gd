class_name DinoFood
extends RigidBody3D

## ============================================================================
## DINO FOOD — Alimento lanzable con diferenciación de dieta (Carne / Pasto)
## ============================================================================
## - food_type == "meat"  -> Atrae exclusivamente a carnívoros / piscívoros.
## - food_type == "grass" -> Atrae exclusivamente a herbívoros.
## - Detecta con precisión si cayó dentro de un estanque acuático específico
##   (comprobando el AABB horizontal de cada WaterManager) para flotar/salpicar
##   solo en agua y reposar en suelo firme en recintos terrestres.
## ============================================================================

const DIET_MEAT: String = "meat"
const DIET_GRASS: String = "grass"

@export_enum("meat", "grass") var food_type: String = "meat"
@export var sink_speed: float = 0.6
@export var water_drag: float = 3.6
@export var float_depth_target: float = -0.75
@export var lifetime: float = 60.0

var _water_manager: WaterManager = null
var _entered_water: bool = false
var _is_being_eaten: bool = false
var _life_timer: float = 0.0

func _ready() -> void:
	add_to_group("dino_food")
	add_to_group("dino_food_" + food_type)

	# Fricción alta y poco rebote para que la comida quede donde el jugador la lanza
	if physics_material_override == null:
		var pm := PhysicsMaterial.new()
		pm.friction = 0.92
		pm.bounce = 0.14
		physics_material_override = pm

	# Ligero efecto de aparición elástico al lanzarla
	var target_scale := scale
	scale = target_scale * 0.35
	var tw := create_tween()
	tw.tween_property(self, "scale", target_scale, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	if _is_being_eaten:
		return

	_life_timer += delta
	if _life_timer >= lifetime:
		fade_out_and_free()
		return

	var wm := _find_containing_water_manager()
	if wm != null:
		_water_manager = wm
		var water_y: float = wm.get_water_height_at(Vector2(global_position.x, global_position.z))
		if global_position.y <= water_y:
			if not _entered_water:
				_entered_water = true
				wm.register_splash(global_position, 1.25)
				linear_velocity *= 0.30
				angular_velocity *= 0.40

			# Física acuática: flotabilidad suave y fricción del agua
			gravity_scale = 0.05
			linear_damp = water_drag
			angular_damp = 2.5

			var target_y: float = water_y + float_depth_target
			if global_position.y < target_y:
				apply_central_force(Vector3.UP * 5.0)
			else:
				apply_central_force(Vector3.DOWN * 2.2)
			return

	# En tierra / aire libre: gravedad normal y reposo limpio al caer
	_entered_water = false
	gravity_scale = 1.0
	linear_damp = 0.25
	angular_damp = 1.4

func _find_containing_water_manager() -> WaterManager:
	var managers := get_tree().get_nodes_in_group("water_manager")
	for node in managers:
		if not is_instance_valid(node) or not (node is WaterManager):
			continue
		var wm := node as WaterManager
		if not wm.is_visible_in_tree():
			continue
		var local_p: Vector3 = wm.global_transform.affine_inverse() * global_position
		var aabb: AABB = wm.get_aabb()
		if aabb.size.x <= 0.01 or aabb.size.z <= 0.01:
			continue
		if local_p.x >= aabb.position.x and local_p.x <= aabb.position.x + aabb.size.x \
				and local_p.z >= aabb.position.z and local_p.z <= aabb.position.z + aabb.size.z:
			# Comprobar también que esté por debajo o cerca de la superficie de esa piscina (no en otro piso)
			if global_position.y <= wm.global_position.y + 1.5 and global_position.y >= wm.global_position.y - 24.0:
				return wm
	return null

func is_edible_for_diet(diet: String) -> bool:
	if _is_being_eaten:
		return false
	return food_type == diet

func consume() -> void:
	if _is_being_eaten:
		return
	_is_being_eaten = true
	remove_from_group("dino_food")
	remove_from_group("dino_food_" + food_type)

	if is_instance_valid(_water_manager) and _entered_water:
		_water_manager.register_splash(global_position, 1.6)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func fade_out_and_free() -> void:
	if _is_being_eaten:
		return
	_is_being_eaten = true
	remove_from_group("dino_food")
	remove_from_group("dino_food_" + food_type)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.45)
	tween.tween_callback(queue_free)

## ============================================================================
## UTILIDAD UNIFICADA DE DETECCIÓN PARA LOS 15 DINOSAURIOS
## ============================================================================
## Busca el alimento más cercano compatible con la dieta del dinosaurio ("meat"
## o "grass") respetando los límites del propio hábitat para que un dinosaurio
## no intente atravesar vallas hacia comida lanzada en otro recinto.
static func find_nearest_for(
	dino: Node3D,
	diet: String,
	max_radius: float,
	habitat_node: Node3D = null,
	bounds_min: Variant = null,
	bounds_max: Variant = null
) -> Node3D:
	if not is_instance_valid(dino) or not dino.is_inside_tree():
		return null

	var tree := dino.get_tree()
	if not tree:
		return null

	var food_items := tree.get_nodes_in_group("dino_food")
	if food_items.is_empty():
		return null

	var has_bounds := is_instance_valid(habitat_node) and bounds_min != null and bounds_max != null
	var min_x: float = 0.0
	var max_x: float = 0.0
	var min_z: float = 0.0
	var max_z: float = 0.0
	if has_bounds:
		if bounds_min is Vector2:
			min_x = bounds_min.x
			min_z = bounds_min.y
			max_x = bounds_max.x
			max_z = bounds_max.y
		elif bounds_min is Vector3:
			min_x = bounds_min.x
			min_z = bounds_min.z
			max_x = bounds_max.x
			max_z = bounds_max.z
		else:
			has_bounds = false

	# Radio efectivo generoso si el alimento cayó dentro del propio hábitat
	var effective_radius: float = maxf(max_radius, 28.0)
	var closest_food: Node3D = null
	var closest_dist: float = effective_radius

	for item in food_items:
		if not is_instance_valid(item) or not (item is Node3D):
			continue
		if item is DinoFood:
			if not (item as DinoFood).is_edible_for_diet(diet):
				continue
		elif item.has_meta("food_type"):
			if str(item.get_meta("food_type")) != diet:
				continue

		var fnode := item as Node3D
		if has_bounds:
			var lp: Vector3 = habitat_node.to_local(fnode.global_position)
			# Margen de 5.5m para que comida caída junto a la valla del propio hábitat sí atraiga al dino,
			# pero comida lanzada en otro recinto vecino sea ignorada.
			if lp.x < min_x - 5.5 or lp.x > max_x + 5.5 or lp.z < min_z - 5.5 or lp.z > max_z + 5.5:
				continue

		var d: float = dino.global_position.distance_to(fnode.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_food = fnode

	return closest_food
