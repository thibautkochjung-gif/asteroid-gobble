class_name FlareRack
extends ItemRack

# Fires flares: bright, short-lived markers. Six in a rack, none come back.


func _init() -> void:
	footprint = Rect2(0, -9, 6, 18)
	capacity = 6
	item_mass = 0.1
	launch_speed = 70.0
	item_color = Color(1.0, 0.45, 0.3)


func _make_item() -> SpaceProp:
	return Flare.new()
