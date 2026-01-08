extends CharacterBody3D

@export var gravity = 9.8
@export var default_weapon_scene: PackedScene # Weapon to equip on spawn

# Team ID
@export var team_id: int = 1 # 1: Blue, 2: Red

@onready var camera: Camera3D
var hud_scene = null
var shop_scene = null
var pause_scene = null
var scoreboard_scene = null # New scoreboard

var hud_instance = null
var shop_instance = null
var pause_instance = null
var scoreboard_instance = null

var name_label: Label3D = null # Visual Name Tag


# Audio Resources
var sound_jump = preload("res://Assets/Sounds/jump.mp3")
var sound_run = preload("res://Assets/Sounds/run.mp3")
var sound_walk = preload("res://Assets/Sounds/walk.mp3")
var sound_crouch = preload("res://Assets/Sounds/crouch.mp3")
var sound_slide = preload("res://Assets/Sounds/slide.mp3")

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
@export var crouch_height_factor = 0.7 # 30% reduction (Factor 0.7)


var current_weapon = null
var is_shop_open = false
var is_paused = false
var can_shop = true
var spawn_position = Vector3.ZERO

# Movement State
var is_crouching = false
var is_sliding = false
var slide_vector = Vector3.ZERO
var default_height = 2.0 # Default capsule height (assuming 2.0)
var original_camera_y = 0.0

# Recoil System
var mouse_rotation_x: float = 0.0 # Rotation X brute (input souris) sans le recul
var current_recoil_x: float = 0.0 # Recul actuel en degrés (PITCH Camera)
var current_recoil_y: float = 0.0 # Recul actuel en degrés (YAW Spray)
var current_spray_pitch: float = 0.0 # Recul actuel en degrés (PITCH Spray - Balles uniquement)
var target_recoil_x: float = 0.0 # Cible du recul
var recoil_recovery_speed: float = 5.0

var is_dead: bool = false # Added new variable

var collision_shape: CollisionShape3D = null
var original_capsule_height = 2.0
var previous_position: Vector3 = Vector3.ZERO

# Network Sync Variables (for Interpolation)
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_rotation: Vector3 = Vector3.ZERO
@export var sync_cam_rotation: float = 0.0
@export var sync_stance: int = 0 # 0: Stand, 1: Crouch, 2: Slide

func _ready():
	# 1. SETUP COMMON (Visuals, Audio, Components) ============
	# Setup Name Label
	_setup_name_label()
	
	# Camera Find (Needed for attachment of weapons for everyone)
	camera = _find_camera_node(self)
	
	# 2. Visual ID & Colors
	var id = str(name).to_int()
	
	# Random Color based on ID to differentiate players
	if has_node("CollisionShape3D/BodyMesh"):
		var mesh_inst = $CollisionShape3D/BodyMesh
		var new_mat = StandardMaterial3D.new()
		var r = (id * 123 % 255) / 255.0
		var g = (id * 321 % 255) / 255.0
		var b = (id * 213 % 255) / 255.0
		new_mat.albedo_color = Color(r, g, b)
		mesh_inst.material_override = new_mat
		
	# Hide own body mesh (Visual comfort for local, but check later)
	# Actually, we ONLY want to hide it if WE are the local player controlling it.
	# But is_multiplayer_authority() handles that. 
	# Wait, if we are Client A viewing Client B (Remote), we WANT to see B's mesh.
	# So hiding should stay in Authority block? 
	# YES. Hiding is only for the "eyes" of the player.
	
	# Default Weapon (Must be equipped for everyone so visuals exist)
	if not default_weapon_scene:
		# Fallback hardcore si la variable export n'est pas remplie
		default_weapon_scene = load("res://Scenes/Weapons/Pistol.tscn")
		
	if default_weapon_scene:
		_equip_weapon_local(default_weapon_scene)
		print("Player ", name, " equipped default weapon: ", default_weapon_scene.resource_path)
	else:
		push_error("No default weapon scene found for Player " + name)

	# Assume CollisionShape
	if has_node("CollisionShape3D"):
		collision_shape = $CollisionShape3D
		# Make shape unique to avoid shared resource issues between players
		if collision_shape.shape:
			collision_shape.shape = collision_shape.shape.duplicate()
			
	# Init prev pos
	previous_position = global_position
		
	# 2. AUTHORITY CHECKS (Input, Physics, UI) =================
	
	# Check Team (Simple Alternating Assigment based on ID parity for now)
	# Default fallback
	if id % 2 == 0:
		team_id = 2
	else:
		team_id = 1
	
	# Fetch Team from GameManager (Server Side Source of Truth)
	if multiplayer.is_server():
		var stored_team = GameManager.get_player_team(id)
		if stored_team != 0:
			team_id = stored_team
		
		# Sync to clients
		rpc("sync_team_data", team_id)
	else:
		# Client: Try to fetch if available
		var stored_team = GameManager.get_player_team(id)
		if stored_team != 0:
			team_id = stored_team
	
	# Initial Color Apply (Might be default Blue, upgraded later by sync)
	_apply_team_color(team_id)

	# Network Authority Check
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process_unhandled_input(false)
		
		# Disable Camera for remotes (We don't want to look through their eyes)
		if camera:
			camera.current = false
			
		return
	
	# --- LOCAL AUTHORITY ONLY BELOW ---
	
	# Hide own body
	if has_node("CollisionShape3D/BodyMesh"):
		$CollisionShape3D/BodyMesh.visible = false
		
	# Authority init
	sync_position = global_position
	sync_rotation = global_rotation
	spawn_position = global_position # Store initial spawn
	
	if camera:
		sync_cam_rotation = camera.rotation.x
		camera.current = true # Ensure we look through our eyes

	GameManager.game_started.connect(_on_respawn_signal) # Hook for respawn
	GameManager.players_updated.connect(_on_players_data_updated) # Hook for team sync
	# Shop Control Hooks
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_active.connect(_on_round_active) # Use this to close shop
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)



	
	# Load UI scenes locally for the player
	hud_scene = load("res://Scenes/UI/HUD.tscn")
	shop_scene = load("res://Scenes/UI/ShopMenu.tscn")
	pause_scene = load("res://Scenes/UI/PauseMenu.tscn")
	scoreboard_scene = load("res://Scenes/UI/Scoreboard.tscn")

	
	# Initialisation du HUD
	if hud_scene:
		hud_instance = hud_scene.instantiate()


	# Setup Audio
	audio_jump = AudioStreamPlayer.new()
	audio_jump.stream = sound_jump
	audio_jump.bus = "Master"
	add_child(audio_jump)
	
	audio_run = AudioStreamPlayer.new()
	audio_run.stream = sound_run
	audio_run.bus = "Master"
	add_child(audio_run)
	
	audio_walk = AudioStreamPlayer.new()
	audio_walk.stream = sound_walk
	audio_walk.bus = "Master"
	add_child(audio_walk)
	
	audio_crouch = AudioStreamPlayer.new()
	audio_crouch.stream = sound_crouch
	audio_crouch.bus = "Master"
	add_child(audio_crouch)
	
	audio_slide = AudioStreamPlayer.new()
	audio_slide.stream = sound_slide
	audio_slide.bus = "Master"
	add_child(audio_slide)
	
	# Recherche plus robuste de la caméra (récursive)
	camera = _find_camera_node(self)
	
	if not camera:
		push_error("ERREUR CRITIQUE: Aucune Camera3D trouvée dans l'arborescence du Player !")
	else:
		# Si on n'est pas l'autorité, on désactive la caméra du joueur distant
		if not is_multiplayer_authority():
			camera.current = false
		else:
			# Si on EST l'autorité, on force cette caméra comme active
			camera.current = true
			
		print("Camera trouvée : " + camera.name)
		original_camera_y = camera.position.y
		mouse_rotation_x = camera.rotation.x
	
	# Visual ID Debug & Color Randomization
	if has_node("NameLabel"):
		get_node("NameLabel").text = "P" + str(id)
	
	if has_node("CollisionShape3D/BodyMesh"):
		var mesh_inst = get_node("CollisionShape3D/BodyMesh")
		var new_mat = StandardMaterial3D.new()
		# Generate color from ID
		var r = (id * 123 % 255) / 255.0
		var g = (id * 321 % 255) / 255.0
		var b = (id * 213 % 255) / 255.0
		new_mat.albedo_color = Color(r, g, b)
		mesh_inst.material_override = new_mat
		
	add_to_group("player")
		
	# Assume CollisionShape is a child named "CollisionShape3D" and has a CapsuleShape3D
	# We will find it dynamically if needed or assume standard structure
	if has_node("CollisionShape3D"):
		collision_shape = $CollisionShape3D
		
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
	
	# Initialisation du Scoreboard
	if scoreboard_scene:
		scoreboard_instance = scoreboard_scene.instantiate()
		add_child(scoreboard_instance)
		scoreboard_instance.visible = false

	
	# Recherche de l'arme et connexion
	# Au lieu de 'find', on équipe l'arme par défaut pour tout le monde au spawn
	# Le host le fait, et les clients le font aussi localement.
	# Idéalement le serveur devrait dire "Equip Pistol", mais ici on force le défaut.
	_equip_weapon_local("res://Scenes/Weapons/Pistol.tscn")
	
	# Connexion HealthComponent
	# 7. Init Spawn Position
	spawn_position = global_position
	
	# 8. Start Health Component
	if has_node("HealthComponent"):
		var health_comp = $HealthComponent
		health_comp.health_changed.connect(_on_health_changed)
		health_comp.died.connect(_on_died)
		var max_hp = health_comp.max_health
		if hud_instance and hud_instance.has_method("update_health"):
			hud_instance.update_health(max_hp)
	
	print("Player Ready: ", name, " Team: ", team_id, " Auth: ", is_multiplayer_authority())

# Shop Control Logic


func _apply_team_color(t_id):
	if has_node("CollisionShape3D/BodyMesh"):
		var mesh_inst = $CollisionShape3D/BodyMesh
		var new_mat = StandardMaterial3D.new()
		if t_id == 1:
			new_mat.albedo_color = Color(0.2, 0.5, 1.0) # Blue
		else:
			new_mat.albedo_color = Color(1.0, 0.2, 0.2) # Red
		mesh_inst.material_override = new_mat


func _on_quit_game():
	# Retour Lobby propre via NetworkManager
	NetworkManager.disconnect_game()

func _toggle_pause():
	is_paused = !is_paused
	pause_instance.visible = is_paused
	# get_tree().paused = is_paused # REMOVED: User wants game to continue
	
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if is_shop_open: _toggle_shop() # Ferme la boutique si elle était ouverte
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_weapon_bought(weapon_path):
	# On ferme la boutique
	_toggle_shop()
	
	# Local Equip + Network Sync
	_equip_weapon_local(weapon_path)
	rpc("equip_weapon_remote", weapon_path)

func _equip_weapon_local(weapon_data):
	# Suppression de l'arme actuelle
	if current_weapon:
		# Cleaning up signals is auto when freeing, but good practice
		current_weapon.queue_free()
		current_weapon = null
	
	print("Equipping weapon data: ", weapon_data)
	
	var new_weapon_scene = null
	if weapon_data is PackedScene:
		new_weapon_scene = weapon_data
	elif weapon_data is String:
		new_weapon_scene = load(weapon_data)
		
	if new_weapon_scene:
		var new_weapon = new_weapon_scene.instantiate()
		
		# Attachement :
		# Si c'est nous (Autorité) -> Camera (Vue FPS)
		# Si c'est un autre (Remote) -> Camera aussi pour l'instant (car le mesh du joueur n'a pas de mains)
		# Le 'MultiplayerSynchronizer' sync la rotation caméra, donc l'arme suivra le regard des autres.
		
		if camera:
			camera.add_child(new_weapon)
		else:
			add_child(new_weapon)
			
		# IMPORTANT: The weapon must belong to the same authority as the player logic
		new_weapon.set_multiplayer_authority(get_multiplayer_authority())
			
		current_weapon = new_weapon
		# Connect signals (Safe to connect even if remote, signals just won't trigger logic if not auth)
		if is_multiplayer_authority():
			current_weapon.ammo_changed.connect(_on_ammo_changed)
			# Only authority controls reloading/ammo
			_on_ammo_changed(current_weapon.current_ammo, current_weapon.reserve_ammo)
		
		if not current_weapon.fired.is_connected(_on_weapon_fired):
			current_weapon.fired.connect(_on_weapon_fired)
			
		# Connect Reload Sync
		if is_multiplayer_authority():
			if not current_weapon.reloading_started.is_connected(_on_reloading_started):
				current_weapon.reloading_started.connect(_on_reloading_started)

func _on_reloading_started():
	rpc("rpc_reload_weapon")

@rpc("call_remote")
func equip_weapon_remote(weapon_path):
	_equip_weapon_local(weapon_path)
		
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

@rpc("call_local")
func rpc_fire_weapon(x, y, z):
	if is_multiplayer_authority(): return
	
	# ISOLATION CHECK: Ignore shots from other lobbies
	var sender_id = multiplayer.get_remote_sender_id()
	if not NetworkManager.is_player_in_my_room(sender_id):
		return
	
	# Debug pour vérifier que le RPC arrive
	# print("RPC Remote Fire received on ", name, " from ", multiplayer.get_remote_sender_id())
	
	if current_weapon:
		current_weapon.trigger_visuals(Vector3(x, y, z))
		_on_weapon_fired()

@rpc("call_local")
func rpc_reload_weapon():
	if is_multiplayer_authority(): return
	
	if current_weapon:
		# On joue juste le son pour l'instant (ou l'anim si on en avait une)
		if current_weapon.reload_sound:
			current_weapon.play_sound(current_weapon.reload_sound)

func _on_weapon_fired():
	# Ajout du recul
	if current_weapon:
		var recoil_vec = current_weapon.get_recoil_vector()
		
		# PITCH CAMERA (Vertical Main)
		current_recoil_x += recoil_vec.x
		if current_recoil_x > current_weapon.max_recoil_deg:
			current_recoil_x = current_weapon.max_recoil_deg
			
		# YAW SPRAY (Horizontal)
		current_recoil_y += recoil_vec.y
		current_recoil_y = clamp(current_recoil_y, -15.0, 15.0)
		
		# PITCH SPRAY (Vertical Jitter)
		if recoil_vec is Vector3:
			current_spray_pitch += recoil_vec.z
			current_spray_pitch = clamp(current_spray_pitch, -5.0, 5.0)
			
		recoil_recovery_speed = current_weapon.recoil_recovery

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
	if not is_multiplayer_authority(): return

	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		
	if Input.is_key_pressed(KEY_B) and not event.is_echo():
		# Petite astuce pour éviter le spam si on maintient B, mais idealement on utilise l'Input Map "shop"
		if event.is_pressed(): # Seulement quand on appuie
			pass # Géré dans _process ou via une action, ici on utilise is_action_just_pressed dans _physics_process ou ici
			
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		if can_shop or is_shop_open: # Allow closing even if can_shop is false
			_toggle_shop()
		
	if is_shop_open or is_paused: return # Pas de mouvement de caméra si boutique/pause ouverte
	
	if not camera: return # Sécurité pour éviter le crash
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		# On modifie la valeur logique, pas directement la caméra (qui recevra aussi le recul)
		mouse_rotation_x -= event.relative.y * sensitivity
		mouse_rotation_x = clamp(mouse_rotation_x, deg_to_rad(-90), deg_to_rad(90))
		# NOTE: On applique pas tout de suite à la caméra, ce sera fait dans _physics_process

func _process(delta):
	# Safety Check: If peer is disconnected, stop processing network logic
	if not multiplayer.has_multiplayer_peer(): return

	# --- BRUTE FORCE VISIBILITY ENFORCEMENT ---
	# Ensure dead players are NEVER visible. Poll GameManager directly.
	var my_pid = str(name).to_int()
	if GameManager.players_data.has(my_pid):
		if not GameManager.players_data[my_pid]["alive"]:
			if visible:
				visible = false
				# Also disable collision if it wasn't done
				if collision_shape and not collision_shape.disabled:
					collision_shape.disabled = true
			
			# If we are the authority (Client or Host dying), run spectator
			if is_multiplayer_authority():
				_process_spectator(delta)
			
			# Stop processing visual interpolation for dead entities
			return

	# Interpolation for remote players
	if not is_multiplayer_authority():
		# Smooth Movement
		global_position = global_position.lerp(sync_position, 20.0 * delta)
		
		# Smooth Rotation (Y quaternion slerp would be better but lerp angle is okay for Y)
		rotation.y = lerp_angle(rotation.y, sync_rotation.y, 20.0 * delta)
		
	# Smooth Camera Look (Up/Down)
		if camera:
			camera.rotation.x = lerp_angle(camera.rotation.x, sync_cam_rotation, 20.0 * delta)
			
	# VISIBILITY RESTORATION (Brute Force Reverse)
	# If we are alive but hidden, show ourselves (fix for respawn visibility)
	if GameManager.players_data.has(my_pid) and GameManager.players_data[my_pid]["alive"]:
		if not visible:
			# Only show if intended (e.g. not local authority wanting to hide body mesh)
			# Actually 'visible' on ROOT should always be true if alive.
			visible = true
			if collision_shape: collision_shape.disabled = false
			
			# Restore Body Mesh Visibility based on Authority
			if has_node("CollisionShape3D/BodyMesh"):
				if is_multiplayer_authority():
					$CollisionShape3D/BodyMesh.visible = false
				else:
					$CollisionShape3D/BodyMesh.visible = true

	# Update Name Tag (Text & Color)
	_update_name_label()
	
	# Visual Update for Stance (Local AND Remote)
	# This ensures remotes see the stance change via sync_stance
	# Remotes read sync_stance. Local sets sync_stance in physics.
	_update_stance_visuals(sync_stance, delta)

func _physics_process(delta):
	if not is_multiplayer_authority(): return
	
	# Determine Stance
	var current_stance = 0 # Stand
	if is_sliding:
		current_stance = 2 # Slide
	elif is_crouching:
		current_stance = 1 # Crouch
		
	sync_stance = current_stance
	
	# Update Sync Vars (Authority)
	sync_position = global_position
	sync_rotation = rotation
	if camera: sync_cam_rotation = camera.rotation.x

	# Add the gravity.
	if not is_on_floor() and not is_dead:
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_dead:
		velocity.y = jump_velocity
		audio_jump.play()

	# Gestion du retour du recul (Recovery)
	# Gestion du retour du recul (Recovery)
	# On applique le recovery TOUT LE TEMPS via Lerp pour un retour smooth.
	# La gâchette n'est pas nécessaire ici car le Weapon.gd gère la montée quand on tire.
	# Si on tire: Montée > Descente (donc ça monte). Si on lâche: Montée = 0, donc Descente gagne.
	
	current_recoil_x = lerp(current_recoil_x, 0.0, recoil_recovery_speed * delta)
	current_recoil_y = lerp(current_recoil_y, 0.0, recoil_recovery_speed * delta)
	current_spray_pitch = lerp(current_spray_pitch, 0.0, recoil_recovery_speed * delta)
	
	# Snap to zero pour éviter les flottements
	if abs(current_recoil_x) < 0.01: current_recoil_x = 0.0
	if abs(current_recoil_y) < 0.01: current_recoil_y = 0.0
	if abs(current_spray_pitch) < 0.01: current_spray_pitch = 0.0
	
	if camera:
		# Application finale:
		# PITCH (X) : mouse_rotation_x + Recul Camera
		camera.rotation.x = mouse_rotation_x + deg_to_rad(abs(current_recoil_x))
		# YAW (Y) : Reset
		camera.rotation.y = 0.0
		
		# Application sur l'Arme/Raycast (Spray Pattern)
		if current_weapon and "raycast_node" in current_weapon and current_weapon.raycast_node:
			# YAW Spray (Horizontal)
			current_weapon.raycast_node.rotation.y = deg_to_rad(current_recoil_y)
			# PITCH Spray (Vertical Jitter) - Added on top of camera pitch
			current_weapon.raycast_node.rotation.x = deg_to_rad(-current_spray_pitch) # Negative because Up is negative X
			
			current_weapon.rotation.y = 0.0 # Reset visual if needed

	# Gestion du tir
	if current_weapon and not is_shop_open and not is_dead and not is_paused: # Added not is_paused
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
			if audio_crouch: audio_crouch.play()
			
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
				
	else:
		if is_crouching:
			# FIN DU CROUCH
			is_crouching = false
			is_sliding = false
			if audio_crouch: audio_crouch.play()

	# --- Movement Physics ---
	# Safety Net for Falling into Void
	if global_position.y < -30.0:
		velocity = Vector3.ZERO
		if spawn_position != Vector3.ZERO:
			global_position = spawn_position
		else:
			global_position = Vector3(0, 5, 0)
			
	if is_dead:
		velocity = Vector3.ZERO # Complete freeze
		move_and_slide()
		return

	var direction = Vector3.ZERO
	var current_speed = speed_walk
	
	# Calcul direction standard
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_sliding:
		# LOGIQUE DE GLISSADE
		# On ignore les inputs de déplacement, on continue sur la lancée avec friction
		# Problème user: "la glissade se fait dans le sens de la course, pas le sens de la camera"
		# Current implementation already USES `velocity` (via flat_vel) which is the movement direction.
		# `slide_vector` was set in the trigger block BEFORE this.
		# Check the Trigger block (see around line 565)
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

# Fonction helper pour animer les visuels en fonction de la stance
func _update_stance_visuals(stance: int, delta: float):
	# stance: 0=Stand, 1=Crouch, 2=Slide
	# 1. Determine Effective Velocity (Visual)
	var visual_velocity = velocity
	if not is_multiplayer_authority():
		# Estimate velocity from position change for remotes
		if delta > 0:
			visual_velocity = (global_position - previous_position) / delta
	
	# Update prev pos for next frame
	previous_position = global_position
	
	# Gestion Camera Height
	var target_cam_y = original_camera_y
	var target_mesh_height = original_capsule_height
	var target_mesh_y = original_capsule_height / 2.0
	var target_mesh_rot_x = 0.0
	
	if stance == 1: # Crouch
		target_cam_y = original_camera_y * crouch_height_factor
	elif stance == 2: # Slide
		target_cam_y = original_camera_y * crouch_height_factor * 0.8
		target_mesh_rot_x = deg_to_rad(75.0)
	
	# Apply Camera
	if camera:
		camera.position.y = move_toward(camera.position.y, target_cam_y, 5.0 * delta)
		
	# Apply Mesh/Collider visual
	if collision_shape:
		# Visuel Mesh
		var mesh = collision_shape.get_node_or_null("BodyMesh")
		if mesh:
			# Height scaling
			var target_scale_y = 1.0
			if stance == 1: target_scale_y = crouch_height_factor # 0.7 now
			if stance == 2: target_scale_y = 1.0
			
			mesh.scale.y = move_toward(mesh.scale.y, target_scale_y, 10.0 * delta)
			
			# Rotation X (Couché)
			var current_rot_x = mesh.rotation.x
			mesh.rotation.x = move_toward(current_rot_x, target_mesh_rot_x, 10.0 * delta)
			
			# Rotation Y (Direction)
			var target_mesh_rot_y = 0.0
			
			if stance == 2: # Slide
				if visual_velocity.length() > 0.1:
					var velocity_local = global_transform.basis.inverse() * visual_velocity
					velocity_local.y = 0
					if velocity_local.length() > 0.1:
						target_mesh_rot_y = Vector3.FORWARD.signed_angle_to(velocity_local.normalized(), Vector3.UP)
			
			mesh.rotation.y = lerp_angle(mesh.rotation.y, target_mesh_rot_y, 10.0 * delta)
			
			# Position offset logic for MESH
			# On descend le mesh pour qu'il soit au sol
			var target_pos_y = 0.0
			if stance == 2: target_pos_y = -0.4 # Moins bas qu'avant (-0.7 était trop)
			
			mesh.position.y = move_toward(mesh.position.y, target_pos_y, 10.0 * delta)

		# COLLIDER PHYSIQUE (POUR TOUS) - SMOOTHED
		if collision_shape.shape is CapsuleShape3D:
			var shp = collision_shape.shape
			var target_h = original_capsule_height
			
			if stance != 0:
				target_h = original_capsule_height * crouch_height_factor
			
			# Modif Hauteur Physics (Smooth)
			# On utilise le meme lerp speed que le visuel pour synchroniser
			var current_h = shp.height
			var new_h = move_toward(current_h, target_h, 10.0 * delta)
			shp.height = new_h
			
			# Modif Position Physics (Calculé sur la hauteur COURANTE pour garder pieds au sol)
			# Center Offset = -(Diff / 2) -> (Orig - Curr) / 2
			var height_diff = original_capsule_height - new_h
			var center_offset = - (height_diff / 2.0)
			
			collision_shape.position.y = center_offset

# --- RESTORED FUNCTIONS ---

func _on_round_started():
	can_shop = true
	if hud_instance and hud_instance.has_method("show_round_start"):
		pass

func _on_round_active():
	can_shop = false
	if is_shop_open:
		_toggle_shop() # Close if open

func _on_died():
	if is_dead: return
	is_dead = true
	print("Player Died! Switching to Spectator Mode.")
	
	# Tell Server we died
	if is_multiplayer_authority():
		var killer_id = -1
		var weapon_name = "Unknown"
		
		# Getting killer algorithm needs improvement in HealthComponent to store weapon
		if has_node("HealthComponent"):
			killer_id = $HealthComponent.last_attacker_id
		
		# Robust Death Reporting: Call GameManager Global RPC to avoid missing node errors
		GameManager.report_player_death.rpc(str(name).to_int(), killer_id, weapon_name)
	
	# Désactiver les collisions
	if collision_shape: collision_shape.disabled = true
	
	# Cacher l'arme et les bras
	if current_weapon:
		current_weapon.visible = false
		
	# Cacher le corps du joueur (GLOBAL HIDE)
	# On cache tout le player pour éviter les glitchs visuels
	visible = false
	
	if has_node("CollisionShape3D/BodyMesh"):
		$CollisionShape3D/BodyMesh.visible = false
	
	# Switch to Spectator
	# Switch to Spectator
	_enable_spectator_mode()
	
	# CRITICAL FIX: Stop Physics completely to prevent falling through map due to no collision
	velocity = Vector3.ZERO
	set_physics_process(false)

@rpc("call_local", "reliable")
func sync_team_data(new_team):
	team_id = new_team
	_apply_team_color(team_id)
	
@rpc("any_peer", "reliable")
func notify_death(id, killer_id = -1, weapon_name = "Weapon"):
	if multiplayer.is_server():
		GameManager.player_died(id, killer_id, weapon_name)

@rpc("any_peer")
func register_request(pid, pname, pteam):
	if multiplayer.is_server():
		GameManager.register_player(pid, pname, pteam)

func _start_spectator():
	_enable_spectator_mode()

var spectating_target = null
var spectating_index = 0

func _enable_spectator_mode():
	var all_players = get_tree().get_nodes_in_group("player")
	var candidates = []
	for p in all_players:
		if p != self and not p.is_dead:
			candidates.append(p)
			
	if candidates.size() > 0:
		spectating_target = candidates[0]
	else:
		spectating_target = null

func _process_spectator(delta):
	# Spectator Controls
	if Input.is_action_just_pressed("fire"):
		_cycle_spectator_target(1)
	elif Input.is_action_just_pressed("aim"): # Right Click
		_cycle_spectator_target(-1)
		
	# If target invalid, cycle
	if spectating_target and (not is_instance_valid(spectating_target) or spectating_target.is_dead):
		_cycle_spectator_target(1)
		
	# Match Camera
	if spectating_target and is_instance_valid(spectating_target) and spectating_target.camera:
		camera.global_transform = spectating_target.camera.global_transform

func _cycle_spectator_target(dir):
	var all_players = get_tree().get_nodes_in_group("player")
	var candidates = []
	for p in all_players:
		if p != self and not p.is_dead:
			candidates.append(p)
	
	if candidates.size() == 0:
		spectating_target = null
		return
		
	spectating_index = (spectating_index + dir) % candidates.size()
	spectating_target = candidates[spectating_index]

func _on_respawn_signal():
	# Reset
	is_dead = false
	if collision_shape: collision_shape.disabled = false
	if current_weapon: current_weapon.visible = true
	
	# Restore Root Visibility
	visible = true
	
	# Restore Body Visibility
	if has_node("CollisionShape3D/BodyMesh"):
		if not is_multiplayer_authority():
			$CollisionShape3D/BodyMesh.visible = true
		else:
			$CollisionShape3D/BodyMesh.visible = false 
	
	# Respawn at original spawn point
	global_position = spawn_position
	velocity = Vector3.ZERO
	
	var health_comp = get_node_or_null("HealthComponent")
	if health_comp: health_comp.reset_health()
	
	camera.current = true
	
	# CRITICAL FIX: Restart Physics
	set_physics_process(true)

func _setup_name_label():
	if name_label: return
	name_label = Label3D.new()
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position.y = 2.3
	name_label.pixel_size = 0.005
	name_label.font_size = 64
	name_label.outline_render_priority = 0
	name_label.modulate = Color.WHITE
	name_label.text = "Loading..."
	add_child(name_label)

func _update_name_label():
	if not name_label: return
	
	# Hide if dead
	if is_dead:
		name_label.visible = false
		return
	
	# 1. Update Name (Lazy Load)
	var pid = str(name).to_int()
	if GameManager.players_data.has(pid):
		name_label.text = GameManager.players_data[pid]["name"]
	else:
		name_label.text = "P" + str(pid)
		
	# 2. Update Visibility/Color based on relation to Local Player
	if is_multiplayer_authority():
		name_label.visible = false # Hide own name
		return
		
	var local_id = multiplayer.get_unique_id()
	var local_team = GameManager.get_player_team(local_id)
	
	# If logic is incomplete, hide to avoid confusion
	if local_team == 0 or team_id == 0:
		name_label.visible = false
		return
		
	if local_team == team_id:
		# Ally -> White
		name_label.modulate = Color.WHITE
		name_label.visible = true
	else:
		# Enemy -> Hidden
		name_label.visible = false

func _on_players_data_updated():
	# Re-fetch team ID
	var id = str(name).to_int()
	var stored_team = GameManager.get_player_team(id)
	if stored_team != 0:
		team_id = stored_team
		_apply_team_color(team_id)
		
		# Check Alive Status
		if GameManager.players_data.has(id):
			var alive = GameManager.players_data[id]["alive"]
			# DEBUG TRACE
			print("Visual Sync for ", name, " (ID: ", id, ") -> Alive: ", alive)
			
			if not alive:
				# Force Hide Logic (Hide ROOT to ensure everything vanishes)
				visible = false
				is_dead = true
				if collision_shape:
					collision_shape.disabled = true
			else:
				# Force Show
				if not is_multiplayer_authority():
					visible = true
					if has_node("CollisionShape3D/BodyMesh"):
						$CollisionShape3D/BodyMesh.visible = true
				else:
					# Local player: Root visible, but BodyMesh hidden
					visible = true
					if has_node("CollisionShape3D/BodyMesh"):
						$CollisionShape3D/BodyMesh.visible = false
						
				if current_weapon:
					current_weapon.visible = true
		
		_update_name_label()
