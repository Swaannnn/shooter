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
		if collider.has_method("take_damage"):
			collider.take_damage(damage) # Dégâts PAR PLOMB
		elif collider.has_node("HealthComponent"):
			collider.get_node("HealthComponent").take_damage(damage)
	else:
		end_pos = raycast_node.global_position + (-raycast_node.global_transform.basis.z * max_distance)
		
	# Tracer
	if tracer_scene:
		_create_tracer(start_pos, end_pos)
		
	# Reset rotation
	raycast_node.rotation = original_rotation
