class_name CacheBuoyRack
extends ItemRack

# Carries one cache buoy.
# - tap, buoy aboard: drop it here.
# - tap, buoy out: if the ship is within release_range of a buoy, that buoy lets go of its chunks.
#   Otherwise, says how far the nearest buoy is.
# An empty buoy goes back into the rack when touched gently.

@export var release_range: float = 160.0 # px from the ship to the buoy


func _init() -> void:
	footprint = Rect2(0, -9, 10, 18)
	capacity = 1
	item_mass = 2.0
	launch_speed = 15.0
	item_color = Color(0.67, 0.36, 0.18)


func _on_tap() -> void:
	if count > 0:
		launch_item()
		return

	var buoy := _find_nearest_buoy()

	if buoy == null:
		say("Cache: no buoy aboard, none out there")
		return

	var distance := buoy.global_position.distance_to(ship.global_position)

	if distance > release_range:
		say("Cache: nearest buoy is %d px away" % distance)
		return

	var count_released := buoy.release_all()
	say("Cache: %d chunks let go" % count_released)


func get_controls_text() -> String:
	return "tap: drop buoy" if count > 0 else "tap: open the cache (near it)"


func _make_item() -> SpaceProp:
	return CacheBuoy.new()


func _is_my_item(prop: SpaceProp) -> bool:
	return prop is CacheBuoy


func _on_item_launched(_item: SpaceProp) -> void:
	say("Cache buoy dropped")


func _find_nearest_buoy() -> CacheBuoy:
	var best: CacheBuoy = null
	var best_distance := INF

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		var buoy := node as CacheBuoy

		if buoy == null:
			continue

		var distance := buoy.global_position.distance_to(ship.global_position)

		if distance < best_distance:
			best_distance = distance
			best = buoy

	return best
