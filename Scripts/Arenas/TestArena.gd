extends Node3D

@onready var players_container = $Players
@onready var spawn_points = $SpawnPoints
@onready var multiplayer_spawner = $MultiplayerSpawner

var player_scene = null
var room_code = ""

func _ready():
	# Use load() instead of preload() to avoid circular dependencies (Player -> HUD -> Player etc.)
	player_scene = load("res://Scenes/Characters/Player.tscn")
	
	# Configure Spawner
	multiplayer_spawner.spawn_function = _spawn_player
	
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
		# Check if we are a dedicated server (Headless or --server)
		var is_dedicated = DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_args()
		
		# INITIAL GAME START
		# Wait a bit for initialization then start the loop
		await get_tree().create_timer(1.0).timeout
		GameManager.start_game()
		
		if not is_dedicated:
			# Only spawn a host player if we are a CLIENT-HOST (Listen Server)
			# Dedicated servers don't need a physical player body
			print("Arena: Server Spawning Host (1)")
			# Auto-register host
			GameManager.register_player(1, NetworkManager.player_name if NetworkManager.player_name != "" else "Host", 1) # Force Team 1 for Host
			multiplayer_spawner.spawn(1)
		else:
			print("Arena: Dedicated Server detected. Skipping Host (1) spawn.")
			
	# Client notifies Server it has loaded the map
	if not multiplayer.is_server():
		# LOBBY ISOLATION CHECK
		if room_code != NetworkManager.current_room:
			print("🙈 Arena: Ignoring foreign room %s (My Room: %s)" % [room_code, NetworkManager.current_room])
			# Hide and Disable this arena for this client
			visible = false
			process_mode = Node.PROCESS_MODE_DISABLED
			return
		
		print("Arena: Client _ready. Sending notify_level_loaded to Server...")
		notify_level_loaded.rpc_id(1)

# Handshake: Client -> Server
@rpc("any_peer", "call_local", "reliable")
func notify_level_loaded():
	var sender_id = multiplayer.get_remote_sender_id()
	print("Arena: Server received notify_level_loaded from %d" % sender_id)
	
	# Verify we haven't already spawned them
	if players_container.has_node(str(sender_id)):
		print("Arena: Player %d already exists. Skipping." % sender_id)
		return
		
	# Register if not exists (Late join)
	if sender_id not in GameManager.players_data:
		# Auto assign team based on count
		var t1 = 0
		var t2 = 0
		for pid in GameManager.players_data:
			if GameManager.players_data[pid]["team"] == 1: t1 += 1
			else: t2 += 1
		
		var new_team = 1 if t1 <= t2 else 2
		GameManager.register_player(sender_id, "Player " + str(sender_id), new_team)
		
	# Spawn the player for this specific peer
	print("Arena: Spawning Player Character for %d" % sender_id)
	multiplayer_spawner.spawn(sender_id)

func _on_peer_connected(id: int):
	# For late joiners or reconnects
	print("Arena: Peer connected %d. Waiting for level load notification..." % id)
	# Do NOT spawn immediately here. Wait for them to send notify_level_loaded()

func _on_peer_disconnected(id: int):
	print("Arena: Removing player for peer ", id)
	if players_container.has_node(str(id)):
		players_container.get_node(str(id)).queue_free()
	
	# Update GameManager
	if id in GameManager.players_data:
		GameManager.players_data.erase(id)

# This function is called by the spawner on all clients
# data is the argument passed to spawn()
func _spawn_player(id: int) -> Node:
	var player = player_scene.instantiate()
	player.name = str(id)
	# Recursive authority because HealthComponent need to be owned by player too
	_set_authority_recursive(player, id)
	
	# Find spawn point based on Team
	var team_id = 1
	if id in GameManager.players_data:
		team_id = GameManager.players_data[id]["team"]
	
	# Update Player Team Prop
	player.team_id = team_id
	
	var spawn_transform = Transform3D()
	var points = []
	
	# Collect valid points
	for child in spawn_points.get_children():
		if "team_id" in child and child.team_id == team_id:
			points.append(child)
			
	if points.size() > 0:
		# Pick one based on modulo ID to have distinct spawns
		var index = id % points.size()
		spawn_transform = points[index].global_transform
	else:
		spawn_transform.origin = Vector3(0, 2, 0) # Fallback
		
	player.transform = spawn_transform
	return player

func _set_authority_recursive(node: Node, id: int):
	node.set_multiplayer_authority(id)
	for child in node.get_children():
		_set_authority_recursive(child, id)
