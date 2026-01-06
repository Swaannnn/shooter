	# Instanciation de la nouvelle arme
	_equip_weapon_local(weapon_path)
	
	# Network Sync: Tell others we equipped this weapon
	if is_multiplayer_authority():
		rpc("equip_weapon_remote", weapon_path)

func _equip_weapon_local(weapon_path):
	# Suppression de l'arme actuelle
	if current_weapon:
		current_weapon.queue_free()
		current_weapon = null
	
	var new_weapon_scene = load(weapon_path)
	if new_weapon_scene:
		var new_weapon = new_weapon_scene.instantiate()
		
		# Attach to Camera (FPS view) or Body (TP view)?
		# For now, we attach to Camera for everyone to keep it simple, 
		# even if TP view might look weird if camera looks up/down.
		# Ideally: Local Player -> Camera. Remote Player -> Body/Hand bone.
		# But we don't have a body rig yet. So let's stick to Camera.
		
		if camera:
			camera.add_child(new_weapon)
		else:
			add_child(new_weapon)
			
		current_weapon = new_weapon
		current_weapon.ammo_changed.connect(_on_ammo_changed)
		if not current_weapon.fired.is_connected(_on_weapon_fired):
			current_weapon.fired.connect(_on_weapon_fired)
			
		_on_ammo_changed(current_weapon.current_ammo, current_weapon.reserve_ammo)

@rpc("call_remote")
func equip_weapon_remote(weapon_path):
	_equip_weapon_local(weapon_path)
