extends "res://_tools/mothership_mockup_trains_v4.gd"

# Round 6: four takes on F2 (reactor spine). Every one has a tow yoke at the back and a deflector
# yoke at the front, so it reads as pulling the train and carrying the deflector. Mockup only.
# - G1 swept: F2 refined, radiator wings swept back like fins, tapered cab
# - G2 tandem: two smaller reactors, three pairs of radiator paddles along the spine
# - G3 ring: a reactor behind a shadow shield at the back, a habitat ring around the spine
# - G4 heavy: a boxed truss in yellow plates, the reactor in a cage, an engine cluster on a thrust frame


func _draw() -> void:
	_rng.seed = 11
	_draw_lashed_flatbeds()

	match concept:
		"G1":
			_draw_g1()
		"G2":
			_draw_g2()
		"G3":
			_draw_g3()
		"G4":
			_draw_g4()

	_draw_deflector()


# --- Shared parts


func _shadow_poly(points: PackedVector2Array) -> void:
	var moved := PackedVector2Array()

	for point in points:
		moved.append(point + Vector2(12, 14))

	draw_colored_polygon(moved, SHADOW)


# A radiator wing: dark frame, fins across, a yellow spar along it. Sweep > 0 pushes the tip back.
func _radiator_wing(root_x: float, root_y: float, tip_y: float, root_half: float, tip_half: float, sweep: float, side: float) -> void:
	var points := PackedVector2Array([
		Vector2(root_x - root_half, side * root_y), Vector2(root_x - sweep - tip_half, side * tip_y),
		Vector2(root_x - sweep + tip_half, side * tip_y), Vector2(root_x + root_half, side * root_y),
	])
	_shadow_poly(points)
	draw_colored_polygon(points, DARK)
	var y := root_y + 14.0

	while y < tip_y - 8.0:
		var t := (y - root_y) / (tip_y - root_y)
		var center := root_x - sweep * t
		var half_width := lerpf(root_half, tip_half, t) - 8.0
		draw_rect(Rect2(center - half_width, side * y - 3.0, half_width * 2.0, 6), FIN)
		y += 16.0

	_strut(Vector2(root_x, side * root_y), Vector2(root_x - sweep, side * tip_y), 8.0, _body_color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE, TEXEL * 2.0)
	draw_circle(Vector2(root_x - sweep, side * (tip_y - 4.0)), 7.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)


func _truss(from_x: float, to_x: float, half: float, chord: Color) -> void:
	var spine := Rect2(from_x, -half, to_x - from_x, half * 2.0)
	_shadow(spine)
	draw_rect(spine, OUTLINE)
	draw_rect(Rect2(from_x, -half + 4.0, spine.size.x, 10), chord)
	draw_rect(Rect2(from_x, half - 14.0, spine.size.x, 10), chord)
	var bay := half * 1.6
	var x := from_x + 4.0

	while x < to_x - bay:
		draw_line(Vector2(x, -half + 14.0), Vector2(x + bay / 2.0, half - 14.0), PIPE, 5.0)
		draw_line(Vector2(x + bay / 2.0, half - 14.0), Vector2(x + bay, -half + 14.0), PIPE, 5.0)
		x += bay


func _reactor(center: Vector2, radius: float) -> void:
	draw_circle(center + Vector2(14, 16), radius - 2.0, SHADOW)
	draw_circle(center, radius + 4.0, OUTLINE)
	draw_circle(center, radius, SUPER_SHADE)
	draw_circle(center + Vector2(-radius * 0.12, -radius * 0.12), radius * 0.8, SUPER)
	draw_arc(center, radius * 0.9, 0.0, TAU, 48, STRIPE, radius * 0.09)

	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		draw_rect(Rect2(center + direction * radius * 0.9 - Vector2(5, 5), Vector2(10, 10)), OUTLINE)

	draw_circle(center, radius * 0.34, OUTLINE)
	draw_circle(center, radius * 0.29, SKY.darkened(0.35))
	draw_circle(center, radius * 0.15, SKY)


# Coupling at the back: a heavy yoke, a hinge pin, the drawbar of the first flatcar goes into it.
func _tow_yoke(back_x: float) -> void:
	var yoke := PackedVector2Array([
		Vector2(back_x + 70.0, -70), Vector2(back_x, -40), Vector2(back_x - 20.0, -20),
		Vector2(back_x - 20.0, 20), Vector2(back_x, 40), Vector2(back_x + 70.0, 70),
	])
	_shadow_poly(yoke)
	_polygon_plate(yoke, DARK)
	draw_circle(Vector2(back_x - 4.0, 0), 16.0, OUTLINE)
	draw_circle(Vector2(back_x - 4.0, 0), 12.0, NOZZLE)
	_stripes(Rect2(back_x + 30.0, -60, 12, 120), 12.0)


# Crossbar at the front that the deflector struts bolt to, held by two braces from the cab.
func _deflector_yoke(from_x: float) -> void:
	var bar_x := _hull_len + 70.0
	var bar := Rect2(bar_x, -150, 40, 300)

	for side: float in [-1.0, 1.0]:
		_strut(Vector2(from_x, side * 40.0), Vector2(bar_x + 20.0, side * 120.0), 14.0, DARK)

	_shadow(bar)
	_smooth_plate(bar, DARK)
	_stripes(Rect2(bar.end.x - 12.0, bar.position.y, 10, bar.size.y), 14.0)


func _outrigger_engine(at: Vector2, length: float, girth: float, spine_y: float) -> void:
	var side := signf(at.y)
	_strut(Vector2(at.x + 40.0, side * spine_y), Vector2(at.x + 80.0, at.y), 14.0, DARK)
	_strut(Vector2(at.x + 160.0, side * spine_y), Vector2(at.x + 120.0, at.y), 14.0, DARK)
	_draw_plume(Vector2(at.x - 80.0, at.y), girth * 0.95, 320.0)
	_capsule(Rect2(at.x - 60.0, at.y - girth, length, girth * 2.0), DARK.lightened(0.05))
	_draw_bell(Vector2(at.x - 40.0, at.y), Vector2(at.x - 80.0 - 20.0, at.y), girth * 0.76, girth)
	draw_rect(Rect2(at.x + 10.0, at.y - 4.0, length - 120.0, 8), STRIPE)


func _cab_glass_arc(center: Vector2, radius: float, spread: float) -> void:
	draw_arc(center, radius, -spread, spread, 14, GLASS_DARK, 18.0)
	draw_arc(center, radius + 6.0, -spread * 0.85, spread * 0.85, 14, GLASS, 3.0)


# --- G1: swept


func _draw_g1() -> void:
	var length := _hull_len
	var reactor := Vector2(300, 0)

	_tow_yoke(0.0)

	for side: float in [-1.0, 1.0]:
		_outrigger_engine(Vector2(60, side * 250.0), 240.0, 48.0, 34.0)

	for side: float in [-1.0, 1.0]:
		_radiator_wing(reactor.x + 40.0, 110.0, 470.0, 80.0, 50.0, 150.0, side)

	_truss(40.0, length - 160.0, 36.0, _body_color)
	_reactor(reactor, 130.0)

	# Tanks in two strapped rows
	for tank_y in [-120.0, -62.0, 62.0, 120.0]:
		_draw_tank(Rect2(500, tank_y - 24.0, 190, 48), _body_color)

	for strap_x in [540.0, 650.0]:
		draw_rect(Rect2(strap_x, -148, 10, 296), OUTLINE)
		draw_rect(Rect2(strap_x + 2.0, -146, 6, 292), STRAP)

	_deflector_yoke(length - 80.0)

	# Tapered cab: a long octagonal pod, glazed nose
	var cab := PackedVector2Array([
		Vector2(length - 300.0, -70), Vector2(length - 240.0, -110), Vector2(length - 60.0, -100),
		Vector2(length + 10.0, -50), Vector2(length + 10.0, 50), Vector2(length - 60.0, 100),
		Vector2(length - 240.0, 110), Vector2(length - 300.0, 70),
	])
	_shadow_poly(cab)
	_polygon_plate(cab, _body_color)
	_polygon_plate(PackedVector2Array([Vector2(length - 240.0, -60), Vector2(length - 100.0, -60), Vector2(length - 100.0, 60), Vector2(length - 240.0, 60)]), SUPER)
	_cab_glass_arc(Vector2(length - 90.0, 0), 80.0, PI * 0.32)

	for k in 4:
		draw_rect(Rect2(length - 230.0 + k * 34.0, -94, 18, 8), GLASS_DARK)
		draw_rect(Rect2(length - 230.0 + k * 34.0, 86, 18, 8), GLASS_DARK)

	_stencil(Vector2(length - 280.0, 160), _loco_name, 30)


# --- G2: tandem


func _draw_g2() -> void:
	var length := _hull_len

	_tow_yoke(0.0)

	for side: float in [-1.0, 1.0]:
		_outrigger_engine(Vector2(60, side * 230.0), 220.0, 42.0, 30.0)

	# Three pairs of rectangular paddles between and around the reactors
	for paddle_x in [110.0, 370.0, 630.0]:
		for side: float in [-1.0, 1.0]:
			var paddle := Rect2(paddle_x, side * 330.0 - (260.0 if side < 0.0 else -70.0) - (0.0 if side < 0.0 else 330.0), 110, 260)
			paddle = Rect2(paddle_x, -330.0 if side < 0.0 else 70.0, 110, 260)
			_shadow(paddle)
			draw_rect(paddle, OUTLINE)
			draw_rect(paddle.grow(-4), DARK)
			var y := paddle.position.y + 10.0

			while y < paddle.end.y - 10.0:
				draw_rect(Rect2(paddle.position.x + 8.0, y, paddle.size.x - 16.0, 6), FIN)
				y += 14.0

			draw_rect(Rect2(paddle.get_center().x - 4.0, paddle.position.y, 8, paddle.size.y), _body_color)

	_truss(40.0, length - 140.0, 30.0, _body_color)
	_reactor(Vector2(260, 0), 90.0)
	_reactor(Vector2(520, 0), 90.0)

	# Coolant loop between the two
	for side: float in [-1.0, 1.0]:
		draw_line(Vector2(260, side * 60.0), Vector2(520, side * 60.0), OUTLINE, 10.0)
		draw_line(Vector2(260, side * 60.0), Vector2(520, side * 60.0), SKY.darkened(0.2), 5.0)

	_deflector_yoke(length - 60.0)

	# Command module: hexagon, dish on a mast
	var cab_center := Vector2(length - 110.0, 0)
	var hexagon := PackedVector2Array()

	for k in 6:
		hexagon.append(cab_center + Vector2.from_angle(TAU * k / 6.0) * 120.0)

	_shadow_poly(hexagon)
	_polygon_plate(hexagon, _body_color)
	_polygon_plate(_octagon(cab_center, 70.0), SUPER)
	_cab_glass_arc(cab_center, 92.0, PI * 0.25)
	var dish := cab_center + Vector2(-60, -150)
	_strut(cab_center + Vector2(-60, -80), dish, 6.0, PIPE_DARK)
	draw_circle(dish, 34.0, OUTLINE)
	draw_circle(dish, 30.0, SUPER)
	draw_circle(dish, 8.0, PIPE_DARK)
	_stencil(Vector2(length - 220.0, 170), _loco_name, 30)


# --- G3: ring


func _draw_g3() -> void:
	var length := _hull_len
	var ring_center := Vector2(560, 0)

	_tow_yoke(0.0)

	# Reactor at the very back, radiators angled behind it
	for side: float in [-1.0, 1.0]:
		_radiator_wing(170.0, 90.0, 400.0, 60.0, 40.0, 120.0, side)
		_outrigger_engine(Vector2(40, side * 200.0), 180.0, 40.0, 30.0)

	_truss(40.0, length - 140.0, 30.0, _body_color)
	_reactor(Vector2(150, 0), 100.0)

	# Shadow shield between the reactor and the crew
	var shield := PackedVector2Array([Vector2(270, -170), Vector2(310, -190), Vector2(310, 190), Vector2(270, 170)])
	_shadow_poly(shield)
	_polygon_plate(shield, DARK)
	_stripes(Rect2(300, -180, 8, 360), 14.0)

	# Habitat ring on four spokes
	for k in 4:
		var direction := Vector2.from_angle(TAU * k / 4.0 + PI / 4.0)
		_strut(ring_center + direction * 40.0, ring_center + direction * 250.0, 12.0, DARK)

	draw_arc(ring_center + Vector2(14, 16), 270.0, 0.0, TAU, 72, SHADOW, 48.0)
	draw_arc(ring_center, 270.0, 0.0, TAU, 72, OUTLINE, 54.0)
	draw_arc(ring_center, 270.0, 0.0, TAU, 72, SUPER, 46.0)
	draw_arc(ring_center, 258.0, 0.0, TAU, 72, SUPER_SHADE, 6.0)

	for k in 36:
		var angle := TAU * k / 36.0
		var at := ring_center + Vector2.from_angle(angle) * 286.0
		draw_rect(Rect2(at - Vector2(5, 3), Vector2(10, 6)), GLASS_DARK if k % 3 != 0 else LIGHT_RED.darkened(0.2))

	for k in 4:
		var at := ring_center + Vector2.from_angle(TAU * k / 4.0) * 270.0
		draw_rect(Rect2(at - Vector2(16, 16), Vector2(32, 32)), OUTLINE)
		draw_rect(Rect2(at - Vector2(12, 12), Vector2(24, 24)), _body_color)

	draw_circle(ring_center, 52.0, OUTLINE)
	draw_circle(ring_center, 46.0, _body_color)
	draw_circle(ring_center, 22.0, DARK)

	_deflector_yoke(length - 60.0)

	# Small cab
	var cab_center := Vector2(length - 90.0, 0)
	_polygon_plate(_octagon(cab_center, 96.0), _body_color)
	_polygon_plate(_octagon(cab_center, 56.0), SUPER)
	_cab_glass_arc(cab_center, 72.0, PI * 0.3)
	_stencil(Vector2(length - 180.0, 140), _loco_name, 30)


# --- G4: heavy


func _draw_g4() -> void:
	var length := _hull_len
	var reactor := Vector2(340, 0)

	_tow_yoke(0.0)

	# Thrust frame with four engines
	var frame := Rect2(20, -260, 70, 520)
	_shadow(frame)
	_smooth_plate(frame, DARK)

	for engine_y in [-200.0, -70.0, 70.0, 200.0]:
		_draw_plume(Vector2(-90, engine_y), 44.0, 300.0)
		_draw_bell(Vector2(20, engine_y), Vector2(-90, engine_y), 34.0, 46.0)

	# Three pairs of short paddles, hinged
	for paddle_x in [170.0, 470.0, 640.0]:
		for side: float in [-1.0, 1.0]:
			_radiator_wing(paddle_x, 80.0, 330.0, 46.0, 46.0, 30.0, side)

	# Boxed truss: plated, with lightening holes
	var box := Rect2(60, -70, length - 230.0, 140)
	_shadow(box)
	_smooth_plate(box, _body_color)
	var x := 110.0

	while x < box.end.x - 60.0:
		draw_circle(Vector2(x, 0), 24.0, OUTLINE)
		draw_circle(Vector2(x, 0), 20.0, DARK.darkened(0.3))
		x += 90.0

	_stripes(Rect2(box.position.x, -70, box.size.x, 8), 20.0)
	_stripes(Rect2(box.position.x, 62, box.size.x, 8), 20.0)

	# Reactor in a cage
	_reactor(reactor, 120.0)

	for k in 6:
		var angle := TAU * k / 6.0
		_strut(reactor + Vector2.from_angle(angle) * 70.0, reactor + Vector2.from_angle(angle + PI * 0.4) * 140.0, 6.0, PIPE_DARK)

	draw_arc(reactor, 140.0, 0.0, TAU, 48, OUTLINE, 10.0)
	draw_arc(reactor, 140.0, 0.0, TAU, 48, PIPE_DARK, 6.0)

	_deflector_yoke(length - 100.0)

	# Chunky cab with wraparound glass
	var cab := Rect2(length - 230.0, -130, 220, 260)
	_shadow(cab)
	_smooth_plate(cab, _body_color)
	_smooth_plate(Rect2(cab.position + Vector2(20, 30), Vector2(110, 200)), SUPER)
	var glass := PackedVector2Array([Vector2(cab.end.x - 50.0, -110), Vector2(cab.end.x - 6.0, -70), Vector2(cab.end.x - 6.0, 70), Vector2(cab.end.x - 50.0, 110)])
	draw_polyline(glass, OUTLINE, 22.0)
	draw_polyline(glass, GLASS_DARK, 16.0)
	draw_polyline(glass, GLASS, 3.0)
	_stencil(Vector2(120, 112), _loco_name, 30)
