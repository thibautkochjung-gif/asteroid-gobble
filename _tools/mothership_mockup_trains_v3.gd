extends "res://_tools/mothership_mockup_trains_v2.gd"

# Round 4: D1's lashed flatbeds, a reworked locomotive (icebreaker layout: armoured ice belt,
# deck, stack, tiered superstructure, bridge with wings, engines in sponsons), and four fronts:
# - E1 deflector: a short nose and D4's emitter ring
# - E2 spoon bow: a rounded, flared bow, like the Arktika-class nuclear icebreakers
# - E3 Thyssen-Waas bow: a flat face that lifts the ice, reamer knives at the corners cut the lane
# - E4 ice knife + bubbler: a ram stem, and air-bubbling nozzles along the flanks (here: gas jets)
# Light comes from the top left: raised parts cast a shadow down and to the right. Mockup only.

const SUPER := Color(0.8, 0.79, 0.74) # Superstructure: off-white, like an icebreaker's
const SUPER_SHADE := Color(0.62, 0.61, 0.57)
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)
const GAS := Color(0.75, 0.92, 1.0)

var _hull_len: float = 1000.0


func _ready() -> void:
	_build({ "S": 680.0, "M": 560.0, "L": 960.0 }, { "S": 170.0, "M": 250.0, "L": 200.0 }, 110.0, 1000.0)
	_layout_flatbeds()
	_hull_len = _tug_front
	_body_color = STRIPE.darkened(0.12)
	_trim_color = DARK
	_accent_color = STRIPE
	_loco_half = 210.0
	_prow_half = 360.0
	_loco_name = "HAULER 7"

	if concept == "E1":
		_tug_front = _hull_len + 110.0 # The deflector ring sits ahead of the short nose

	_extent = _extent.expand(Vector2(_hull_len + 900.0, 0)).expand(Vector2(_hull_len, -_prow_half - 160.0)).expand(Vector2(_hull_len, _prow_half + 160.0))


func get_close_focus() -> Vector2:
	return Vector2(_hull_len * 0.55, 0)


func _draw() -> void:
	_rng.seed = 11
	_draw_lashed_flatbeds()
	_draw_loco_v3()


# --- Locomotive


func _draw_loco_v3() -> void:
	var length := _hull_len
	var half := _loco_half
	var nacelle_y := _prow_half - 50.0

	# Engines in sponsons faired into the hull
	for side: float in [-1.0, 1.0]:
		var y := side * nacelle_y
		_draw_plume(Vector2(-30, y), 44.0, 320.0)
		var fairing := PackedVector2Array([Vector2(60, side * half), Vector2(150, y), Vector2(560, y), Vector2(660, side * half)])
		_belted(fairing, _body_color, 18.0, true)
		var nacelle := Rect2(90, y - 46.0, 450, 92)
		_smooth_plate(nacelle, _body_color.darkened(0.08))
		draw_rect(Rect2(nacelle.position.x + 40.0, y - 3.0, nacelle.size.x - 100.0, 6), DARK)
		_rivet_row(Vector2(nacelle.position.x + 40.0, y - 16.0), Vector2(nacelle.end.x - 60.0, y - 16.0), _body_color)
		_draw_intake(Vector2(nacelle.end.x, y), 42.0)
		_draw_bell(Vector2(90, y), Vector2(-30, y), 34.0, 46.0)

	# Hull with its ice belt
	var hull := PackedVector2Array([Vector2(0, -half * 0.7), Vector2(50, -half), Vector2(length, -half), Vector2(length, half), Vector2(50, half), Vector2(0, half * 0.7)])
	_belted(hull, _body_color, 22.0, false)

	# Bow, after the hull: it covers the hull's front edge
	match concept:
		"E1":
			_draw_short_nose()
		"E2":
			_draw_spoon_bow()
		"E3":
			_draw_thyssen_waas_bow()
		"E4":
			_draw_knife_bow()

	_draw_deck(length, half)
	_draw_superstructure(length, half)

	if concept == "E1":
		_draw_deflector()


# Armour band (dark, riveted) around a deck of `color`. Open = no band along the back edge.
func _belted(points: PackedVector2Array, color: Color, band: float, is_open: bool) -> void:
	draw_colored_polygon(points, DARK)
	var inner := Geometry2D.offset_polygon(points, -band)

	if not inner.is_empty():
		var deck: PackedVector2Array = inner[0]
		draw_colored_polygon(deck, color)
		var deck_outline := deck.duplicate()
		deck_outline.append(deck[0])
		draw_polyline(deck_outline, color.lightened(0.18), TEXEL)

	# Rivets along the band
	for k in points.size():
		var from := points[k]
		var to := points[(k + 1) % points.size()]
		var steps := floori(from.distance_to(to) / 14.0)
		var inward := (to - from).orthogonal().normalized()
		inward = inward if Geometry2D.is_point_in_polygon((from + to) / 2.0 + inward * band * 0.5, points) else -inward

		for j in steps:
			var at := from.lerp(to, (j + 0.5) / steps) + inward * band * 0.5
			draw_rect(Rect2(at - Vector2.ONE, Vector2(TEXEL, TEXEL)), DARK.lightened(0.2))

	var outline := points.duplicate()

	if is_open:
		draw_polyline(outline, OUTLINE, TEXEL * 2.0)
	else:
		outline.append(points[0])
		draw_polyline(outline, OUTLINE, TEXEL * 2.0)


func _draw_deck(length: float, half: float) -> void:
	var inner_half := half - 24.0

	# Long deck plates, every other one a shade darker
	var x := 60.0
	var k := 0

	while x < length - 40.0:
		var width := minf(180.0, length - 40.0 - x)

		if k % 2 == 1:
			draw_rect(Rect2(x, -inner_half, width, inner_half * 2.0), _body_color.darkened(0.05))

		draw_rect(Rect2(x, -inner_half, TEXEL, inner_half * 2.0), _body_color.darkened(0.2))
		x += width
		k += 1

	_grime(Rect2(60, -inner_half, length - 120.0, inner_half * 2.0), int(length * half / 600.0))

	# Railings along the deck edges
	for side: float in [-1.0, 1.0]:
		var rail_x := 70.0

		while rail_x < length - 30.0:
			draw_rect(Rect2(rail_x, side * (inner_half - 8.0) - 1.0, 6, TEXEL), PIPE_DARK)
			rail_x += 14.0

	# Drone pad on the aft deck
	var pad := Vector2(150, 0)
	draw_circle(pad, 86.0, DARK)
	_dashed_circle(pad, 80.0, STRIPE, STRIPE_DARK, 24)
	draw_circle(pad, 66.0, DARK.lightened(0.05))
	draw_rect(Rect2(pad + Vector2(-28, -30), Vector2(10, 60)), STRIPE)
	draw_rect(Rect2(pad + Vector2(18, -30), Vector2(10, 60)), STRIPE)
	draw_rect(Rect2(pad + Vector2(-28, -5), Vector2(56, 10)), STRIPE)

	# Cargo hatches
	for hatch_y in [-120.0, 20.0]:
		var hatch := Rect2(290, hatch_y, 150, 100)
		draw_rect(Rect2(hatch.position + Vector2(8, 10), hatch.size), SHADOW)
		_smooth_plate(hatch, DARK.lightened(0.08))

		for rib in 5:
			draw_rect(Rect2(hatch.position.x + 14.0 + rib * 28.0, hatch.position.y + 8.0, 6, hatch.size.y - 16.0), DARK)

	# Deck crane
	var crane := Vector2(470, -inner_half + 34.0)
	var tip := crane + Vector2(-150, 30)
	draw_line(crane + Vector2(6, 8), tip + Vector2(6, 8), SHADOW, 10.0)
	draw_line(crane, tip, OUTLINE, 12.0)
	draw_line(crane, tip, STRIPE, 6.0)
	draw_line(tip, tip + Vector2(0, 30), PIPE_DARK, 2.0)
	draw_rect(Rect2(tip + Vector2(-5, 30), Vector2(10, 8)), OUTLINE)
	draw_circle(crane, 18.0, OUTLINE)
	draw_circle(crane, 15.0, DARK.lightened(0.1))

	# Stack (funnel)
	var stack := Vector2(560, 0)
	_draw_oval(stack + Vector2(10, 12), Vector2(56, 82), SHADOW)
	_draw_oval(stack, Vector2(58, 84), OUTLINE)
	_draw_oval(stack, Vector2(54, 80), SUPER)
	_draw_oval(stack, Vector2(44, 68), STRIPE)
	_draw_oval(stack, Vector2(34, 56), SUPER_SHADE)
	_draw_oval(stack, Vector2(26, 46), OUTLINE)

	for h in 6:
		draw_rect(Rect2(stack + Vector2(_rng.randf_range(-18, 18), _rng.randf_range(-36, 36)), Vector2(4, 4)), Color(1, 0.8, 0.5, 0.35))

	_stencil(Vector2(40, half - 36.0), _loco_name, 34)


func _draw_superstructure(length: float, half: float) -> void:
	# Tier 1: accommodation block
	var block := Rect2(640, -150, 230, 300)
	draw_rect(Rect2(block.position + Vector2(12, 14), block.size), SHADOW)
	_smooth_plate(block, SUPER)

	for side: float in [-1.0, 1.0]:
		for w in 7:
			draw_rect(Rect2(block.position.x + 16.0 + w * 30.0, side * 134.0 - 4.0, 14, 8), GLASS_DARK)

	# Reactor dome on its roof
	var dome := Vector2(705, 0)
	draw_circle(dome + Vector2(8, 10), 54.0, SHADOW)
	draw_circle(dome, 56.0, OUTLINE)
	draw_circle(dome, 52.0, SUPER_SHADE)
	draw_circle(dome, 38.0, SUPER)
	draw_circle(dome, 22.0, OUTLINE)
	draw_circle(dome, 18.0, SKY.darkened(0.3))
	draw_circle(dome, 9.0, SKY)

	# Radiator strips on the roof
	for side: float in [-1.0, 1.0]:
		var radiator := Rect2(770, side * 70.0 - (40.0 if side < 0.0 else 0.0), 80, 40)
		draw_rect(radiator, OUTLINE)
		var fin_x := radiator.position.x + 4.0

		while fin_x < radiator.end.x - 4.0:
			draw_rect(Rect2(fin_x, radiator.position.y + 4.0, TEXEL * 2.0, radiator.size.y - 8.0), FIN)
			fin_x += TEXEL * 4.0

	# Tier 2: the bridge, full width with wings past the hull
	var wing := half + 46.0
	var bridge := Rect2(880, -wing, 90, wing * 2.0)
	draw_rect(Rect2(bridge.position + Vector2(14, 16), bridge.size), SHADOW)
	_smooth_plate(bridge, SUPER)
	draw_rect(Rect2(bridge.position.x + 10.0, -half + 30.0, bridge.size.x - 30.0, (half - 30.0) * 2.0), SUPER_SHADE)

	# Forward window band, wing windows
	var glass := Rect2(bridge.end.x - 16.0, -wing + 10.0, 10, wing * 2.0 - 20.0)
	draw_rect(glass.grow(TEXEL), OUTLINE)
	draw_rect(glass, GLASS_DARK)
	draw_rect(Rect2(glass.position, Vector2(TEXEL * 2.0, glass.size.y)), GLASS)

	for side: float in [-1.0, 1.0]:
		draw_rect(Rect2(bridge.position.x + 10.0, side * (wing - 8.0) - 4.0, bridge.size.x - 30.0, 8), GLASS_DARK)
		draw_circle(Vector2(bridge.end.x - 6.0, side * (wing - 4.0)), 7.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)

	# Mast with a radar bar
	var mast := Vector2(912, 0)
	draw_line(mast + Vector2(-60, 6) + Vector2(10, 12), mast + Vector2(60, -6) + Vector2(10, 12), SHADOW, 10.0)
	draw_line(mast + Vector2(-60, 6), mast + Vector2(60, -6), OUTLINE, 10.0)
	draw_line(mast + Vector2(-60, 6), mast + Vector2(60, -6), NOZZLE, 6.0)
	draw_circle(mast, 14.0, OUTLINE)
	draw_circle(mast, 11.0, SUPER_SHADE)
	draw_circle(mast + Vector2(-26, 70), 14.0, OUTLINE)
	draw_circle(mast + Vector2(-26, 70), 11.0, Color.WHITE.darkened(0.15))


# --- Fronts


func _draw_short_nose() -> void:
	var length := _hull_len
	var half := _loco_half
	var points := PackedVector2Array([Vector2(length - 40.0, -half)])

	for k in 13:
		var angle := lerpf(-PI / 2.0, PI / 2.0, k / 12.0)
		points.append(Vector2(length + cos(angle) * 110.0, sin(angle) * half))

	points.append(Vector2(length - 40.0, half))
	_belted(points, _body_color, 26.0, true)


func _spoon_points() -> PackedVector2Array:
	var length := _hull_len
	var half := _loco_half
	var width := _prow_half
	var points := PackedVector2Array([Vector2(length - 40.0, -half), Vector2(length + 20.0, -width * 0.9)])

	for k in 25:
		var angle := lerpf(-PI / 2.0, PI / 2.0, k / 24.0)
		points.append(Vector2(length + 80.0 + cos(angle) * 460.0, sin(angle) * width))

	points.append(Vector2(length + 20.0, width * 0.9))
	points.append(Vector2(length - 40.0, half))
	return points


func _draw_spoon_bow() -> void:
	var length := _hull_len
	var width := _prow_half
	var points := _spoon_points()
	_belted(points, _body_color, 34.0, true)

	# Hazard band inside the belt, at the stem only
	var stem := Vector2(length + 540.0, 0)

	for k in 9:
		var angle := lerpf(-0.6, 0.6, k / 8.0)
		var at := Vector2(length + 80.0 + cos(angle) * 400.0, sin(angle) * width * 0.87)
		draw_circle(at, 9.0, STRIPE if k % 2 == 0 else STRIPE_DARK)

	# Ice knife: a heavy bar along the stem
	draw_line(stem + Vector2(-90, 0), stem + Vector2(10, 0), OUTLINE, 22.0)
	draw_line(stem + Vector2(-90, 0), stem + Vector2(8, 0), NOZZLE, 14.0)

	# Bow thruster tunnels and anchor pockets
	for side: float in [-1.0, 1.0]:
		for tunnel_x in [length + 200.0, length + 280.0]:
			var tunnel_y := side * sqrt(maxf(0.0, 1.0 - pow((tunnel_x - length - 80.0) / 460.0, 2.0))) * width
			var at := Vector2(tunnel_x, tunnel_y - side * 50.0)
			draw_circle(at, 22.0, OUTLINE)
			draw_circle(at, 18.0, DARK.darkened(0.3))
			draw_line(at - Vector2(16, 0), at + Vector2(16, 0), PIPE_DARK, 3.0)

		var anchor := Vector2(length + 400.0, side * width * 0.62)
		_draw_oval(anchor, Vector2(22, 14), OUTLINE)
		_draw_oval(anchor, Vector2(18, 10), DARK.darkened(0.3))

	# Bow chevrons on the foredeck
	for k in 2:
		var x := length + 140.0 + k * 90.0
		draw_line(Vector2(x, -90), Vector2(x + 54.0, 0), STRIPE, 14.0)
		draw_line(Vector2(x + 54.0, 0), Vector2(x, 90), STRIPE, 14.0)

	draw_circle(stem + Vector2(-40, 0), 8.0, Color.WHITE)


func _draw_thyssen_waas_bow() -> void:
	var length := _hull_len
	var half := _loco_half
	var width := _prow_half
	var face_x := length + 380.0
	var points := PackedVector2Array([
		Vector2(length - 40.0, -half), Vector2(length + 110.0, -width), Vector2(face_x + 90.0, -width + 6.0),
		Vector2(face_x, -width + 80.0), Vector2(face_x + 14.0, -width * 0.4), Vector2(face_x + 14.0, width * 0.4),
		Vector2(face_x, width - 80.0), Vector2(face_x + 90.0, width - 6.0), Vector2(length + 110.0, width), Vector2(length - 40.0, half),
	])
	_belted(points, _body_color, 30.0, true)

	# The flat face: heavy horizontal ribs that lift and break the rock
	var face := Rect2(face_x - 70.0, -width + 90.0, 80, (width - 90.0) * 2.0)
	draw_rect(face, DARK)
	var rib_y := face.position.y + 8.0

	while rib_y < face.end.y - 8.0:
		draw_rect(Rect2(face.position.x + 4.0, rib_y, face.size.x - 4.0, 12), NOZZLE.darkened(0.15))
		draw_rect(Rect2(face.position.x + 4.0, rib_y, face.size.x - 4.0, 3), NOZZLE)
		rib_y += 26.0

	# Reamer knives at the corners, polished edges
	for side: float in [-1.0, 1.0]:
		var knife := PackedVector2Array([Vector2(face_x - 40.0, side * (width - 2.0)), Vector2(face_x + 96.0, side * (width - 4.0)), Vector2(face_x - 10.0, side * (width - 90.0))])
		draw_colored_polygon(knife, NOZZLE)
		draw_line(knife[0], knife[1], Color.WHITE.darkened(0.1), 4.0)
		knife.append(knife[0])
		draw_polyline(knife, OUTLINE, TEXEL * 2.0)
		_stripes(Rect2(length + 140.0, side * (width - 40.0) - 7.0, 200, 14), 14.0)

	# Spray nozzles above the face, as on the real bow
	for k in 7:
		var y := lerpf(-width * 0.5, width * 0.5, k / 6.0)
		draw_circle(Vector2(face_x - 100.0, y), 8.0, OUTLINE)
		draw_circle(Vector2(face_x - 100.0, y), 5.0, PIPE)


func _draw_knife_bow() -> void:
	var length := _hull_len
	var half := _loco_half
	var width := _prow_half
	var points := PackedVector2Array([
		Vector2(length - 40.0, -half), Vector2(length + 80.0, -width), Vector2(length + 140.0, -width + 10.0),
		Vector2(length + 330.0, -width * 0.62), Vector2(length + 480.0, -70), Vector2(length + 500.0, 0),
		Vector2(length + 480.0, 70), Vector2(length + 330.0, width * 0.62), Vector2(length + 140.0, width - 10.0),
		Vector2(length + 80.0, width), Vector2(length - 40.0, half),
	])

	# Bubbler jets first, under the hull: gas puffs blowing out of the flanks
	for side: float in [-1.0, 1.0]:
		var from := Vector2(length + 160.0, side * (width - 14.0))
		var to := Vector2(length + 460.0, side * 90.0)
		var out := (to - from).orthogonal().normalized() * -side
		out = out if out.y * side > 0.0 else -out

		for k in 7:
			var at := from.lerp(to, (k + 0.5) / 7.0)

			for puff in 4:
				var reach := 26.0 + puff * 30.0 + _rng.randf_range(-6, 6)
				draw_circle(at + out * reach + Vector2(-puff * 12.0, 0), 10.0 + puff * 7.0, Color(GAS, 0.32 - puff * 0.07))

	_belted(points, _body_color, 30.0, true)

	# Nozzle row along each flank
	for side: float in [-1.0, 1.0]:
		var from := Vector2(length + 160.0, side * (width - 30.0))
		var to := Vector2(length + 455.0, side * 100.0)

		for k in 7:
			var at := from.lerp(to, (k + 0.5) / 7.0)
			draw_circle(at, 9.0, OUTLINE)
			draw_circle(at, 6.0, SKY.darkened(0.2))

		# Reamer shoulder
		var shoulder := PackedVector2Array([Vector2(length + 60.0, side * (width - 4.0)), Vector2(length + 170.0, side * (width + 18.0)), Vector2(length + 150.0, side * (width - 26.0))])
		draw_colored_polygon(shoulder, NOZZLE)
		shoulder.append(shoulder[0])
		draw_polyline(shoulder, OUTLINE, TEXEL * 2.0)

	# Ice knife: the ram stem
	var knife := PackedVector2Array([Vector2(length + 430.0, -26), Vector2(length + 650.0, 0), Vector2(length + 430.0, 26)])
	draw_colored_polygon(knife, NOZZLE)
	draw_line(knife[0], knife[1], Color.WHITE.darkened(0.1), 3.0)
	knife.append(knife[0])
	draw_polyline(knife, OUTLINE, TEXEL * 2.0)

	for k in 2:
		var x := length + 200.0 + k * 90.0
		draw_line(Vector2(x, -80), Vector2(x + 50.0, 0), STRIPE, 14.0)
		draw_line(Vector2(x + 50.0, 0), Vector2(x, 80), STRIPE, 14.0)


# --- Shapes


func _draw_oval(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()

	for k in 24:
		points.append(center + Vector2(cos(TAU * k / 24.0) * radii.x, sin(TAU * k / 24.0) * radii.y))

	draw_colored_polygon(points, color)


func _dashed_circle(center: Vector2, radius: float, color_a: Color, color_b: Color, segments: int) -> void:
	for k in segments:
		var from := TAU * k / segments
		draw_arc(center, radius, from, from + TAU / segments, 4, color_a if k % 2 == 0 else color_b, 8.0)
