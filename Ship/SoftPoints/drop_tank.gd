class_name DropTank
extends SoftPoint

# An external fuel tank. The thrusters burn it before the tanks inside (ShipMovement asks
# ShipSoftPoints first). Hold the key to jettison it: empty or not, it's dead weight on one side.
# Jettisoned, it floats away with the fuel it had left. Touch it gently to bolt it back on.

@export var capacity: float = 60.0
@export var fuel_mass_per_unit: float = 0.05 # Keep equal to ShipMass.fuel_mass_per_unit
@export var start_full: bool = true

@export_group("Look")
@export var fuel_color: Color = Color(0.33, 0.77, 0.57)
@export var gauge_color: Color = Color(0.16, 0.27, 0.23)
@export var stripe_dark_color: Color = Color(0.12, 0.11, 0.11)

var fuel: float = 0.0

var _drawn_ratio: float = -1.0


func _init() -> void:
	footprint = Rect2(0, -11, 10, 22)
	dry_mass = 1.0
	can_jettison = true
	body_color = Color(0.67, 0.36, 0.18)


func _ready() -> void:
	if start_full:
		fuel = capacity


func draw_fuel(amount: float) -> float:
	var granted := minf(amount, fuel)

	if granted <= 0.0:
		return 0.0

	fuel -= granted
	_redraw_if_changed()
	return granted


func get_fuel() -> float:
	return fuel


func get_fuel_capacity() -> float:
	return capacity


func restock() -> void:
	fuel = capacity
	_redraw_if_changed()


func get_status_text() -> String:
	return "%d / %d fuel" % [fuel, capacity]


func _on_tap() -> void:
	say("Drop tank: hold the key to jettison it")


func _get_load_mass() -> float:
	return fuel * fuel_mass_per_unit


# A rounded tank strapped across, with a gauge window and a hazard band at each end.
func _draw_module() -> void:
	_draw_plate(footprint, body_color)

	var inner := footprint.grow(-TEXEL)

	for y in [inner.position.y, inner.end.y - TEXEL * 2.0]:
		var x := inner.position.x

		while x < inner.end.x:
			var color := accent_color if int(x / TEXEL) % 2 == 0 else stripe_dark_color
			draw_rect(Rect2(x, y, TEXEL, TEXEL * 2.0), color)
			x += TEXEL

	var gauge := Rect2(inner.get_center().x - TEXEL, inner.position.y + TEXEL * 3.0, TEXEL * 2.0, inner.size.y - TEXEL * 6.0)
	_draw_gauge(gauge, fuel / capacity, fuel_color, gauge_color)


# The gauge is a few texels tall: only redraw when it shows a different level.
func _redraw_if_changed() -> void:
	var ratio := snappedf(fuel / capacity, 0.05)

	if ratio != _drawn_ratio:
		_drawn_ratio = ratio
		queue_redraw()
