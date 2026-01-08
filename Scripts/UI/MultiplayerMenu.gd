extends Control

# Containers
@onready var main_menu = $Panel/MainMenu
@onready var lobby_ui = $Panel/LobbyUI

# Main Menu Widgets
@onready var name_input = $Panel/MainMenu/NameInput
@onready var join_input = $Panel/MainMenu/JoinInput
@onready var status_label = $Panel/MainMenu/StatusLabel
@onready var host_button = $Panel/MainMenu/HostButton
@onready var join_button = $Panel/MainMenu/JoinButton
@onready var quit_game_button = $Panel/MainMenu/QuitGameButton

# Lobby Widgets
@onready var code_button = $Panel/LobbyUI/CodeButton
@onready var blue_list = $Panel/LobbyUI/TeamColumns/BlueColumn/BlueList
@onready var red_list = $Panel/LobbyUI/TeamColumns/RedColumn/RedList
@onready var join_blue_btn = $Panel/LobbyUI/TeamColumns/BlueColumn/JoinBlueButton
@onready var join_red_btn = $Panel/LobbyUI/TeamColumns/RedColumn/JoinRedButton
@onready var start_button = $Panel/LobbyUI/StartButton
@onready var leave_button = $Panel/LobbyUI/LeaveButton

func _ready():
	_show_main_menu()
	NetworkManager.join_room_success.connect(_on_join_room_success)
	NetworkManager.player_list_updated.connect(_update_lobby_ui)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.game_ended.connect(_show_main_menu)
	
	if quit_game_button:
		quit_game_button.pressed.connect(_on_quit_game_pressed)
	
	# Initial UI State
	if start_button: start_button.disabled = true
	
	if OS.has_feature("web"):
		# Hide QUIT button on Web (Quitting browser is handled by browser)
		# But LEAVE button (return to menu) should be VISIBLE.
		if quit_game_button: quit_game_button.visible = false
		
		# Allow leaving lobby
		if leave_button: leave_button.visible = true

func _on_game_started():
	print("Menu: Game Started! Hiding UI.")
	hide() # Hide the entire MultiplayerMenu Control


func _show_main_menu():
	show() # CRITICAL: Make sure the root Control is visible again!
	main_menu.visible = true
	lobby_ui.visible = false
	status_label.text = "Status: Idle"
	
	if OS.has_feature("web"):
		# Web users can now Create Rooms (Virtual Host)
		pass
	else:
		host_button.disabled = false
		
	join_button.disabled = false

func _show_lobby_ui():
	main_menu.visible = false
	lobby_ui.visible = true
	_update_lobby_ui()

# --- MAIN MENU ACTIONS ---

func _on_host_pressed():
	# Save Name
	if name_input and name_input.text.strip_edges() != "":
		NetworkManager.player_name = name_input.text.strip_edges()
	else:
		NetworkManager.player_name = "Player_" + str(randi() % 1000)

	# "Host" now means "Create Private Room" on the Dedicated Server
	status_label.text = "Status: Creating Room..."
	host_button.disabled = true
	join_button.disabled = true
	
	var new_room_code = NetworkManager.generate_random_code()
	NetworkManager.join_game(NetworkManager.server_url, new_room_code)

func _on_join_pressed():
	# Save Name
	if name_input and name_input.text.strip_edges() != "":
		NetworkManager.player_name = name_input.text.strip_edges()
	else:
		NetworkManager.player_name = "Player_" + str(randi() % 1000)

	var code = join_input.text.strip_edges().to_upper()
	if code == "":
		status_label.text = "Error: Input Room Code"
		return
		
	status_label.text = "Status: Joining Room..."
	join_button.disabled = true
	host_button.disabled = true
	
	NetworkManager.join_game(NetworkManager.server_url, code)
	
	# UI Feedback
	code_button.text = "JOINING: " + code
	start_button.visible = true # Everyone can start? Or logic handled by server?
	_show_lobby_ui()

# --- LOCAL ACTIONS ---
func _on_host_local_pressed():
	# Use current name
	if name_input and name_input.text.strip_edges() != "":
		NetworkManager.player_name = name_input.text.strip_edges()
	
	status_label.text = "Status: Hosting Local..."
	NetworkManager.host_game_local()

func _on_join_local_pressed():
	# Use current name
	if name_input and name_input.text.strip_edges() != "":
		NetworkManager.player_name = name_input.text.strip_edges()
		
	status_label.text = "Status: Joining Local..."
	# Connect to localhost
	NetworkManager.join_game("ws://127.0.0.1:7777", "LOCAL")

	
func _on_quit_game_pressed():
	get_tree().quit()

# --- LOBBY ACTIONS ---

func _on_join_room_success(code: String):
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
	# Request server to start (we can't call start_game directly anymore)
	NetworkManager.request_start_game.rpc()

func _on_leave_pressed():
	NetworkManager.disconnect_game()
	_show_main_menu()
	status_label.text = "Status: Idle"

func _on_join_blue_pressed():
	NetworkManager.request_change_team.rpc(1)

func _on_join_red_pressed():
	NetworkManager.request_change_team.rpc(2)

func _update_lobby_ui():
	# Refresh Player List
	if not lobby_ui.visible: return
	if blue_list: blue_list.clear()
	if red_list: red_list.clear()
	
	# Use the Room-Specific List
	var players = NetworkManager.players_in_room
	var my_id = multiplayer.get_unique_id()
	var am_i_host = false
	
	var blue_count = 0
	var red_count = 0
	
	for id in players:
		var info = players[id]
		var txt = info.get("name", "Unknown")
		var team = info.get("team", 1)
		
		if info.get("is_host", false):
			txt += " (HOST)"
			if id == my_id: am_i_host = true
		
		# Add to list
		if team == 1:
			if blue_list: blue_list.add_item(txt)
			blue_count += 1
		else:
			if red_list: red_list.add_item(txt)
			red_count += 1
			
	# Update Button Texts
	if join_blue_btn:
		join_blue_btn.text = "JOIN BLUE (%d/5)" % blue_count
		join_blue_btn.disabled = (blue_count >= 5)
		
	if join_red_btn:
		join_red_btn.text = "JOIN RED (%d/5)" % red_count
		join_red_btn.disabled = (red_count >= 5)

	# Enable Start Button ONLY if Host
	if start_button:
		start_button.disabled = not am_i_host
		if not am_i_host:
			start_button.tooltip_text = "Waiting for Host to start..."
		else:
			start_button.tooltip_text = ""
