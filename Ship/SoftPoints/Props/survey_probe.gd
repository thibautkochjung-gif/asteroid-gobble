class_name SurveyProbe
extends SpaceProp

# A drifting sensor. No thrusters: it keeps the momentum it was launched with, so aim the ship
# (and mind its speed) before you launch. While its battery lasts, it pings every ping_interval:
# a ring grows out to scan_radius, and every ore cell inside the ring is revealed, however deep
# in the rock (Asteroid.reveal_ore_near). A cheap, slow, one-spot version of a scanner.
# Out of battery, it goes dark and just drifts. Take it back to recharge it.

static var _next_number: int = 1

@export var battery_time: float = 60.0 # s of pinging
@export var ping_interval: float = 1.5 # s
@export var ring_time: float = 0.6 # s for the ring to reach scan_radius
@export var scan_radius: float = 150.0 # px

@export_group("Look")
@export var ring_color: Color = Color(0.35, 0.85, 1.0, 0.5)

var number: int = 0
var battery_left: float = 0.0

var _ping_timer: float = 0.0
var _ring_age: float = -1.0 # < 0: no ring showing


func _init() -> void:
	super()
	radius = 4.0
	body_color = Color(0.31, 0.3, 0.31)
	light_color = Color(0.35, 0.85, 1.0)
	marker_color = Color(0.35, 0.85, 1.0)


func _ready() -> void:
	super()
	number = _next_number
	_next_number += 1
	battery_left = battery_time


func _prop_process(delta: float) -> void:
	if _ring_age >= 0.0:
		_ring_age += delta

		if _ring_age > ring_time:
			_ring_age = -1.0

	if battery_left <= 0.0:
		return

	battery_left -= delta
	_ping_timer -= delta

	if _ping_timer <= 0.0:
		_ping_timer = ping_interval
		_ping()


func is_powered() -> bool:
	return battery_left > 0.0


func get_marker_text() -> String:
	if not is_powered():
		return "P%d dead" % number

	return "P%d %ds" % [number, ceili(battery_left)]


func _ping() -> void:
	_ring_age = 0.0

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		var rock := node as Asteroid

		if rock == null:
			continue

		if rock.get_closest_point(global_position).distance_to(global_position) > scan_radius:
			continue

		rock.reveal_ore_near(global_position, scan_radius)


func _draw_prop() -> void:
	# The ring is drawn without the probe's spin.
	draw_set_transform(Vector2.ZERO, -rotation)

	if _ring_age >= 0.0:
		var t := _ring_age / ring_time
		var color := ring_color
		color.a *= 1.0 - t
		draw_arc(Vector2.ZERO, scan_radius * t, 0.0, TAU, 48, color, TEXEL * 0.5)

	draw_set_transform(Vector2.ZERO)
	draw_circle(Vector2.ZERO, radius, outline_color)
	draw_circle(Vector2.ZERO, radius - TEXEL * 0.5, body_color)

	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		draw_line(Vector2.from_angle(angle) * radius, Vector2.from_angle(angle) * (radius + TEXEL * 2.0), outline_color, TEXEL * 0.5)

	_draw_light(Vector2.ZERO, is_powered() and is_blink_on(ping_interval, 0.2))
