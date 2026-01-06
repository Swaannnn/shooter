extends Node

signal game_started
signal game_ended(winner_id)

var player_score = 0
var enemy_score = 0
var max_score = 5

func start_game():
	player_score = 0
	enemy_score = 0
	emit_signal("game_started")

func add_score(is_player: bool):
	if is_player:
		player_score += 1
	else:
		enemy_score += 1
	
	if player_score >= max_score:
		end_game(1) # Player wins
	elif enemy_score >= max_score:
		end_game(2) # Enemy wins

func end_game(winner):
	emit_signal("game_ended", winner)
