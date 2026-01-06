extends Control

signal resume_requested
# signal quit_requested # Handled internally via NetworkManager now or still useful for parent?

@onready var main_container = $MainContainer
@onready var settings_container = $SettingsContainer
@onready var sensitivity_slider = $SettingsContainer/VBoxContainer/SensitivitySlider
@onready var sensitivity_value_label = $SettingsContainer/VBoxContainer/SensitivityValue
@onready var volume_slider = $SettingsContainer/VBoxContainer/VolumeSlider # Ensure paths matching scene
@onready var volume_value_label = $SettingsContainer/VBoxContainer/VolumeValue

var player_ref = null

# Sensitivity Config
const SENS_MIN = 0.0001
const SENS_MAX = 0.02

func _ready():
	_setup_initial_ui()
	
	# Menu Buttons
	$MainContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$MainContainer/VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$MainContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	
	# Settings Buttons
	$SettingsContainer/VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	
	# Sliders
	sensitivity_slider.min_value = 0.0
	sensitivity_slider.max_value = 1.0
	sensitivity_slider.step = 0.01
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	
	if volume_slider:
		volume_slider.min_value = 0.0
		volume_slider.max_value = 1.0
		volume_slider.step = 0.01
		volume_slider.value_changed.connect(_on_volume_changed)
		
		# Set Default Volume 30% if not previously set (just enforce it once?)
		# Or sync with current bus volume.
		# User requested "Default 30%".
		var bus_index = AudioServer.get_bus_index("Master")
		# Check if we should enforce default (e.g. first run? Or simply start at 30%)
		# Let's start at 30% as requested.
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(0.3))
		volume_slider.value = 0.3
		_on_volume_changed(0.3)

func _setup_initial_ui():
	main_container.visible = true
	settings_container.visible = false

func setup(player):
	player_ref = player
	if player_ref:
		# Sync Slider with Player's current sensitivity
		# Reverse mapping: Val -> (Val - Min) / (Max - Min)
		var current_sens = player_ref.sensitivity
		if current_sens == null: current_sens = 0.003
		
		var slider_val = inverse_lerp(SENS_MIN, SENS_MAX, current_sens)
		sensitivity_slider.value = slider_val
		_update_sens_label(current_sens)

func _on_resume_pressed():
	emit_signal("resume_requested")

func _on_settings_pressed():
	main_container.visible = false
	settings_container.visible = true

func _on_back_pressed():
	settings_container.visible = false
	main_container.visible = true

func _on_quit_pressed():
	# Return to Lobby
	NetworkManager.disconnect_game()

# --- SETTINGS LOGIC ---

func _on_sensitivity_changed(value_01):
	# Map 0-1 to SENS_MIN - SENS_MAX
	var real_sens = lerp(SENS_MIN, SENS_MAX, value_01)
	
	if player_ref:
		player_ref.sensitivity = real_sens
		
	_update_sens_label(real_sens)

func _update_sens_label(val):
	# Show clean number
	sensitivity_value_label.text = "%.4f" % val

func _on_volume_changed(value):
	var bus_index = AudioServer.get_bus_index("Master")
	var volume_db = linear_to_db(value)
	AudioServer.set_bus_volume_db(bus_index, volume_db)
	
	if volume_value_label:
		volume_value_label.text = str(round(value * 100)) + "%"

