class_name BeaconRack
extends ItemRack

# Drops beacons: bookmarks that stop where you leave them and show on the map (B1, B2...).


func _init() -> void:
	footprint = Rect2(0, -10, 8, 20)
	capacity = 3
	item_mass = 0.5
	launch_speed = 20.0
	item_color = Color(0.4, 1.0, 0.5)


func _make_item() -> SpaceProp:
	return Beacon.new()


func _is_my_item(prop: SpaceProp) -> bool:
	return prop is Beacon


func _on_item_launched(item: SpaceProp) -> void:
	say("Beacon B%d dropped" % (item as Beacon).number)
