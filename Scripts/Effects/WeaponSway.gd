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
	
	# Application
	position = position.lerp(final_pos, delta * sway_smooth)
	
	# Reset input (car _input n'est pas appelé chaque frame si la souris ne bouge pas)
	mouse_input = Vector2.ZERO
