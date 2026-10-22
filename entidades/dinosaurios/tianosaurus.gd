extends Node3D

@onready var anim_player: AnimationPlayer = $Esqueleto_Titanosaurus/AnimationPlayer

func _ready():
	if anim_player:
		# Aseguramos que la animación esté en modo Loop
		var anim = anim_player.get_animation("idle")
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		
		# Reproducir
		anim_player.play("idle")
