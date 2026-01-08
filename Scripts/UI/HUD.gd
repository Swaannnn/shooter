extends Control
# HUD Script

@onready var ammo_label = $AmmoContainer/AmmoLabel
@onready var health_label = $HealthContainer/HealthLabel
# Assumes we will add these nodes to the Scene
@onready var score_label = $TopBar/ScoreLabel
@onready var round_label = $CenterContainer/RoundLabel

func _ready():
	# Cache munition au départ
	ammo_label.visible = false
	if round_label:
		round_label.text = ""

func update_ammo(current, max_ammo):
	if max_ammo > 0:
		ammo_label.visible = true
		ammo_label.text = str(current) + " / " + str(max_ammo)
	else:
		ammo_label.visible = false 

func update_health(amount):
	if health_label:
		health_label.text = "HP: " + str(amount)

func update_scores(t1, t2):
	if score_label:
		score_label.text = "BLUE: %d  |  RED: %d" % [t1, t2]

func show_round_start():
	if round_label:
		round_label.text = "NEXT ROUND IN 5..."
		round_label.visible = true
		await get_tree().create_timer(1.0).timeout
		round_label.text = "NEXT ROUND IN 4..."
		await get_tree().create_timer(1.0).timeout
		round_label.text = "NEXT ROUND IN 3..."
		await get_tree().create_timer(1.0).timeout
		round_label.text = "NEXT ROUND IN 2..."
		await get_tree().create_timer(1.0).timeout
		round_label.text = "NEXT ROUND IN 1..."
		await get_tree().create_timer(1.0).timeout
		round_label.text = "FIGHT !"
		await get_tree().create_timer(1.0).timeout
		round_label.visible = false
