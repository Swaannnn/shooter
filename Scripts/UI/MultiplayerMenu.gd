extends Control

@onready var join_input = $Panel/VBoxContainer/JoinInput
@onready var status_label = $Panel/VBoxContainer/StatusLabel
@onready var code_display = $Panel/VBoxContainer/CodeDisplay

func _ready():
	# Hide code display by default
	if code_display: code_display.visible = false

func _on_host_pressed():
	status_label.text = "Status: Creating Match..."
	NetworkManager.host_game()
	
	# Show Code
	var code = NetworkManager.get_join_code()
	if code_display:
		code_display.text = "JOIN CODE: " + code
		code_display.visible = true
		DisplayServer.clipboard_set(code) # Auto copy needed? Optional convenience.
		status_label.text = "Status: Hosting (Code Copied!)"
	
	# Load level locally but keep menu visible? No, we spawn.
	# Wait, if we change scene, the menu is gone!
	# We need a Lobby UI or the Menu must stay.
	# For this quick test, we load the level. The code will be lost if we don't print it or show it in-game.
	# User wants to give the code.
	
	# CRITICAL: If we change scene, this UI dies.
	# We should print it to console at least.
	print("JOIN CODE: ", code)
	
	_load_level()

func _on_join_pressed():
	status_label.text = "Status: Connecting..."
	var code = join_input.text
	if code == "":
		status_label.text = "Error: Empty Code"
		return
		
	NetworkManager.join_with_code(code)
	_load_level()

func _load_level():
	get_tree().change_scene_to_file("res://Scenes/Arenas/TestArena.tscn")
