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

func _ready():
	_load_env() # Try to load .env override
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	# --- AUTO-HOST LOGIC (FOR RENDER/DOCKER) ---
	var args = OS.get_cmdline_args()
	if "--server" in args or DisplayServer.get_name() == "headless":
		print("🚀 STARTING DEDICATED SERVER MODE...")
		_start_server()

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
	var error = peer.create_server(DEFAULT_PORT)
	if error != OK:
		print("❌ Failed to bind port %d: %s" % [DEFAULT_PORT, error])
		return
		
	multiplayer.multiplayer_peer = peer
	print("✅ Dedicated Server Listening on Port %d" % DEFAULT_PORT)

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
	# (In a real optimized server, we'd only notify people in the same room)
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

@rpc("call_local", "authority")
func start_game():
	print("Starting Game...")
	# Change scene on all clients
	get_tree().change_scene_to_file("res://Scenes/Arenas/TestArena.tscn")
	game_started.emit()
