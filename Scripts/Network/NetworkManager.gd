extends Node

const PORT = 7777
const MAX_CLIENTS = 10

var peer = ENetMultiplayerPeer.new()

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func host_game():
	var error = peer.create_server(PORT, MAX_CLIENTS)
	if error != OK:
		print("Cannot host: " + str(error))
		return
		
	# Compress bandwidth
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	
	multiplayer.multiplayer_peer = peer
	print("Waiting for players...")
	
var upnp: UPNP = null

func _exit_tree():
	# Security Cleanup: Remove port mapping when quitting
	if upnp:
		upnp.delete_port_mapping(PORT, "UDP")
		upnp.delete_port_mapping(PORT, "TCP")
		print("UPNP Port Mappings cleared.")

func setup_upnp():
	upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		print("UPNP Discover Failed! Error %s" % discover_result)
		return

	if upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		var map_result_udp = upnp.add_port_mapping(PORT, PORT, "Godot_Shooter_UDP", "UDP", 0)
		# TCP often not needed for ENet but good for discovery if used later
		# var map_result_tcp = upnp.add_port_mapping(PORT, PORT, "Godot_Shooter_TCP", "TCP", 0)
		
		if map_result_udp != UPNP.UPNP_RESULT_SUCCESS:
			print("UPNP UDP Port Mapping Failed! Error %s" % map_result_udp)
		else:
			print("UPNP Success! External IP: %s" % upnp.query_external_address())
			
	else:
		print("UPNP Invalid Gateway!")

# --- JOIN CODE SYSTEM ---
# Basic Base64 obfuscation to hide raw IP
func get_join_code() -> String:
	var ip = ""
	if upnp and upnp.get_gateway() and upnp.get_gateway().is_valid_gateway():
		ip = upnp.query_external_address()
	
	# Fallback to LAN if no UPnP or invalid
	if ip == "":
		ip = IP.resolve_hostname(str(OS.get_environment("COMPUTERNAME")), 1) # Windows Hack
		# Or generic get_local_addresses() check
		if ip == "": ip = "127.0.0.1"
		
	var data = (ip + ":" + str(PORT)).to_utf8_buffer()
	return Marshalls.raw_to_base64(data)

func join_with_code(code: String):
	if code == "":
		print("Empty code!")
		return
		
	# Decode
	var error = OK
	var decoded_data = Marshalls.base64_to_raw(code)
	var decoded_str = decoded_data.get_string_from_utf8()
	
	if decoded_str == "":
		print("Invalid Code structure")
		return
		
	var parts = decoded_str.split(":")
	var ip = parts[0]
	
	join_game(ip)

func join_game(address: String):
	if address == "":
		address = "127.0.0.1"
		
	var error = peer.create_client(address, PORT)
	if error != OK:
		print("Cannot join: " + str(error))
		return
	
	# Compress bandwidth
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	
	multiplayer.multiplayer_peer = peer
	print("Connecting to " + address + "...")

func _on_peer_connected(id):
	print("Player connected: " + str(id))

func _on_peer_disconnected(id):
	print("Player disconnected: " + str(id))

func _on_connected_to_server():
	print("Connected to server!")

func _on_connection_failed():
	print("Connection failed!")
