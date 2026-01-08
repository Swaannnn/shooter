extends Node

signal game_started
signal round_started
signal round_active
signal round_ended(winning_team)
signal game_ended(winning_team)
signal score_updated(team1_score, team2_score)
signal timer_updated(time_left)
signal kill_feed(killer_name, victim_name, weapon, k_team, v_team)
signal players_updated


enum GameState {WAITING, PRE_ROUND, IN_ROUND, ROUND_END, GAME_OVER}

# Config
var max_score = 10
var round_prep_time = 5.0 # Temps des barrières
var round_end_time = 5.0 # Temps après le round

# State
var current_state = GameState.WAITING
var team1_score = 0
var team2_score = 0
var round_timer = 0.0

# Player Tracking
# Dictionary: peer_id -> { "team": 1 or 2, "alive": bool, "name": "..." }
var players_data = {}

func _ready():
	# Enable process for everyone to handle timer countdown
	set_process(true)

func register_player(id, p_name, team):
	players_data[id] = {
		"team": team,
		"alive": true,
		"name": p_name,
		"kills": 0,
		"deaths": 0
	}
	print("Player Registered: ", id, " Team: ", team)
	# Sync full list to everyone (Heavy but safe for small counts)
	rpc("sync_players_data", players_data)

@rpc("call_remote", "authority", "reliable")
func sync_players_data(new_data):
	players_data = new_data
	emit_signal("players_updated")
	# Refresh scoreboard signal if needed
	pass

func get_player_team(id) -> int:
	if id in players_data:
		return players_data[id]["team"]
	return 0

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
	
	# Sync alive status to all clients (Critical for visibility updates)
	rpc("sync_players_data", players_data)
	
	# Appeler une fonction sur tous les clients pour qu'ils respawnent leur joueur local
	rpc("rpc_respawn_players")

func check_round_win_condition():
	var team1_alive = 0
	var team2_alive = 0
	
	for id in players_data:
		if players_data[id]["alive"]:
			if players_data[id]["team"] == 1: team1_alive += 1
			elif players_data[id]["team"] == 2: team2_alive += 1
			
	# Debug checking
	print("Checking Win Condition: T1 Alive=", team1_alive, " T2 Alive=", team2_alive)
			
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
		# Wait for round end time before starting new round
		# This prevents the "Host Dies Last -> Immediate Respawn -> Recurse Death" bug
		await get_tree().create_timer(round_end_time).timeout
		start_round()

func game_over(winner):
	current_state = GameState.GAME_OVER
	emit_signal("game_ended", winner)
	rpc("sync_game_over", winner)

@rpc("any_peer", "call_local", "reliable")
func report_player_death(victim_id, killer_id, weapon_name):
	# CRITICAL FIX: Only the Server should process the logical consequences of death
	# This prevents Clients from running this logic locally + receiving the sync (Double Entry)
	if not multiplayer.is_server(): return
	
	player_died(victim_id, killer_id, weapon_name)

func player_died(id, killer_id = -1, weapon_name = "Killed"):
	# Ensure ID is int for dictionary lookup
	id = int(id)
	if killer_id != -1: killer_id = int(killer_id)
	
	if id in players_data:
		# Prevent Double Counting
		if not players_data[id]["alive"]:
			print("⚠️ Double Kill Prevented for ", id, " (Already Dead)")
			return
			
		players_data[id]["alive"] = false
		players_data[id]["deaths"] += 1
		
		# Credit Killer
		var killer_name = ""
		var victim_name = players_data[id]["name"]
		var k_team = 0
		var v_team = players_data[id]["team"]
		
		if killer_id != -1 and killer_id in players_data:
			players_data[killer_id]["kills"] += 1
			killer_name = players_data[killer_id]["name"]
			k_team = players_data[killer_id]["team"]
		else:
			killer_name = "Environment"
		
		# Debug checking
		print("Kill Credit: ", killer_name, " killed ", victim_name)
		
		# Broadcast Killfeed
		rpc("sync_kill_feed", killer_name, victim_name, weapon_name, k_team, v_team)
		
		# Sync Player Data (Scores) to everyone
		rpc("sync_players_data", players_data)
		
		check_round_win_condition()

# --- SIGNALS ---
# signal round_timer_updated(time) # Already defined at top

func _process(delta):
	# Update timer locally for smooth UI on clients too
	if current_state == GameState.PRE_ROUND:
		round_timer -= delta
		emit_signal("timer_updated", round_timer)
		
		# Server triggers transition
		if multiplayer.is_server() and round_timer <= 0:
			current_state = GameState.IN_ROUND
			rpc("sync_round_state", current_state, 0)

# --- RPCs for Clients ---

@rpc("call_local", "authority", "reliable")
func sync_round_state(new_state, time):
	current_state = new_state
	round_timer = time
	if new_state == GameState.PRE_ROUND:
		emit_signal("round_started") # Barriers UP, Shop OPEN
	elif new_state == GameState.IN_ROUND:
		emit_signal("round_active") # Barriers DOWN, Shop CLOSED

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
func sync_kill_feed(k_name, v_name, weapon, k_team, v_team):
	emit_signal("kill_feed", k_name, v_name, weapon, k_team, v_team)

@rpc("call_local", "authority", "reliable")
func rpc_respawn_players():
	# Signal global pour dire au PlayerController de se reset
	emit_signal("game_started") # Reuse logic for now
