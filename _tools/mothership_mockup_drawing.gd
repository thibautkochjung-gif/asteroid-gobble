extends Node2D

# One mothership concept, drawn once in ShipHull's pixel language. Mockup only.
# Local space: +x = bow. 1 px = 1 m, like the rest of the game.

const TEXEL: float = 2.0
const OUTLINE := Color(0.06, 0.055, 0.07)
const DARK := Color(0.21, 0.2, 0.22)
const GRAY := Color(0.31, 0.3, 0.31)
const RUST := Color(0.46, 0.24, 0.15)
const BARE := Color(0.48, 0.47, 0.45)
const CABIN := Color(0.33, 0.35, 0.24)
const GLASS := Color(0.38, 0.69, 0.77)
const GLASS_DARK := Color(0.2, 0.39, 0.47)
const PRIMER := Color(0.67, 0.36, 0.18)
const STRIPE := Color(0.83, 0.64, 0.16)
const STRIPE_DARK := Color(0.12, 0.11, 0.11)
const PIPE := Color(0.54, 0.5, 0.45)
const PIPE_DARK := Color(0.36, 0.34, 0.31)
const ENGINE := Color(0.26, 0.27, 0.31)
const ENGINE_INSIDE := Color(0.09, 0.09, 0.13)
const NOZZLE := Color(0.59, 0.59, 0.63)
const TEAL_GRAY := Color(0.24, 0.32, 0.32)
const GRIME: Array[Color] = [Color(0.19, 0.18, 0.18), Color(0.38, 0.24, 0.16), Color(0.25, 0.24, 0.23)]
const LIGHT_GREEN := Color(0.4, 0.95, 0.35)
const LIGHT_RED := Color(0.85, 0.22, 0.14)
const FLAME := Color(1.0, 0.6, 0.25, 0.8)
const FLAME_CORE := Color(1.0, 0.92, 0.7)
const FLEET_PAINTS: Array[Color] = [Color(0.22, 0.38, 0.38), Color(0.28, 0.33, 0.42), Color(0.36, 0.37, 0.22), Color(0.46, 0.24, 0.15), Color(0.31, 0.3, 0.31), Color(0.55, 0.42, 0.18)]

var concept: String = "A"

var _rng := RandomNumberGenerator.new()
var _bays: Array[Dictionary] = [] # { "xform", "number", "is_player" }
var _player_cradle := Transform2D()
var _center := Vector2.ZERO
var _player_approach := Transform2D() # Where the Bucket waits in the close-up shot
var _extent := Rect2(-2800, -520, 5900, 1040) # Whole ship, for the wide shot


func _ready() -> void:
	if concept == "A":
		_layout_rack_carrier()
	else:
		_layout_road_train()

	_player_approach = _player_cradle.translated_local(Vector2(-170, -230))


func get_player_cradle() -> Transform2D:
	return _player_cradle


func get_center() -> Vector2:
	return _center


func get_player_approach() -> Transform2D:
	return _player_approach


func get_extent() -> Rect2:
	return _extent


func _draw() -> void:
	_rng.seed = 7

	if concept == "A":
		_draw_rack_carrier()
	else:
		_draw_road_train()


# --- A: rack carrier


func _layout_rack_carrier() -> void:
	_center = Vector2(150, 0)
	var number := 1

	for side: float in [-1.0, 1.0]:
		for i in 13:
			var xform := Transform2D(-side * deg_to_rad(20.0), Vector2(-1950.0 + i * 290.0, side * 345.0))
			var is_player := side < 0.0 and i == 7
			_bays.append({ "xform": xform, "number": number, "is_player": is_player })

			if is_player:
				_player_cradle = xform

			number += 1


func _draw_rack_carrier() -> void:
	# Engines and plumes at the stern
	for y in [-180.0, -60.0, 60.0, 180.0]:
		_draw_plume(Vector2(-2620, y), 46.0, 260.0)

	# Rails along the flanks, with an arm to each cradle
	for side: float in [-1.0, 1.0]:
		_plate(Rect2(-2120, side * 268.0 - 14.0, 3780, 28), PIPE_DARK, 0.3)

	for bay in _bays:
		var xform: Transform2D = bay.xform
		var root := Vector2(xform.origin.x, signf(xform.origin.y) * 268.0)
		draw_line(root, xform.origin, OUTLINE, 22.0)
		draw_line(root, xform.origin, PIPE, 14.0)

	# Spine
	_panels(Rect2(-2200, -230, 3900, 460), GRAY, Vector2(150, 115))

	for i in 14:
		var x := -2095.0 + i * 290.0
		_plate(Rect2(x - 12, -230, 24, 460), DARK, 0.2)

	_plate(Rect2(-2150, -34, 3800, 68), DARK, 0.4)
	_stripes(Rect2(-2140, -34, 3780, 8), 16.0)
	_stripes(Rect2(-2140, 26, 3780, 8), 16.0)

	# Container stacks between the ribs
	for i in 13:
		if i % 3 == 1:
			continue

		var x := -2060.0 + i * 290.0

		for row in 2:
			var y := -200.0 if row == 0 else 60.0
			_plate(Rect2(x, y, 100, 60), FLEET_PAINTS[(i + row * 2) % FLEET_PAINTS.size()], 0.8)
			_plate(Rect2(x + 110, y, 100, 60), FLEET_PAINTS[(i * 3 + row) % FLEET_PAINTS.size()], 0.8)

	# Engine block
	_panels(Rect2(-2500, -260, 310, 520), DARK, Vector2(100, 130))

	for y in [-180.0, -60.0, 60.0, 180.0]:
		_draw_bell(Vector2(-2500, y), Vector2(-2620, y), 30.0, 46.0)

	# Bridge, ahead of the racks
	_draw_bridge(Rect2(1250, -150, 330, 300))

	# Prow: a plough wider than the racks, so the parked miners ride in its wake
	_draw_prow(1700.0, 2620.0, 480.0)

	# Cradles and the parked miners
	for bay in _bays:
		_draw_cradle(bay.xform, bay.is_player, bay.number, true)


# --- C: road train


func _layout_road_train() -> void:
	_center = Vector2(480, 0)
	var number := 1

	for i in 5:
		if i == 2:
			continue # The cargo car

		var x0 := 760.0 - i * 700.0

		for side: float in [-1.0, 1.0]:
			for slot in 2:
				var xform := Transform2D(0.0, Vector2(x0 + 145.0 + slot * 280.0, side * 230.0))
				var is_player := i == 1 and side < 0.0 and slot == 0
				_bays.append({ "xform": xform, "number": number, "is_player": is_player })

				if is_player:
					_player_cradle = xform

				number += 1


func _draw_road_train() -> void:
	var car_colors: Array[Color] = [GRAY, RUST, BARE, TEAL_GRAY, GRAY]

	# Plumes from the tug's engine pods
	for side: float in [-1.0, 1.0]:
		_draw_plume(Vector2(1380, side * 430.0), 50.0, 300.0)

	# Couplers: visual only, the cars follow the tug in a straight line
	for i in 5:
		var x_end := 760.0 - i * 700.0
		_draw_coupler(x_end - 140.0, x_end)

	_draw_coupler(1320.0, 1460.0)

	# Cars
	for i in 5:
		var x0 := 760.0 - i * 700.0

		if i == 2:
			_draw_cargo_car(x0, car_colors[i])
		else:
			_draw_bay_car(x0, car_colors[i])

		_stencil(Vector2(x0 + 230, 18), "CAR %d" % (i + 1), 40)

	# Tail light on the last car
	draw_circle(Vector2(-2040 + 6, 0), 10.0, LIGHT_RED)

	# Tug
	_panels(Rect2(1460, -290, 760, 580), GRAY, Vector2(150, 115))
	_stripes(Rect2(1470, -290, 740, 10), 16.0)
	_stripes(Rect2(1470, 280, 740, 10), 16.0)

	for side: float in [-1.0, 1.0]:
		_plate(Rect2(1520, side * 330.0 - 20.0 if side > 0.0 else -350.0, 60, 40), PIPE_DARK, 0.2)
		_plate(Rect2(1500, side * 430.0 - 70.0, 320, 140), ENGINE, 0.6)
		_draw_bell(Vector2(1500, side * 430.0), Vector2(1380, side * 430.0), 34.0, 50.0)

	_draw_bridge(Rect2(1800, -150, 330, 300))
	_draw_prow(2220.0, 3000.0, 480.0)

	for bay in _bays:
		_draw_cradle(bay.xform, bay.is_player, bay.number, false)


func _draw_bay_car(x0: float, color: Color) -> void:
	_panels(Rect2(x0, -160, 560, 320), color, Vector2(140, 107))

	# Posts between the bays, and the back wall of each bay
	for side: float in [-1.0, 1.0]:
		var y := -300.0 if side < 0.0 else 160.0

		for x in [x0, x0 + 275.0, x0 + 550.0]:
			_plate(Rect2(x, y, 10 if x != x0 + 275.0 else 10, 140), DARK, 0.2)

		_stripes(Rect2(x0 + 10, side * 162.0 - 3.0, 540, 6), 12.0)


func _draw_cargo_car(x0: float, color: Color) -> void:
	_panels(Rect2(x0, -300, 560, 600), color, Vector2(140, 120))

	for row in 4:
		for column in 3:
			var paint := FLEET_PAINTS[(row * 3 + column * 2) % FLEET_PAINTS.size()]
			_plate(Rect2(x0 + 40 + column * 165, -270 + row * 140, 150, 110), paint, 0.8)


func _draw_coupler(x_from: float, x_to: float) -> void:
	for y in [-60.0, 40.0]:
		_plate(Rect2(x_from - 10, y, x_to - x_from + 20, 20), PIPE_DARK, 0.1)

	var x := x_from

	while x < x_to - 10.0:
		draw_line(Vector2(x, -42), Vector2(x + 35, 42), PIPE, 6.0)
		draw_line(Vector2(x + 35, -42), Vector2(x + 70, 42), PIPE, 6.0)
		x += 70.0


# --- Shared parts


# The cradle, in its own frame: a parked miner faces +x. Rack cradles are pads on arms; train bays
# are recesses in the car (no pad, just clamps and lights).
func _draw_cradle(xform: Transform2D, is_player: bool, number: int, has_pad: bool) -> void:
	draw_set_transform_matrix(xform)

	# Open frame: two rails and a stop bar at the nose end. Space shows through
	if has_pad:
		_plate(Rect2(-150, -80, 300, 16), DARK, 0.4)
		_plate(Rect2(-150, 64, 300, 16), DARK, 0.4)
		_plate(Rect2(130, -80, 22, 160), DARK, 0.4)
		_stripes(Rect2(-150, -80, 24, 4), 8.0)
		_stripes(Rect2(-150, 76, 24, 4), 8.0)

	# Clamp arms: closed on a parked miner, open on an empty cradle
	var reach := 30.0 if is_player else 10.0

	for x in [-60.0, 40.0]:
		for side: float in [-1.0, 1.0]:
			var y_from := side * 66.0
			var y_to := side * (36.0 + reach)
			_plate(Rect2(x - 5, minf(y_from, y_to), 10, absf(y_to - y_from) + 2), PIPE_DARK, 0.0)

	# Lights at the mouth (the back): green for the player's bay, red for taken bays
	for side: float in [-1.0, 1.0]:
		draw_circle(Vector2(-140, side * 66.0), 6.0, LIGHT_GREEN if is_player else LIGHT_RED.darkened(0.3))

	if is_player:
		for i in 7:
			var x := -110.0 + i * 36.0
			var lit := i % 3 == 0
			draw_rect(Rect2(x, -62, 8, 6), LIGHT_GREEN if lit else LIGHT_GREEN.darkened(0.6))
			draw_rect(Rect2(x, 56, 8, 6), LIGHT_GREEN if lit else LIGHT_GREEN.darkened(0.6))
	else:
		_draw_miner(number)

	draw_set_transform_matrix(Transform2D.IDENTITY)
	_stencil(xform * Vector2(-120, -86 if xform.origin.y < 0.0 else 104), "%02d" % number, 28)


# A parked miner: the Bucket's layout, other paint jobs.
func _draw_miner(seed_value: int) -> void:
	var paint := FLEET_PAINTS[seed_value % FLEET_PAINTS.size()]
	var second := DARK if seed_value % 2 == 0 else GRAY
	var cabin_side := -1.0 if seed_value % 3 != 0 else 1.0

	for side: float in [-1.0, 1.0]:
		draw_rect(Rect2(-86, minf(side * 18.0, side * 42.0), 8, 24), OUTLINE)
		draw_rect(Rect2(-84, minf(side * 18.0, side * 42.0), 4, 24), PIPE)

	_draw_bell(Vector2(-96, 0), Vector2(-116, 0), 12.0, 18.0)
	_plate(Rect2(-96, -18, 20, 36), DARK, 1.0)
	_plate(Rect2(-80, -28, 40, 56), second, 1.0)
	_plate(Rect2(-46, -36, 72, 72), paint, 1.0)
	_plate(Rect2(22, -28, 52, 56), second if seed_value % 4 != 1 else paint, 1.0)
	_plate(Rect2(-30, cabin_side * 43.0 - 7.0, 36, 14), CABIN, 0.5)
	draw_rect(Rect2(-24, cabin_side * 43.0 - 3.0, 24, 6), GLASS_DARK)

	for side: float in [-1.0, 1.0]:
		var prong := Rect2(72, -32 if side < 0.0 else 16, 38, 16)
		_plate(prong, BARE if seed_value % 5 == 2 and side < 0.0 else paint, 0.5)

	if seed_value % 4 == 3:
		draw_rect(Rect2(-36, 18, 16, 12), PRIMER)


func _draw_bridge(rect: Rect2) -> void:
	_plate(rect, CABIN, 0.6)
	_plate(rect.grow(-40), CABIN.darkened(0.15), 0.3)
	var glass := Rect2(rect.end.x - 26, rect.position.y + 30, 14, rect.size.y - 60)
	draw_rect(glass.grow(TEXEL), OUTLINE)
	draw_rect(glass, GLASS_DARK)
	draw_rect(Rect2(glass.position.x, glass.position.y, TEXEL * 2.0, glass.size.y), GLASS)

	for y in [rect.position.y + 50.0, rect.end.y - 70.0]:
		draw_rect(Rect2(rect.position.x + 60, y, 120, 20), OUTLINE)
		draw_rect(Rect2(rect.position.x + 62, y + 2, 116, 16), PIPE)


# Wedge plough. Wider than the ship behind it.
func _draw_prow(back_x: float, tip_x: float, half_width: float, base_color: Color = DARK, inner_color: Color = ENGINE, chevron: Color = STRIPE) -> void:
	var shoulder_x := lerpf(back_x, tip_x, 0.45)
	var points := PackedVector2Array([
		Vector2(back_x, -half_width), Vector2(shoulder_x, -half_width * 0.82), Vector2(tip_x, -70),
		Vector2(tip_x, 70), Vector2(shoulder_x, half_width * 0.82), Vector2(back_x, half_width),
	])
	draw_colored_polygon(points, base_color)

	var inner := Geometry2D.offset_polygon(points, -24.0)

	if not inner.is_empty():
		draw_colored_polygon(inner[0], inner_color)

	# Chevrons
	for k in 3:
		var x := back_x + 120.0 + k * 150.0
		var arm := half_width * 0.55 - k * 40.0
		draw_line(Vector2(x, -arm), Vector2(x + arm * 0.6, 0), chevron, 18.0)
		draw_line(Vector2(x + arm * 0.6, 0), Vector2(x, arm), chevron, 18.0)

	# Teeth along the front edges
	var edges := [[points[1], points[2]], [points[2], points[3]], [points[3], points[4]]]

	for edge in edges:
		var from: Vector2 = edge[0]
		var to: Vector2 = edge[1]
		var along := (to - from).normalized()
		var out := along.orthogonal()

		if out.dot((from + to) / 2.0 - Vector2(back_x, 0)) < 0.0:
			out = -out

		var count := floori(from.distance_to(to) / 40.0)

		for j in count:
			var base := from + along * (j * 40.0 + 6.0)
			var tooth := PackedVector2Array([base, base + along * 14.0 + out * 26.0, base + along * 28.0])
			draw_colored_polygon(tooth, NOZZLE)
			tooth.append(tooth[0])
			draw_polyline(tooth, OUTLINE, TEXEL * 2.0)

	points.append(points[0])
	draw_polyline(points, OUTLINE, TEXEL * 3.0)
	draw_circle(points[0] + Vector2(30, 30), 10.0, LIGHT_RED)
	draw_circle(points[5] + Vector2(30, -30), 10.0, LIGHT_GREEN)


# Bell like the Bucket's main engine: mount, exit, ribs, dark mouth.
func _draw_bell(mount: Vector2, exit: Vector2, mount_half: float, exit_half: float) -> void:
	var points := PackedVector2Array([
		mount + Vector2(0, -mount_half), exit + Vector2(0, -exit_half),
		exit + Vector2(0, exit_half), mount + Vector2(0, mount_half),
	])
	draw_colored_polygon(points, ENGINE)

	var length := mount.x - exit.x
	var step := maxf(TEXEL * 3.0, absf(length) / 12.0)
	var x := mount.x - signf(length) * TEXEL * 2.0

	while absf(x - exit.x) > TEXEL and signf(x - exit.x) == signf(length):
		var t := (mount.x - x) / length
		var half := lerpf(mount_half, exit_half, t) - TEXEL
		draw_rect(Rect2(x, mount.y - half, TEXEL, half * 2.0), ENGINE.lightened(0.15))
		x -= signf(length) * step

	draw_rect(Rect2(exit.x - (TEXEL * 2.0 if length < 0.0 else 0.0), exit.y - exit_half + TEXEL, TEXEL * 2.0, exit_half * 2.0 - TEXEL * 2.0), ENGINE_INSIDE)
	points.append(points[0])
	draw_polyline(points, OUTLINE, TEXEL)


func _draw_plume(exit: Vector2, half: float, length: float) -> void:
	draw_colored_polygon(PackedVector2Array([exit + Vector2(0, -half * 0.8), exit + Vector2(-length, 0), exit + Vector2(0, half * 0.8)]), FLAME)
	draw_colored_polygon(PackedVector2Array([exit + Vector2(0, -half * 0.4), exit + Vector2(-length * 0.45, 0), exit + Vector2(0, half * 0.4)]), FLAME_CORE)


# --- Plates (same recipe as ShipHull)


func _plate(rect: Rect2, color: Color, grime_density: float = 1.0) -> void:
	draw_rect(rect, OUTLINE)

	var inner := rect.grow(-TEXEL)

	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return

	draw_rect(inner, color)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, TEXEL)), color.lightened(0.2))
	draw_rect(Rect2(inner.position.x, inner.end.y - TEXEL, inner.size.x, TEXEL), color.darkened(0.3))

	var rivet := color.darkened(0.35)
	var x := inner.position.x + TEXEL

	while x < inner.end.x - TEXEL:
		draw_rect(Rect2(x, inner.position.y + TEXEL, TEXEL, TEXEL), rivet)
		draw_rect(Rect2(x, inner.end.y - TEXEL * 2.0, TEXEL, TEXEL), rivet)
		x += TEXEL * 4.0

	_grime(inner, int(inner.get_area() / 300.0 * grime_density))


# A big surface as a patchwork of plates: mostly the base colour, some darker or lighter
# replacements, the odd primer or rust patch. Old hull, repaired many times.
func _panels(rect: Rect2, base: Color, panel: Vector2) -> void:
	var y := rect.position.y

	while y < rect.end.y - 1.0:
		var height := minf(panel.y, rect.end.y - y)
		var x := rect.position.x + (panel.x * 0.5 if int((y - rect.position.y) / panel.y) % 2 == 1 else 0.0)

		if x > rect.position.x:
			_plate(Rect2(rect.position.x, y, x - rect.position.x, height), base, 0.6)

		while x < rect.end.x - 1.0:
			var width := minf(panel.x, rect.end.x - x)
			var roll := _rng.randf()
			var color := base

			if roll < 0.12:
				color = base.darkened(0.12)
			elif roll < 0.2:
				color = base.lightened(0.08)
			elif roll < 0.23:
				color = PRIMER
			elif roll < 0.26:
				color = RUST

			_plate(Rect2(x, y, width, height), color, 0.6)
			x += width

		y += height


func _stripes(rect: Rect2, block: float) -> void:
	var is_vertical := rect.size.y > rect.size.x
	var length := rect.size.y if is_vertical else rect.size.x
	var t := 0.0
	var i := 0

	while t < length:
		var size := minf(block, length - t)
		var color := STRIPE if i % 2 == 0 else STRIPE_DARK
		var piece := Rect2(rect.position.x, rect.position.y + t, rect.size.x, size) if is_vertical else Rect2(rect.position.x + t, rect.position.y, size, rect.size.y)
		draw_rect(piece, color)
		t += block
		i += 1


func _grime(rect: Rect2, count: int) -> void:
	var columns := int(rect.size.x / TEXEL)
	var rows := int(rect.size.y / TEXEL)

	if columns <= 0 or rows <= 0:
		return

	for i in count:
		var cell := Vector2(_rng.randi_range(0, columns - 1), _rng.randi_range(0, rows - 1))
		draw_rect(Rect2(rect.position + cell * TEXEL, Vector2(TEXEL, TEXEL)), GRIME[_rng.randi_range(0, GRIME.size() - 1)])


func _stencil(at: Vector2, text: String, size: int) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, STRIPE.darkened(0.1))
