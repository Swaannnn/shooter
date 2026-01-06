extends Weapon
class_name HitscanWeapon

@export var max_distance: float = 100.0
@export var raycast_node: RayCast3D # Référence au RayCast3D de l'arme ou de la caméra
@export var impact_effect_scene: PackedScene # Scène à instancier à l'impact
@export var decal_scene: PackedScene # Scène de trou de balle (Decal)
@export var tracer_scene: PackedScene # Scène du tracé de balle
@export var muzzle_point: Marker3D # Point de sortie du canon (dans le modèle visuel)

func _ready():
	super._ready()
	# Délai pour être sûr que tout est initialisé
	await get_tree().process_frame
	
	if raycast_node:
		# On cherche le joueur pour l'ignorer
		var players = get_tree().get_nodes_in_group("player")
		for p in players:
			raycast_node.add_exception(p)

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
		
		# Impact Effect
		if impact_effect_scene:
			var effect = impact_effect_scene.instantiate()
			get_tree().root.add_child(effect)
			effect.global_position = point
			if normal.is_normalized() and normal != Vector3.UP:
				effect.look_at(point + normal, Vector3.UP)
			elif normal == Vector3.UP:
				effect.look_at(point + normal, Vector3.RIGHT)
				
		# Dégâts via HealthComponent (Standard)
		if collider:
			# D'abord on cherche un HealthComponent
			var health_comp = collider.get_node_or_null("HealthComponent")
			if health_comp:
				health_comp.take_damage(damage)
			elif collider.has_method("take_damage"):
				collider.take_damage(damage)
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
					
					# Petit offset pour éviter le Z-fighting si le decal est trop plat (bien que Decal gère ça)
					# Par défaut le Decal projette vers le bas (-Y local), donc look_at aligne -Z.
					# Decal projection axis is -Y. look_at aligns -Z.
					# On doit faire pivoter le decal de -90 deg sur X pour que son -Y (projection) s'aligne avec la normale (Z après look_at)
					decal.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))
			
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
	# Le tracer gère sa propre vie via init()
	if tracer.has_method("init"):
		tracer.init(start, end)
