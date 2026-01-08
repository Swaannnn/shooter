extends Node

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 100

var peer: WebSocketMultiplayerPeer
var player_name: String = "Guest"

signal player_list_updated
signal game_started
signal game_ended # Checkpoint for UI to re-appear
signal join_room_success(room_code: String)

# Local Player Info

var current_room = ""

# Server State: { peer_id: { "name": "...", "room": "ABCD" } }
var players_on_server = {}

# ENVIRONMENTS
const URL_PROD = "wss://shooter-5785.onrender.com"
const URL_DEV = "wss://shooter-dev.onrender.com"

# Config
@export_enum("Auto", "Prod", "Dev", "Local") var target_environment: String = "Auto"
var server_url = URL_DEV
 

# --- SPAWNING SYSTEM FOR PARALLEL GAMES ---
var arena_scene = preload("res://Scenes/Arenas/TestArena.tscn")
var arena_spawner: MultiplayerSpawner

func _ready():
	randomize() # Ensure random room codes
	
	print("\n\n---------------------------------")
	print("--- NETWORK MANAGER INITIALIZING ---")
	print("CMD ARGS: ", OS.get_cmdline_args())
	print("HAS 'PORT' ENV: ", OS.has_environment("PORT"))
	print("DISPLAY SERVER: ", DisplayServer.get_name())
	print("---------------------------------\n\n")

	print("[INIT] Step 1: Loading Env...")
	# _load_env() # Optional if you use .env
	
	# Resolve Auto Environment
	var final_env = target_environment
	if final_env == "Auto":
		if OS.is_debug_build():
			final_env = "Dev" # Editeur Godot = Dev Server
		else:
			final_env = "Prod" # Export Release (.exe public) = Prod Server
			
	# Select URL
	match final_env:
		"Prod": server_url = URL_PROD
		"Dev": server_url = URL_DEV
		"Local": server_url = "ws://127.0.0.1:7777"
		
	print("NetworkManager Configured for: ", final_env, " (Target: ", target_environment, ")")
	print("Target URL: ", server_url)
 
	
	print("[INIT] Step 2: Creating MultiplayerSpawner...")
	# Setup MultiplayerSpawner for Dynamic Arenas
	arena_spawner = MultiplayerSpawner.new()
	arena_spawner.name = "ArenaSpawner"
	
	# Fix: Explicitly point to Parent (NetworkManager) as the container for arenas.
	# "." = Spawner itself (Wrong, unless Spawner is a Node3D/Container and we want hierarchy there)
	# ".." = NetworkManager (Correct, arenas are children of NetworkManager)
	arena_spawner.spawn_path = NodePath("..")
	
	arena_spawner.spawn_function = _spawn_arena # Callback
	
	# We still add the scene to list for validation
	arena_spawner.add_spawnable_scene("res://Scenes/Arenas/TestArena.tscn")
	arena_spawner.spawned.connect(_on_arena_spawned)
	add_child(arena_spawner)
	
	print("[INIT] Step 3: Connecting Signals...")
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	print("[INIT] Step 4: Checking Auto-Host...")
	# --- AUTO-HOST LOGIC ---
	# We verify multiple conditions to ensure it triggers on Render
	var args = OS.get_cmdline_args()
	var is_rendered_env = OS.has_environment("PORT")
	if "--server" in args or DisplayServer.get_name() == "headless" or is_rendered_env:
		print("🚀 STARTING DEDICATED SERVER MODE (Enforced)...")
		# Give it a tiny delay to ensure peer is ready? No, should be fine.
		call_deferred("_start_server")

func _on_arena_spawned(node):
	print("✅ ArenaSpawner: Successfully spawned node: ", node.name)

# Custom Spawn Function (Executed on Server AND Clients)
func _spawn_arena(room_code: Variant) -> Node:
	print("⚡ Spawning Arena for Room: ", room_code)
	var arena = arena_scene.instantiate()
	arena.name = "Arena_" + str(room_code)
	arena.room_code = str(room_code)
	
	# Register Players in GameManager (SERVER ONLY)
	# Because GameManager is global, this supports only 1 active game per server instance properly
	# For multi-game, GameManager logic needs to be moved inside Arena
	if multiplayer.is_server():
		print("Server: Registering players for room ", room_code)
		# We use players_on_server for source of truth
		for pid in players_on_server:
			if players_on_server[pid]["room"] == str(room_code):
				var info = players_on_server[pid]
				var team = info.get("team", 1)
				GameManager.register_player(pid, info["name"], team)
	
	return arena

func generate_random_code() -> String:
	var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var code = ""
	for i in range(4):
		code += chars[randi() % chars.length()]
	return code
	
func _load_env():
	if FileAccess.file_exists("res://.env"):
		var file = FileAccess.open("res://.env", FileAccess.READ)
		while file.get_position() < file.get_length():
			var line = file.get_line()
			if line.begins_with("SERVER_URL="):
				server_url = line.replace("SERVER_URL=", "").strip_edges()
				print("Loaded SERVER_URL: ", server_url)

# --- SERVER HOSTING ---
func _start_server():
	peer = WebSocketMultiplayerPeer.new()
	
	# Check for Render's PORT environment variable
	var port = DEFAULT_PORT
	if OS.has_environment("PORT"):
		port = OS.get_environment("PORT").to_int()
		print("ℹ️ Render Environment Detected. Using Port: ", port)
	
	var error = peer.create_server(port)
	if error != OK:
		print("❌ Failed to bind port %d: %s" % [port, error])
		return
		
	multiplayer.multiplayer_peer = peer
	print("✅ Dedicated Server Listening on Port %d" % port)

func host_game_local(room_code = "LOCAL"):
	# Hosts a LISTEN server (Client acts as Host)
	peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT)
	if error != OK:
		print("❌ Failed to create local server: ", error)
		return
		
	multiplayer.multiplayer_peer = peer
	print("✅ Local Server Started on Port %d" % DEFAULT_PORT)
	
	# Register Self as Host
	current_room = room_code
	# my_name = "LocalHost" # REMOVED: Keep the name set by input
	
	# Manually register self in players_on_server
	players_on_server[1] = {
		"name": player_name,
		"room": room_code,
		"is_host": true
	}
	players_in_room = players_on_server.duplicate()
	
	# Trigger UI success
	join_room_success.emit(room_code)
	player_list_updated.emit()


# --- CLIENT JOINING ---
func join_game(url: String, room_code: String):
	if url.strip_edges() == "":
		# Dev fallback
		url = "ws://127.0.0.1:7777"
	
	# Fix URL scheme if missing
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "wss://" + url # Default to secure wss for Render
		
	print("Connecting to %s..." % url)
	
	current_room = room_code
	
	if peer: peer.close()
	peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_client(url)
	if error != OK:
		print("❌ Client Connection Error: ", error)
		return
		
	multiplayer.multiplayer_peer = peer

# Client-side cache of players in MY room
var players_in_room = {}

# --- ROOM MANAGEMENT ---

@rpc("any_peer", "call_local", "reliable")
func request_change_team(new_team: int):
	var sender_id = multiplayer.get_remote_sender_id()
	
	if multiplayer.is_server():
		if players_on_server.has(sender_id):
			var room = players_on_server[sender_id]["room"]
			
			# Check Capacity
			var count = 0
			for pid in players_on_server:
				if players_on_server[pid]["room"] == room and players_on_server[pid].get("team", 1) == new_team:
					count += 1
			
			if count >= 5:
				print("Team Full!")
				return # Reject change
			
			players_on_server[sender_id]["team"] = new_team
			_update_room_players(room)
			print("Player ", sender_id, " changed to team ", new_team)

@rpc("any_peer", "call_local", "reliable")
func register_player(new_name: String, room_code: String):
	var sender_id = multiplayer.get_remote_sender_id()
	print("📩 Player %d registering for Room: %s" % [sender_id, room_code])
	
	# Determine Host (First player in this room)
	var is_host = true
	var blue_count = 0
	var red_count = 0
	
	for pid in players_on_server:
		if players_on_server[pid]["room"] == room_code:
			is_host = false
			if players_on_server[pid].get("team", 1) == 1:
				blue_count += 1
			else:
				red_count += 1
	
	# Auto-Balance Assign
	var assigned_team = 1
	if red_count < blue_count:
		assigned_team = 2
	
	players_on_server[sender_id] = {
		"name": new_name,
		"room": room_code,
		"is_host": is_host,
		"team": assigned_team
	}
	
	# Confirm join to the client
	if multiplayer.is_server():
		send_join_success.rpc_id(sender_id, room_code)
		# Update lists for everyone in this room
		_update_room_players(room_code)

func _update_room_players(room_code: String):
	# Gather players for this room
	var room_players = {}
	for pid in players_on_server:
		if players_on_server[pid]["room"] == room_code:
			room_players[pid] = players_on_server[pid]
	
	# Send specific list to each member of the room
	for pid in room_players:
		update_client_player_list.rpc_id(pid, room_players)

@rpc("authority", "call_local", "reliable")
func update_client_player_list(room_players: Dictionary):
	# Client receives ONLY members of their room
	players_in_room = room_players
	player_list_updated.emit()
	
	# Debug
	print("Updated Room List: ", players_in_room.keys())

@rpc("authority", "call_local", "reliable")
func send_join_success(room_code: String):
	print("✅ Joined Room: ", room_code)
	current_room = room_code # Server confirms room
	join_room_success.emit(room_code)

# --- EVENTS ---

func _on_connected_to_server():
	print("✅ Connected! Sending Registration...")
	# Once connected, we MUST tell the server which room we want
	register_player.rpc_id(1, player_name, current_room)

func _on_peer_connected(id):
	print("New Peer Connected: ", id)

func _on_peer_disconnected(id):
	print("Peer Disconnected: ", id)
	
	# Handle cleanup
	if players_on_server.has(id):
		var room = players_on_server[id]["room"]
		players_on_server.erase(id)
		
		# If user was host, promote new host? (Optional, maybe later)
		# For now just update list
		_update_room_players(room)
		
	player_list_updated.emit()

func _on_connection_failed():
	print("❌ Connection Failed. Check URL.")
	players_on_server.clear()
	players_in_room.clear()
	player_list_updated.emit()

# --- UTILS ---
func disconnect_game():
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	
	# Cleanup local state
	current_room = ""
	players_on_server.clear()
	players_in_room.clear()
	
	# Manually clean up any Arena nodes
	for child in get_children():
		if child.name.begins_with("Arena_"):
			print("Display Cleanup: Removing ", child.name)
			child.queue_free()
	
	game_ended.emit()

# Client-side Helper
func is_player_in_my_room(id: int) -> bool:
	return players_in_room.has(id) or id == multiplayer.get_unique_id() # Self is always in room

@rpc("any_peer", "call_local", "reliable")
func request_start_game():
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Only server processes this request
	if multiplayer.is_server():
		print("Received Request to Start Game from ", sender_id)
		
		# 1. Identify Room
		if not players_on_server.has(sender_id):
			print("Error: Player not found")
			return
		var room_code = players_on_server[sender_id]["room"]
		
		# 1.5 CHECK AUTHORITY (HOST ONLY)
		if not players_on_server[sender_id].get("is_host", false):
			print("⚠️ PERMISSION DENIED: Peer %d is not Host of room %s" % [sender_id, room_code])
			return
		
		# 2. Check if game already running for this room
		var arena_name = "Arena_" + room_code
		if has_node(arena_name):
			print("Game already running for room ", room_code)
			return

		# 3. Start Game (Instantiate Node)
		print("Starting Game for Room: ", room_code)
		start_game(room_code)

func start_game(room_code: String):
	# Using Explicit Spawn Function for reliability
	print("[Start Game] Requesting Spawn for Room: ", room_code)
	
	# This triggers _spawn_arena on Server AND checks inputs
	# The return value (Arena Node) is then added as child of spawn_path (NetworkManager)
	arena_spawner.spawn(room_code)

	# Notify clients in this room to switch UI
	notify_game_started.rpc(room_code)

@rpc("call_local", "reliable")
func notify_game_started(room_code: String):
	# Client side: Check if this is MY room
	if current_room == room_code:
		print("My Game Started! Hiding Menu...")
		game_started.emit() # Signal for UI to hide
