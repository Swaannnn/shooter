extends Control

@onready var ammo_label = $MarginContainer/AmmoLabel

func update_ammo(current: int, max_ammo: int):
	ammo_label.text = str(current) + " / " + str(max_ammo)
