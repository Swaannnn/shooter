extends Node3D

@onready var health_component = $HealthComponent

func _ready():
	# Connecter le signal died du HealthComponent à notre fonction _on_died
	if health_component:
		health_component.died.connect(_on_died)
		health_component.health_changed.connect(_on_hit)

func _on_hit(current, _max_h):
	# Petit effet visuel : le cube rougit brièvement (optionnel, on verra plus tard les shaders)
	print("Target hit! HP: ", current)

func _on_died():
	print("Target destroyed!")
	queue_free()
