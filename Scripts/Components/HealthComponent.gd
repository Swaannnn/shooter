extends Node
class_name HealthComponent

signal health_changed(amount, current_health)
signal died

@export var max_health: int = 100
var current_health: int = 0
var last_attacker_id: int = -1

func _ready():
	current_health = max_health
	# We don't emit signal here to avoid spam, but we could sync initial state if needed.

# Expose this function to network so other players can damage us
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, attacker_id: int):
	# Only the owner of this character (Authority) processes the damage 
	if is_multiplayer_authority():
		last_attacker_id = attacker_id
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

@rpc("call_remote", "reliable")
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

func reset_health():
	current_health = max_health
	last_attacker_id = -1
	emit_signal("health_changed", 0, current_health)
	# Sync if needed
	if is_multiplayer_authority():
		rpc("_sync_health", current_health)
