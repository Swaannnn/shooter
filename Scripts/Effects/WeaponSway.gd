extends Node3D

@export var sway_amount: float = 0.05
@export var sway_smooth: float = 10.0
@export var max_sway: float = 0.1

@export var bob_freq: float = 2.0
@export var bob_amp: float = 0.02
@export var is_active: bool = false # Désactivé sur demande du joueur

var mouse_input: Vector2
var initial_pos: Vector3
var bob_time: float = 0.0

func _ready():
	initial_pos = position
	_connect_to_weapon()

func _connect_to_weapon():
	var node = get_parent()
	while node:
		if node is Weapon:
			if not node.fired.is_connected(_on_weapon_fired):
				node.fired.connect(_on_weapon_fired)
			break
		node = node.get_parent()

func _on_weapon_fired():
	# Coup de fusil visuel
	# Recul Z (vers l'arrière) + Y (montée légère)
	# Valeurs hardcodées pour le "feel" universel, ou à récupérer du Weapon si ajouté
	print("WeaponSway: Visual Kick triggered!")
	apply_visual_recoil(0.15, 0.05)

func _input(event):
	if event is InputEventMouseMotion:
		mouse_input = event.relative

func _process(delta):
	if not is_active: return
	
	# 1. Weapon Sway (Inertie souris)
	# On inverse le mouvement de la souris pour donner l'impression de poids
	var target_x = -mouse_input.x * sway_amount
	var target_y = mouse_input.y * sway_amount # Inversé car Y vers le bas en 2D mais ... testons
	
	target_x = clamp(target_x, -max_sway, max_sway)
	target_y = clamp(target_y, -max_sway, max_sway)
	
	var final_pos = initial_pos + Vector3(target_x, target_y, 0)
	
	# 2. Weapon Bob (Marche)
	# On vérifie si le joueur bouge (on suppose que le parent est la caméra, et grand-parent le joueur)
	var player = get_parent().get_parent() # Camera -> Player (au cas où, a adapter selon hierarchie)
	if player and player is CharacterBody3D and player.velocity.length() > 0.1 and player.is_on_floor():
		bob_time += delta * player.velocity.length() * bob_freq
		var bob_y = sin(bob_time) * bob_amp
		var bob_x = cos(bob_time / 2.0) * bob_amp # Mouvement en 8
		final_pos += Vector3(bob_x, bob_y, 0)
	
	# 3. Visual Recoil Kick
	if current_recoil_kick.length() > 0.001:
		final_pos += current_recoil_kick
		# Recovery
		current_recoil_kick = current_recoil_kick.lerp(Vector3.ZERO, rec_recovery * delta)
	
	# Application
	position = position.lerp(final_pos, delta * sway_smooth)
	
	# Reset input (car _input n'est pas appelé chaque frame si la souris ne bouge pas)
	mouse_input = Vector2.ZERO

var current_recoil_kick: Vector3 = Vector3.ZERO
var rec_recovery: float = 10.0

func apply_visual_recoil(amount_z: float, amount_y: float):
	# Z positif = vers l'arrière pour une arme en main (dépend du repère)
	# Habituellement -Z est devant. Donc +Z vient vers la caméra.
	current_recoil_kick += Vector3(0, amount_y, amount_z)
