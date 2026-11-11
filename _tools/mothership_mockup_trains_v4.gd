extends "res://_tools/mothership_mockup_trains_v3.gd"

# Round 5: four locomotives, all with D1's lashed flatbeds and the deflector. Mockup only.
# - F1 catamaran: two slender hulls joined by crossbeams, a crew capsule slung between them
# - F2 reactor spine: a truss spine, a reactor sphere with huge radiator wings, a cab pod up front
# - F3 road locomotive: a long diesel-electric style hood unit, fans and stacks on the roof
# - F4 heavy tug: an armoured block, strapped-on tanks, four engine pods, a cab out on an arm


func _ready() -> void:
	super()
	_tug_front = _hull_len + 110.0
	_loco_name = { "F1": "HAULER 7", "F2": "HAULER 7", "F3": "07", "F4": "HAULER 7" }.get(concept, "HAULER 7")


func _draw() -> void:
	_rng.seed = 11
	_draw_lashed_flatbeds()

	match concept:
		"F1":
			_draw_catamaran()
		"F2":
			_draw_reactor_spine()
		"F3":
			_draw_road_loco()
		"F4":
			_draw_heavy_tug()

	_draw_deflector()


func _shadow(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(12, 14), rect.size), SHADOW)


func _strut(from: Vector2, to: Vector2, width: float, color: Color) -> void:
	draw_line(from, to, OUTLINE, width + 4.0)
	draw_line(from, to, color, width)


# A capsule along x: round ends, outline, light top edge.
func _capsule(rect: Rect2, color: Color) -> void:
	var radius := rect.size.y / 2.0
	var y := rect.get_center().y
	var left := Vector2(rect.position.x + radius, y)
	var right := Vector2(rect.end.x - radius, y)
	draw_circle(left, radius + TEXEL, OUTLINE)
	draw_circle(right, radius + TEXEL, OUTLINE)
	draw_rect(Rect2(left.x, rect.position.y - TEXEL, right.x - left.x, rect.size.y + TEXEL * 2.0), OUTLINE)
	draw_circle(left, radius, color)
	draw_circle(right, radius, color)
	draw_rect(Rect2(left.x, rect.position.y, right.x - left.x, rect.size.y), color)
	draw_rect(Rect2(left.x, rect.position.y + radius * 0.25, right.x - left.x, TEXEL * 2.0), color.lightened(0.25))
	draw_rect(Rect2(left.x, rect.end.y - radius * 0.3, right.x - left.x, TEXEL * 2.0), color.darkened(0.25))


func _fan(center: Vector2, radius: float) -> void:
	draw_circle(center, radius + TEXEL, OUTLINE)
	draw_circle(center, radius, DARK)

	for k in 6:
		var direction := Vector2.from_angle(TAU * k / 6.0 + 0.3)
		draw_line(center + direction * 6.0, center + direction * (radius - 3.0), PIPE_DARK, 6.0)

	draw_circle(center, 7.0, PIPE)


# --- F1: catamaran


func _draw_catamaran() -> void:
	var length := _hull_len
	var hull_y := 250.0

	for side: float in [-1.0, 1.0]:
		var y := side * hull_y
		_draw_plume(Vector2(-60, y), 50.0, 320.0)
		_draw_bell(Vector2(40, y), Vector2(-60, y), 40.0, 54.0)

	# Crossbeams, under the hulls and the capsule
	for beam_x in [150.0, 480.0, 820.0]:
		var beam := Rect2(beam_x - 22.0, -hull_y, 44, hull_y * 2.0)
		_shadow(beam)
		_smooth_plate(beam, DARK)

		for k in 8:
			var y := lerpf(-hull_y + 20.0, hull_y - 40.0, k / 7.0)
			draw_line(Vector2(beam_x - 18.0, y), Vector2(beam_x + 18.0, y + 20.0), PIPE_DARK, 3.0)

	# Hulls: long capsules with an ice belt and a hazard bow
	for side: float in [-1.0, 1.0]:
		var hull := Rect2(30, side * hull_y - 74.0, length - 40.0, 148)
		draw_rect(Rect2(hull.position + Vector2(10, 12), hull.size), SHADOW)
		_capsule(hull, DARK)
		_capsule(hull.grow(-14.0), _body_color)
		_rivet_row(Vector2(hull.position.x + 60.0, side * hull_y - 50.0), Vector2(hull.end.x - 80.0, side * hull_y - 50.0), _body_color)

		for k in 6:
			var stripe_x := hull.end.x - 150.0 + k * 18.0
			draw_rect(Rect2(stripe_x, side * hull_y - 40.0, 10, 80), STRIPE_DARK if k % 2 == 0 else STRIPE)

		for k in 4:
			_fan(Vector2(200.0 + k * 90.0, side * hull_y), 26.0)

		draw_circle(Vector2(hull.end.x - 30.0, side * hull_y), 9.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)

	# Crew capsule slung between the hulls
	var pod := Rect2(330, -112, 520, 224)
	draw_rect(Rect2(pod.position + Vector2(14, 16), pod.size), SHADOW)
	_capsule(pod, SUPER)

	for side: float in [-1.0, 1.0]:
		for k in 9:
			draw_rect(Rect2(pod.position.x + 110.0 + k * 34.0, side * 88.0 - 5.0, 18, 10), GLASS_DARK)

	_capsule(Rect2(400, -48, 300, 96), SUPER_SHADE)
	draw_circle(Vector2(500, 0), 30.0, OUTLINE)
	draw_circle(Vector2(500, 0), 26.0, SKY.darkened(0.3))
	draw_circle(Vector2(500, 0), 13.0, SKY)

	# Glazed nose of the capsule
	var nose := Vector2(pod.end.x - 112.0, 0)
	draw_arc(nose, 98.0, -PI * 0.4, PI * 0.4, 16, GLASS_DARK, 16.0)
	draw_arc(nose, 104.0, -PI * 0.35, PI * 0.35, 16, GLASS, 3.0)
	_stencil(Vector2(380, 150), _loco_name, 34)


# --- F2: reactor spine


func _draw_reactor_spine() -> void:
	var length := _hull_len
	var reactor := Vector2(330, 0)

	# Engine cluster on outriggers at the back
	for side: float in [-1.0, 1.0]:
		var y := side * 280.0
		_strut(Vector2(60, side * 30.0), Vector2(120, y), 14.0, DARK)
		_strut(Vector2(200, side * 30.0), Vector2(160, y), 14.0, DARK)
		_draw_plume(Vector2(-20, y), 48.0, 320.0)
		_capsule(Rect2(40, y - 50.0, 220, 100), DARK.lightened(0.05))
		_draw_bell(Vector2(60, y), Vector2(-20, y), 38.0, 50.0)
		draw_rect(Rect2(110, y - 4.0, 120, 8), STRIPE)

	# Radiator wings: wide, thin, ribbed panels
	for side: float in [-1.0, 1.0]:
		var wing := PackedVector2Array([
			Vector2(reactor.x - 70.0, side * 110.0), Vector2(reactor.x - 120.0, side * 460.0),
			Vector2(reactor.x + 120.0, side * 460.0), Vector2(reactor.x + 70.0, side * 110.0),
		])
		draw_colored_polygon(PackedVector2Array(Array(wing).map(func(p: Vector2) -> Vector2: return p + Vector2(12, 14))), SHADOW)
		draw_colored_polygon(wing, DARK)
		var rib_y := 130.0

		while rib_y < 450.0:
			var t := (rib_y - 110.0) / 350.0
			var half_width := lerpf(70.0, 120.0, t) - 8.0
			draw_rect(Rect2(reactor.x - half_width, side * rib_y - 3.0, half_width * 2.0, 6), FIN)
			rib_y += 16.0

		_strut(Vector2(reactor.x, side * 110.0), Vector2(reactor.x, side * 460.0), 8.0, _body_color)
		var outline := wing.duplicate()
		outline.append(wing[0])
		draw_polyline(outline, OUTLINE, TEXEL * 2.0)

	# Truss spine end to end
	var spine := Rect2(0, -34, length - 120.0, 68)
	_shadow(spine)
	draw_rect(spine, OUTLINE)
	draw_rect(Rect2(spine.position.x, -30, spine.size.x, 10), _body_color)
	draw_rect(Rect2(spine.position.x, 20, spine.size.x, 10), _body_color)
	var x := 4.0

	while x < spine.end.x - 30.0:
		draw_line(Vector2(x, -20), Vector2(x + 28.0, 20), PIPE, 5.0)
		draw_line(Vector2(x + 28.0, 20), Vector2(x + 56.0, -20), PIPE, 5.0)
		x += 56.0

	# Reactor sphere
	draw_circle(reactor + Vector2(14, 16), 132.0, SHADOW)
	draw_circle(reactor, 134.0, OUTLINE)
	draw_circle(reactor, 130.0, SUPER_SHADE)
	draw_circle(reactor + Vector2(-16, -16), 104.0, SUPER)
	draw_arc(reactor, 118.0, 0.0, TAU, 48, STRIPE, 12.0)

	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		draw_rect(Rect2(reactor + direction * 118.0 - Vector2(6, 6), Vector2(12, 12)), OUTLINE)

	draw_circle(reactor, 44.0, OUTLINE)
	draw_circle(reactor, 38.0, SKY.darkened(0.35))
	draw_circle(reactor, 20.0, SKY)

	# Tank cluster around the spine
	for tank_y in [-150.0, -80.0, 80.0, 150.0]:
		_draw_tank(Rect2(520, tank_y - 26.0, 200, 52), _body_color)

	for strap_x in [560.0, 680.0]:
		draw_rect(Rect2(strap_x, -180, 10, 360), DARK)

	# Cab pod at the front of the spine
	var cab_center := Vector2(length - 60.0, 0)
	var cab := _octagon(cab_center, 130.0)
	draw_colored_polygon(PackedVector2Array(Array(cab).map(func(p: Vector2) -> Vector2: return p + Vector2(12, 14))), SHADOW)
	_polygon_plate(cab, _body_color)
	_polygon_plate(_octagon(cab_center, 84.0), SUPER)
	draw_arc(cab_center, 100.0, -PI * 0.3, PI * 0.3, 12, GLASS_DARK, 18.0)
	draw_arc(cab_center, 106.0, -PI * 0.25, PI * 0.25, 12, GLASS, 3.0)
	draw_circle(cab_center, 22.0, NOZZLE)
	_stencil(Vector2(length - 160.0, 170), _loco_name, 30)


# --- F3: road locomotive


func _draw_road_loco() -> void:
	var length := _hull_len
	var half := 175.0

	# Drive pods low on the flanks
	for side: float in [-1.0, 1.0]:
		var y := side * 270.0
		_strut(Vector2(140, side * half), Vector2(140, y), 26.0, DARK)
		_strut(Vector2(340, side * half), Vector2(340, y), 26.0, DARK)
		_draw_plume(Vector2(-30, y), 42.0, 300.0)
		_capsule(Rect2(40, y - 44.0, 380, 88), DARK.lightened(0.05))
		_draw_bell(Vector2(60, y), Vector2(-30, y), 32.0, 42.0)

	# Body: chamfered box, dark walkway border, yellow hood
	var body := PackedVector2Array([
		Vector2(0, -half + 40.0), Vector2(40, -half), Vector2(length - 120.0, -half), Vector2(length, -half + 70.0),
		Vector2(length, half - 70.0), Vector2(length - 120.0, half), Vector2(40, half), Vector2(0, half - 40.0),
	])
	draw_colored_polygon(PackedVector2Array(Array(body).map(func(p: Vector2) -> Vector2: return p + Vector2(10, 12))), SHADOW)
	_belted(body, DARK.lightened(0.08), 4.0, false)

	# Handrails along the walkway
	for side: float in [-1.0, 1.0]:
		var x := 50.0

		while x < length - 130.0:
			draw_rect(Rect2(x, side * (half - 10.0) - 1.0, 8, TEXEL), PIPE)
			x += 16.0

	# Long hood
	var hood := Rect2(30, -half + 26.0, length - 280.0, (half - 26.0) * 2.0)
	_shadow(hood)
	_smooth_plate(hood, _body_color)

	# Livery: black chevrons running back from the cab, red base stripe
	for side: float in [-1.0, 1.0]:
		for k in 5:
			var x := hood.end.x - 60.0 - k * 46.0
			var stripe := PackedVector2Array([
				Vector2(x, side * (half - 30.0)), Vector2(x + 22.0, side * (half - 30.0)),
				Vector2(x + 64.0, side * (half - 100.0)), Vector2(x + 42.0, side * (half - 100.0)),
			])
			draw_colored_polygon(stripe, STRIPE_DARK)

	draw_rect(Rect2(hood.position.x + 6.0, -6, hood.size.x - 12.0, 12), LIGHT_RED.darkened(0.35))

	# Roof gear: radiator fans, exhaust stacks, a brake grid, a horn
	for k in 4:
		_fan(Vector2(120.0 + k * 100.0, -70), 36.0)
		_fan(Vector2(120.0 + k * 100.0, 70), 36.0)

	for k in 2:
		var stack := Vector2(560.0 + k * 70.0, 0)
		_draw_oval(stack + Vector2(6, 8), Vector2(24, 38), SHADOW)
		_draw_oval(stack, Vector2(24, 38), OUTLINE)
		_draw_oval(stack, Vector2(20, 34), DARK)
		_draw_oval(stack, Vector2(12, 24), STRIPE_DARK)

	var grid := Rect2(660, -110, 60, 220)
	draw_rect(grid, OUTLINE)
	var grid_x := grid.position.x + 4.0

	while grid_x < grid.end.x - 4.0:
		draw_rect(Rect2(grid_x, grid.position.y + 4.0, 4, grid.size.y - 8.0), PIPE_DARK)
		grid_x += 8.0

	_stencil(Vector2(260, -112), "BELT FREIGHT", 34)

	# Cab at the front: raised, wide windscreen, number boards, headlights
	var cab := Rect2(length - 250.0, -half + 20.0, 200, (half - 20.0) * 2.0)
	_shadow(cab)
	_smooth_plate(cab, _body_color)
	var screen := Rect2(cab.end.x - 30.0, cab.position.y + 30.0, 18, cab.size.y - 60.0)
	draw_rect(screen.grow(TEXEL), OUTLINE)
	draw_rect(screen, GLASS_DARK)
	draw_rect(Rect2(screen.position, Vector2(TEXEL * 2.0, screen.size.y)), GLASS)
	draw_rect(Rect2(screen.position.x + 6.0, -4, 6, 8), OUTLINE)

	for side: float in [-1.0, 1.0]:
		draw_rect(Rect2(cab.position.x + 30.0, side * (cab.size.y / 2.0 - 16.0) - 6.0, 110, 12), GLASS_DARK)
		draw_circle(Vector2(length - 20.0, side * 70.0), 12.0, OUTLINE)
		draw_circle(Vector2(length - 20.0, side * 70.0), 9.0, Color(1.0, 0.95, 0.75))

	_stencil(Vector2(cab.position.x + 50.0, 18), _loco_name, 64)


# --- F4: heavy tug


func _draw_heavy_tug() -> void:
	var length := _hull_len
	var half := 170.0

	# Four engine pods: two big ones aft, two smaller ones forward
	for side: float in [-1.0, 1.0]:
		var aft_y := side * 270.0
		_strut(Vector2(120, side * half), Vector2(160, aft_y), 30.0, DARK)
		_draw_plume(Vector2(-60, aft_y), 54.0, 340.0)
		_capsule(Rect2(0, aft_y - 58.0, 300, 116), GRAY)
		_draw_bell(Vector2(30, aft_y), Vector2(-60, aft_y), 44.0, 58.0)
		_stripes(Rect2(200, aft_y - 58.0, 20, 116), 14.0)

		var fore_y := side * 250.0
		_strut(Vector2(length - 300.0, side * half), Vector2(length - 300.0, fore_y), 22.0, DARK)
		_draw_plume(Vector2(length - 450.0, fore_y), 30.0, 140.0)
		_capsule(Rect2(length - 420.0, fore_y - 36.0, 190, 72), GRAY)
		_draw_bell(Vector2(length - 400.0, fore_y), Vector2(length - 450.0, fore_y), 26.0, 34.0)

	# Armoured block
	var block := Rect2(60, -half, length - 140.0, half * 2.0)
	_shadow(block)
	_smooth_plate(block, GRAY)

	for k in 6:
		var x := block.position.x + 40.0 + k * 140.0
		draw_rect(Rect2(x, -half + 6.0, TEXEL, half * 2.0 - 12.0), GRAY.darkened(0.25))

	_stripes(Rect2(block.position.x, -half, block.size.x, 12), 20.0)
	_stripes(Rect2(block.position.x, half - 12.0, block.size.x, 12), 20.0)

	# Tanks strapped across the top
	for tank_y in [-110.0, -38.0, 34.0, 106.0]:
		_draw_tank(Rect2(180, tank_y - 30.0, 360, 60), _body_color)

	for strap_x in [230.0, 360.0, 490.0]:
		draw_rect(Rect2(strap_x, -150, 12, 300), OUTLINE)
		draw_rect(Rect2(strap_x + 2.0, -148, 8, 296), STRAP)

	# Machinery deck: vents, a winch drum
	for k in 3:
		var vent := Rect2(620 + k * 60.0, -120, 40, 80)
		_stripes(vent, 10.0)
		draw_rect(vent.grow(-5), DARK.darkened(0.3))

	var drum := Rect2(620, 30, 170, 90)
	_shadow(drum)
	_smooth_plate(drum, DARK)

	for k in 10:
		draw_rect(Rect2(drum.position.x + 10.0 + k * 15.0, drum.position.y + 8.0, 8, drum.size.y - 16.0), PIPE if k % 2 == 0 else PIPE_DARK)

	# Front bumper the deflector struts bolt to
	var bumper := Rect2(length - 90.0, -half - 20.0, 80, (half + 20.0) * 2.0)
	_shadow(bumper)
	_smooth_plate(bumper, DARK)
	_stripes(Rect2(bumper.end.x - 18.0, bumper.position.y, 14, bumper.size.y), 16.0)

	# Cab out on an arm, port side, for a view down the train
	var arm_from := Vector2(length - 220.0, -half)
	var cab_center := Vector2(length - 180.0, -330.0)
	_strut(arm_from, cab_center, 30.0, DARK)
	_strut(arm_from + Vector2(60, 0), cab_center + Vector2(20, 20), 14.0, PIPE_DARK)
	var cab := _octagon(cab_center, 80.0)
	draw_colored_polygon(PackedVector2Array(Array(cab).map(func(p: Vector2) -> Vector2: return p + Vector2(12, 14))), SHADOW)
	_polygon_plate(cab, _body_color)
	draw_arc(cab_center, 60.0, -PI * 0.6, PI * 0.4, 14, GLASS_DARK, 16.0)
	draw_arc(cab_center, 66.0, -PI * 0.5, PI * 0.3, 14, GLASS, 3.0)
	draw_circle(cab_center, 20.0, SUPER)
	_stencil(Vector2(100, half - 30.0), _loco_name, 34)
