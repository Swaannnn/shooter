extends Node
class_name HealthComponent

signal health_changed(amount, current_health)
signal died

@export var max_health: int = 100
var current_health: int = 0

func _ready():
	current_health = max_health
	# We don't emit signal here to avoid spam, but we could sync initial state if needed.

# Expose this function to network so other players can damage us
@rpc("any_peer", "call_local")
func take_damage(amount: int):
	# Only the owner of this character (Authority) processes the damage 
	
	if is_multiplayer_authority():
		_apply_damage(amount)
		rpc("_sync_health", current_health)

func _apply_damage(amount: int):
	if current_health <= 0: return
	
	current_health -= amount
	current_health = max(0, current_health)
	
	emit_signal("health_changed", -amount, current_health)
	print(get_parent().name + " took " + str(amount) + " damage. Health: " + str(current_health))
	
	if current_health == 0:
		die()

@rpc("call_remote")
func _sync_health(new_health: int):
	var diff = new_health - current_health
	current_health = new_health
	emit_signal("health_changed", diff, current_health)
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
