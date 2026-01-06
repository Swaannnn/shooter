extends Control
# HUD Script

@onready var ammo_label = $AmmoContainer/AmmoLabel
@onready var health_label = $HealthContainer/HealthLabel

func _ready():
	# Cache munition au départ
	ammo_label.visible = false

func update_ammo(current, max_ammo):
	if max_ammo > 0:
		ammo_label.visible = true
		ammo_label.text = str(current) + " / " + str(max_ammo)
	else:
		ammo_label.visible = false 

func update_health(amount):
	if health_label:
		health_label.text = "HP: " + str(amount)
