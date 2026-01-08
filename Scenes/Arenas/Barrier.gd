extends StaticBody3D

@export var duration = 5.0
@export var team_id = 1 # 1: Blue, 2: Red

func _ready():
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_active.connect(_on_round_active)
	GameManager.game_started.connect(_on_round_started)
	
	# Initial Setup
	_apply_color()

func _apply_color():
	var mesh = $MeshInstance3D
	if mesh:
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if team_id == 1:
			mat.albedo_color = Color(0.0, 0.0, 1.0, 0.5)
		else:
			mat.albedo_color = Color(1.0, 0.0, 0.0, 0.5)
		mesh.material_override = mat

func _on_round_started():
	# Enable Barrier
	visible = true
	set_collision_layer_value(1, true)
	print("Barrier Enabled")

func _on_round_active():
	# Disable Barrier
	visible = false
	set_collision_layer_value(1, false)
	print("Barrier Disabled")
