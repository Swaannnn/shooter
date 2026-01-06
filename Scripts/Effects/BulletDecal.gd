extends Decal

func _ready():
	# Disparait après 5 secondes
	var tween = create_tween()
	tween.tween_interval(5.0) # Reste visible 5s
	tween.tween_property(self, "modulate:a", 0.0, 2.0) # Fade out sur 2s
	tween.tween_callback(queue_free)
