class_name DinoJawController
extends RefCounted

## ============================================================================
## DINO JAW CONTROLLER — Control Unificado de Mandíbula para los 15 Dinosaurios
## ============================================================================
## Garantiza que todos los dinosaurios mantengan la boca CERRADA de forma natural
## durante Idle, Caminata, Nado y Patrulla, abriéndola únicamente en:
##   1. Animaciones / estados puntuales (Comer, Rugir, Pescar, Embestir, Saltar,
##      Coletear, Cornada, Llamado, Caza activa).
##   2. Ocasionalmente ("de vez en cuando"), mediante un gesto natural breve de
##      respiración, bostezo o vocalización suave cada 14-30 segundos.
## ============================================================================

enum Mode {
	CLOSED,      # Boca cerrada (Idle, caminar, nadar, patrullar, olfatear)
	EAT,         # Masticación rítmica durante alimentación
	ROAR,        # Apertura expresiva en rugido, amenaza, embestida, salto o pesca
	CHASE        # Boca ligeramente entreabierta en carrera de caza/ataque
}

## Calibración medida visualmente en Godot (grados en eje X local respecto a rest_q)
## closed_deg: ángulo donde la mandíbula cierra al ras sin atravesar el maxilar
## open_sign:  +1.0 o -1.0 indicando la dirección que ABRE la boca
## max_open:   apertura máxima natural (grados) en rugido / mordida
## occ_open:   apertura suave ocasional (bostezo / respiración / vocalización)
const SPECIES_PROFILES := {
	"aquilops":           {"closed_deg":  -6.0, "open_sign":  1.0, "max_open": 20.0, "occ_open": 10.0},
	"carnotaurus":        {"closed_deg": -60.0, "open_sign":  1.0, "max_open": 36.0, "occ_open": 16.0},
	"elasmosaurus":       {"closed_deg": -52.0, "open_sign":  1.0, "max_open": 32.0, "occ_open": 14.0},
	"erlikosaurus":       {"closed_deg":  42.0, "open_sign": -1.0, "max_open": 28.0, "occ_open": 13.0},
	"espinosaurio":       {"closed_deg": -41.0, "open_sign":  1.0, "max_open": 34.0, "occ_open": 15.0},
	"estegosaurio":       {"closed_deg": -36.0, "open_sign":  1.0, "max_open": 22.0, "occ_open": 11.0},
	"euoplocephalus":     {"closed_deg": -32.0, "open_sign":  1.0, "max_open": 22.0, "occ_open": 11.0},
	"liopleurodon":       {"closed_deg": -24.0, "open_sign":  1.0, "max_open": 34.0, "occ_open": 14.0},
	"mosasaurus":         {"closed_deg": -38.0, "open_sign":  1.0, "max_open": 34.0, "occ_open": 15.0},
	"pachycephalosaurus": {"closed_deg": -12.0, "open_sign":  1.0, "max_open": 22.0, "occ_open": 11.0},
	"quetzalcoatlus":     {"closed_deg":  26.5, "open_sign": -1.0, "max_open": 28.0, "occ_open": 13.0},
	"trex":               {"closed_deg": -38.0, "open_sign":  1.0, "max_open": 40.0, "occ_open": 18.0},
	"titanosaurus":       {"closed_deg":  24.0, "open_sign": -1.0, "max_open": 22.0, "occ_open": 11.0},
	"triceratops":        {"closed_deg":  68.0, "open_sign": -1.0, "max_open": 28.0, "occ_open": 13.0},
	"velociraptor":       {"closed_deg": -58.0, "open_sign":  1.0, "max_open": 34.0, "occ_open": 15.0},
}

var _skeleton: Skeleton3D
var _bone_jaw: int = -1
var _jaw_rest_q: Quaternion = Quaternion.IDENTITY

var closed_deg: float = 0.0
var open_sign: float = 1.0
var max_open_deg: float = 28.0
var occasional_open_deg: float = 13.0

var _current_open_deg: float = 0.0
var _time: float = 0.0

# Temporizador para apertura ocasional natural ("de vez en cuando")
var _occ_cooldown: float = 16.0
var _occ_active: bool = false
var _occ_elapsed: float = 0.0
var _occ_duration: float = 2.0
var _occ_peak_deg: float = 12.0


func setup(skeleton: Skeleton3D, species_key: String, anim_player: AnimationPlayer = null) -> bool:
	_skeleton = skeleton
	if not is_instance_valid(_skeleton):
		return false
	_bone_jaw = _skeleton.find_bone("Jaw")
	if _bone_jaw < 0:
		return false

	_jaw_rest_q = _skeleton.get_bone_rest(_bone_jaw).basis.get_rotation_quaternion()

	var key := species_key.to_lower().replace("dino_", "").replace("dino", "").replace("_", "").replace("-", "")
	if key == "swimmer":
		key = "mosasaurus"
	if SPECIES_PROFILES.has(key):
		var prof: Dictionary = SPECIES_PROFILES[key]
		closed_deg = float(prof["closed_deg"])
		open_sign = float(prof["open_sign"])
		max_open_deg = float(prof["max_open"])
		occasional_open_deg = float(prof["occ_open"])

	_current_open_deg = 0.0
	_time = randf_range(0.0, 20.0)
	_occ_cooldown = randf_range(11.0, 26.0)
	_occ_active = false

	# Conectar directamente a mixer_applied para garantizar que la mandíbula
	# siempre se aplique DESPUÉS del AnimationPlayer sin importar el orden del árbol
	if is_instance_valid(anim_player) and anim_player.has_signal("mixer_applied"):
		if not anim_player.mixer_applied.is_connected(apply):
			anim_player.mixer_applied.connect(apply)

	# Cerrar de inmediato desde el primer frame
	apply()
	return true


func is_valid() -> bool:
	return is_instance_valid(_skeleton) and _bone_jaw >= 0


## Infiera el modo automáticamente si el script solo pasa el AnimationPlayer,
## o combine con el modo explícito de la IA del dinosaurio.
static func infer_mode_from_anim(anim_player: AnimationPlayer) -> int:
	if not is_instance_valid(anim_player):
		return Mode.CLOSED
	var an := anim_player.current_animation.to_lower()
	if an == "":
		return Mode.CLOSED
	if "comer" in an and not ("buscar" in an):
		return Mode.EAT
	if "rugir" in an or "coletear" in an or "cornada" in an or "pescar" in an \
		or "embestida" in an or "salto" in an or "llamado" in an or "cabezazo" in an:
		return Mode.ROAR
	return Mode.CLOSED


func update(delta: float, explicit_mode: int = Mode.CLOSED, anim_player: AnimationPlayer = null) -> void:
	if not is_valid():
		return
	_time += delta

	var mode := explicit_mode
	if mode == Mode.CLOSED and anim_player != null:
		mode = infer_mode_from_anim(anim_player)

	var target_open_deg: float = 0.0
	var blend_speed: float = 6.5

	match mode:
		Mode.EAT:
			_occ_active = false
			# Masticación rítmica orgánica (abre y cierra con cadencia natural)
			var chew_wave := sin(_time * 4.8)
			var chew_01 := pow(maxf(0.0, chew_wave), 0.75)
			target_open_deg = max_open_deg * (0.12 + 0.62 * chew_01)
			blend_speed = 9.5

		Mode.ROAR:
			_occ_active = false
			# Apertura expresiva en animaciones puntuales (rugir, embestir, pescar, amenaza, llamado)
			var pulse := 0.80 + 0.20 * sin(_time * 3.4)
			target_open_deg = max_open_deg * pulse
			blend_speed = 7.5

		Mode.CHASE:
			_occ_active = false
			# Ligeramente entreabierta al cazar/perseguir presa a toda velocidad
			var pant := 0.35 + 0.12 * sin(_time * 5.0)
			target_open_deg = max_open_deg * pant
			blend_speed = 6.0

		_:
			# CLOSED por defecto + gesto ocasional breve ("de vez en cuando")
			if _occ_active:
				_occ_elapsed += delta
				if _occ_elapsed >= _occ_duration:
					_occ_active = false
					_occ_cooldown = randf_range(14.0, 30.0)
					target_open_deg = 0.0
				else:
					var u := clampf(_occ_elapsed / maxf(_occ_duration, 0.01), 0.0, 1.0)
					# Curva suave en campana: abre lentamente, sostiene un instante y cierra sin golpe
					var env := pow(sin(u * PI), 1.55)
					target_open_deg = _occ_peak_deg * env
					blend_speed = 7.0
			else:
				_occ_cooldown -= delta
				if _occ_cooldown <= 0.0:
					_occ_active = true
					_occ_elapsed = 0.0
					_occ_duration = randf_range(1.6, 2.7)
					_occ_peak_deg = occasional_open_deg * randf_range(0.70, 1.15)
				target_open_deg = 0.0
				blend_speed = 7.5

	_current_open_deg = lerpf(_current_open_deg, target_open_deg, clampf(delta * blend_speed, 0.0, 1.0))


func apply() -> void:
	if not is_valid():
		return
	var final_deg := closed_deg + open_sign * _current_open_deg
	var q_jaw := Quaternion(Vector3.RIGHT, deg_to_rad(final_deg))
	_skeleton.set_bone_pose_rotation(_bone_jaw, _jaw_rest_q * q_jaw)


func get_current_open_deg() -> float:
	return _current_open_deg
