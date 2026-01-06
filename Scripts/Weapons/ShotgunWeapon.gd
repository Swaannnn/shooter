extends HitscanWeapon
class_name ShotgunWeapon

@export var pellet_count: int = 8 # Nombre de plombs
@export var spread_angle: float = 5.0 # Angle de dispersion en degrés

func _perform_shoot():
	# On tire plusieurs rayons
	for i in range(pellet_count):
		_fire_ray_with_spread()

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
				health_comp.take_damage(damage)
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
		
	# Tracer
	if tracer_scene:
		_create_tracer(start_pos, end_pos)
		
	# Reset rotation
	raycast_node.rotation = original_rotation

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
	
	# Son spécifique shotgun si besoin (déjà géré par reloading_started via Weapon.gd s'il est generic, 
	# mais ici on veut le jouer à chaque shell. Weapon.gd le joue dans start_reload.
	# Comme on override start_reload, Weapon.gd ne le joue PAS.
	# On doit le jouer ici.
	if reload_sound:
		play_sound(reload_sound, 0.95, 1.05)
	
	# Attendre le temps d'insertion (peut être plus court que le reload_time global)
	# Disons 0.6s par cartouche
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
			
			super.shoot()
	else:
		super.shoot()
