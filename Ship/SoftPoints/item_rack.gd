class_name ItemRack
extends SoftPoint

# Base for the soft points that hold a few items and put them in space: beacons, probes, flares,
# charges, the cache buoy. A tap launches one item outward from the rack.
# Items are props (SpaceProp). An item that comes home (touches the hull slowly, or is reeled in)
# goes back into any rack of its kind with room, not necessarily the one it left from.
# Each loaded item adds item_mass to the rack, at the rack.
# Subclasses say which props are theirs (_make_item, _is_my_item).

@export var capacity: int = 3
@export var item_mass: float = 0.5
@export var launch_speed: float = 30.0 # px/s outward, on top of the ship's own motion
@export var start_full: bool = true

@export_group("Look")
@export var item_color: Color = Color(0.83, 0.64, 0.16)

var count: int = 0
var launched: Array[SpaceProp] = [] # Items out in space that left from this rack, oldest first


func _ready() -> void:
	if start_full:
		count = capacity


func _on_tap() -> void:
	launch_item()


func launch_item() -> SpaceProp:
	if count <= 0:
		say("%s: empty" % get_type_name())
		return null

	var item := _make_item()
	item.mass = item_mass
	count -= 1

	var at := get_tip() + get_outward() * (item.radius + TEXEL)
	launch_prop(item, at, get_outward() * launch_speed)
	launched.append(item)
	_on_item_launched(item)
	queue_redraw()
	return item


func get_status_text() -> String:
	return "%d / %d" % [count, capacity]


func get_controls_text() -> String:
	return "tap: launch"


func get_aim_speed() -> float:
	return launch_speed if count > 0 else 0.0


func restock() -> void:
	count = capacity
	queue_redraw()


func accepts_prop(prop: SpaceProp) -> bool:
	return _is_my_item(prop) and count < capacity


func recover_prop(prop: SpaceProp) -> bool:
	if not accepts_prop(prop):
		return false

	count += 1
	launched.erase(prop)
	_on_item_recovered(prop)
	prop.queue_free()
	say("%s: item recovered (%d / %d)" % [get_type_name(), count, capacity])
	queue_redraw()
	return true


# Items still out there, oldest first. Freed ones are dropped from the list.
func get_launched() -> Array[SpaceProp]:
	var alive: Array[SpaceProp] = []

	for item in launched:
		if is_instance_valid(item) and not item.is_queued_for_deletion():
			alive.append(item)

	launched = alive
	return alive


func _get_load_mass() -> float:
	return count * item_mass


func _make_item() -> SpaceProp:
	return SpaceProp.new()


func _is_my_item(_prop: SpaceProp) -> bool:
	return false


func _on_item_launched(_item: SpaceProp) -> void:
	pass


func _on_item_recovered(_item: SpaceProp) -> void:
	pass


# Plate, with one slot per item along the hull: lit when loaded. Too many items for the slots to
# fit: a gauge instead.
func _draw_module() -> void:
	_draw_plate(footprint, body_color)

	if capacity <= 0:
		return

	var inner := footprint.grow(-TEXEL * 2.0)
	var slot_length := floorf(inner.size.y / capacity / TEXEL) * TEXEL

	if slot_length < TEXEL * 2.0:
		_draw_gauge(inner, float(count) / capacity, item_color, outline_color)
		return

	for i in capacity:
		var slot := Rect2(inner.position.x, inner.position.y + i * slot_length, inner.size.x, slot_length - TEXEL)
		draw_rect(slot, outline_color)

		if i < count:
			draw_rect(slot.grow(-TEXEL * 0.5), item_color)
