class_name FuelTankRoom
extends Room

# Holds the fuel the thrusters burn. ShipMovement draws from every tank through ShipRooms.
# Capacity comes from the room's size: capacity_per_texel for every texel of floor.
# The fuel sits in pressurised tanks (as many as fit across the room), so it doesn't slosh:
# its weight counts at the room's centre, and the tanks are drawn as gauges, filled bottom up.

@export var capacity_per_texel: float = 0.3 # A 17x24 texel room (the old size) holds about 120
@export var start_full: bool = true # Prototype: a freshly installed tank comes full

@export_group("Visuals")
@export var tank_width_texels: int = 8 # Rough width of one tank: sets how many fit side by side
@export var fuel_color: Color = Color(0.33, 0.77, 0.57)
@export var tank_color: Color = Color(0.16, 0.27, 0.23)
@export var tank_rim_color: Color = Color(0.54, 0.5, 0.45)

var capacity: float = 0.0 # Set from the size in _ready
var fuel: float = 0.0


func _ready() -> void:
	super()
	capacity = get_area_texels() * capacity_per_texel

	if start_full:
		fuel = capacity


# Returns how much fuel was actually given.
func draw_fuel(amount: float) -> float:
	var granted := minf(amount, fuel)

	if granted <= 0.0:
		return 0.0

	fuel -= granted
	contents_changed.emit()
	return granted


func refuel() -> void:
	fuel = capacity
	contents_changed.emit()


func get_fill_ratio() -> float:
	return fuel / capacity


func get_status_text() -> String:
	return "%d / %d fuel" % [fuel, capacity]


func clear_contents() -> void:
	fuel = 0.0
	contents_changed.emit()


# Tanks side by side, one texel apart, each with a rim and a gauge.
func _draw_contents() -> void:
	var inner := get_inner_rect().grow(-TEXEL)
	var tank_count := maxi(1, roundi(inner.size.x / (tank_width_texels * TEXEL)))
	var tank_width := snap_texel((inner.size.x - TEXEL * (tank_count - 1)) / tank_count)
	var ratio := clampf(get_fill_ratio(), 0.0, 1.0)

	for i in tank_count:
		var tank := Rect2(inner.position.x + i * (tank_width + TEXEL), inner.position.y, tank_width, inner.size.y)
		draw_rect(tank, tank_rim_color)

		var inside := tank.grow(-TEXEL)
		draw_rect(inside, tank_color)

		var level := snap_texel(inside.size.y * ratio)
		draw_rect(Rect2(inside.position.x, inside.end.y - level, inside.size.x, level), fuel_color)
