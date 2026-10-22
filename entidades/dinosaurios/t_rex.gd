#extends Node3D
#
#@onready var anim_player: AnimationPlayer = $AnimationPlayer # Ajusta si tu AnimationPlayer está dentro de otro nodo
#
#func _ready():
	#if anim_player:
		## Aseguramos que la animación esté en modo Loop
		#var anim = anim_player.get_animation("idle")
		#if anim:
			#anim.loop_mode = Animation.LOOP_LINEAR
		#
		## Reproducir
		#anim_player.play("idle")

#Nuevo Script

extends Node3D

@onready var anim_player: AnimationPlayer = $AnimationPlayer

var animations: PackedStringArray = []
var current_anim_index: int = 0

func _ready() -> void:
	if not anim_player:
		push_error("No se encontró el nodo AnimationPlayer.")
		return

	# Obtiene todas las animaciones disponibles en la librería del modelo
	animations = anim_player.get_animation_list()
	
	# Escuchar cuando una animación termina para encadenar
	anim_player.animation_finished.connect(_on_animation_finished)

	# Configurar bucle para animaciones continuas
	_configure_loop("idle", true)
	_configure_loop("walk", true)
	_configure_loop("run", true)

	play_animation("idle")

func _configure_loop(anim_name: String, is_loop: bool) -> void:
	if anim_player.has_animation(anim_name):
		var anim: Animation = anim_player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if is_loop else Animation.LOOP_NONE

func play_animation(anim_name: String, blend_time: float = 0.3) -> void:
	if anim_player.has_animation(anim_name):
		# blend_time suaviza la transición entre la pose actual y la nueva
		anim_player.play(anim_name, blend_time)
		print("[Dino] Reproduciendo: ", anim_name)

func cycle_next_animation() -> void:
	if animations.is_empty():
		return
	current_anim_index = (current_anim_index + 1) % animations.size()
	var selected_anim := animations[current_anim_index]
	play_animation(selected_anim)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Presiona N para ciclar a la siguiente animación
		if event.keycode == KEY_N:
			cycle_next_animation()
		# Teclas 1, 2, 3 para disparar animaciones específicas de prueba
		elif event.keycode == KEY_1:
			play_animation("idle")
		elif event.keycode == KEY_2:
			play_animation("roar")
		elif event.keycode == KEY_3:
			play_animation("attack")

func _on_animation_finished(anim_name: StringName) -> void:
	# Si terminó una animación que no es de bucle, regresar al estado base
	if anim_player.has_animation(anim_name):
		var anim := anim_player.get_animation(anim_name)
		if anim.loop_mode == Animation.LOOP_NONE:
			play_animation("idle")
