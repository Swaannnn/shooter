extends Node3D

@onready var players_container = $Players
@onready var spawn_points = $SpawnPoints
@onready var multiplayer_spawner = $MultiplayerSpawner

var player_scene = null

func _ready():
	# Use load() instead of preload() to avoid circular dependencies (Player -> HUD -> Player etc.)
	player_scene = load("res://Scenes/Characters/Player.tscn")
	
	# Configure Spawner
	multiplayer_spawner.spawn_function = _spawn_player
	
	# Only the server needs to handle connections and spawning
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
		# 1. Spawn Host (Self)
		_spawn_player(1) # Call spawn function directly or use spawner?
		# Note: spawner.spawn(id) triggers replication.
		# But 'spawn(id)' requires the arg to be passed.
		# Let's use the spawner properly.
		print("Arena: Server Spawning Host (1)")
		multiplayer_spawner.spawn(1)
		
		# 2. Spawn Existing Clients (who connected in Lobby)
		for id in multiplayer.get_peers():
			print("Arena: Server Spawning Client ", id)
			multiplayer_spawner.spawn(id)

func _on_peer_connected(id: int):
	# Handle late joiners (if allowed)
	print("Arena: Late joiner connected ", id)
	multiplayer_spawner.spawn(id)

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
