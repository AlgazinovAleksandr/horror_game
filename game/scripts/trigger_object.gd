extends StaticBody3D

# A trap prop. Triggers screamer on direct interaction OR after 3 seconds of gaze.


func interact() -> void:
	Screamer.trigger()


func on_gaze_tick() -> void:
	# Called every frame while player gazes at this object (handled in player.gd).
	pass


func on_gaze_trigger() -> void:
	Screamer.trigger()
