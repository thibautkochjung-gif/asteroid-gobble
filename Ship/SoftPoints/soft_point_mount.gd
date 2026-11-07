@tool
class_name SoftPointMount
extends Marker2D

# A place on the hull where a soft point can be bolted on.
# +x points away from the hull: soft points are drawn along it, and throw things along it.
# Rotate the marker to face outward (-90° on the left flank, 90° on the right).
# ShipSoftPoints treats every SoftPointMount child as a mount, in tree order:
# mount N uses the input action "soft_point_N".
# The bracket is drawn in game too, so an empty mount still shows. In the editor, a dashed outline
# shows roughly how far a module sticks out.

const TEXEL: float = 2.0

@export var display_name: String = "Mount"
@export var bracket_length: float = 16.0 # Along the hull, in px

@export_group("Colors")
@export var bracket_color: Color = Color(0.36, 0.34, 0.31)
@export var bolt_color: Color = Color(0.54, 0.5, 0.45)
@export var outline_color: Color = Color(0.06, 0.055, 0.07)
@export var editor_outline_color: Color = Color(1.0, 0.75, 0.3, 0.7)


func _draw() -> void:
	var half := bracket_length * 0.5
	draw_rect(Rect2(-TEXEL * 2.0, -half, TEXEL * 3.0, bracket_length), outline_color)
	draw_rect(Rect2(-TEXEL, -half + TEXEL, TEXEL, bracket_length - TEXEL * 2.0), bracket_color)
	draw_rect(Rect2(-TEXEL, -half + TEXEL, TEXEL, TEXEL), bolt_color)
	draw_rect(Rect2(-TEXEL, half - TEXEL * 2.0, TEXEL, TEXEL), bolt_color)

	if Engine.is_editor_hint():
		draw_rect(Rect2(0.0, -12.0, 12.0, 24.0), editor_outline_color, false, 1.0)
