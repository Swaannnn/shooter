extends Control

signal resume_requested
# signal quit_requested # Handled internally via NetworkManager now or still useful for parent?

@onready var main_container = $MainContainer
@onready var settings_container = $SettingsContainer
@onready var sensitivity_slider = $SettingsContainer/VBoxContainer/SensitivitySlider
@onready var sensitivity_value_label = $SettingsContainer/VBoxContainer/SensitivityValue
@onready var volume_slider = $SettingsContainer/VBoxContainer/VolumeSlider # Ensure paths matching scene
@onready var volume_value_label = $SettingsContainer/VBoxContainer/VolumeValue
@onready var display_option_button = $SettingsContainer/VBoxContainer/DisplayOptionButton

var player_ref = null

# Sensitivity Config
const SENS_MIN = 0.0001
const SENS_MAX = 0.02

func _ready():
	_setup_initial_ui()
	
	# Menu Buttons
	$MainContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$MainContainer/VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	
	var quit_btn = $MainContainer/VBoxContainer/QuitButton
	quit_btn.pressed.connect(_on_quit_pressed)
	
	if OS.get_name() == "Web":
		quit_btn.text = "Disconnect"
	else:
		quit_btn.text = "Quit to Desktop"
	
	# Settings Buttons
	$SettingsContainer/VBoxContainer/BackButton.pressed.connect(_on_back_pressed)
	
	# Sliders
	sensitivity_slider.min_value = 1.0
	sensitivity_slider.max_value = 10.0
	sensitivity_slider.step = 0.1
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	

	
	if volume_slider:
		volume_slider.min_value = 0.0
		volume_slider.max_value = 1.0
		volume_slider.step = 0.01
		volume_slider.value_changed.connect(_on_volume_changed)
		
	if display_option_button:
		display_option_button.item_selected.connect(_on_display_mode_selected)
		_setup_display_options()
		
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
		
		# Visual Mapping: 1.0 - 10.0 corresponds to SENS_MIN - SENS_MAX
		# inverse_lerp returns 0-1. We map that to 1-10.
		var t = inverse_lerp(SENS_MIN, SENS_MAX, current_sens)
		var slider_val = lerp(1.0, 10.0, t)
		sensitivity_slider.value = slider_val
		_update_sens_label(slider_val)

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

# --- SETTINGS LOGIC ---

func _on_sensitivity_changed(value_1_10):
	# Map 1-10 to SENS_MIN - SENS_MAX
	# First normalize 1-10 to 0-1
	var t = inverse_lerp(1.0, 10.0, value_1_10)
	var real_sens = lerp(SENS_MIN, SENS_MAX, t)
	
	if player_ref:
		player_ref.sensitivity = real_sens
		
	_update_sens_label(value_1_10)

func _update_sens_label(val):
	# Show clean number 1.0 - 10.0
	sensitivity_value_label.text = "%.1f" % val

func _on_volume_changed(value):
	var bus_index = AudioServer.get_bus_index("Master")
	var volume_db = linear_to_db(value)
	AudioServer.set_bus_volume_db(bus_index, volume_db)
	
	if volume_value_label:
		volume_value_label.text = str(round(value * 100)) + "%"

func _setup_display_options():
	if not display_option_button: return
	
	display_option_button.clear()
	display_option_button.add_item("Windowed", 0) 
	display_option_button.add_item("Fullscreen", 1) 
	
	# Get current mode
	var current_mode = DisplayServer.window_get_mode()
	var selected_id = 1 # Default Fullscreen
	
	if current_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		selected_id = 0
	else:
		# Any other fullscreen mode = Fullscreen selected
		selected_id = 1
		
	display_option_button.select(selected_id)

func _on_display_mode_selected(index):
	match index:
		0: # Windowed
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1: # Fullscreen (Borderless/Exclusive)
			# User asked for "Just one fullscreen". Fullscreen (Mode 3) is best for Borderless.
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

