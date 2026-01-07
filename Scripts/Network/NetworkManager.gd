extends Node

const DEFAULT_PORT = 7777
const MAX_CLIENTS = 10

var peer: WebSocketMultiplayerPeer
var current_port = DEFAULT_PORT

signal join_code_ready(code: String)
signal player_list_updated
signal game_started

var players = {}

func _ready():
	_load_env()
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

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

func _register_lobby_server():
	print("Registering to Lobby Server...")
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(self._on_lobby_registered)
	http.timeout = 5.0
	
	# Send Port (IP is detected by server)
	var body = JSON.stringify({"port": current_port})
	var headers = ["Content-Type: application/json"]
	var error = http.request(lobby_url + "/host", headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		print("Lobby Server Request Failed: ", error)
		network_status += " | Lobby Server Unreachable"
		emit_signal("join_code_ready", "")

func _on_lobby_registered(_result, response_code, _headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.has("code"):
			var code = json["code"]
			print("Lobby Created! Code: ", code)
			network_status += " | Lobby Registered."
			emit_signal("join_code_ready", code)
		else:
			print("Invalid Lobby Response")
	else:
		print("Lobby Server Error: ", response_code)
		network_status += " | Lobby Register Error (%s)" % response_code
		emit_signal("join_code_ready", "")

# --- JOIN CODE SYSTEM ---
# No more Get Join Code locally. We get it from signal `join_code_ready`.
# We keep this function just in case UI calls it defensively? No, UI waits for signal.
func get_join_code() -> String:
	return "WAITING..." 

func join_with_code(code: String):
	if code == "": return
	
	# If raw IP, direct join
	if code.is_valid_ip_address():
		join_game(code)
		return
		
	# Else, Resolve via Lobby
	print("Resolving Code via Lobby...")
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(self._on_code_resolved)
	http.request(lobby_url + "/join/" + code)

func _on_code_resolved(_result, response_code, _headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.has("ip"):
			var ip = json["ip"]
			var port = json.get("port", DEFAULT_PORT) # Default fallback
			print("Code Resolved! Host: ", ip, ":", port)
			join_game(ip, port)
		else:
			print("Invalid JSON from Lobby")
	else:
		print("Code Resolution Failed: ", response_code)

func join_game(address: String, port: int = DEFAULT_PORT):
	if address == "":
		address = "127.0.0.1"
	
	# Clean up previous peer
	if peer: peer.close()
	peer = WebSocketMultiplayerPeer.new()
	
	# WebSocket needs ws:// or wss:// schema
	var url = "ws://" + address + ":" + str(port)
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
