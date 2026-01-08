extends StaticBody3D

@export var duration = 5.0

func _ready():
	GameManager.round_started.connect(_on_round_started)

func _on_round_started():
	visible = true
	set_collision_layer_value(1, true)
	await get_tree().create_timer(duration).timeout
	disable_barrier()

func disable_barrier():
	visible = false
	set_collision_layer_value(1, false) # Disable collision
