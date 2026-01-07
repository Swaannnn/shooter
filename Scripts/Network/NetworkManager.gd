extends Node

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 100 

var peer: WebSocketMultiplayerPeer

signal player_list_updated
signal game_started
signal join_room_success(room_code: String)

# Local Player Info
var my_name = "Player"
var current_room = ""

# Server State: { peer_id: { "name": "...", "room": "ABCD" } }
var players_on_server = {} 

# PRODUCTION URL
var server_url = "wss://shooter-5785.onrender.com" 

# --- SPAWNING SYSTEM FOR PARALLEL GAMES ---
var arena_scene = preload("res://Scenes/Arenas/TestArena.tscn")
var arena_spawner: MultiplayerSpawner

func _ready():
	print("\n\n---------------------------------")
	print("--- NETWORK MANAGER INITIALIZING ---")
	print("CMD ARGS: ", OS.get_cmdline_args())
	print("HAS 'PORT' ENV: ", OS.has_environment("PORT"))
	print("DISPLAY SERVER: ", DisplayServer.get_name())
	print("---------------------------------\n\n")

	print("[INIT] Step 1: Loading Env...")
	_load_env() 
	
	print("[INIT] Step 2: Creating MultiplayerSpawner...")
	# Setup MultiplayerSpawner for Dynamic Arenas
	arena_spawner = MultiplayerSpawner.new()
	arena_spawner.name = "ArenaSpawner" # CRITICAL: Names must match on Client/Server!
	# arena_spawner.spawn_path defaults to Parent (NetworkManager), which is correct.
	# Setting it to "." made it look inside itself, but we add_child to NetworkManager.
	
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

# --- ROOM MANAGEMENT ---

@rpc("any_peer", "call_local", "reliable")
func register_player(new_name: String, room_code: String):
	var sender_id = multiplayer.get_remote_sender_id()
	print("📩 Player %d registering for Room: %s" % [sender_id, room_code])
	
	players_on_server[sender_id] = {"name": new_name, "room": room_code}
	
	# Notify clients to refresh their lists
	player_list_updated.emit()
	
	# Confirm join to the client
	if multiplayer.is_server():
		send_join_success.rpc_id(sender_id, room_code)

@rpc("authority", "call_local", "reliable")
func send_join_success(room_code: String):
	print("✅ Joined Room: ", room_code)
	join_room_success.emit(room_code)

# --- EVENTS ---

func _on_connected_to_server():
	print("✅ Connected! Sending Registration...")
	# Once connected, we MUST tell the server which room we want
	register_player.rpc_id(1, my_name, current_room)

func _on_peer_connected(id):
	print("New Peer Connected: ", id)

func _on_peer_disconnected(id):
	print("Peer Disconnected: ", id)
	players_on_server.erase(id)
	player_list_updated.emit()

func _on_connection_failed():
	print("❌ Connection Failed. Check URL.")
	players_on_server.clear()
	player_list_updated.emit()

# --- UTILS ---
func disconnect_game():
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	players_on_server.clear()
	game_started.emit() # Reset UI?

@rpc("any_peer", "call_local", "reliable")
func request_start_game():
	var sender_id = multiplayer.get_remote_sender_id()
	
	if multiplayer.is_server():
		print("Received Request to Start Game from ", sender_id)
		
		# 1. Identify Room
		if not players_on_server.has(sender_id):
			print("Error: Player not found")
			return
		var room_code = players_on_server[sender_id]["room"]
		
		# 2. Check if game already running for this room
		var arena_name = "Arena_" + room_code
		if has_node(arena_name):
			print("Game already running for room ", room_code)
			return

		# 3. Start Game (Instantiate Node)
		print("Starting Game for Room: ", room_code)
		start_game(room_code)

func start_game(room_code: String):
	# Server-side instantiation
	# The MultiplayerSpawner will automatically replicate this new node to ALL clients
	
	var arena = arena_scene.instantiate()
	arena.name = "Arena_" + room_code
	
	print("[Before Spawn] Arena Path: ", arena.scene_file_path)
	print("[Before Spawn] Spawner Configured Scenes: ", arena_spawner.get_spawnable_scene_count())
	# print("[Before Spawn] Spawner Spawn Path: ", arena_spawner.spawn_path)
	
	add_child(arena, true) # Force readable name
	
	# Notify clients in this room to switch UI
	notify_game_started.rpc(room_code)

@rpc("call_local", "reliable")
func notify_game_started(room_code: String):
	# Client side: Check if this is MY room
	if current_room == room_code:
		print("My Game Started! Hiding Menu...")
		game_started.emit() # Signal for UI to hide
