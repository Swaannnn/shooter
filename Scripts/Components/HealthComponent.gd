extends Node
class_name HealthComponent

signal health_changed(amount, current_health)
signal died

@export var max_health: int = 100
var current_health: int = 0

func _ready():
	current_health = max_health
	emit_signal("health_changed", 0, current_health)

func take_damage(amount: int):
	if current_health <= 0: return # Déjà mort
	
	current_health -= amount
	current_health = max(0, current_health) # Ne descend pas sous 0
	
	emit_signal("health_changed", -amount, current_health)
	
	print(get_parent().name + " took " + str(amount) + " damage. Health: " + str(current_health))
	
	if current_health == 0:
		die()

func heal(amount: int):
	if current_health <= 0: return # Ne peut pas soigner un mort (sauf si résurrection ?)
	
	current_health += amount
	current_health = min(current_health, max_health)
	
	emit_signal("health_changed", amount, current_health)

func die():
	emit_signal("died")
	# Optionnel : libérer le parent ou lancer une animation via un autre script
