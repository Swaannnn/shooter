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
# Nouveaux sons
var sound_crouch = preload("res://test/crouch.mp3")
var sound_slide = preload("res://test/slide.mp3")

# Audio Players
var audio_jump: AudioStreamPlayer = null
var audio_run: AudioStreamPlayer = null
var audio_walk: AudioStreamPlayer = null
var audio_crouch: AudioStreamPlayer = null
var audio_slide: AudioStreamPlayer = null

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

# Recoil System
var mouse_rotation_x: float = 0.0 # Rotation X brute (input souris) sans le recul
var current_recoil_x: float = 0.0 # Recul actuel en degrés (PITCH)
var current_recoil_y: float = 0.0 # Recul actuel en degrés (YAW - Horizontal)
var target_recoil_x: float = 0.0 # Cible du recul
var recoil_recovery_speed: float = 5.0

var is_dead: bool = false # Added new variable

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
	
	audio_crouch = AudioStreamPlayer.new()
	audio_crouch.stream = sound_crouch
	audio_crouch.bus = "SFX"
	add_child(audio_crouch)
	
	audio_slide = AudioStreamPlayer.new()
	audio_slide.stream = sound_slide
	audio_slide.bus = "SFX"
	add_child(audio_slide)
	
	# Recherche plus robuste de la caméra (récursive)
	camera = _find_camera_node(self)
	
	if not camera:
		push_error("ERREUR CRITIQUE: Aucune Camera3D trouvée dans l'arborescence du Player !")
	else:
		print("Camera trouvée : " + camera.name)
		original_camera_y = camera.position.y
		mouse_rotation_x = camera.rotation.x
		
	add_to_group("player")
		
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
	
	# Connexion HealthComponent
	var health_comp = get_node_or_null("HealthComponent")
	if health_comp:
		health_comp.health_changed.connect(_on_health_changed)
		health_comp.died.connect(_on_died)
		# Update UI init
		_on_health_changed(0, health_comp.current_health)

func _on_died():
	if is_dead: return
	is_dead = true
	print("Player Died! Switching to Spectator Mode.")
	
	# Désactiver les collisions
	$CollisionShape3D.disabled = true
	
	# Cacher l'arme et les bras
	if current_weapon:
		current_weapon.visible = false
	
	# Optionnel: Cacher le HUD ou afficher "DEAD"
	# if hud_instance: hud_instance.visible = false 
	
	# On garde la caméra active, mais on change la logique de mouvement dans physics_process

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
		if not current_weapon.fired.is_connected(_on_weapon_fired):
			current_weapon.fired.connect(_on_weapon_fired)
			print("PlayerController (Shop): Signal 'fired' Connected")
			
		_on_ammo_changed(current_weapon.current_ammo, current_weapon.reserve_ammo)
		
func _toggle_shop():
	is_shop_open = !is_shop_open
	shop_instance.visible = is_shop_open
	
	if is_shop_open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _find_and_connect_weapon(node: Node) -> bool:
	print("Searching for weapon in: ", node.name)
	for child in node.get_children():
		if child is Weapon:
			print("Weapon FOUND: ", child.name)
			current_weapon = child
			current_weapon.ammo_changed.connect(_on_ammo_changed)
			if not current_weapon.fired.is_connected(_on_weapon_fired):
				current_weapon.fired.connect(_on_weapon_fired)
				print("Signal 'fired' Connected to _on_weapon_fired")
			else:
				print("Signal 'fired' ALREADY connected")
			
			# Initial update
			_on_ammo_changed(current_weapon.current_ammo, current_weapon.reserve_ammo)
			return true
		
		if _find_and_connect_weapon(child):
			return true
			
	return false

func _on_ammo_changed(amount, reserve = 0):
	if hud_instance:
		# On passe aussi la réserve (faudrait mettre à jour le HUD pour l'afficher)
		hud_instance.update_ammo(amount, current_weapon.max_ammo if current_weapon else 0)

func _on_weapon_fired():
	# Ajout du recul
	if current_weapon:
		# On récupère le vecteur de recul (X=Pitch, Y=Yaw)
		var recoil_vec = current_weapon.get_recoil_vector()
		
		# PITCH (Vertical)
		current_recoil_x += recoil_vec.x
		if current_recoil_x > current_weapon.max_recoil_deg:
			current_recoil_x = current_weapon.max_recoil_deg
			
		# YAW (Horizontal / Spray)
		# Pas de clamp strict sur le yaw, ça dépend pattern
		current_recoil_y += recoil_vec.y
		# On peut clamper le Y si besoin pour pas tourner à 360
		current_recoil_y = clamp(current_recoil_y, -15.0, 15.0)
			
		recoil_recovery_speed = current_weapon.recoil_recovery
		# print("Recoil applied! Vec: ", recoil_vec)

func _on_health_changed(amount, current):
	if hud_instance:
		hud_instance.update_health(current)
	# Feedback visuel de dégats ? (Flash rouge)

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
		# On modifie la valeur logique, pas directement la caméra (qui recevra aussi le recul)
		mouse_rotation_x -= event.relative.y * sensitivity
		mouse_rotation_x = clamp(mouse_rotation_x, deg_to_rad(-90), deg_to_rad(90))
		# NOTE: On applique pas tout de suite à la caméra, ce sera fait dans _physics_process

func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor() and not is_dead:
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_dead:
		velocity.y = jump_velocity
		audio_jump.play()

	# Gestion du retour du recul (Recovery)
	if current_weapon:
		var current_time = Time.get_ticks_msec() / 1000.0
		var time_since_fire = current_time - current_weapon.get("last_fire_time")
		
		if time_since_fire > 0.4:
			# APRES le tir (Idle) : Recovery accéléré pour un reset net
			# User request: "Commence direct, mais plus lent qu'il monte" + "Pas de TP à la fin"
			# + "Augmente de 0.5s" -> On ralentit encore le retour
			# Multiplicateur réduit à 1.0 (Vitesse normale) pour un atterrissage en douceur
			var fast_recovery = recoil_recovery_speed * 1.0
			current_recoil_x = move_toward(current_recoil_x, 0.0, fast_recovery * delta)
			current_recoil_y = move_toward(current_recoil_y, 0.0, fast_recovery * delta)
			
			# Snap to zero: Seuil minime pour éviter le TP visible
			if abs(current_recoil_x) < 0.01: current_recoil_x = 0.0
			if abs(current_recoil_y) < 0.01: current_recoil_y = 0.0
		else:
			# PENDANT ou JUSTE APRES : Recovery normale
			# Pour le Pistolet, le user veut que ça redescende "direct" mais "smooth".
			# Donc on applique la recovery tout le temps.
			current_recoil_x = move_toward(current_recoil_x, 0.0, recoil_recovery_speed * delta)
			current_recoil_y = move_toward(current_recoil_y, 0.0, recoil_recovery_speed * delta)
	else:
		current_recoil_x = move_toward(current_recoil_x, 0.0, recoil_recovery_speed * delta)
		current_recoil_y = move_toward(current_recoil_y, 0.0, recoil_recovery_speed * delta)
	
	if camera:
		# Application finale:
		# PITCH (X) : mouse_rotation_x + Recul (toujours positif accumulé, on l'ajoute/soustrait selon le sens voulu)
		# User wanted UP -> So we subtract absolute recoil value to X (Negative X = Look Up).
		# Mais le user a dit que "mouse + abs()" montait. (Probablement mouse_x est inversé quelque part, bref on garde ce qui marche).
		camera.rotation.x = mouse_rotation_x + deg_to_rad(abs(current_recoil_x))
		
		# YAW (Y) : Recul Horizontal
		# On applique ça sur la caméra uniquement (pas le corps du joueur), pour que le crosshair bouge
		# mais que le "devant" du joueur reste stable (plus simple pour la recovery).
		# Attention : camera.rotation.y est généralement 0.
		camera.rotation.y = deg_to_rad(current_recoil_y)

	# Gestion du tir
	if current_weapon and not is_shop_open and not is_dead: # Added not is_dead
		if current_weapon.automatic:
			if Input.is_action_pressed("fire"):
				current_weapon.shoot()
		else:
			if Input.is_action_just_pressed("fire"):
				current_weapon.shoot()
				
		# Rechargement
		if Input.is_key_pressed(KEY_R):
			current_weapon.start_reload()
	
	# --- Crouch & Slide System ---
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
				
				# Son de slide
				if audio_slide: audio_slide.play()
				
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
	# Son de crouch/stand (bruit de tissu)
	if audio_crouch: 
		# On joue le son aussi bien en se baissant qu'en se relevant
		if not audio_crouch.playing: # Evite le spam si spam touche
			audio_crouch.pitch_scale = randf_range(0.9, 1.1)
			audio_crouch.play()
			
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
