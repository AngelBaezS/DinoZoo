extends Node3D

var interface : XRInterface

# Called when the node enters the scene tree for the first time.
func _ready():
	interface = XRServer.find_interface("OpenXR")
	if interface and interface.is_initialized():
		print("¡OpenXR iniciado correctamente!")
		
		# Le decimos a Godot que renderice en las gafas
		get_viewport().use_xr = true
	else:
		print("No se encontraron gafas conectadas.")
