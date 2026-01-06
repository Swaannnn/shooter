extends Node
class_name HealthComponent

signal health_changed(new_health, max_health)
signal died

@export var max_health: int = 10
@onready var current_health: int = max_health

func take_damage(amount: int):
	current_health -= amount
	current_health = max(0, current_health)
	
	emit_signal("health_changed", current_health, max_health)
	
	if current_health <= 0:
		emit_signal("died")
		get_parent().queue_free() # Comportement par défaut simple : détruire le parent
