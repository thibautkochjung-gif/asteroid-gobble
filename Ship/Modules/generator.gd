class_name Generator
extends Node2D

# Produces power into a small battery. Consumers (laser charge, smelter) call draw_power()
# and get back what the battery could give, so they slow down when power runs short.
# Reserves (soft point capacitor packs) are drawn from first, and get whatever the full battery
# can't hold: they refill while the ship idles.
# Named draw_power() and not draw(): CanvasItem already has a signal called "draw".

@export var output_per_second: float = 6.0
@export var battery_capacity: float = 30.0
@export var reserves: ShipSoftPoints # Optional

@export_group("Visuals")
@export var core_radius: float = 5.0
@export var empty_color: Color = Color(0.1, 0.18, 0.22)
@export var full_color: Color = Color(0.25, 0.82, 0.88)

var stored: float = 0.0


func _ready() -> void:
	stored = battery_capacity


func _physics_process(delta: float) -> void:
	var produced := output_per_second * delta
	var new_stored := minf(stored + produced, battery_capacity)
	var surplus := stored + produced - new_stored

	if reserves != null and surplus > 0.0:
		reserves.store_power(surplus)

	if new_stored != stored:
		stored = new_stored
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, core_radius, empty_color.lerp(full_color, get_ratio()))


# Returns how much power was actually given.
func draw_power(amount: float) -> float:
	var from_reserves := 0.0

	if reserves != null and amount > 0.0:
		from_reserves = reserves.draw_power(amount)

	var from_battery := minf(amount - from_reserves, stored)

	if from_battery <= 0.0:
		return from_reserves

	stored -= from_battery
	queue_redraw()
	return from_reserves + from_battery


func get_ratio() -> float:
	return stored / battery_capacity
