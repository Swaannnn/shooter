extends Node3D
class_name Weapon

@export var damage: int = 1
@export var fire_rate: float = 0.5 # Tirs par seconde
@export var automatic: bool = false # Si vrai, tire en continu quand on maintient
@export var shoot_sound: AudioStream # Son de tir
@export var max_ammo: int = 10
@export var current_ammo: int = 10
@export var reserve_ammo: int = 90 # Munitions en réserve
@export var reload_time: float = 1.5 # Temps de rechargement en secondes
@export var reload_sound: AudioStream # Son de rechargement

@export_group("Recoil")
@export var recoil_amount: float = 2.0 # Degrés de montée par tir
@export var recoil_recovery: float = 5.0 # Vitesse de retour (Degrés par seconde en mode linéaire)
@export var max_recoil_deg: float = 10.0 # Plafond du recul accumulé
@export var recoil_growth_start: int = 0 # À partir de quel tir le recul augmente
@export var recoil_growth_factor: float = 0.0 # Augmentation par tir supplémentaire

var burst_count: int = 0

var last_fire_time: float = 0.0
# var audio_player: AudioStreamPlayer3D = null # On utilise des joueurs dynamiques maintenant
var is_reloading: bool = false

signal fired
signal out_of_ammo
signal ammo_changed(current, reserved) # Changé pour inclure reserve
signal reloading_started
signal reloading_finished

func _ready():
	current_ammo = max_ammo
	emit_signal("ammo_changed", current_ammo, reserve_ammo)

func can_shoot() -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_ammo > 0 and (current_time - last_fire_time) >= fire_rate and not is_reloading

func shoot():
	if is_reloading: return
	
	if not can_shoot():
		if current_ammo <= 0:
			print("Weapon: Empty! Triggering Auto-Reload.")
			emit_signal("out_of_ammo")
			start_reload() # Auto-reload
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Gestion du burst
	if (current_time - last_fire_time) > (fire_rate * 2.0):
		burst_count = 0
		
	burst_count += 1
	
	last_fire_time = current_time
	current_ammo -= 1
	emit_signal("ammo_changed", current_ammo, reserve_ammo)
	emit_signal("fired")
	
	if shoot_sound:
		play_sound(shoot_sound, 0.95, 1.05)
		
	_perform_shoot()
	
	# Auto-Reload immédiat après le dernier tir
	if current_ammo <= 0:
		start_reload()

func _perform_shoot():
	# À surcharger par les classes enfants
	pass

func get_current_recoil_amount() -> float:
	# Deprecated, kept for safety but redirected
	return get_recoil_vector().x

func get_recoil_vector() -> Vector2:
	# X = Vertical (Pitch), Y = Horizontal (Yaw)
	
	var vertical = recoil_amount
	var horizontal = 0.0
	
	if automatic and burst_count > 0:
		# --- M4 Spray Pattern Complex ---
		# X = Vertical, Y = Horizontal (Positive=Left, Negative=Right)
		
		# 1. Montée Principale (Juste Verticale)
		if burst_count < 5:
			# Balles 1-4 : Tout droit
			var growth = max(0, burst_count - recoil_growth_start)
			vertical += (growth * recoil_growth_factor)
			horizontal = randf_range(-0.1, 0.1) # Micro jitter
			
		# 2. Début dérive Droite (Légère)
		elif burst_count < 12:
			# Balles 5-11 : Commence à aller un PEU à DROITE
			# On continue de monter un peu mais moins vite
			vertical *= 0.85 
			vertical += sin(burst_count) * 0.2
			
			# Dérive Droite légère
			# Negative Y = Right
			# On veut juste "un tout petit peu" -> Max -0.8
			var progress = float(burst_count - 4) / 8.0 # 0.0 à 1.0
			horizontal = -0.2 - (progress * 0.6) 
			
		# 3. Oscillation Stabilisée (Centrée)
		else:
			# Balles 12+ : Droite/Gauche régulier (période 4-6 balles)
			vertical *= 0.3 # Plafond
			
			# Oscillation autour du CENTRE (0.0) ou presque
			# On veut que ça reste "au dessus du centre de la balle de base"
			# Pattern sinusoïdal lent
			# Freq 0.8 -> Période ~8 balles (4 gauche, 4 droite)
			var wave = sin((burst_count - 10) * 0.8) * 1.5
			horizontal = wave
			
	return Vector2(vertical, horizontal)

func start_reload():
	if is_reloading: return
	if current_ammo == max_ammo: return # Déjà plein
	if reserve_ammo <= 0: return # Plus de munitions
	
	is_reloading = true
	emit_signal("reloading_started")
	print("Reloading...")
	
	# Audio generic (si pas override par Shotgun)
	if reload_sound:
		play_sound(reload_sound)
	
	# Timer simple via SceneTree
	await get_tree().create_timer(reload_time).timeout
	
	_finish_reload()

func _finish_reload():
	if not is_reloading: return # Si annulé entre temps
	
	var needed = max_ammo - current_ammo
	var available = min(needed, reserve_ammo)
	
	current_ammo += available
	reserve_ammo -= available
	
	is_reloading = false
	emit_signal("reloading_finished")
	emit_signal("ammo_changed", current_ammo, reserve_ammo)
	print("Reloaded. Ammo: ", current_ammo, " Reserve: ", reserve_ammo)

# Legacy / Cheat function
func instant_reload():
	current_ammo = max_ammo
	is_reloading = false
	emit_signal("ammo_changed", current_ammo, reserve_ammo)

# Helper pour l'audio polyphonique
func play_sound(stream: AudioStream, pitch_min: float = 1.0, pitch_max: float = 1.0):
	if not stream: return
	
	var player = AudioStreamPlayer3D.new()
	add_child(player)
	player.bus = "SFX"
	player.stream = stream
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	
	# Auto-destruction à la fin du son
	player.finished.connect(player.queue_free)
	player.play()
