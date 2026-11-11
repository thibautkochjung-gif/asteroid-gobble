extends "res://_tools/mothership_mockup_trains_v5.gd"

# Round 7: G4 (heavy) in four meaner palettes. Same shapes, colours from the palette below.
# - H1 gunmetal and red: dark steel, red hazard bands, a red-hot reactor
# - H2 black and yellow: near-black plate, wasp stripes, a white-hot reactor
# - H3 oxblood: deep red-brown plate, cream stencils, a green reactor
# - H4 olive drab: military olive, orange bands, an orange reactor, red cab glass

const PALETTES := {
	"H1": { "hull": Color(0.24, 0.25, 0.28), "trim": Color(0.1, 0.1, 0.11), "accent": Color(0.78, 0.13, 0.08), "accent_dark": Color(0.1, 0.1, 0.11), "glow": Color(1.0, 0.35, 0.15), "fin": Color(0.42, 0.2, 0.14), "inset": Color(0.36, 0.37, 0.4), "glass": Color(0.95, 0.55, 0.2) },
	"H2": { "hull": Color(0.14, 0.14, 0.15), "trim": Color(0.07, 0.07, 0.08), "accent": Color(0.93, 0.72, 0.1), "accent_dark": Color(0.07, 0.07, 0.08), "glow": Color(1.0, 0.95, 0.75), "fin": Color(0.32, 0.28, 0.18), "inset": Color(0.26, 0.26, 0.27), "glass": Color(0.93, 0.72, 0.1) },
	"H3": { "hull": Color(0.38, 0.12, 0.1), "trim": Color(0.11, 0.08, 0.08), "accent": Color(0.85, 0.8, 0.68), "accent_dark": Color(0.11, 0.08, 0.08), "glow": Color(0.55, 1.0, 0.35), "fin": Color(0.3, 0.22, 0.18), "inset": Color(0.25, 0.1, 0.09), "glass": Color(0.55, 1.0, 0.35) },
	"H4": { "hull": Color(0.29, 0.31, 0.21), "trim": Color(0.1, 0.11, 0.08), "accent": Color(0.92, 0.45, 0.1), "accent_dark": Color(0.1, 0.11, 0.08), "glow": Color(1.0, 0.55, 0.15), "fin": Color(0.36, 0.3, 0.2), "inset": Color(0.21, 0.23, 0.15), "glass": Color(0.9, 0.15, 0.1) },
}

var _hull := GRAY
var _trim := DARK
var _accent := STRIPE
var _accent_dark := STRIPE_DARK
var _glow := SKY
var _fin := FIN
var _inset := SUPER
var _glass := GLASS


func _ready() -> void:
	super()
	var palette: Dictionary = PALETTES.get(concept, PALETTES["H1"])
	_hull = palette.hull
	_trim = palette.trim
	_accent = palette.accent
	_accent_dark = palette.accent_dark
	_glow = palette.glow
	_fin = palette.fin
	_inset = palette.inset
	_glass = palette.glass
	_body_color = _hull # The deflector reads these
	_trim_color = _trim
	_accent_color = _accent


func _draw() -> void:
	_rng.seed = 11
	_draw_lashed_flatbeds()
	_draw_heavy()
	_draw_deflector()


# --- Palette versions of the shared parts


func _p_stripes(rect: Rect2, block: float) -> void:
	var is_vertical := rect.size.y > rect.size.x
	var length := rect.size.y if is_vertical else rect.size.x
	var t := 0.0
	var i := 0

	while t < length:
		var size := minf(block, length - t)
		var piece := Rect2(rect.position.x, rect.position.y + t, rect.size.x, size) if is_vertical else Rect2(rect.position.x + t, rect.position.y, size, rect.size.y)
		draw_rect(piece, _accent if i % 2 == 0 else _accent_dark)
		t += block
		i += 1


func _p_reactor(center: Vector2, radius: float) -> void:
	draw_circle(center + Vector2(14, 16), radius - 2.0, SHADOW)
	draw_circle(center, radius + 4.0, OUTLINE)
	draw_circle(center, radius, _inset.darkened(0.2))
	draw_circle(center + Vector2(-radius * 0.12, -radius * 0.12), radius * 0.8, _inset)
	draw_arc(center, radius * 0.9, 0.0, TAU, 48, _accent, radius * 0.09)

	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		draw_rect(Rect2(center + direction * radius * 0.9 - Vector2(5, 5), Vector2(10, 10)), OUTLINE)

	draw_circle(center, radius * 0.4, Color(_glow, 0.25))
	draw_circle(center, radius * 0.34, OUTLINE)
	draw_circle(center, radius * 0.29, _glow.darkened(0.45))
	draw_circle(center, radius * 0.17, _glow)


func _p_wing(root_x: float, root_y: float, tip_y: float, half_width: float, sweep: float, side: float) -> void:
	var points := PackedVector2Array([
		Vector2(root_x - half_width, side * root_y), Vector2(root_x - sweep - half_width, side * tip_y),
		Vector2(root_x - sweep + half_width, side * tip_y), Vector2(root_x + half_width, side * root_y),
	])
	_shadow_poly(points)
	draw_colored_polygon(points, _trim)
	var y := root_y + 14.0

	while y < tip_y - 8.0:
		var t := (y - root_y) / (tip_y - root_y)
		draw_rect(Rect2(root_x - sweep * t - half_width + 8.0, side * y - 3.0, half_width * 2.0 - 16.0, 6), _fin)
		y += 16.0

	_strut(Vector2(root_x, side * root_y), Vector2(root_x - sweep, side * tip_y), 8.0, _accent)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE, TEXEL * 2.0)
	draw_circle(Vector2(root_x - sweep, side * (tip_y - 4.0)), 7.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)


func _p_stencil(at: Vector2, text: String, size: int) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _accent)


# --- The heavy locomotive (G4's shapes)


func _draw_heavy() -> void:
	var length := _hull_len
	var reactor := Vector2(340, 0)

	# Tow yoke
	var yoke := PackedVector2Array([Vector2(70, -70), Vector2(0, -40), Vector2(-20, -20), Vector2(-20, 20), Vector2(0, 40), Vector2(70, 70)])
	_shadow_poly(yoke)
	_polygon_plate(yoke, _trim)
	draw_circle(Vector2(-4, 0), 16.0, OUTLINE)
	draw_circle(Vector2(-4, 0), 12.0, NOZZLE)
	_p_stripes(Rect2(30, -60, 12, 120), 12.0)

	# Engines on sponsons, outboard of the widest car (250 px): the exhaust passes beside the train
	for side: float in [-1.0, 1.0]:
		var sponson := Rect2(10, side * 380.0 - 110.0, 120, 220)

		for brace_x in [40.0, 100.0]:
			_strut(Vector2(brace_x + 40.0, side * 70.0), Vector2(brace_x, side * 280.0), 18.0, _trim)

		_strut(Vector2(150, side * 70.0), Vector2(40, side * 420.0), 8.0, _trim.lightened(0.15))

		for engine_y in [side * 325.0, side * 435.0]:
			_draw_plume(Vector2(-100, engine_y), 44.0, 320.0)
			_draw_bell(Vector2(10, engine_y), Vector2(-100, engine_y), 34.0, 46.0)

		_shadow(sponson)
		_smooth_plate(sponson, _trim)
		_p_stripes(Rect2(sponson.end.x - 12.0, sponson.position.y, 10, sponson.size.y), 14.0)
		draw_circle(Vector2(70, side * 490.0 - side * 4.0), 7.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)

	# Thrust frame: now only carries the yoke and the sponson braces
	var frame := Rect2(20, -110, 70, 220)
	_shadow(frame)
	_smooth_plate(frame, _trim)

	# Radiator paddles
	for paddle_x in [210.0, 470.0, 640.0]:
		for side: float in [-1.0, 1.0]:
			_p_wing(paddle_x, 80.0, 330.0, 46.0, 30.0, side)

	# Boxed truss
	var box := Rect2(60, -70, length - 230.0, 140)
	_shadow(box)
	_smooth_plate(box, _hull)
	var x := 110.0

	while x < box.end.x - 60.0:
		draw_circle(Vector2(x, 0), 24.0, OUTLINE)
		draw_circle(Vector2(x, 0), 20.0, _trim)
		x += 90.0

	_p_stripes(Rect2(box.position.x, -70, box.size.x, 8), 20.0)
	_p_stripes(Rect2(box.position.x, 62, box.size.x, 8), 20.0)

	# Caged reactor
	_p_reactor(reactor, 120.0)

	for k in 6:
		var angle := TAU * k / 6.0
		_strut(reactor + Vector2.from_angle(angle) * 70.0, reactor + Vector2.from_angle(angle + PI * 0.4) * 140.0, 6.0, _trim.lightened(0.15))

	draw_arc(reactor, 140.0, 0.0, TAU, 48, OUTLINE, 10.0)
	draw_arc(reactor, 140.0, 0.0, TAU, 48, _trim.lightened(0.15), 6.0)

	# Deflector yoke
	var bar_x := length + 70.0
	var bar := Rect2(bar_x, -150, 40, 300)

	for side: float in [-1.0, 1.0]:
		_strut(Vector2(length - 100.0, side * 40.0), Vector2(bar_x + 20.0, side * 120.0), 14.0, _trim)

	_shadow(bar)
	_smooth_plate(bar, _trim)
	_p_stripes(Rect2(bar.end.x - 12.0, bar.position.y, 10, bar.size.y), 14.0)

	# Cab
	var cab := Rect2(length - 230.0, -130, 220, 260)
	_shadow(cab)
	_smooth_plate(cab, _hull)
	_smooth_plate(Rect2(cab.position + Vector2(20, 30), Vector2(110, 200)), _inset)
	var glass := PackedVector2Array([Vector2(cab.end.x - 50.0, -110), Vector2(cab.end.x - 6.0, -70), Vector2(cab.end.x - 6.0, 70), Vector2(cab.end.x - 50.0, 110)])
	draw_polyline(glass, OUTLINE, 22.0)
	draw_polyline(glass, _glass.darkened(0.5), 16.0)
	draw_polyline(glass, _glass, 3.0)
	_p_stencil(Vector2(120, 112), _loco_name, 30)
