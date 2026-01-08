extends Control
# HUD Script

@onready var ammo_label = $AmmoContainer/AmmoLabel
@onready var health_label = $HealthContainer/HealthLabel
# Assumes we will add these nodes to the Scene
@onready var score_label = $TopBar/ScoreLabel
@onready var round_label = $TextContainer/RoundLabel
var shop_hint = null # New Label "Press B for Shop"

# Dynamic creation of Killfeed Container if not present
var killfeed_container = null

func _ready():
	# Cache munition au départ
	ammo_label.visible = false
	if round_label:
		round_label.text = ""
		
	# Killfeed Setup
	if has_node("KillfeedContainer"):
		killfeed_container = $KillfeedContainer
	else:
		killfeed_container = VBoxContainer.new()
		killfeed_container.name = "KillfeedContainer"
		# Position Top Center
		killfeed_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		killfeed_container.position = Vector2(-250, 20) # Margin
		killfeed_container.size = Vector2(230, 200)
		killfeed_container.alignment = BoxContainer.ALIGNMENT_END
		add_child(killfeed_container)

	# Connect to GameManager signals for HUD updates
	GameManager.timer_updated.connect(_on_round_timer_updated)
	GameManager.score_updated.connect(update_scores)
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_active.connect(_on_round_active)
	GameManager.kill_feed.connect(_on_kill_feed)

func update_ammo(current, max_ammo):
	if max_ammo > 0:
		ammo_label.visible = true
		ammo_label.text = str(current) + " / " + str(max_ammo)
	else:
		ammo_label.visible = false


func _on_round_started():
	if round_label: round_label.visible = true
	# Show Shop Hint
	if not has_node("ShopHintLabel"):
		# Create it if missing (or use existing if created in scene)
		pass 
	# Actually I added the variable above, assuming user might add it or I create it
	# For now, let's just stick to Round Label showing the countdown

func _on_round_active():
	if round_label: 
		round_label.text = "FIGHT !"
		await get_tree().create_timer(1.0).timeout
		round_label.visible = false

func _on_round_timer_updated(time_left):
	if round_label:
		if time_left > 0:
			round_label.text = "STARTS IN %.1f" % time_left
			round_label.visible = true
			# Show Shop Hint
			if not shop_hint:
				var parent = get_node_or_null("TextShopContainer")
				if parent:
					if parent.has_node("ShopHintLabel"):
						shop_hint = parent.get_node("ShopHintLabel")
					else:
						var lbl = Label.new()
						lbl.name = "ShopHintLabel"
						lbl.text = "PRESS B FOR SHOP"
						lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
						parent.add_child(lbl)
						shop_hint = lbl
			
			if shop_hint: shop_hint.visible = true
		else:
			if shop_hint: shop_hint.visible = false

func update_health(amount):
	if health_label:
		health_label.text = "HP: " + str(amount)

func update_scores(t1, t2):
	if score_label:
		score_label.text = "BLUE: %d  |  RED: %d" % [t1, t2]

func _on_kill_feed(k_name, v_name, weapon, k_team, v_team):
	var entry = Label.new()
	# Color Formatting
	var k_color = "dodger_blue" if k_team == 1 else "red"
	var v_color = "dodger_blue" if v_team == 1 else "red"
	
	entry.text = "%s [%s] %s" % [k_name, weapon, v_name]
	# RichTextLabel would be better for colors, but Label with modulations is hard per word.
	# Let's use simple text for now or RichTextLabel.
	# Doing RichTextLabel for colors:
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = "[right][color=%s]%s[/color] [color=white][%s][/color] [color=%s]%s[/color][/right]" % [k_color, k_name, weapon, v_color, v_name]
	rtl.fit_content = true
	rtl.custom_minimum_size = Vector2(200, 24)
	
	killfeed_container.add_child(rtl)
	
	# Self destruct after 3s
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(rtl):
		rtl.queue_free()
