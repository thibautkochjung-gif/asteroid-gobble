class_name RockReadout
extends Control

# The flight computer's readout on rocks (ShipComputer):
# - Mouse over a rock: brackets, its speed relative to the ship (REL), how fast the gap between
#   them shrinks (CLOSING) or grows (OPENING), and an arrow for where the rock is going as seen
#   from the ship.
# - The rock being matched (F) keeps its brackets in yellow, tagged MATCH.
# Screen-space overlay like MapMarkers: lives in the HUD's CanvasLayer, reads the camera through
# the viewport's canvas transform.

const BRACKET_ARM: float = 7.0 # px, length of each corner's arms
const BRACKET_MARGIN: float = 6.0 # px between the rock and its brackets
const ARROW_HEAD := Vector2(6.0, 4.0) # Depth, half-width

@export var computer: ShipComputer
@export var pixels_per_meter: float = 1.0 # Keep equal to Cockpit.pixels_per_meter
@export var font_size: int = 12
@export var arrow_scale: float = 0.8 # Screen px per px/s of relative speed
@export var max_arrow_length: float = 90.0 # Screen px
@export var min_arrow_speed: float = 1.0 # px/s. Slower: no arrow

@export_group("Colors")
@export var hover_color: Color = CockpitPalette.SCOPE
@export var match_color: Color = CockpitPalette.YELLOW


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if computer == null:
		return

	var target: Asteroid = computer.target if computer.order == ShipComputer.Order.MATCH else null

	if is_instance_valid(target):
		_draw_rock(target, match_color, "MATCH")

	if is_instance_valid(computer.hovered) and computer.hovered != target:
		_draw_rock(computer.hovered, hover_color, "")


func _draw_rock(rock: Asteroid, color: Color, title: String) -> void:
	var canvas := get_viewport().get_canvas_transform()
	var local_bounds := _get_local_bounds(rock)
	var bounds := _get_screen_bounds(local_bounds, canvas * rock.global_transform).grow(BRACKET_MARGIN)
	_draw_brackets(bounds, color)

	var ship := computer.ship
	var relative := rock.linear_velocity - ship.linear_velocity
	var line_of_sight := (rock.to_global(local_bounds.get_center()) - ship.global_position).normalized()
	var closing := -relative.dot(line_of_sight) / pixels_per_meter
	var lines := PackedStringArray()

	if not title.is_empty():
		lines.append(title)

	lines.append("REL %d m/s" % roundi(relative.length() / pixels_per_meter))
	lines.append("%s %d" % ["CLOSING" if closing >= 0.0 else "OPENING", absi(roundi(closing))])

	var font := get_theme_default_font()
	var at := Vector2(bounds.end.x + 8.0, bounds.position.y + font_size)

	for line in lines:
		draw_string_outline(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, CockpitPalette.SHADOW)
		draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		at.y += font_size + 2.0

	if relative.length() >= min_arrow_speed:
		var direction := canvas.basis_xform(relative).normalized()
		var length := minf(relative.length() * arrow_scale, max_arrow_length)
		_draw_arrow(bounds.get_center(), direction, length, color)


# The rock's collision rectangles, merged into one box in the rock's own space.
func _get_local_bounds(rock: Asteroid) -> Rect2:
	var rects := rock.get_collision_rects()

	if rects.is_empty():
		return Rect2()

	var bounds := Rect2(rects[0])

	for rect in rects:
		bounds = bounds.merge(Rect2(rect))

	return Rect2(bounds.position * rock.cell_size, bounds.size * rock.cell_size)


# The box of a (possibly rotated) local rectangle, on screen.
func _get_screen_bounds(local_bounds: Rect2, to_screen: Transform2D) -> Rect2:
	var corners := [
		local_bounds.position,
		Vector2(local_bounds.end.x, local_bounds.position.y),
		local_bounds.end,
		Vector2(local_bounds.position.x, local_bounds.end.y),
	]
	var bounds := Rect2(to_screen * local_bounds.position, Vector2.ZERO)

	for corner in corners:
		bounds = bounds.expand(to_screen * corner)

	return bounds


func _draw_brackets(bounds: Rect2, color: Color) -> void:
	var corners := [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	var center := bounds.get_center()

	for corner: Vector2 in corners:
		var inward := Vector2(signf(center.x - corner.x), signf(center.y - corner.y)) * BRACKET_ARM
		var points := PackedVector2Array([corner + Vector2(inward.x, 0.0), corner, corner + Vector2(0.0, inward.y)])
		draw_polyline(points, CockpitPalette.SHADOW, 4.0, true)
		draw_polyline(points, color, 2.0, true)


func _draw_arrow(from: Vector2, direction: Vector2, length: float, color: Color) -> void:
	var tip := from + direction * length
	var back := tip - direction * ARROW_HEAD.x
	var side := direction.orthogonal() * ARROW_HEAD.y
	var head := PackedVector2Array([back + side, tip, back - side])
	draw_line(from, tip, CockpitPalette.SHADOW, 4.0, true)
	draw_polyline(head, CockpitPalette.SHADOW, 4.0, true)
	draw_line(from, tip, color, 2.0, true)
	draw_polyline(head, color, 2.0, true)
