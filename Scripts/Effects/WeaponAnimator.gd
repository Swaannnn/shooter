extends Node3D

@export var gun_container_path: NodePath = "GunContainer"
@export var left_arm_path: NodePath = "LeftArm"

@export var reload_tilt_angle: float = -45.0 # Degrés
@export var reload_pos_offset: Vector3 = Vector3(0, -0.2, 0)

@onready var gun_container: Node3D = get_node_or_null(gun_container_path)
@onready var left_arm: Node3D = get_node_or_null(left_arm_path)

var initial_gun_rot: Vector3
var initial_gun_pos: Vector3
var initial_left_arm_pos: Vector3
var left_arm_active_pos: Vector3 # Calculated automatically

var weapon_ref: Weapon = null
var active_tween: Tween = null

func _ready():
	# Délai pour initialisation
	await get_tree().process_frame
	
	# Sauvegarde des transforms initiaux
	if gun_container:
		initial_gun_rot = gun_container.rotation
		initial_gun_pos = gun_container.position
		
	if left_arm:
		initial_left_arm_pos = left_arm.position
		# On suppose que le bras gauche est caché en bas ou invisible
		# Mais pour l'animation, on veut qu'il vienne à la hauteur de l'arme
		# Donc on va définir sa position "active" comme étant proche de la position actuelle (si on le place bien dans l'éditeur)
		# Ou alors on hardcode un offset vertical.
		# Stratégie : Le Left Arm est placé visible dans l'éditeur pour réglage, on le cache au start.
		left_arm_active_pos = initial_left_arm_pos
		# On le déplace en bas pour le cacher
		left_arm.position = initial_left_arm_pos + Vector3(0, -1.0, 0)
		left_arm.visible = false
		
	# Connexion au Weapon parent (remonte l'arbre)
	_find_weapon_parent()

func _find_weapon_parent():
	var node = get_parent()
	while node:
		if node is Weapon:
			weapon_ref = node
			weapon_ref.reloading_started.connect(_on_reload_start)
			weapon_ref.reloading_finished.connect(_on_reload_end)
			break
		node = node.get_parent()

@export var anim_down_time: float = 0.5
@export var anim_up_time: float = 0.5

func _on_reload_start():
	if active_tween: active_tween.kill()
	
	var total_time = weapon_ref.reload_time
	var down_time = anim_down_time
	var up_time = anim_up_time
	var hold_time = max(0.0, total_time - down_time - up_time)
	
	# Cas particulier Shotgun (ou temps très court) : on fait simple
	if total_time < 0.8:
		down_time = total_time / 2.0
		up_time = total_time / 2.0
		hold_time = 0.0
	
	var tween = create_tween().set_parallel(false) # Séquentiel pour les étapes
	active_tween = tween
	
	# Étape 1 : Down (Rotation + Position)
	# On utilise set_parallel(true) à l'intérieur d'une étape via tweener ou des Sub-Tweens ? 
	# Godot 4 Tween : on peut faire tween.parallel().tween_property(...)
	
	# -- PHASE 1 : DOWN --
	tween.set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if gun_container:
		tween.tween_property(gun_container, "rotation:x", deg_to_rad(reload_tilt_angle), down_time)
		tween.tween_property(gun_container, "position", initial_gun_pos + reload_pos_offset, down_time)
	if left_arm:
		left_arm.visible = true
		tween.tween_property(left_arm, "position", left_arm_active_pos, down_time)
		
	# -- PHASE 2 : HOLD --
	# On ajoute un délai
	tween.chain().tween_interval(hold_time)
	
	# -- PHASE 3 : UP (Anticipation de la fin) --
	tween.chain().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if gun_container:
		tween.tween_property(gun_container, "rotation", initial_gun_rot, up_time)
		tween.tween_property(gun_container, "position", initial_gun_pos, up_time)
	if left_arm:
		tween.tween_property(left_arm, "position", initial_left_arm_pos + Vector3(0, -1.0, 0), up_time)
		# On cache le bras à la toute fin
		tween.chain().tween_callback(func(): left_arm.visible = false)

func _on_reload_end():
	if active_tween: active_tween.kill()
	
	var duration = 0.3
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	active_tween = tween
	
	# Reset Arme
	if gun_container:
		tween.tween_property(gun_container, "rotation", initial_gun_rot, duration)
		tween.tween_property(gun_container, "position", initial_gun_pos, duration)
		
	# Reset Bras Gauche
	if left_arm:
		tween.tween_property(left_arm, "position", initial_left_arm_pos + Vector3(0, -1.0, 0), duration)
		tween.chain().tween_callback(func(): left_arm.visible = false)
