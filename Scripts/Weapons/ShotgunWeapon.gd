extends HitscanWeapon
class_name ShotgunWeapon

@export var pellet_count: int = 8 # Nombre de plombs
@export var spread_angle: float = 5.0 # Angle de dispersion en degrés

func _perform_shoot() -> Vector3:
	var last_hit = Vector3.ZERO
	# On tire plusieurs rayons
	for i in range(pellet_count):
		last_hit = _fire_ray_with_spread()
	
	return last_hit

func _fire_ray_with_spread():
	if not raycast_node: return
	
	# Calcul de la dispersion aléatoire
	var spread_rad = deg_to_rad(spread_angle)
	var rand_x = randf_range(-spread_rad, spread_rad)
	var rand_y = randf_range(-spread_rad, spread_rad)
	
	# On simule le tir sans bouger le vrai RayCast (pour ne pas casser la visée centrale)
	# On utilise l'espace local de la caméra/arme
	var origin = raycast_node.global_position
	var forward = -raycast_node.global_transform.basis.z # Z négatif = devant
	
	# Application de la dispersion
	# Note : Une méthode plus robuste consisterait à utiliser un PhysicsRayQueryParameters3D
	# Mais pour faire simple avec le RayCast existant, on va tricher un peu ou utiliser force_raycast_update avec rotation temporaire
	
	# Méthode "Rotation Temporaire" du RayCast (Rapide et sale mais efficace pour prototypes)
	var original_rotation = raycast_node.rotation
	
	raycast_node.rotate_x(rand_x)
	raycast_node.rotate_y(rand_y)
	raycast_node.force_raycast_update()
	
	# Logique de touche (copiée de HitscanWeapon, mais adaptée)
	var start_pos = Vector3.ZERO
	if muzzle_point:
		start_pos = muzzle_point.global_position
	else:
		start_pos = origin
		
	var end_pos = Vector3.ZERO
	
	if raycast_node.is_colliding():
		var collider = raycast_node.get_collider()
		var point = raycast_node.get_collision_point()
		var normal = raycast_node.get_collision_normal()
		end_pos = point
		
		# Impact
		if impact_effect_scene:
			var effect = impact_effect_scene.instantiate()
			get_tree().root.add_child(effect)
			effect.global_position = point
			if normal.is_normalized() and normal != Vector3.UP:
				effect.look_at(point + normal, Vector3.UP)
			elif normal == Vector3.UP:
				effect.look_at(point + normal, Vector3.RIGHT)
				
		# Dégâts
		if collider:
			# D'abord on cherche un HealthComponent
			var health_comp = collider.get_node_or_null("HealthComponent")
			if health_comp:
				# Networked Damage
				if is_multiplayer_authority():
					health_comp.take_damage.rpc(damage)
			elif collider.has_method("take_damage"):
				collider.take_damage(damage) # Dégâts PAR PLOMB
			else:
				# C'est un mur/objet sans vie -> On met un Decal (trou de balle)
				if decal_scene:
					var decal = decal_scene.instantiate()
					collider.add_child(decal)
					decal.global_position = point
					
					# Orientation du decal selon la normale
					if normal != Vector3.UP and normal != Vector3.DOWN:
						decal.look_at(point + normal, Vector3.UP)
					else:
						decal.look_at(point + normal, Vector3.RIGHT)
					
					decal.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
					
		# Legacy check
		elif collider.has_node("HealthComponent"):
			collider.get_node("HealthComponent").take_damage(damage)
	else:
		end_pos = raycast_node.global_position + (-raycast_node.global_transform.basis.z * max_distance)
		
	# Tracer handled by trigger_visuals now (or duplicated for local shooter?)
	# If we remove tracer generation here, local shooter won't see them unless trigger_visuals does it.
	# But _perform_shoot is called by shoot(), and then trigger_visuals is called.
	# So _perform_shoot SHOULD NOT create visuals directly if trigger_visuals does it.
	# HOWEVER, _perform_shoot has the EXACT spread data. trigger_visuals has only "one point" or assumes random.
	# Solution: 
	# Local Shooter: _perform_shoot calculates logic. trigger_visuals creates visuals.
	# BUT passing 8 points is hard.
	# Let's let _perform_shoot create tracers for the SHOOTER.
	# And trigger_visuals create tracers for the REMOTE.
	# So if is_multiplayer_authority(), we create tracers here?
	# Or let trigger_visuals handle everything.
	
	# Current approach: _fire_ray_with_spread does logic AND visuals (tracer).
	# We should disable tracer creation here if it's going to be called by visuals?
	# No, _perform_shoot is for Logic.
	
	# Let's keep tracer creation here for the shooter (precise).
	if is_multiplayer_authority() or multiplayer.get_unique_id() == get_multiplayer_authority():
		if tracer_scene:
			_create_tracer(start_pos, end_pos)
		
	# Reset rotation
	raycast_node.rotation = original_rotation
	
	return end_pos
	
	# Return last end_pos (just to satisfy return type, though triggers handle visuals internally)
	return end_pos

# OVERRIDE: Visuals for Shotgun need to spawn multiple tracers
func trigger_visuals(hit_point = null):
	emit_signal("fired")
	if shoot_sound: play_sound(shoot_sound, 0.95, 1.05)
	
	# If hit_point is provided (from RPC), it's likely just one point (the main hit or ZERO).
	# For shotgun, we want to simulate the spread visuals on the Client.
	# HACK: If we are a remote client (or calling visually), we re-run the "visual only" raycast loop
	# to generate nicer tracers.
	
	var start_pos = Vector3.ZERO
	if muzzle_point:
		start_pos = muzzle_point.global_position
	elif raycast_node:
		start_pos = raycast_node.global_position
		
	# On génère plusieurs tracers visuels
	for i in range(pellet_count):
		# Random spread for visual
		var spread_rad = deg_to_rad(spread_angle)
		var rand_x = randf_range(-spread_rad, spread_rad)
		var rand_y = randf_range(-spread_rad, spread_rad)
		
		# Fake dispersion direction based on camera forward
		var forward = -global_transform.basis.z
		if raycast_node:
			forward = -raycast_node.global_transform.basis.z
			
		# Apply rotation
		var spread_dir = forward.rotated(Vector3.RIGHT, rand_x).rotated(Vector3.UP, rand_y)
		var end = start_pos + (spread_dir * max_distance)
		
		# Raycast for visual collision (optional, expensive?)
		# To be cheap, we just draw to max distance or a random distance?
		# But tracers going through walls looks bad.
		# Let's assume we don't raycast 8 times for visuals on remote to save CPU.
		# Just draw to hit_point (if provided) with offset?
		
		# Better: Just call the tracer creator with random endpoints around the target direction
		if tracer_scene:
			# If we have a main hit point, we bias towards it? No, shotgun is random.
			_create_tracer(start_pos, end)

	# Network Sync Trigger (Done by parent Weapon.gd via super or manual check?)
	# Weapon.gd trigger_visuals does the RPC call. Since we override, we must copy that logic.
	
	var owner_node = get_parent()
	while owner_node:
		if owner_node is CharacterBody3D: break
		owner_node = owner_node.get_parent()

	if owner_node and owner_node.has_method("rpc_fire_weapon") and owner_node.is_multiplayer_authority():
		# Send RPC with a "center" point (not perfect but enough to verify firing)
		var center_hit = hit_point if hit_point else (start_pos + (-global_transform.basis.z * 10.0))
		owner_node.rpc("rpc_fire_weapon", center_hit.x, center_hit.y, center_hit.z)

# OVERRIDE: Shell-by-Shell Reload
func start_reload():
	print("Shotgun: start_reload called. IsReloading: ", is_reloading, " Ammo: ", current_ammo, " Reserve: ", reserve_ammo)
	if is_reloading: return
	if current_ammo == max_ammo: return
	if reserve_ammo <= 0: return
	
	print("Shotgun: Starting reload sequence.")
	is_reloading = true
	_reload_shell()

func _reload_shell():
	# Check conditions pour continuer
	if not is_reloading: return # Cancelled
	if current_ammo >= max_ammo or reserve_ammo <= 0:
		is_reloading = false
		emit_signal("reloading_finished")
		return
		
	emit_signal("reloading_started") # Declenche Anim + Son
	
	# Son spécifique shotgun
	if reload_sound:
		play_sound(reload_sound, 0.95, 1.05)
	
	# Attendre le temps d'insertion
	await get_tree().create_timer(0.6).timeout
	
	if not is_reloading: return # Cancelled pendant le wait
	
	# Ajout d'une cartouche
	current_ammo += 1
	reserve_ammo -= 1
	emit_signal("ammo_changed", current_ammo, reserve_ammo)
	
	# Loop
	_reload_shell()

# OVERRIDE: Allow shooting to interrupt reload
func shoot():
	if is_reloading:
		# On ne peut interrompre que si on a au moins une balle pour tirer
		if current_ammo > 0:
			# Interrupt reload
			is_reloading = false
			emit_signal("reloading_finished") # Reset anims
			
			# Call parent shoot logic? No, Shotgun shoot logic is custom.
			# Re-call shoot (which will fall to else)
			shoot()
	else:
		# Logic copied from Weapon.gd but calling _perform_shoot()
		# We need to ensure we call trigger_visuals()
		
		var current_time = Time.get_ticks_msec() / 1000.0
		if not can_shoot():
			if current_ammo <= 0:
				emit_signal("out_of_ammo")
				start_reload()
			return

		last_fire_time = current_time
		current_ammo -= 1
		emit_signal("ammo_changed", current_ammo, reserve_ammo)
		
		# Logic
		var hit_point = _perform_shoot()
		
		# Visuals
		trigger_visuals(hit_point)
		
		if current_ammo <= 0:
			start_reload()

