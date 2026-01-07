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

# PRODUCTION URL (Update this after Render deploy!)
var server_url = "wss://shooter-game.onrender.com" 

func _ready():
	_load_env() # Try to load .env override
	multiplayer.peer_connected.connect(_on_peer_connected)
# ...

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
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	# --- AUTO-HOST LOGIC (FOR RENDER/DOCKER) ---
	var args = OS.get_cmdline_args()
	if "--server" in args or DisplayServer.get_name() == "headless":
		print("🚀 STARTING DEDICATED SERVER MODE...")
		_start_server()

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

func _load_env():
	var env_path = "res://.env"
	if FileAccess.file_exists(env_path):
		var file = FileAccess.open(env_path, FileAccess.READ)
		while file.get_position() < file.get_length():
			var line = file.get_line().strip_edges()
			if line.begins_with("#") or line == "":
				continue
				
			var parts = line.split("=", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges()
				var value = parts[1].strip_edges()
				
				if key == "LOBBY_URL":
					lobby_url = value
					print("Loaded LOBBY_URL from .env: ", lobby_url)
	else:
		print("No .env file found. Using default LOBBY_URL: ", lobby_url)

@rpc("call_local", "authority")
func start_game():
	print("Starting Game...")
	# Change scene on all clients
	get_tree().change_scene_to_file("res://Scenes/Arenas/TestArena.tscn")
	game_started.emit()

func _on_peer_connected(id):
	print("Player connected: " + str(id))
	# Add to list (simple ID for now)
	players[id] = {"name": "Player " + str(id)}
	player_list_updated.emit()

func _on_peer_disconnected(id):
	print("Player disconnected: " + str(id))
	players.erase(id)
	player_list_updated.emit()

func _on_connected_to_server():
	print("Connected to server!")
	# Add self
	players[multiplayer.get_unique_id()] = {"name": "Me"}
	player_list_updated.emit()
	
func _on_connection_failed():
	print("Connection failed!")
	players.clear()
	player_list_updated.emit()

func host_game():
	# Clean up previous peer if any
	if peer: peer.close()
	peer = WebSocketMultiplayerPeer.new()
	
	var error = OK
	# Try ports 7777 to 7782 (allow 5 instances)
	for p in range(DEFAULT_PORT, DEFAULT_PORT + 5):
		current_port = p
		# WebSocket create_server takes port and optional bind address
		error = peer.create_server(current_port)
		if error == OK:
			print("Hosting Success on Port: ", current_port)
			break
		else:
			print("Port %d busy, trying next..." % current_port)
			
	if error != OK:
		print("Cannot host: " + str(error))
		return
		
	multiplayer.multiplayer_peer = peer
	print("Waiting for players...")
	
	setup_upnp()

var upnp: UPNP = null

func _exit_tree():
	# Security Cleanup: Remove port mapping when quitting
	if upnp:
		upnp.delete_port_mapping(current_port, "UDP")
		upnp.delete_port_mapping(current_port, "TCP")
		print("UPNP Port Mappings cleared.")

var verified_public_ip = ""
var network_status = "Initializing..."
# LOBBY SERVER URL (Overridden by .env)
var lobby_url = "https://shooter.up.railway.app" # Default to PROD for ease

func setup_upnp():
	network_status = "Starting UPnP Discovery..."
	
	upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result == UPNP.UPNP_RESULT_SUCCESS:
		if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
			# Use current_port!
			# For WebSocket (TCP), we map TCP. UDP is not used for WS.
			var map_result_tcp = upnp.add_port_mapping(current_port, current_port, "Godot_Shooter_WS", "TCP", 0)
			
			if map_result_tcp != UPNP.UPNP_RESULT_SUCCESS:
				network_status = "UPnP Mapping Failed: %s" % map_result_tcp
				print(network_status)
			else:
				network_status = "UPnP Success!"
				verified_public_ip = upnp.query_external_address()
				print("UPNP External IP: ", verified_public_ip)
	else:
		network_status = "UPnP Discovery Failed: %s" % discover_result
		print(network_status)
		
	# REGISTER TO LOBBY SERVER
	_register_lobby_server()


var host_address_override = "" # For Ngrok/Tunnels (e.g. "my-tunnel.ngrok-free.app")

func _register_lobby_server():
	print("Registering to Lobby Server...")
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(self._on_lobby_registered)
	http.timeout = 5.0
	
	# Prepare Body
	var data = {"port": current_port}
	
	# If using Ngrok/Tunnel, send the override address and "wss" scheme
	if host_address_override != "":
		data["address"] = host_address_override
		# Tunnels usually provide HTTPS/WSS
		data["scheme"] = "wss" 
		
	var body = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	var error = http.request(lobby_url + "/host", headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		print("Lobby Server Request Failed: ", error)
		network_status += " | Lobby Server Unreachable"
		emit_signal("join_code_ready", "")

# ... (Previous code) ...

func _on_code_resolved(_result, response_code, _headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.has("ip"):
			var ip = json["ip"]
			var port = json.get("port", DEFAULT_PORT)
			var scheme = json.get("scheme", "ws") # Default to WS
			
			print("Code Resolved! Host: ", scheme, "://", ip, ":", port)
			join_game(ip, port, scheme)
		else:
			print("Invalid JSON from Lobby")
	else:
		print("Code Resolution Failed: ", response_code)

func join_game(address: String, port: int = DEFAULT_PORT, scheme: String = "ws"):
	if address == "":
		address = "127.0.0.1"
	
	# Clean up previous peer
	if peer: peer.close()
	peer = WebSocketMultiplayerPeer.new()
	
	# Handle Scheme
	var url = ""
	if scheme == "wss":
		# WSS usually implies 443, usually clean url like wss://xxx.ngrok.app
		# If port is 443, we can omit it, but creating client with port is fine.
		url = "wss://" + address
		if port != 443 and port != 80:
			url += ":" + str(port)
	else:
		url = "ws://" + address + ":" + str(port)
		
	print("Connecting to " + url + "...")
	
	var error = peer.create_client(url)
	if error != OK:
		print("Cannot join: " + str(error))
		return
	
	multiplayer.multiplayer_peer = peer

func disconnect_game():
	print("Disconnecting game...")
	if peer:
		peer.close()
		peer = null
		
	multiplayer.multiplayer_peer = null
	players.clear()
	
	# Scene change back to Menu
	# Using call_deferred to avoid issues if called during physics frame
	get_tree().change_scene_to_file.call_deferred("res://Scenes/UI/MultiplayerMenu.tscn")
	
	# UI Signal
	player_list_updated.emit()
