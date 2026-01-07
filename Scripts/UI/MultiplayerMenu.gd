extends Control

# Containers
@onready var main_menu = $Panel/MainMenu
@onready var lobby_ui = $Panel/LobbyUI

# Main Menu Widgets
@onready var join_input = $Panel/MainMenu/JoinInput
@onready var status_label = $Panel/MainMenu/StatusLabel
@onready var host_button = $Panel/MainMenu/HostButton
@onready var join_button = $Panel/MainMenu/JoinButton
@onready var quit_game_button = $Panel/MainMenu/QuitGameButton

# Lobby Widgets
@onready var code_button = $Panel/LobbyUI/CodeButton
@onready var player_list = $Panel/LobbyUI/PlayerList
@onready var start_button = $Panel/LobbyUI/StartButton

func _ready():
	_show_main_menu()
	NetworkManager.join_code_ready.connect(_on_join_code_ready)
	NetworkManager.player_list_updated.connect(_update_lobby_ui)
	
	if quit_game_button:
		quit_game_button.pressed.connect(_on_quit_game_pressed)
	
	# Initial UI State
	if start_button: start_button.disabled = true
	
	if OS.has_feature("web"):
		host_button.disabled = true
		host_button.tooltip_text = "Hosting is not available on Web."
		status_label.text = "Web Client Mode (Hosting Disabled)"

func _show_main_menu():
	main_menu.visible = true
	lobby_ui.visible = false
	status_label.text = "Status: Idle"
	host_button.disabled = false
	join_button.disabled = false

func _show_lobby_ui():
	main_menu.visible = false
	lobby_ui.visible = true
	if player_list: player_list.clear() # Safety check
	_update_lobby_ui()

# --- MAIN MENU ACTIONS ---

func _on_host_pressed():
	status_label.text = "Status: Creating Lobby..."
	host_button.disabled = true
	join_button.disabled = true
	NetworkManager.host_game()
	# Wait for code...

func _on_join_pressed():
	var code = join_input.text
	if code == "":
		status_label.text = "Error: Input Code or IP"
		return
		
	status_label.text = "Status: Joining..."
	join_button.disabled = true
	host_button.disabled = true
	NetworkManager.join_with_code(code)
	
	# Assume join success for now, switch to lobby view waiting for confirmation?
	# Better to wait or just switch and show "Connecting..." inside lobby?
	# Let's switch and disable Start button
	_show_lobby_ui()
	code_button.text = "JOINING: " + code
	_show_lobby_ui()
	code_button.text = "JOINING: " + code
	start_button.visible = false # Clients don't see start
	
func _on_quit_game_pressed():
	get_tree().quit()

# --- LOBBY ACTIONS ---

func _on_join_code_ready(code: String):
	if code == "":
		status_label.text = "Error: Lobby Failed"
		host_button.disabled = false
		join_button.disabled = false
		return
		
	_show_lobby_ui()
	code_button.text = "CODE: " + code
	DisplayServer.clipboard_set(code)
	
	# I am Host
	start_button.visible = true
	start_button.disabled = false

func _on_code_copy_pressed():
	# Extract code from text "CODE: ABCD"
	var text = code_button.text.replace("CODE: ", "")
	DisplayServer.clipboard_set(text)
	code_button.text = "COPIED!"
	# Use a timer but without await to prevent blocking issues if scene changes
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(func(): if code_button: code_button.text = "CODE: " + text)

func _on_start_game_pressed():
	NetworkManager.start_game.rpc()

func _on_leave_pressed():
	# Stop Host/Client
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	# Update NetworkManager state if needed (clear players)
	NetworkManager.players.clear()
	
	# Reset UI to Main Menu
	_show_main_menu()
	status_label.text = "Status: Idle"

func _update_lobby_ui():
	# Refresh Player List
	if not player_list or not lobby_ui.visible: return
	player_list.clear()
	
	var players = NetworkManager.players
	for id in players:
		var info = players[id]
		player_list.add_item(info.get("name", "Unknown"))
