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
		# On cherche le propriétaire pour l'ignorer (et pas tous les joueurs !)
		# Hypothèse: Arme attachée à Camera -> CollisionShape -> Player (CharacterBody3D)
		# Ou: Camera -> Player
		var owner_node = _find_owner(self)
		if owner_node:
			raycast_node.add_exception(owner_node)
			# print("Weapon ignored owner: ", owner_node.name)
			
	if not muzzle_point:
		# Try to find it by name if export failed
		muzzle_point = find_child("MuzzlePoint", true, false)
		if muzzle_point:
			print("Weapon ", name, ": MuzzlePoint found dynamically.")
		else:
			print("Weapon ", name, ": No MuzzlePoint found!")

func _find_owner(node):
	var p = node.get_parent()
	while p:
		if p is CharacterBody3D: return p
		p = p.get_parent()
	return null

func _perform_shoot() -> Vector3:
	if not raycast_node:
		push_warning("RayCast node not assigned in HitscanWeapon")
		return Vector3.ZERO
	
	# On force la update
	raycast_node.force_raycast_update()
	
	var end_pos = Vector3.ZERO
	
	if raycast_node.is_colliding():
		var collider = raycast_node.get_collider()
		var point = raycast_node.get_collision_point()
		var normal = raycast_node.get_collision_normal()
		end_pos = point
		
		# Impact Effect (Immediately for shooter? Yes)
		_create_impact_at(point, normal, collider)
				
		# Dégâts via HealthComponent (Authority only)
		if collider and is_multiplayer_authority():
			# Friendly Fire Check
			var shooter = _find_owner(self)
			var is_teammate = false
			if shooter and "team_id" in shooter and "team_id" in collider:
				if shooter.team_id == collider.team_id and shooter != collider:
					is_teammate = true
					# print("Friendly Fire Ignored!")
			
			if not is_teammate:
				var health_comp = collider.get_node_or_null("HealthComponent")
				if health_comp:
					health_comp.take_damage.rpc(damage, multiplayer.get_unique_id())
				elif collider.has_method("take_damage"):
					collider.take_damage(damage) # Legacy/Dummy support (assumed 1 arg)
					
		# print("Hit: " + collider.name)
	else:
		# Max range
		end_pos = raycast_node.global_position + (-raycast_node.global_transform.basis.z * max_distance)
	
	return end_pos

func create_tracer_effect(target_point: Vector3):
	var start_pos = Vector3.ZERO
	if muzzle_point:
		start_pos = muzzle_point.global_position
	elif raycast_node:
		start_pos = raycast_node.global_position
		
	if tracer_scene:
		# print("Creating tracer from ", start_pos, " to ", target_point)
		_create_tracer(start_pos, target_point)
	if tracer_scene:
		# print("Creating tracer from ", start_pos, " to ", target_point)
		_create_tracer(start_pos, target_point)
		
	# Pour les joueurs distants (RPC), on doit recalculer le contexte du hit (Normale, Collider)
	# pour pouvoir placer les Decals (trous de balle) et orienter l'impact.
	if not is_multiplayer_authority():
		# Raycast Physique pour retrouver la surface
		var space_state = get_world_3d().direct_space_state
		# On tire du début vers le point d'impact (un peu plus loin pour être sûr de toucher)
		var dir = (target_point - start_pos).normalized()
		var query = PhysicsRayQueryParameters3D.create(start_pos, target_point + (dir * 0.5))
		
		# Ignorer le tireur (comme le RayCast3D principal)
		var owner_node = _find_owner(self)
		if owner_node:
			query.exclude = [owner_node.get_rid()]
			
		var result = space_state.intersect_ray(query)
		
		if result:
			# On a trouvé la surface !
			_create_impact_at(result.position, result.normal, result.collider)
		else:
			# Fallback si le raycast échoue (glitch geom ou lag), on met juste l'effet
			if impact_effect_scene:
				var effect = impact_effect_scene.instantiate()
				get_tree().root.add_child(effect)
				effect.global_position = target_point
				effect.look_at(target_point + Vector3.UP, Vector3.RIGHT) # Orientation par défaut

func _create_impact_at(point, normal, collider):
	# Impact Effect
	if impact_effect_scene:
		var effect = impact_effect_scene.instantiate()
		get_tree().root.add_child(effect)
		effect.global_position = point
		if normal.is_normalized() and normal != Vector3.UP:
			effect.look_at(point + normal, Vector3.UP)
		elif normal == Vector3.UP:
			effect.look_at(point + normal, Vector3.RIGHT)
	
	# Decals (Optional, logic simplified here)
	if collider and not collider.get_node_or_null("HealthComponent"): # Only on walls
		if decal_scene:
			var decal = decal_scene.instantiate()
			collider.add_child(decal)
			decal.global_position = point
			if normal != Vector3.UP and normal != Vector3.DOWN:
				decal.look_at(point + normal, Vector3.UP)
			else:
				decal.look_at(point + normal, Vector3.RIGHT)
			decal.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90))

func _create_tracer(start: Vector3, end: Vector3):
	var tracer = tracer_scene.instantiate()
	get_tree().root.add_child(tracer)
	# Le tracer gère sa propre vie via init()
	if tracer.has_method("init"):
		tracer.init(start, end)
