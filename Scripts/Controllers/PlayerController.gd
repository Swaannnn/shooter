extends CharacterBody3D

@export var gravity = 9.8

@onready var camera: Camera3D
var hud_scene = preload("res://Scenes/UI/HUD.tscn")
var shop_scene = preload("res://Scenes/UI/ShopMenu.tscn")
var pause_scene = preload("res://Scenes/UI/PauseMenu.tscn")

# Audio Resources
var sound_jump = preload("res://Assets/Sounds/jump.mp3")
var sound_run = preload("res://Assets/Sounds/run.mp3")
var sound_walk = preload("res://Assets/Sounds/walk.mp3")

# Audio Players
var audio_jump: AudioStreamPlayer = null
var audio_run: AudioStreamPlayer = null
var audio_walk: AudioStreamPlayer = null

# Movement Config
@export var speed_walk = 5.0
@export var speed_run = 8.0
@export var speed_crouch = 2.5
@export var jump_velocity = 4.5
@export var sensitivity = 0.003
@export var slide_speed_boost = 12.0
@export var slide_friction = 4.0
@export var crouch_height_factor = 0.5 # Percentage of height when crouching

var hud_instance = null
var shop_instance = null
var pause_instance = null
var current_weapon = null
var is_shop_open = false
var is_paused = false

# Movement State
var is_crouching = false
var is_sliding = false
var slide_vector = Vector3.ZERO
var default_height = 2.0 # Default capsule height (assuming 2.0)
var original_camera_y = 0.0

var collision_shape: CollisionShape3D = null
var original_capsule_height = 2.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Setup Audio
	audio_jump = AudioStreamPlayer.new()
	audio_jump.stream = sound_jump
	audio_jump.bus = "SFX"
	add_child(audio_jump)
	
	audio_run = AudioStreamPlayer.new()
	audio_run.stream = sound_run
	audio_run.bus = "SFX"
	add_child(audio_run)
	
	audio_walk = AudioStreamPlayer.new()
	audio_walk.stream = sound_walk
	audio_walk.bus = "SFX"
	add_child(audio_walk)
	
	# Recherche plus robuste de la caméra (récursive)
	camera = _find_camera_node(self)
	
	if not camera:
		push_error("ERREUR CRITIQUE: Aucune Camera3D trouvée dans l'arborescence du Player !")
	else:
		print("Camera trouvée : " + camera.name)
		original_camera_y = camera.position.y
		
	# Assume CollisionShape is a child named "CollisionShape3D" and has a CapsuleShape3D
	# We will find it dynamically if needed or assume standard structure
		
	# Initialisation du HUD
	hud_instance = hud_scene.instantiate()
	add_child(hud_instance)
	
	# Initialisation de la Boutique (cachée au début)
	shop_instance = shop_scene.instantiate()
	add_child(shop_instance)
	shop_instance.visible = false
	shop_instance.weapon_selected.connect(_on_weapon_bought)
	
	# Initialisation du Menu Pause (caché au début)
	pause_instance = pause_scene.instantiate()
	add_child(pause_instance)
	pause_instance.visible = false
	pause_instance.setup(self) # On passe self pour que le menu puisse modifier la sensibilité
	pause_instance.resume_requested.connect(_toggle_pause)
	pause_instance.quit_requested.connect(_on_quit_game)
	
	# Recherche de l'arme et connexion
	_find_and_connect_weapon(self)

func _on_quit_game():
	get_tree().quit()

func _toggle_pause():
	is_paused = !is_paused
	pause_instance.visible = is_paused
	get_tree().paused = is_paused # Met le jeu en pause (arrête _process et _physics_process sur les noeuds par défaut)
	
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if is_shop_open: _toggle_shop() # Ferme la boutique si elle était ouverte
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_weapon_bought(weapon_path):
	# On ferme la boutique
	_toggle_shop()
	
	# Suppression de l'arme actuelle
	if current_weapon:
		current_weapon.queue_free()
		current_weapon = null
	
	# Instanciation de la nouvelle arme
	var new_weapon_scene = load(weapon_path)
	if new_weapon_scene:
		var new_weapon = new_weapon_scene.instantiate()
		# On attache l'arme à la CAMÉRA pour qu'elle suive la vue
		if camera:
			camera.add_child(new_weapon)
		else:
			add_child(new_weapon)
			
		# On laisse le temps à la node d'être prête avant de la connecter
		# Ou on appelle manuellement la connexion
		current_weapon = new_weapon
		current_weapon.ammo_changed.connect(_on_ammo_changed)
		_on_ammo_changed(current_weapon.max_ammo)
		
func _toggle_shop():
	is_shop_open = !is_shop_open
	shop_instance.visible = is_shop_open
	
	if is_shop_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _find_and_connect_weapon(node: Node):
	for child in node.get_children():
		if child is Weapon:
			current_weapon = child
			current_weapon.ammo_changed.connect(_on_ammo_changed)
			# Initial update
			_on_ammo_changed(current_weapon.max_ammo)
			return
		_find_and_connect_weapon(child)

func _on_ammo_changed(amount):
	if hud_instance:
		hud_instance.update_ammo(amount, current_weapon.max_ammo if current_weapon else 0)

# Fonction utilitaire pour chercher une Camera3D dans tous les descendants
func _find_camera_node(node: Node) -> Camera3D:
	for child in node.get_children():
		if child is Camera3D:
			return child
		# Recherche récursive dans les enfants
		var found = _find_camera_node(child)
		if found:
			return found
	return null

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		
	if Input.is_key_pressed(KEY_B) and not event.is_echo():
		# Petite astuce pour éviter le spam si on maintient B, mais idealement on utilise l'Input Map "shop"
		if event.is_pressed(): # Seulement quand on appuie
			pass # Géré dans _process ou via une action, ici on utilise is_action_just_pressed dans _physics_process ou ici
			
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		_toggle_shop()
		
	if is_shop_open: return # Pas de mouvement de caméra si boutique ouverte
	
	if not camera: return # Sécurité pour éviter le crash
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotate_x(-event.relative.y * sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		audio_jump.play()

	# Gestion du tir
	if current_weapon and not is_shop_open:
		if current_weapon.automatic:
			if Input.is_action_pressed("fire"):
				current_weapon.shoot()
		else:
			if Input.is_action_just_pressed("fire"):
				current_weapon.shoot()
		
	# --- Crouch & Slide System ---
	# On utilise la touche CONTROL (faut vérifier si l'action 'crouch' est mappée ou utiliser un check clavier direct)
	# Pour simplifier on va accepter 'crouch' s'il existe, ou KEY_CTRL
	var crouch_pressed = Input.is_key_pressed(KEY_CTRL) or Input.is_action_pressed("crouch")
	
	if crouch_pressed:
		if not is_crouching:
			# DÉBUT DU CROUCH
			is_crouching = true
			
			# Slide trigger : Si on est au sol et qu'on sprintait/courait vite
			# On check si on bouge assez vite
			var flat_vel = Vector2(velocity.x, velocity.z)
			if flat_vel.length() > speed_walk + 0.5 and is_on_floor():
				is_sliding = true
				# Boost de slide dans la direction actuelle
				var slide_dir = flat_vel.normalized()
				slide_vector = Vector3(slide_dir.x, 0, slide_dir.y) * slide_speed_boost
				velocity.x = slide_vector.x
				velocity.z = slide_vector.z
				
			_update_crouch_visuals(true)
	else:
		if is_crouching:
			# FIN DU CROUCH = On se relève (sauf si obstacle ? Pour l'instant on force)
			is_crouching = false
			is_sliding = false
			_update_crouch_visuals(false)

	# --- Movement Physics ---
	var direction = Vector3.ZERO
	var current_speed = speed_walk
	
	# Calcul direction standard
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_sliding:
		# LOGIQUE DE GLISSADE
		# On ignore les inputs de déplacement, on continue sur la lancée avec friction
		# Appliquer une friction pour ralentir le slide
		var flat_vel = Vector2(velocity.x, velocity.z)
		# Ralentissement (Lerp vers 0)
		flat_vel = flat_vel.move_toward(Vector2.ZERO, slide_friction * delta)
		
		velocity.x = flat_vel.x
		velocity.z = flat_vel.y
		
		# Si on est trop lent, on arrête de slider (mais on reste accroupi)
		if flat_vel.length() < speed_crouch:
			is_sliding = false
			
	else:
		# LOGIQUE DE DÉPLACEMENT NORMALE
		if is_crouching:
			current_speed = speed_crouch
		elif Input.is_action_pressed("sprint") and not is_crouching:
			current_speed = speed_run
		
		# Application vélocité
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			# Pas de direction = arrêt
			velocity.x = move_toward(velocity.x, 0, current_speed)
			velocity.z = move_toward(velocity.z, 0, current_speed)

	# --- Gestion Audio ---
	if is_on_floor() and direction.length() > 0 and not is_sliding:
		# On bouge au sol
		if current_speed == speed_run:
			# Course
			if not audio_run.playing:
				audio_run.play()
			audio_walk.stop()
		else:
			# Marche (ou Crouch walk)
			if not audio_walk.playing:
				# Pour le crouch, on pourrait pitch down, mais ici on joue walk
				audio_walk.play()
			audio_run.stop()
	else:
		# En l'air, immobile ou Glissade (on pourrait ajouter un son de slide...)
		audio_run.stop()
		audio_walk.stop()

	move_and_slide()

# Fonction helper pour animer la caméra/collider
func _update_crouch_visuals(crouching: bool):
	var tween = get_tree().create_tween()
	
	# Gestion Camera
	var target_cam_y = original_camera_y
	if crouching:
		target_cam_y = original_camera_y * crouch_height_factor
	
	if camera:
		tween.parallel().tween_property(camera, "position:y", target_cam_y, 0.2)
		
	# Gestion Hitbox (CollisionShape)
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var target_height = original_capsule_height
		if crouching:
			target_height = original_capsule_height * crouch_height_factor
			
		# Tween de la hauteur de la capsule
		tween.parallel().tween_property(collision_shape.shape, "height", target_height, 0.2)
		
		# Ajustement de la position pour garder les pieds au sol
		# Si l'origine est au centre de la capsule (standard) :
		# Pos Y = Hauteur / 2
		var target_shape_y = target_height / 2.0
		tween.parallel().tween_property(collision_shape, "position:y", target_shape_y, 0.2)
