extends Control

signal weapon_selected(weapon_scene_path)

func _ready():
	# Connexion des boutons (on suppose qu'ils s'appellent ButtonPistol et ButtonRifle)
	# Ces chemins devront correspondre à la structure de la scène créée
	var btn_pistol = find_child("ButtonPistol")
	var btn_rifle = find_child("ButtonRifle")
	var btn_shotgun = find_child("ButtonShotgun")
	
	if btn_pistol:
		btn_pistol.pressed.connect(_on_pistol_pressed)
	if btn_rifle:
		btn_rifle.pressed.connect(_on_rifle_pressed)
	if btn_shotgun:
		btn_shotgun.pressed.connect(_on_shotgun_pressed)

func _on_pistol_pressed():
	emit_signal("weapon_selected", "res://Scenes/Weapons/Pistol.tscn")
	# On pourrait fermer le menu ici, mais on laissera le PlayerController gérer ça

func _on_rifle_pressed():
	emit_signal("weapon_selected", "res://Scenes/Weapons/Rifle.tscn")

func _on_shotgun_pressed():
	emit_signal("weapon_selected", "res://Scenes/Weapons/Shotgun.tscn")
