extends Node3D

@export var speed = 150.0 # Mètres par seconde

func init(start_pos: Vector3, end_pos: Vector3):
	global_position = start_pos
	
	# Calcul de la distance et de la durée
	var distance = start_pos.distance_to(end_pos)
	var duration = distance / speed
	
	# Orientation vers la cible
	look_at(end_pos)
	
	# Animation de déplacement avec un Tween
	var tween = create_tween()
	tween.tween_property(self, "global_position", end_pos, duration)
	tween.tween_callback(queue_free) # Auto-suppression à l'arrivée
