extends Node

signal game_started
signal round_started
signal round_ended(winning_team)
signal game_ended(winning_team)
signal score_updated(team1_score, team2_score)
signal timer_updated(time_left)

enum GameState { WAITING, PRE_ROUND, IN_ROUND, ROUND_END, GAME_OVER }

# Config
var max_score = 10
var round_prep_time = 5.0 # Temps des barrières

# State
var current_state = GameState.WAITING
var team1_score = 0
var team2_score = 0
var round_timer = 0.0

# Player Tracking
# Dictionary: peer_id -> { "team": 1 or 2, "alive": bool, "name": "..." }
var players_data = {} 

func _ready():
	# Si on est sur le serveur, on gère la boucle
	if multiplayer.is_server():
		set_process(true)
	else:
		set_process(false) # Les clients écoutent juste les signaux

func register_player(id, name, team):
	players_data[id] = {
		"team": team,
		"alive": true,
		"name": name,
		"kills": 0,
		"deaths": 0
	}
	print("Player Registered: ", id, " Team: ", team)

func start_game():
	team1_score = 0
	team2_score = 0
	emit_signal("score_updated", team1_score, team2_score)
	emit_signal("game_started")
	start_round()

func start_round():
	current_state = GameState.PRE_ROUND
	round_timer = round_prep_time
	
	# Respawn tout le monde
	_respawn_all_players()
	
	# Sync Timer & State aux clients
	rpc("sync_round_state", current_state, round_timer)

func _respawn_all_players():
	# Remettre 'alive' à true
	for id in players_data:
		players_data[id]["alive"] = true
	
	# Appeler une fonction sur tous les clients pour qu'ils respawnent leur joueur local
	rpc("rpc_respawn_players")

func check_round_win_condition():
	var team1_alive = 0
	var team2_alive = 0
	
	for id in players_data:
		if players_data[id]["alive"]:
			if players_data[id]["team"] == 1: team1_alive += 1
			elif players_data[id]["team"] == 2: team2_alive += 1
			
	# Si une équipe est éliminée
	if team1_alive == 0 and team2_alive > 0:
		end_round(2)
	elif team2_alive == 0 and team1_alive > 0:
		end_round(1)
	elif team1_alive == 0 and team2_alive == 0:
		end_round(0) # Draw (rare)

func end_round(winning_team):
	if current_state != GameState.IN_ROUND: return
	
	current_state = GameState.ROUND_END
	
	if winning_team == 1:
		team1_score += 1
	elif winning_team == 2:
		team2_score += 1
		
	emit_signal("score_updated", team1_score, team2_score)
	rpc("sync_score", team1_score, team2_score)
	
	emit_signal("round_ended", winning_team)
	rpc("sync_round_end", winning_team)
	
	# Check Game Win
	if team1_score >= max_score:
		game_over(1)
	elif team2_score >= max_score:
		game_over(2)
	else:
		# Next round after delay
		await get_tree().create_timer(3.0).timeout
		start_round()

func game_over(winner):
	current_state = GameState.GAME_OVER
	emit_signal("game_ended", winner)
	rpc("sync_game_over", winner)

func player_died(id):
	if id in players_data:
		players_data[id]["alive"] = false
		players_data[id]["deaths"] += 1
		
		# Trouver le tueur (si on a l'info, à faire plus tard via arguments)
		# Pour l'instant on check juste la win condition
		check_round_win_condition()

func _process(delta):
	# Gestion du Timer Serveur
	if current_state == GameState.PRE_ROUND:
		round_timer -= delta
		if round_timer <= 0:
			current_state = GameState.IN_ROUND
			rpc("sync_round_state", current_state, 0) # 0 means go!
			
	elif current_state == GameState.IN_ROUND:
		# Logic de round (time limit ?)
		pass

# --- RPCs for Clients ---

@rpc("call_local", "authority", "reliable")
func sync_round_state(new_state, time):
	current_state = new_state
	round_timer = time
	if new_state == GameState.PRE_ROUND:
		emit_signal("round_started") # Client side hook for barriers etc
	
@rpc("call_local", "authority", "reliable")
func sync_score(t1, t2):
	team1_score = t1
	team2_score = t2
	emit_signal("score_updated", t1, t2)

@rpc("call_local", "authority", "reliable")
func sync_round_end(winner):
	emit_signal("round_ended", winner)

@rpc("call_local", "authority", "reliable")
func sync_game_over(winner):
	emit_signal("game_ended", winner)

@rpc("call_local", "authority", "reliable")
func rpc_respawn_players():
	# Signal global pour dire au PlayerController de se reset
	var local_player = get_tree().get_nodes_in_group("player")
	if local_player.size() > 0:
		# On utilise 'game_started' ou un signal custom sur le noeud
		# Mais le PlayerController écoute GameManager.game_started pour respawn
		emit_signal("game_started")
