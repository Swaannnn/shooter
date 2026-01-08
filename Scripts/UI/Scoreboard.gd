extends Control

@onready var team1_list = $CenterContainer/HBoxContainer/Team1Panel/VBoxContainer
@onready var team2_list = $CenterContainer/HBoxContainer/Team2Panel/VBoxContainer
@onready var team1_score_label = $CenterContainer/HBoxContainer/Team1Panel/ScoreLabel
@onready var team2_score_label = $CenterContainer/HBoxContainer/Team2Panel/ScoreLabel


func _process(delta):
	if Input.is_action_pressed("scoreboard"): # Tab
		visible = true
		update_board()
	else:
		visible = false

func update_board():
	# Clear lists
	for child in team1_list.get_children():
		if child.name != "Header": child.queue_free()
	for child in team2_list.get_children():
		if child.name != "Header": child.queue_free()
		
	# Update Scores
	team1_score_label.text = str(GameManager.team1_score)
	team2_score_label.text = str(GameManager.team2_score)
	
	# Populate lists
	for id in GameManager.players_data:
		var data = GameManager.players_data[id]
		var entry = Label.new() # Simple Label for now, make Scene later
		entry.text = "%s - K: %d / D: %d" % [data["name"], data["kills"], data["deaths"]]
		
		if data["team"] == 1:
			team1_list.add_child(entry)
		else:
			team2_list.add_child(entry)
