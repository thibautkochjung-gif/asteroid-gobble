class_name DropMap
extends Control

# The undock map: the belt seen from above (depth to the right), the mothership's route for the
# next run, and the survey's estimate of where the valuable ore is, drawn as contour bands.
# The player clicks anywhere to pick a drop point. The route leg nearest to it is used, being the
# cheapest (DropQuote).
#
# The survey estimate comes from the same belt the field will build (BeltSettings, BeltSampler),
# shifted and blurred by the survey's error: a better survey (crew, later) sharpens it.
# Layers: this node draws the background and the depth grid, the Survey child the contour bands
# (survey_contours.gdshader), the Overlay child the route, the pin and the legends.

signal point_picked(km: Vector2)

const STATION_KM: float = 4.0 # Width of the station's strip, left of depth 0
const RULER_HEIGHT: float = 20.0 # px, depth labels along the top
const RIGHT_MARGIN_KM: float = 8.0 # Room for the last depth label
const SURVEY_FINE_BLUR: float = 4.0 # km. Surveys sharper than this are sampled at 2 pixels per km, the others at 1
const SURVEY_DISPLAY_PER_KM: float = 4.0 # Pixels per km of the texture the shader draws
const VALUE_CURVE: float = 0.85 # Values are shown as (value / max) ^ this. Under 1: the shallow belt's best pockets still show
const BACKGROUND := Color(0.05, 0.068, 0.072)
const GRID := Color(0.1, 0.145, 0.155)
const ROUTE_COLOR := CockpitPalette.CREAM
const TRANSFER_COLOR := CockpitPalette.SCOPE
const SURVEY_SHADER: Shader = preload("res://Hub/DropMap/survey_contours.gdshader")
const SURVEY_NAMES: Array[String] = ["Basic survey", "Surveyor's chart", "Geologist's chart"]

# The last survey texture: building one takes a fraction of a second, and the panel is opened
# again and again before a run.
static var _cached_survey: ImageTexture
static var _cached_key := Vector2i(-1, -1) # (run seed, survey level)

var route: BeltRoute
var run_seed: int = 0
var survey_level: int = 0 # Crew will raise it. 0 = the station's basic survey
var picked := Vector2.ZERO # km
var has_pick: bool = false

var _belt: BeltSettings
var _scale: float = 1.0 # px per km
var _origin := Vector2.ZERO # px of the belt point (0, 0)
var _hover := Vector2.ZERO # km
var _has_hover: bool = false
var _survey: TextureRect
var _overlay: Control


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	_belt = GameState.ECONOMY.belt

	_survey = TextureRect.new()
	_survey.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_survey.stretch_mode = TextureRect.STRETCH_SCALE
	_survey.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_survey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_survey)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	mouse_exited.connect(_on_mouse_exited)


func setup(belt_route: BeltRoute, seed_value: int) -> void:
	route = belt_route
	run_seed = seed_value
	_build_survey()
	_layout()


func pick(km: Vector2) -> void:
	picked = _clamp_to_belt(km)
	has_pick = true
	_overlay.queue_redraw()
	point_picked.emit(picked)


func km_to_px(km: Vector2) -> Vector2:
	return _origin + km * _scale


func px_to_km(px: Vector2) -> Vector2:
	return (px - _origin) / _scale


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion

	if motion != null:
		_hover = _clamp_to_belt(px_to_km(motion.position))
		_has_hover = true
		_overlay.queue_redraw()
		return

	var button := event as InputEventMouseButton

	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		pick(px_to_km(button.position))
		accept_event()


func _on_mouse_exited() -> void:
	_has_hover = false
	_overlay.queue_redraw()


# --- Layout


func _layout() -> void:
	if size.x <= 0.0 or size.y <= RULER_HEIGHT:
		return

	var span := Vector2(STATION_KM + _belt.depth_km + RIGHT_MARGIN_KM, _belt.width_km)
	var room := size - Vector2(0.0, RULER_HEIGHT)
	_scale = minf(room.x / span.x, room.y / span.y)
	_origin = Vector2((size.x - span.x * _scale) * 0.5 + STATION_KM * _scale, RULER_HEIGHT + room.y * 0.5)

	_survey.position = km_to_px(Vector2(0.0, -_belt.width_km * 0.5))
	_survey.size = Vector2(_belt.depth_km, _belt.width_km) * _scale
	queue_redraw()
	_overlay.queue_redraw()


func _clamp_to_belt(km: Vector2) -> Vector2:
	var half := _belt.width_km * 0.5
	return Vector2(clampf(km.x, 0.5, _belt.depth_km), clampf(km.y, -half, half))


# --- Survey


# The estimated value over the whole belt, shifted and blurred by the survey's error, as a texture.
func _build_survey() -> void:
	var level := _belt.survey_levels[clampi(survey_level, 0, _belt.survey_levels.size() - 1)]
	var material := ShaderMaterial.new()
	material.shader = SURVEY_SHADER
	material.set_shader_parameter(&"bands", level.z)
	material.set_shader_parameter(&"fill_color", CockpitPalette.YELLOW)
	material.set_shader_parameter(&"line_color", CockpitPalette.YELLOW_LIT)
	_survey.material = material

	var key := Vector2i(run_seed, survey_level)

	if _cached_key != key:
		_cached_survey = _make_survey_texture(level)
		_cached_key = key

	_survey.texture = _cached_survey


func _make_survey_texture(level: Vector3) -> ImageTexture:
	var sampler := BeltSampler.new(_belt, run_seed, Vector2.ZERO)
	var error := FastNoiseLite.new()
	error.seed = run_seed + 1
	error.frequency = 0.05
	var pixels_per_km := 2.0 if level.y < SURVEY_FINE_BLUR else 1.0
	var width := ceili(_belt.depth_km * pixels_per_km)
	var height := ceili(_belt.width_km * pixels_per_km)
	var values := PackedFloat32Array()
	values.resize(width * height)
	var top := 0.0

	# Depth's share of the value is common knowledge (deeper pays): only the rich and poor areas are
	# shifted by the survey's error.
	var by_depth := PackedFloat32Array()

	for x in width:
		by_depth.append(_belt.get_depth_value((x + 0.5) / pixels_per_km))

	for y in height:
		for x in width:
			var km := Vector2(x + 0.5, y + 0.5) / pixels_per_km - Vector2(0.0, _belt.width_km * 0.5)
			var shift := Vector2(error.get_noise_2dv(km), error.get_noise_3d(km.x, km.y, 50.0)) * level.x * 2.0
			var value := by_depth[x] * _belt.get_richness_factor(sampler.get_richness_at_km(km + shift))
			values[y * width + x] = value
			top = maxf(top, value)

	var image := Image.create_empty(width, height, false, Image.FORMAT_RF)

	for y in height:
		for x in width:
			image.set_pixel(x, y, Color(pow(values[y * width + x] / top, VALUE_CURVE) if top > 0.0 else 0.0, 0.0, 0.0))

	# Blur: down to one pixel per blur distance, then up smoothly to a size where the contour lines
	# come out round.
	var blur_size := maxf(level.y, 0.5) * pixels_per_km
	image.resize(maxi(roundi(width / blur_size), 2), maxi(roundi(height / blur_size), 2), Image.INTERPOLATE_BILINEAR)
	image.resize(ceili(_belt.depth_km * SURVEY_DISPLAY_PER_KM), ceili(_belt.width_km * SURVEY_DISPLAY_PER_KM), Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(image)


# --- Drawing


# Background, depth grid and ruler. The survey and the overlay come on top.
func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var top := km_to_px(Vector2(0.0, -_belt.width_km * 0.5)).y
	var bottom := km_to_px(Vector2(0.0, _belt.width_km * 0.5)).y

	for depth in range(0, int(_belt.depth_km) + 1, 10):
		var x := km_to_px(Vector2(depth, 0.0)).x
		draw_line(Vector2(x, top), Vector2(x, bottom), GRID, 1.0)
		draw_string(font, Vector2(x + 3.0, 14.0), "%d km" % depth, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HubStyle.DIM)

	for across in range(-30, 31, 10):
		var y := km_to_px(Vector2(0.0, across)).y
		draw_line(Vector2(km_to_px(Vector2.ZERO).x, y), Vector2(km_to_px(Vector2(_belt.depth_km, 0.0)).x, y), GRID, 1.0)


func _draw_overlay() -> void:
	if route == null:
		return

	_draw_station()
	_draw_route()

	if _has_hover:
		_draw_hover()

	if has_pick:
		_draw_pick()

	_draw_legends()


func _draw_station() -> void:
	var font := get_theme_default_font()
	var rect := Rect2(km_to_px(Vector2(-STATION_KM, -_belt.width_km * 0.5)), Vector2(STATION_KM, _belt.width_km) * _scale)
	_overlay.draw_rect(rect, CockpitPalette.STEEL_DARK)
	_overlay.draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), CockpitPalette.YELLOW)
	_overlay.draw_rect(rect, CockpitPalette.OUTLINE, false, 2.0)

	var text := "UNION RING FOUR"
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_overlay.draw_set_transform(Vector2(rect.get_center().x + 5.0, rect.get_center().y + text_width * 0.5), -PI * 0.5)
	_overlay.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CockpitPalette.YELLOW_LIT)
	_overlay.draw_set_transform(Vector2.ZERO)


func _draw_route() -> void:
	var outbound := _to_px(route.outbound)
	var inbound := _to_px(route.inbound)
	_overlay.draw_polyline(outbound, CockpitPalette.OUTLINE, 6.0, true)
	_overlay.draw_polyline(inbound, CockpitPalette.OUTLINE, 6.0, true)
	_overlay.draw_polyline(outbound, ROUTE_COLOR, 3.0, true)
	_draw_dashed_polyline(inbound, 12.0, 6.0, ROUTE_COLOR, 3.0)
	_draw_chevrons(outbound)
	_draw_chevrons(inbound)

	# Near the station, clear of the default drop point (20 km out).
	_draw_tag("OUTBOUND", outbound[outbound.size() / 14] + Vector2(-20.0, -26.0))
	_draw_tag("RETURN", inbound[inbound.size() - 1 - inbound.size() / 14] + Vector2(-20.0, 10.0))
	var tip := km_to_px(route.turnaround)
	_draw_tag("TURNS AT %d km" % roundi(route.turnaround.x), tip + Vector2(-60.0, -34.0) if tip.y > size.y * 0.5 else tip + Vector2(-60.0, 18.0))


func _draw_hover() -> void:
	var quote := DropQuote.create(route, _hover)
	var at := km_to_px(_hover)
	var hop := km_to_px(quote.hop.point)
	var ghost := Color(TRANSFER_COLOR, 0.5)
	_overlay.draw_dashed_line(at, hop, ghost, 1.5, 4.0)
	_draw_crosshair(at, Color(HubStyle.TEXT, 0.6), 10.0)

	if has_pick and at.distance_to(km_to_px(picked)) < 4.0:
		return

	var lines: Array[String] = ["%d km deep, %.1f km off" % [roundi(quote.depth), quote.hop.distance], HubStyle.format_credits(quote.fee)]
	_draw_box(lines, at + Vector2(16.0, 12.0), [HubStyle.TEXT, CockpitPalette.YELLOW_LIT])


func _draw_pick() -> void:
	var quote := DropQuote.create(route, picked)
	var at := km_to_px(picked)
	var hop := km_to_px(quote.hop.point)
	_overlay.draw_dashed_line(at, hop, TRANSFER_COLOR, 2.5, 5.0)

	# The hop: a diamond on the route, and the heading the ship leaves with.
	var diamond := PackedVector2Array([hop + Vector2(0.0, -8.0), hop + Vector2(8.0, 0.0), hop + Vector2(0.0, 8.0), hop + Vector2(-8.0, 0.0)])
	_overlay.draw_colored_polygon(diamond, CockpitPalette.YELLOW_LIT)
	diamond.append(diamond[0])
	_overlay.draw_polyline(diamond, CockpitPalette.OUTLINE, 2.0)

	_draw_crosshair(at, HubStyle.TEXT, 16.0)
	_overlay.draw_circle(at, 4.0, CockpitPalette.ALARM)
	_overlay.draw_circle(at, 4.0, CockpitPalette.OUTLINE, false, 1.5)


func _draw_legends() -> void:
	var font := get_theme_default_font()
	var level_name: String = SURVEY_NAMES[clampi(survey_level, 0, SURVEY_NAMES.size() - 1)]
	var error_km := _belt.survey_levels[clampi(survey_level, 0, _belt.survey_levels.size() - 1)].x
	var note := "%s, ±%d km" % [level_name, roundi(error_km)] if error_km > 0.0 else level_name
	var title := "ESTIMATED ORE VALUE"
	var bar_width := 150.0
	var padding := 10.0
	var note_width := font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var box_width := maxf(bar_width, maxf(note_width, font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)) + padding * 2.0
	var box := Rect2(Vector2(8.0, size.y - 92.0), Vector2(box_width, 84.0))
	_overlay.draw_rect(box, Color(BACKGROUND, 0.92))
	_overlay.draw_rect(box, CockpitPalette.STEEL_DARK, false, 2.0)
	var x := box.position.x + padding
	_overlay.draw_string(font, Vector2(x, box.position.y + 18.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HubStyle.TEXT)

	var bar := Rect2(Vector2(x, box.position.y + 26.0), Vector2(bar_width, 12.0))
	var low := Color(CockpitPalette.YELLOW, 0.0)
	var high := Color(CockpitPalette.YELLOW_LIT, 0.8)
	_overlay.draw_polygon(PackedVector2Array([bar.position, Vector2(bar.end.x, bar.position.y), bar.end, Vector2(bar.position.x, bar.end.y)]), PackedColorArray([low, high, high, low]))
	_overlay.draw_rect(bar, CockpitPalette.YELLOW_DARK, false, 1.0)
	_overlay.draw_string(font, Vector2(x, bar.end.y + 14.0), "LESS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HubStyle.DIM)
	_overlay.draw_string(font, Vector2(bar.end.x - font.get_string_size("MORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, bar.end.y + 14.0), "MORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HubStyle.DIM)
	_overlay.draw_string(font, Vector2(x, box.end.y - 8.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HubStyle.DIM)

	# Route key, next to it.
	var key := Rect2(Vector2(box.end.x + 8.0, box.position.y + 26.0), Vector2(0.0, 58.0))
	var labels: Array[String] = ["Mothership, outbound", "Mothership, return"]
	key.size.x = font.get_string_size(labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 60.0 + padding
	_overlay.draw_rect(key, Color(BACKGROUND, 0.92))
	_overlay.draw_rect(key, CockpitPalette.STEEL_DARK, false, 2.0)
	var line_y := key.position.y + 18.0
	_overlay.draw_line(Vector2(key.position.x + padding, line_y), Vector2(key.position.x + 44.0, line_y), ROUTE_COLOR, 3.0)
	_overlay.draw_string(font, Vector2(key.position.x + 52.0, line_y + 4.0), labels[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HubStyle.TEXT)
	line_y += 22.0
	_draw_dashed_polyline(PackedVector2Array([Vector2(key.position.x + padding, line_y), Vector2(key.position.x + 44.0, line_y)]), 8.0, 4.0, ROUTE_COLOR, 3.0)
	_overlay.draw_string(font, Vector2(key.position.x + 52.0, line_y + 4.0), labels[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HubStyle.TEXT)


# --- Drawing helpers


func _to_px(line: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()

	for km in line:
		points.append(km_to_px(km))

	return points


func _draw_crosshair(at: Vector2, color: Color, radius: float) -> void:
	_overlay.draw_arc(at, radius, 0.0, TAU, 24, color, 2.0, true)

	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_overlay.draw_line(at + direction * (radius + 2.0), at + direction * (radius + 8.0), color, 2.0)


# Dashes that run on across the points, not restarting at each one.
func _draw_dashed_polyline(points: PackedVector2Array, dash: float, gap: float, color: Color, width: float) -> void:
	var period := dash + gap
	var travelled := 0.0

	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var along := 0.0

		while along < length:
			var phase := fmod(travelled + along, period)
			var step := minf((dash - phase) if phase < dash else (period - phase), length - along)

			if phase < dash:
				_overlay.draw_line(a.lerp(b, along / length), a.lerp(b, (along + step) / length), color, width)

			along += maxf(step, 0.01)

		travelled += length


# Small arrows along a leg, pointing the way the mothership travels.
func _draw_chevrons(points: PackedVector2Array) -> void:
	var spacing := 90.0
	var travelled := 0.0
	var next := spacing * 0.5

	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)

		while next <= travelled + length:
			var at := a.lerp(b, (next - travelled) / length)
			var forward := (b - a).normalized()
			var side := forward.orthogonal()
			_overlay.draw_polyline(PackedVector2Array([at - forward * 5.0 + side * 5.0, at + forward * 3.0, at - forward * 5.0 - side * 5.0]), CockpitPalette.OUTLINE, 2.5)
			next += spacing

		travelled += length


# A strip of masking tape with a label, sized to its text.
func _draw_tag(text: String, at: Vector2) -> void:
	var font := get_theme_default_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var rect := Rect2(at, text_size + Vector2(12.0, 4.0))
	rect.position = rect.position.clamp(Vector2(2.0, RULER_HEIGHT + 2.0), size - rect.size - Vector2(2.0, 2.0))
	_overlay.draw_rect(rect, Color(CockpitPalette.CREAM, 0.92))
	_overlay.draw_string(font, rect.position + Vector2(6.0, text_size.y - 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CockpitPalette.MARKER_INK)


# A dark box with a few lines of text, kept inside the map.
func _draw_box(lines: Array[String], at: Vector2, colors: Array[Color]) -> void:
	var font := get_theme_default_font()
	var line_height := 17.0
	var width := 0.0

	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)

	var rect := Rect2(at, Vector2(width + 16.0, lines.size() * line_height + 8.0))

	if rect.end.x > size.x - 4.0:
		rect.position.x = at.x - rect.size.x - 32.0

	if rect.end.y > size.y - 4.0:
		rect.position.y = at.y - rect.size.y - 24.0

	_overlay.draw_rect(rect, Color(CockpitPalette.OUTLINE, 0.9))
	_overlay.draw_rect(rect, TRANSFER_COLOR, false, 1.0)

	for i in lines.size():
		_overlay.draw_string(font, rect.position + Vector2(8.0, 4.0 + line_height * (i + 1) - 4.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, colors[i])
