extends Node3D
class_name Weapon

@export var damage: int = 1
@export var fire_rate: float = 0.5 # Tirs par seconde
@export var automatic: bool = false # Si vrai, tire en continu quand on maintient
@export var shoot_sound: AudioStream # Son de tir
@export var max_ammo: int = 10
@export var current_ammo: int = 10

var last_fire_time: float = 0.0
var audio_player: AudioStreamPlayer3D = null

signal fired
signal out_of_ammo
signal ammo_changed(new_amount)

func _ready():
	current_ammo = max_ammo
	emit_signal("ammo_changed", current_ammo)
	
	# Création dynamique du lecteur audio si non présent
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		add_child(audio_player)
		audio_player.bus = "SFX" # On utilisera le bus SFX (ou Master par défaut si inexistant)

func can_shoot() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_ammo > 0 and (current_time - last_fire_time) >= fire_rate

func shoot():
	if not can_shoot():
		if current_ammo <= 0:
			emit_signal("out_of_ammo")
		return
	
	last_fire_time = Time.get_ticks_msec() / 1000.0
	current_ammo -= 1
	emit_signal("ammo_changed", current_ammo)
	emit_signal("fired")
	
	if shoot_sound and audio_player:
		audio_player.stream = shoot_sound
		audio_player.pitch_scale = randf_range(0.95, 1.05) # Variation légère
		audio_player.play()
		
	_perform_shoot()

func _perform_shoot():
	# À surcharger par les classes enfants
	pass

func reload():
	current_ammo = max_ammo
	emit_signal("ammo_changed", current_ammo)
