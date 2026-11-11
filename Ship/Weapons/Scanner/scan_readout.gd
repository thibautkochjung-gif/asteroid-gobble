class_name ScanReadout
extends Control

# What a scanner says about each rock its scan line has crossed lately (Scanner.readout_rocks),
# next to the rock, in screen space. Two looks, like the two builds:
# - basic: yellow corner ticks around the rock and a small dark tag with a hazard stripe, in the
#   cockpit's colours. It says SCANNING with a progress bar, then POSSIBLE ORE: and one to three
#   guesses once the line has met ore, or NO ORE DETECTED once it has covered the whole rock.
# - precision: cyan brackets, a scan line going over the rock, and a data block: the ore, how many
#   ore cells have been found, what they're worth, and how much of the rock has been scanned.
# It lives on a CanvasLayer under the scanner, so it goes away with it.

const BRACKET_ARM: float = 9.0
const BRACKET_MARGIN: float = 6.0
const TEXT_GAP: float = 10.0 # Between the brackets and the text
const TAG_PADDING := Vector2(8.0, 5.0)
const STRIPE_WIDTH: float = 5.0
const BAR_HEIGHT: float = 4.0

@export var font_size: int = 13
@export var small_font_size: int = 10

@export_group("Basic")
@export var tag_color: Color = Color(CockpitPalette.STEEL_DARK, 0.92)
@export var text_color: Color = CockpitPalette.YELLOW_LIT
@export var caption_color: Color = CockpitPalette.TILE_OFF_TEXT
@export var tick_color: Color = CockpitPalette.YELLOW

@export_group("Precision")
@export var tech_color: Color = Color(0.4, 0.95, 1.0)
@export var tech_dim_color: Color = Color(0.4, 0.95, 1.0, 0.35)
@export var scan_line_period: float = 1.6 # s for the scan line to cross the rock

var scanner: Scanner

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if scanner == null:
		return

	for rock in scanner.readout_rocks:
		if not is_instance_valid(rock):
			continue

		var bounds := _get_screen_bounds(rock).grow(BRACKET_MARGIN)

		if scanner.precise:
			_draw_precise(rock, bounds)
		else:
			_draw_basic(rock, bounds)


# --- Basic: a tag


func _draw_basic(rock: Asteroid, bounds: Rect2) -> void:
	_draw_brackets(bounds, tick_color, BRACKET_ARM * 0.7)

	var is_complete := scanner.is_fully_scanned(rock)
	var line: String

	if rock.scan_found_ore:
		var names := PackedStringArray()

		for ore in scanner.get_probable_ores(rock):
			names.append(CellMaterials.get_material(ore).display_name.to_upper())

		line = "POSSIBLE ORE: " + ", ".join(names)
	elif is_complete:
		line = "NO ORE DETECTED"
	else:
		line = "SCANNING..."

	var font := get_theme_default_font()
	var caption := "SCAN %d%%" % roundi(scanner.get_progress(rock) * 100.0)
	var text_width := maxf(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, 90.0)
	var height := TAG_PADDING.y * 2.0 + small_font_size + 3.0 + font_size

	if not is_complete:
		height += BAR_HEIGHT + 5.0

	var tag := Rect2(bounds.end.x + TEXT_GAP, bounds.position.y, STRIPE_WIDTH + TAG_PADDING.x * 2.0 + text_width, height)

	# Shadow, panel, outline, then the hazard stripe down its left edge.
	draw_rect(Rect2(tag.position + Vector2(2.0, 2.0), tag.size), Color(0.0, 0.0, 0.0, 0.4))
	draw_rect(tag, tag_color)
	draw_rect(tag, CockpitPalette.OUTLINE, false, 1.0)
	var stripe_rows := ceili(tag.size.y / STRIPE_WIDTH)

	for i in stripe_rows:
		var row_y := tag.position.y + i * STRIPE_WIDTH
		var cell := Rect2(tag.position.x, row_y, STRIPE_WIDTH, minf(STRIPE_WIDTH, tag.end.y - row_y))
		draw_rect(cell, CockpitPalette.YELLOW if i % 2 == 0 else CockpitPalette.OUTLINE)

	var x := tag.position.x + STRIPE_WIDTH + TAG_PADDING.x
	var y := tag.position.y + TAG_PADDING.y + small_font_size
	draw_string(font, Vector2(x, y), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, small_font_size, caption_color)
	y += 3.0 + font_size
	draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	if not is_complete:
		var bar := Rect2(x, y + 5.0, text_width, BAR_HEIGHT)
		draw_rect(bar, CockpitPalette.OUTLINE)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * scanner.get_progress(rock), bar.size.y)), CockpitPalette.YELLOW)


# --- Precision: tech readout


func _draw_precise(rock: Asteroid, bounds: Rect2) -> void:
	_draw_brackets(bounds, tech_color, BRACKET_ARM)
	_draw_scan_line(bounds)

	var font := get_theme_default_font()
	var at := Vector2(bounds.end.x + TEXT_GAP, bounds.position.y + small_font_size)
	var ore_name := CellMaterials.get_material(rock.ore_type).display_name.to_upper()
	_draw_tech_text(font, at, "SPECTRAL ANALYSIS", small_font_size, tech_dim_color)
	at.y += small_font_size + 6.0

	var lines: Array[String] = []
	var dim_lines: Array[String] = []

	if rock.scan_found_ore or not rock.revealed_ore.is_empty():
		lines.append(ore_name)
		lines.append("%d ORE CELLS FOUND" % rock.revealed_ore.size())
		lines.append("VALUE FOUND  %s CR" % _format_credits(scanner.get_found_value(rock)))
	elif scanner.is_fully_scanned(rock):
		lines.append("NO ORE DETECTED")
		dim_lines.append("TRACES  " + ore_name)
	else:
		lines.append("SCANNING...")

	for line in lines:
		at.y += font_size - small_font_size
		_draw_tech_text(font, at, line, font_size, tech_color)
		at.y += small_font_size + 5.0

	for line in dim_lines:
		_draw_tech_text(font, at, line, small_font_size, tech_dim_color)
		at.y += small_font_size + 5.0

	var progress := scanner.get_progress(rock)
	_draw_tech_text(font, at, "SCANNED %d%%" % roundi(progress * 100.0), small_font_size, tech_dim_color)
	var bar := Rect2(at.x, at.y + 4.0, 90.0, 4.0)
	draw_rect(bar, tech_dim_color, false, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), tech_color)


func _draw_brackets(bounds: Rect2, color: Color, arm: float) -> void:
	var corners := [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]
	var center := bounds.get_center()

	for corner: Vector2 in corners:
		var inward := Vector2(signf(center.x - corner.x), signf(center.y - corner.y)) * arm
		var points := PackedVector2Array([corner + Vector2(inward.x, 0.0), corner, corner + Vector2(0.0, inward.y)])
		draw_polyline(points, CockpitPalette.SHADOW, 4.0)
		draw_polyline(points, color, 2.0)


# A thin line going down over the rock, again and again, with a faint trail.
func _draw_scan_line(bounds: Rect2) -> void:
	var progress := fmod(_time, scan_line_period) / scan_line_period
	var y := bounds.position.y + bounds.size.y * progress

	for i in 4:
		var trail_y := y - i * 3.0

		if trail_y < bounds.position.y:
			break

		var color := tech_color
		color.a = 0.5 / (i + 1)
		draw_line(Vector2(bounds.position.x, trail_y), Vector2(bounds.end.x, trail_y), color, 1.0)


func _draw_tech_text(font: Font, at: Vector2, text: String, text_size: int, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, 4, CockpitPalette.SHADOW)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)


# "12 480"
func _format_credits(amount: float) -> String:
	var digits := str(roundi(amount))
	var grouped := ""

	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += " "

		grouped += digits[i]

	return grouped


# --- Bounds


# The rock's collision rectangles, merged into one box, then that box on screen.
func _get_screen_bounds(rock: Asteroid) -> Rect2:
	var rects := rock.get_collision_rects()

	if rects.is_empty():
		var point := get_viewport().get_canvas_transform() * rock.global_position
		return Rect2(point, Vector2.ZERO)

	var local := Rect2(rects[0])

	for rect in rects:
		local = local.merge(Rect2(rect))

	local = Rect2(local.position * rock.cell_size, local.size * rock.cell_size)

	var to_screen := get_viewport().get_canvas_transform() * rock.global_transform
	var corners := [
		local.position,
		Vector2(local.end.x, local.position.y),
		local.end,
		Vector2(local.position.x, local.end.y),
	]
	var bounds := Rect2(to_screen * local.position, Vector2.ZERO)

	for corner in corners:
		bounds = bounds.expand(to_screen * corner)

	return bounds
