extends Node3D

func _ready() -> void:
	# Soporte OpenXR si está disponible
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F1 or event.keycode == KEY_1:
			cargar_habitat_mosasaurus()
		elif event.keycode == KEY_F2 or event.keycode == KEY_2:
			cargar_habitat_triceratops()
		elif event.keycode == KEY_F3 or event.keycode == KEY_3:
			cargar_habitat_titanosaurus()
		elif event.keycode == KEY_F4 or event.keycode == KEY_4:
			cargar_habitat_trex()

func cargar_habitat_mosasaurus() -> void:
	get_tree().change_scene_to_file("res://niveles/habitat_mosasaurus.tscn")

func cargar_habitat_triceratops() -> void:
	get_tree().change_scene_to_file("res://niveles/habitat_triceratops.tscn")

func cargar_habitat_titanosaurus() -> void:
	get_tree().change_scene_to_file("res://niveles/habitat_titanosaurus.tscn")

func cargar_habitat_trex() -> void:
	get_tree().change_scene_to_file("res://niveles/habitat_trex.tscn")


