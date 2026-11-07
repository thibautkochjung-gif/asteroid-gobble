class_name Beacon
extends SpaceProp

# A bookmark in space. Small thrusters bring it to a stop after launch (_hold_station), then it
# stays put and blinks. It shows on the map markers as B1, B2... wherever you go.
# Touch it gently, or harpoon it, to take it back into a beacon rack.

static var _next_number: int = 1

@export var settle_time: float = 2.0 # s to come to a stop
@export var max_station_acceleration: float = 40.0 # px/s². A hard shove still pushes it away

var number: int = 0


func _init() -> void:
	super()
	radius = 4.0
	light_color = Color(0.4, 1.0, 0.5)
	marker_color = Color(0.4, 1.0, 0.5)


func _ready() -> void:
	super()
	number = _next_number
	_next_number += 1


func _prop_process(delta: float) -> void:
	_hold_station(delta, settle_time, max_station_acceleration)


func get_marker_text() -> String:
	return "B%d" % number


func _draw_prop() -> void:
	draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), outline_color)
	draw_rect(Rect2(-radius + TEXEL * 0.5, -radius + TEXEL * 0.5, radius * 2.0 - TEXEL, radius * 2.0 - TEXEL), body_color)
	draw_line(Vector2(0, -radius), Vector2(0, -radius - TEXEL * 3.0), outline_color, TEXEL * 0.5) # Antenna
	_draw_light(Vector2.ZERO, is_blink_on(1.0, 0.3))
