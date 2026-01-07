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
		
		if not is_dedicated:
			# Only spawn a host player if we are a CLIENT-HOST (Listen Server)
			# Dedicated servers don't need a physical player body
			print("Arena: Server Spawning Host (1)")
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

# This function is called by the spawner on all clients
# data is the argument passed to spawn()
func _spawn_player(id: int) -> Node:
	var player = player_scene.instantiate()
	player.name = str(id)
	# Recursive authority because HealthComponent need to be owned by player too
	_set_authority_recursive(player, id)
	
	# Find spawn point
	var spawn_transform = Transform3D()
	if spawn_points.get_child_count() > 0:
		var index = id % spawn_points.get_child_count()
		spawn_transform = spawn_points.get_child(index).global_transform
	else:
		spawn_transform.origin = Vector3(0, 2, 0) # Fallback
		
	player.transform = spawn_transform
	return player

func _set_authority_recursive(node: Node, id: int):
	node.set_multiplayer_authority(id)
	for child in node.get_children():
		_set_authority_recursive(child, id)
