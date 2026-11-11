@tool
class_name HudNeedle
extends Control

# A gauge needle, centred in its rect. The dial face (ticks, red zone) is baked into the panel art.
# value 0..1 sweeps from MIN_ANGLE to MAX_ANGLE, 0° pointing up, to match the baked faces.

const MIN_ANGLE: float = -120.0
const MAX_ANGLE: float = 120.0
const REDRAW_STEP: float = 0.0005 # Share of the dial. Smaller moves are under a tenth of a pixel at the tip

@export_range(0.0, 1.0) var value: float = 0.5
@export var length: float = 23.0
@export var tail: float = 4.0 # Short stub on the other side of the hub
@export var color: Color = Color(0.12, 0.11, 0.11)
@export var response: float = 5.0 # Higher = snappier. The needle eases toward the value, like a real gauge
@export_range(0.0, 1.0) var jitter: float = 0.0 # Set by Cockpit after a hit: the needle shakes
@export var max_jitter: float = 0.15 # Share of the dial the needle can be knocked off by, at full jitter

var _shown: float = 0.5
var _drawn: float = -1.0 # _shown at the last redraw. A resting needle isn't redrawn


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shown = value


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_shown = value
	else:
		var target := clampf(value + randf_range(-1.0, 1.0) * jitter * max_jitter, 0.0, 1.0)
		_shown = lerpf(_shown, target, 1.0 - exp(-response * (1.0 + jitter * 4.0) * delta))

	if absf(_shown - _drawn) > REDRAW_STEP:
		_drawn = _shown
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var direction := Vector2.UP.rotated(deg_to_rad(lerpf(MIN_ANGLE, MAX_ANGLE, _shown)))
	var start := center - direction * tail
	var end := center + direction * length
	var shadow_offset := Vector2(1.0, 2.0)

	draw_line(start + shadow_offset, end + shadow_offset, Color(0.0, 0.0, 0.0, 0.35), 2.5, true)
	draw_line(start, end, color, 2.5, true)
	draw_circle(center, 3.5, color)
