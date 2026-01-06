extends Weapon
class_name HitscanWeapon

@export var max_distance: float = 100.0
@export var raycast_node: RayCast3D # Référence au RayCast3D de l'arme ou de la caméra
@export var impact_effect_scene: PackedScene # Scène à instancier à l'impact
@export var tracer_scene: PackedScene # Scène du tracé de balle
@export var muzzle_point: Marker3D # Point de sortie du canon (dans le modèle visuel)

func _perform_shoot():
	if not raycast_node:
		push_warning("RayCast node not assigned in HitscanWeapon")
		return

	# On force la mise à jour du RayCast pour avoir la position exacte
	raycast_node.force_raycast_update()
	
	var start_pos = Vector3.ZERO
	if muzzle_point:
		start_pos = muzzle_point.global_position
	elif raycast_node:
		start_pos = raycast_node.global_position
		
	var end_pos = Vector3.ZERO
	
	if raycast_node.is_colliding():
		var collider = raycast_node.get_collider()
		var point = raycast_node.get_collision_point()
		var normal = raycast_node.get_collision_normal()
		end_pos = point
		
		# Effet visuel d'impact
		if impact_effect_scene:
			var effect = impact_effect_scene.instantiate()
			get_tree().root.add_child(effect)
			effect.global_position = point
			if normal.is_normalized() and normal != Vector3.UP:
				effect.look_at(point + normal, Vector3.UP)
			elif normal == Vector3.UP:
				effect.look_at(point + normal, Vector3.RIGHT)
		
		# Vérifier si l'objet touché a un HealthComponent ou une méthode take_damage
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
		elif collider.has_node("HealthComponent"):
			collider.get_node("HealthComponent").take_damage(damage)
			
		print("Hit: " + collider.name)
	else:
		# Si on ne touche rien, le tracé va jusqu'à la portée max
		end_pos = raycast_node.global_position + (-raycast_node.global_transform.basis.z * max_distance)

	# Création du Tracer
	if tracer_scene:
		_create_tracer(start_pos, end_pos)

func _create_tracer(start: Vector3, end: Vector3):
	var tracer = tracer_scene.instantiate()
	get_tree().root.add_child(tracer)
	
	# Utilisation de ImmediateMesh pour dessiner une ligne
	# IMPORTANT : On crée un nouveau mesh UNIQUE pour éviter que tous les tracers partagent le même (et s'effacent mutuellement)
	var mesh = ImmediateMesh.new()
	tracer.mesh = mesh
	
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
	mesh.surface_end()
	
	# Fade out animation
	var tween = get_tree().create_tween()
	tween.tween_property(tracer, "transparency", 1.0, 0.1) # Disparait en 0.1s
	tween.tween_callback(tracer.queue_free)
