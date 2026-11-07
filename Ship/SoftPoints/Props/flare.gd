class_name Flare
extends SpaceProp

# A short-lived marker: it burns bright for burn_time, shows on the map markers while it burns,
# then fades and is gone. Cheap: nobody takes flares back.

@export var burn_time: float = 25.0 # s
@export var fade_time: float = 2.0 # s
@export var glow_radius: float = 28.0 # px

@export_group("Look")
@export var core_color: Color = Color(1.0, 0.95, 0.8)
@export var glow_color: Color = Color(1.0, 0.35, 0.2)

var burn_left: float = 0.0


func _init() -> void:
	super()
	radius = 2.0
	recoverable = false
	marker_color = Color(1.0, 0.45, 0.3)
	z_index = 2


func _ready() -> void:
	super()
	burn_left = burn_time


func _prop_process(delta: float) -> void:
	burn_left -= delta

	if burn_left <= -fade_time:
		queue_free()


func get_marker_text() -> String:
	return "Flare" if burn_left > 0.0 else ""


func _draw_prop() -> void:
	var strength := 1.0 if burn_left > 0.0 else clampf(1.0 + burn_left / fade_time, 0.0, 1.0)
	var flicker := 0.85 + 0.15 * sin(_age * 37.0) * sin(_age * 13.0)

	for i in 4:
		var ring := 1.0 - i * 0.25
		var color := glow_color
		color.a = 0.07 * strength * flicker * (i + 1)
		draw_circle(Vector2.ZERO, glow_radius * ring * flicker, color)

	draw_rect(Rect2(-TEXEL, -TEXEL, TEXEL * 2.0, TEXEL * 2.0), outline_color)
	var core := core_color
	core.a = strength
	draw_rect(Rect2(-TEXEL * 0.5, -TEXEL * 0.5, TEXEL, TEXEL), core)
