class_name MothershipArt
extends Node2D

# The parts of the mothership that don't move: flatbeds with their parked ships and lashings,
# the locomotive, the deflector. Drawn once; the train calls queue_redraw() when the player's
# slot changes. Pixel language of ShipHull: 2 px texels, outlined plates, light top edge, dark
# bottom edge, rivets, grime. Light comes from the top left: raised parts cast a shadow down and
# to the right. Placeholder art, drawn in code.

const TEXEL: float = 2.0

const OUTLINE := Color(0.06, 0.055, 0.07) # Same as the ship's and the rocks'
const DARK := Color(0.21, 0.2, 0.22)
const GRAY := Color(0.31, 0.3, 0.31)
const BARE := Color(0.48, 0.47, 0.45)
const CABIN := Color(0.33, 0.35, 0.24)
const GLASS_DARK := Color(0.2, 0.39, 0.47)
const PRIMER := Color(0.67, 0.36, 0.18)
const STRIPE := Color(0.83, 0.64, 0.16)
const STRIPE_DARK := Color(0.12, 0.11, 0.11)
const PIPE := Color(0.54, 0.5, 0.45)
const PIPE_DARK := Color(0.36, 0.34, 0.31)
const ENGINE := Color(0.26, 0.27, 0.31)
const ENGINE_INSIDE := Color(0.09, 0.09, 0.13)
const NOZZLE := Color(0.59, 0.59, 0.63)
const STRAP := Color(0.78, 0.45, 0.12)
const SKY := Color(0.55, 0.85, 0.95)
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)
const GRIME: Array[Color] = [Color(0.19, 0.18, 0.18), Color(0.38, 0.24, 0.16), Color(0.25, 0.24, 0.23)]
const FLEET_PAINTS: Array[Color] = [Color(0.22, 0.38, 0.38), Color(0.28, 0.33, 0.42), Color(0.36, 0.37, 0.22), Color(0.46, 0.24, 0.15), Color(0.31, 0.3, 0.31), Color(0.55, 0.42, 0.18)]
const LIGHT_GREEN := Color(0.4, 0.95, 0.35)
const LIGHT_AMBER := Color(1.0, 0.62, 0.15)
const LIGHT_RED := Color(0.85, 0.22, 0.14)

# Locomotive livery: black and yellow
const HULL := Color(0.14, 0.14, 0.15)
const TRIM := Color(0.07, 0.07, 0.08)
const ACCENT := Color(0.93, 0.72, 0.1)
const GLOW := Color(1.0, 0.95, 0.75)
const FIN := Color(0.32, 0.28, 0.18)
const INSET := Color(0.26, 0.26, 0.27)

const FLATBED := Color(0.73, 0.56, 0.14) # Rail yellow

var _rng := RandomNumberGenerator.new()


func _draw() -> void:
	var train := get_parent() as Mothership

	if train == null:
		return

	_rng.seed = 11 # Same grime every redraw
	_draw_flatbeds(train)
	_draw_locomotive()
	_draw_deflector()


# --- Flatbeds


func _draw_flatbeds(train: Mothership) -> void:
	for i in train.cars.size():
		var car := train.cars[i]
		var x0: float = car.x0
		var x1: float = car.x1
		var half: float = car.half

		# Drawbar to the car ahead
		var ahead_x := 0.0 if i == 0 else float(train.cars[i - 1].x0)
		_plate(Rect2(x1 - 10.0, -16, ahead_x - x1 + 20.0, 32), DARK, 0.2)
		draw_circle(Vector2((x1 + ahead_x) / 2.0, 0), 14.0, PIPE_DARK)

		# Open deck: cross members, girders, end beams
		var x := x0 + 30.0

		while x < x1 - 30.0:
			_plate(Rect2(x, -half, 12, half * 2.0), DARK, 0.1)
			x += 80.0

		_plate(Rect2(x0, -half, x1 - x0, 20), FLATBED, 0.4)
		_plate(Rect2(x0, half - 20.0, x1 - x0, 20), FLATBED, 0.4)

		if car.cls != "L":
			_plate(Rect2(x0, -10, x1 - x0, 20), DARK, 0.3)

		_plate(Rect2(x0, -half, 26, half * 2.0), DARK, 0.3)
		_plate(Rect2(x1 - 26.0, -half, 26, half * 2.0), DARK, 0.3)
		_stripes(Rect2(x0 + 4.0, -half, 18, half * 2.0), 16.0, STRIPE, STRIPE_DARK)

		for slot in train.slots:
			var slot_x: float = slot.xform.origin.x

			if slot_x < x0 or slot_x > x1:
				continue

			_draw_slot(train, slot, half)

		_stencil(Vector2(x0 + 40.0, half + 100.0), "%s-CLASS FLAT %d" % [car.cls, i + 1], 30, STRIPE.darkened(0.1))


func _draw_slot(train: Mothership, slot: Dictionary, car_half: float) -> void:
	var cls: String = slot.cls
	var slot_size: Vector2 = Mothership.SLOT_SIZE[cls]
	var is_player: bool = slot.is_player
	draw_set_transform_matrix(slot.xform)

	for saddle_x in [-slot_size.x * 0.28, slot_size.x * 0.22]:
		_plate(Rect2(saddle_x - 14.0, -slot_size.y / 2.0, 28, slot_size.y), PIPE_DARK, 0.2)

	if not is_player:
		_draw_parked(cls, slot.number)
		draw_circle(Vector2(-slot_size.x / 2.0 + 8.0, -slot_size.y / 2.0 + 8.0), 5.0, LIGHT_RED.darkened(0.3))

	_draw_lashing(cls, is_player and not train.is_player_secured)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	var slot_xform: Transform2D = slot.xform
	var slot_y := slot_xform.origin.y
	var label_y := -car_half - 12.0 if slot_y <= 0.0 else car_half + 40.0
	_stencil(Vector2(slot_xform.origin.x - slot_size.x / 2.0 + 10.0, label_y), "%02d" % slot.number, 30, STRIPE.darkened(0.1))


# Winches on the frame, cables to the hull, ratchet straps over it, clamp pads on its flanks.
# An empty slot: clamps open, straps hanging loose, cables reeled in.
func _draw_lashing(cls: String, is_empty: bool) -> void:
	var slot: Vector2 = Mothership.SLOT_SIZE[cls]
	var ship_size: Vector2 = Mothership.SHIP_SIZE[cls]
	var half_slot := slot / 2.0
	var half_ship := ship_size / 2.0

	for x_ratio in [-0.3, 0.12]:
		for side: float in [-1.0, 1.0]:
			var x: float = ship_size.x * x_ratio
			var reach := half_ship.y * 0.92 if not is_empty else half_slot.y - 16.0
			var from_y := side * half_slot.y
			var to_y := side * reach
			_plate(Rect2(x - 7.0, minf(from_y, to_y), 14, absf(to_y - from_y)), PIPE_DARK, 0.0)
			_plate(Rect2(x - 16.0, to_y - (0.0 if side > 0.0 else 8.0), 32, 8), DARK, 0.0)

	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var winch: Vector2 = corner * (half_slot - Vector2(24, 4))
		_plate(Rect2(winch - Vector2(16, 12), Vector2(32, 24)), DARK, 0.0)
		draw_rect(Rect2(winch - Vector2(10, 6), Vector2(20, 12)), PIPE)
		draw_rect(Rect2(winch - Vector2(10, 1), Vector2(20, 2)), PIPE_DARK)

		if not is_empty:
			var anchor: Vector2 = corner * half_ship * Vector2(0.62, 0.78)
			draw_line(winch, anchor, OUTLINE, 5.0)
			draw_line(winch, anchor, NOZZLE, 2.0)
			draw_rect(Rect2(anchor - Vector2(4, 4), Vector2(8, 8)), STRIPE)

	var strap_width := 8.0 * clampf(ship_size.x / 230.0, 1.0, 2.0)

	for x_ratio in [-0.08, 0.3]:
		var x: float = ship_size.x * x_ratio

		if is_empty:
			draw_rect(Rect2(x - strap_width / 2.0, -half_slot.y, strap_width, 26), OUTLINE)
			draw_rect(Rect2(x - strap_width / 2.0 + 2.0, -half_slot.y, strap_width - 4.0, 24), STRAP)
		else:
			draw_rect(Rect2(x - strap_width / 2.0, -half_slot.y + 4.0, strap_width, slot.y - 8.0), OUTLINE)
			draw_rect(Rect2(x - strap_width / 2.0 + 2.0, -half_slot.y + 4.0, strap_width - 4.0, slot.y - 8.0), STRAP)
			draw_rect(Rect2(x - strap_width / 2.0 - 2.0, half_ship.y + 4.0, strap_width + 4.0, 10), STRIPE_DARK)
			draw_rect(Rect2(x - strap_width / 2.0, half_ship.y + 6.0, strap_width, 6), STRIPE)


func _draw_parked(cls: String, seed_value: int) -> void:
	if cls == "S":
		_draw_small_ship(seed_value)
	else:
		var ship_size: Vector2 = Mothership.SHIP_SIZE[cls]
		_draw_big_ship(ship_size.x, ship_size.y, seed_value)


# A small miner: the Bucket's layout, other paint jobs.
func _draw_small_ship(seed_value: int) -> void:
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


# Placeholder for the medium and large classes, in the Bucket's layout and plates.
func _draw_big_ship(length: float, width: float, seed_value: int) -> void:
	var paint := FLEET_PAINTS[seed_value % FLEET_PAINTS.size()]
	var second := DARK if seed_value % 2 == 0 else GRAY
	var l := length / 2.0
	var w := width / 2.0
	var engines := 2 if width < 250.0 else 3

	for k in engines:
		var y := lerpf(-w * 0.45, w * 0.45, float(k) / (engines - 1))
		_draw_bell(Vector2(-l + 30.0, y), Vector2(-l, y), w * 0.14, w * 0.22)

	_plate(Rect2(-l + 30.0, -w * 0.72, length * 0.1, w * 1.44), DARK, 0.8)
	_plate(Rect2(-l * 0.72, -w * 0.7, length * 0.28, w * 1.4), second, 0.8)
	_plate(Rect2(-l * 0.18, -w, length * 0.38, w * 2.0), paint, 0.8)
	_plate(Rect2(l * 0.56, -w * 0.7, length * 0.18, w * 1.4), second if seed_value % 4 != 1 else paint, 0.8)

	for side: float in [-1.0, 1.0]:
		var y0 := -w * 0.7 if side < 0.0 else w * 0.3
		_plate(Rect2(l * 0.74, y0, length * 0.13, w * 0.4), paint, 0.5)

	var cabin_side := -1.0 if seed_value % 3 != 0 else 1.0
	var cabin := Rect2(-l * 0.1, cabin_side * w * 1.06 - w * 0.12, length * 0.16, w * 0.24)
	_plate(cabin, CABIN, 0.4)
	draw_rect(Rect2(cabin.position.x + 6.0, cabin.position.y + cabin.size.y * 0.3, cabin.size.x - 12.0, cabin.size.y * 0.4), GLASS_DARK)


# --- Locomotive


func _draw_locomotive() -> void:
	var length := Mothership.LOCO_LENGTH
	var reactor := Vector2(340, 0)

	# Tow yoke
	var yoke := PackedVector2Array([Vector2(70, -70), Vector2(0, -40), Vector2(-20, -20), Vector2(-20, 20), Vector2(0, 40), Vector2(70, 70)])
	_shadow_polygon(yoke)
	_polygon_plate(yoke, TRIM)
	draw_circle(Vector2(-4, 0), 16.0, OUTLINE)
	draw_circle(Vector2(-4, 0), 12.0, NOZZLE)
	_stripes(Rect2(30, -60, 12, 120), 12.0, ACCENT, TRIM)

	# Engines on sponsons, outboard of the widest car: the exhaust passes beside the train
	for side: float in [-1.0, 1.0]:
		var sponson := Rect2(10, side * 380.0 - 110.0, 120, 220)

		for brace_x in [40.0, 100.0]:
			_strut(Vector2(brace_x + 40.0, side * 70.0), Vector2(brace_x, side * 280.0), 18.0, TRIM)

		_strut(Vector2(150, side * 70.0), Vector2(40, side * 420.0), 8.0, TRIM.lightened(0.15))

		for engine_y in [side * 325.0, side * 435.0]:
			_draw_bell(Vector2(10, engine_y), Vector2(Mothership.ENGINE_EXIT_X, engine_y), 34.0, 46.0)

		_shadow(sponson)
		_smooth_plate(sponson, TRIM)
		_stripes(Rect2(sponson.end.x - 12.0, sponson.position.y, 10, sponson.size.y), 14.0, ACCENT, TRIM)
		draw_circle(Vector2(70, side * 486.0), 7.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)

	# Thrust frame: carries the yoke and the sponson braces
	var frame := Rect2(20, -110, 70, 220)
	_shadow(frame)
	_smooth_plate(frame, TRIM)

	# Radiator paddles
	for paddle_x in [210.0, 470.0, 640.0]:
		for side: float in [-1.0, 1.0]:
			_draw_paddle(paddle_x, side)

	# Boxed truss
	var box := Rect2(60, -70, length - 230.0, 140)
	_shadow(box)
	_smooth_plate(box, HULL)
	var x := 110.0

	while x < box.end.x - 60.0:
		draw_circle(Vector2(x, 0), 24.0, OUTLINE)
		draw_circle(Vector2(x, 0), 20.0, TRIM)
		x += 90.0

	_stripes(Rect2(box.position.x, -70, box.size.x, 8), 20.0, ACCENT, TRIM)
	_stripes(Rect2(box.position.x, 62, box.size.x, 8), 20.0, ACCENT, TRIM)

	# Caged reactor
	_draw_reactor(reactor, 120.0)

	for k in 6:
		var angle := TAU * k / 6.0
		_strut(reactor + Vector2.from_angle(angle) * 70.0, reactor + Vector2.from_angle(angle + PI * 0.4) * 140.0, 6.0, TRIM.lightened(0.15))

	draw_arc(reactor, 140.0, 0.0, TAU, 48, OUTLINE, 10.0)
	draw_arc(reactor, 140.0, 0.0, TAU, 48, TRIM.lightened(0.15), 6.0)

	# Deflector yoke
	var bar := Rect2(length + 70.0, -150, 40, 300)

	for side: float in [-1.0, 1.0]:
		_strut(Vector2(length - 100.0, side * 40.0), Vector2(bar.position.x + 20.0, side * 120.0), 14.0, TRIM)

	_shadow(bar)
	_smooth_plate(bar, TRIM)
	_stripes(Rect2(bar.end.x - 12.0, bar.position.y, 10, bar.size.y), 14.0, ACCENT, TRIM)

	# Cab with wraparound glass
	var cab := Rect2(length - 230.0, -130, 220, 260)
	_shadow(cab)
	_smooth_plate(cab, HULL)
	_smooth_plate(Rect2(cab.position + Vector2(20, 30), Vector2(110, 200)), INSET)
	var glass := PackedVector2Array([Vector2(cab.end.x - 50.0, -110), Vector2(cab.end.x - 6.0, -70), Vector2(cab.end.x - 6.0, 70), Vector2(cab.end.x - 50.0, 110)])
	draw_polyline(glass, OUTLINE, 22.0)
	draw_polyline(glass, ACCENT.darkened(0.5), 16.0)
	draw_polyline(glass, ACCENT, 3.0)
	_stencil(Vector2(120, 112), "HAULER 7", 30, ACCENT)


func _draw_paddle(root_x: float, side: float) -> void:
	var points := Mothership.get_paddle(root_x, side)
	var root_y := 80.0
	var tip_y := 330.0
	var sweep := 30.0
	_shadow_polygon(points)
	draw_colored_polygon(points, TRIM)
	var y := root_y + 14.0

	while y < tip_y - 8.0:
		var t := (y - root_y) / (tip_y - root_y)
		draw_rect(Rect2(root_x - sweep * t - 38.0, side * y - 3.0, 76, 6), FIN)
		y += 16.0

	_strut(Vector2(root_x, side * root_y), Vector2(root_x - sweep, side * tip_y), 8.0, ACCENT)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE, TEXEL * 2.0)
	draw_circle(Vector2(root_x - sweep, side * (tip_y - 4.0)), 7.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)


func _draw_reactor(center: Vector2, radius: float) -> void:
	draw_circle(center + Vector2(14, 16), radius - 2.0, SHADOW)
	draw_circle(center, radius + 4.0, OUTLINE)
	draw_circle(center, radius, INSET.darkened(0.2))
	draw_circle(center + Vector2(-radius * 0.12, -radius * 0.12), radius * 0.8, INSET)
	draw_arc(center, radius * 0.9, 0.0, TAU, 48, ACCENT, radius * 0.09)

	for k in 8:
		var direction := Vector2.from_angle(TAU * k / 8.0)
		draw_rect(Rect2(center + direction * radius * 0.9 - Vector2(5, 5), Vector2(10, 10)), OUTLINE)

	draw_circle(center, radius * 0.4, Color(GLOW, 0.25))
	draw_circle(center, radius * 0.34, OUTLINE)
	draw_circle(center, radius * 0.29, GLOW.darkened(0.45))
	draw_circle(center, radius * 0.17, GLOW)


# --- Deflector


func _draw_deflector() -> void:
	var center := Mothership.DEFLECTOR_CENTER
	var radius := Mothership.DEFLECTOR_RADIUS
	var arc := Mothership.DEFLECTOR_ARC
	var steps := 40

	# The field: a soft band ahead of the ring, a brighter rim
	draw_colored_polygon(Mothership.get_field_polygon(), Color(SKY, 0.16))
	var rim := PackedVector2Array()

	for k in steps + 1:
		rim.append(center + Vector2.from_angle(lerpf(-arc, arc, float(k) / steps)) * (radius + Mothership.FIELD_DEPTH))

	draw_polyline(rim, Color(SKY, 0.7), 4.0)

	for k in range(0, steps, 3):
		var angle := lerpf(-arc, arc, float(k) / steps)
		draw_line(center + Vector2.from_angle(angle) * (radius + 30.0), center + Vector2.from_angle(angle) * (radius + 110.0), Color(SKY, 0.25), 2.0)

	# Struts back to the yoke
	for k in [1, 3, 5]:
		var at := center + Vector2.from_angle(lerpf(-arc, arc, k / 6.0)) * radius
		var mount := Vector2(Mothership.LOCO_LENGTH + 90.0, clampf(at.y, -126.0, 126.0))
		_strut(mount, at, 12.0, TRIM)

	# Ring
	var ring := PackedVector2Array()

	for k in steps + 1:
		ring.append(center + Vector2.from_angle(lerpf(-arc, arc, float(k) / steps)) * radius)

	draw_polyline(ring, OUTLINE, 22.0)
	draw_polyline(ring, TRIM, 16.0)
	draw_polyline(ring, ACCENT, 4.0)

	# Emitter pylons (the glow is in MothershipLights)
	for k in 7:
		var angle := lerpf(-arc, arc, k / 6.0)
		var at := center + Vector2.from_angle(angle) * radius
		var out := Vector2.from_angle(angle)
		draw_line(at - out * 10.0, at + out * 34.0, OUTLINE, 22.0)
		draw_line(at - out * 10.0, at + out * 30.0, HULL, 16.0)
		draw_circle(at + out * 36.0, 14.0, OUTLINE)
		draw_circle(at + out * 36.0, 11.0, SKY.darkened(0.2))


# --- Drawing helpers


static func get_emitters() -> PackedVector2Array:
	var points := PackedVector2Array()

	for k in 7:
		var angle := lerpf(-Mothership.DEFLECTOR_ARC, Mothership.DEFLECTOR_ARC, k / 6.0)
		points.append(Mothership.DEFLECTOR_CENTER + Vector2.from_angle(angle) * (Mothership.DEFLECTOR_RADIUS + 36.0))

	return points


# Outline, fill, a light top edge, a dark bottom edge, rivets, and some dirt (like ShipHull).
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


# A plate with sparser rivets and no grime: the locomotive's cleaner finish.
func _smooth_plate(rect: Rect2, color: Color) -> void:
	draw_rect(rect, OUTLINE)
	var inner := rect.grow(-TEXEL)
	draw_rect(inner, color)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, TEXEL)), color.lightened(0.2))
	draw_rect(Rect2(inner.position.x, inner.end.y - TEXEL, inner.size.x, TEXEL), color.darkened(0.3))
	_rivet_row(inner.position + Vector2(TEXEL, TEXEL), inner.end.x - TEXEL, color)
	_rivet_row(Vector2(inner.position.x + TEXEL, inner.end.y - TEXEL * 2.0), inner.end.x - TEXEL, color)


func _rivet_row(from: Vector2, to_x: float, color: Color) -> void:
	var x := from.x

	while x < to_x:
		draw_rect(Rect2(x, from.y, TEXEL, TEXEL), color.darkened(0.35))
		x += TEXEL * 6.0


# A plate that isn't a rectangle: fill, a lighter rim, rivets along the edges, outline.
func _polygon_plate(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var rim := Geometry2D.offset_polygon(points, -TEXEL * 2.0)

	if not rim.is_empty():
		var rim_line: PackedVector2Array = rim[0]
		rim_line.append(rim_line[0])
		draw_polyline(rim_line, color.lightened(0.15), TEXEL)

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE, TEXEL * 2.0)


func _stripes(rect: Rect2, block: float, color_a: Color, color_b: Color) -> void:
	var is_vertical := rect.size.y > rect.size.x
	var length := rect.size.y if is_vertical else rect.size.x
	var t := 0.0
	var i := 0

	while t < length:
		var size := minf(block, length - t)
		var piece := Rect2(rect.position.x, rect.position.y + t, rect.size.x, size) if is_vertical else Rect2(rect.position.x + t, rect.position.y, size, rect.size.y)
		draw_rect(piece, color_a if i % 2 == 0 else color_b)
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


func _shadow(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(12, 14), rect.size), SHADOW)


func _shadow_polygon(points: PackedVector2Array) -> void:
	var moved := PackedVector2Array()

	for point in points:
		moved.append(point + Vector2(12, 14))

	draw_colored_polygon(moved, SHADOW)


func _strut(from: Vector2, to: Vector2, width: float, color: Color) -> void:
	draw_line(from, to, OUTLINE, width + 4.0)
	draw_line(from, to, color, width)


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

	draw_rect(Rect2(exit.x, exit.y - exit_half + TEXEL, TEXEL * 2.0, exit_half * 2.0 - TEXEL * 2.0), ENGINE_INSIDE)
	points.append(points[0])
	draw_polyline(points, OUTLINE, TEXEL)


func _stencil(at: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
