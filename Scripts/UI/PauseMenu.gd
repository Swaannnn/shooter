extends Control

signal resume_requested
signal quit_requested

@onready var main_container = $MainContainer
@onready var settings_container = $SettingsContainer
@onready var sensitivity_slider = $SettingsContainer/VBoxContainer/SensitivitySlider
@onready var sensitivity_value_label = $SettingsContainer/VBoxContainer/SensitivityValue

var player_ref = null

func _ready():
	# Cacher les paramètres au début
	main_container.visible = true
	settings_container.visible = false
	
	# Connexion des boutons du menu principal
	$MainContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$MainContainer/VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$MainContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	
	# Connexion des boutons des paramètres
	$SettingsContainer/VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	
	# Connexion du slider
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	if $SettingsContainer/VBoxContainer/VolumeSlider:
		$SettingsContainer/VBoxContainer/VolumeSlider.value_changed.connect(_on_volume_changed)

func setup(player):
	player_ref = player
	if player_ref:
		if player_ref.sensitivity == null:
			player_ref.sensitivity = 0.003 # Default fallback
		sensitivity_slider.value = player_ref.sensitivity
		sensitivity_value_label.text = str(player_ref.sensitivity)
		
	# Init volume slider with current master volume
	var bus_index = AudioServer.get_bus_index("Master")
	var volume_db = AudioServer.get_bus_volume_db(bus_index)
	# Convert db to linear (0-1) roughly, or just use db if slider is db
	# Let's assume slider is linear 0-1
	var volume_linear = db_to_linear(volume_db)
	if $SettingsContainer/VBoxContainer/VolumeSlider:
		$SettingsContainer/VBoxContainer/VolumeSlider.value = volume_linear
		$SettingsContainer/VBoxContainer/VolumeValue.text = str(round(volume_linear * 100)) + "%"

func _on_resume_pressed():
	emit_signal("resume_requested")

# ... (other functions)

func _on_volume_changed(value):
	var bus_index = AudioServer.get_bus_index("Master")
	var volume_db = linear_to_db(value)
	AudioServer.set_bus_volume_db(bus_index, volume_db)
	if $SettingsContainer/VBoxContainer/VolumeValue:
		$SettingsContainer/VBoxContainer/VolumeValue.text = str(round(value * 100)) + "%"

func _on_settings_pressed():
	main_container.visible = false
	settings_container.visible = true

func _on_quit_pressed():
	emit_signal("quit_requested")

func _on_back_pressed():
	settings_container.visible = false
	main_container.visible = true

func _on_sensitivity_changed(value):
	sensitivity_value_label.text = str(value)
	if player_ref:
		player_ref.sensitivity = value
