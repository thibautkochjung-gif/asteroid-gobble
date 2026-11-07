class_name CapacitorPack
extends SoftPoint

# Spare power. Consumers (laser charge, smelter, grinder, harpoon reel...) draw from the capacitors
# before the generator's battery (Generator asks ShipSoftPoints first). The generator refills
# them with whatever the full battery can't hold, so they recharge whenever the ship is idle.

@export var capacity: float = 40.0
@export var start_full: bool = true

@export_group("Look")
@export var charge_color: Color = Color(0.25, 0.82, 0.88)
@export var cell_color: Color = Color(0.1, 0.18, 0.22)

var stored: float = 0.0

var _drawn_ratio: float = -1.0


func _init() -> void:
	footprint = Rect2(0, -8, 8, 16)
	dry_mass = 2.0
	body_color = Color(0.31, 0.3, 0.31)


func _ready() -> void:
	if start_full:
		stored = capacity


func draw_power(amount: float) -> float:
	var granted := minf(amount, stored)

	if granted <= 0.0:
		return 0.0

	stored -= granted
	_redraw_if_changed()
	return granted


func store_power(amount: float) -> float:
	var accepted := minf(amount, capacity - stored)

	if accepted <= 0.0:
		return 0.0

	stored += accepted
	_redraw_if_changed()
	return accepted


func get_power() -> float:
	return stored


func get_power_capacity() -> float:
	return capacity


func restock() -> void:
	stored = capacity
	_redraw_if_changed()


func get_status_text() -> String:
	return "%d / %d power" % [stored, capacity]


func get_controls_text() -> String:
	return ""


# Two cells side by side, each with a gauge.
func _draw_module() -> void:
	_draw_plate(footprint, body_color)

	var inner := footprint.grow(-TEXEL * 2.0)
	var half := floorf(inner.size.y * 0.5 / TEXEL) * TEXEL

	for i in 2:
		var cell := Rect2(inner.position.x, inner.position.y + i * half, inner.size.x, half - TEXEL)
		_draw_gauge(cell, stored / capacity, charge_color, cell_color)


func _redraw_if_changed() -> void:
	var ratio := snappedf(stored / capacity, 0.05)

	if ratio != _drawn_ratio:
		_drawn_ratio = ratio
		queue_redraw()
