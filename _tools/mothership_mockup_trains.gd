extends "res://_tools/mothership_mockup_drawing.gd"

# Four looks for the road train (concept C). Same modules for all four: a tug with the plough,
# then cars sized for small (S), medium (M) and large (L) ships. Mockup only.
# - C1 flatbed freight: open girder flatcars, ships clamped on deck, rail-yellow frames
# - C2 hangar liner: enclosed cars with side hangar doors, cream company livery
# - C3 pod string: octagonal pods on a thin truss spine, ships berthed nose-in around each hub
# - C4 scrap convoy: old hulls turned into cars (tanker, gutted freighter, barge), towed on cables

const CAR_ORDER: Array[String] = ["S", "M", "L", "S", "M"]
const SHIP_SIZE := { "S": Vector2(230, 100), "M": Vector2(420, 180), "L": Vector2(800, 320) }
const SLOT_SIZE := { "S": Vector2(300, 150), "M": Vector2(480, 230), "L": Vector2(870, 370) }
const CREAM := Color(0.74, 0.7, 0.6)
const LINER_TEAL := Color(0.16, 0.27, 0.29)
const CANVAS := Color(0.42, 0.43, 0.3)

var _cars: Array[Dictionary] = [] # { "cls", "x0", "x1", "half" }
var _tug_back: float = 0.0
var _tug_front: float = 0.0
var _prow_half: float = 0.0


func _ready() -> void:
	match concept:
		"C1":
			_build({ "S": 680.0, "M": 560.0, "L": 960.0 }, { "S": 170.0, "M": 250.0, "L": 200.0 }, 110.0, 760.0)
			_layout_flatbeds()
		"C2":
			_build({ "S": 940.0, "M": 1000.0, "L": 980.0 }, { "S": 210.0, "M": 270.0, "L": 420.0 }, 90.0, 820.0)
			_layout_liner()
		"C3":
			_build({ "S": 720.0, "M": 1040.0, "L": 1100.0 }, { "S": 360.0, "M": 520.0, "L": 380.0 }, 170.0, 900.0)
			_layout_pods()
		"C4":
			_build({ "S": 760.0, "M": 900.0, "L": 1100.0 }, { "S": 215.0, "M": 300.0, "L": 260.0 }, 220.0, 780.0)
			_layout_scrap()


func _draw() -> void:
	_rng.seed = 11

	match concept:
		"C1":
			_draw_flatbeds()
		"C2":
			_draw_liner()
		"C3":
			_draw_pods()
		"C4":
			_draw_scrap()


# Cars from the tug backward. The tug's back is at x = 0.
func _build(lengths: Dictionary, halves: Dictionary, gap: float, tug_length: float) -> void:
	var x := -gap
	var widest := 0.0

	for cls in CAR_ORDER:
		var length: float = lengths[cls]
		var half: float = halves[cls]
		_cars.append({ "cls": cls, "x0": x - length, "x1": x, "half": half })
		widest = maxf(widest, half)
		x -= length + gap

	_tug_back = 0.0
	_tug_front = tug_length
	_prow_half = widest + 70.0
	var tail := x + gap
	_extent = Rect2(tail - 250.0, -_prow_half - 150.0, _tug_front + 800.0 - tail + 250.0, (_prow_half + 150.0) * 2.0)
	_center = _extent.get_center()


func _add_bay(xform: Transform2D, cls: String, is_player: bool, approach: Vector2 = Vector2(-170, -230)) -> void:
	_bays.append({ "xform": xform, "cls": cls, "number": _bays.size() + 1, "is_player": is_player })

	if is_player:
		_player_cradle = xform
		_player_approach = xform.translated_local(approach)


func _bays_in(car: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []

	for bay in _bays:
		var x: float = bay.xform.origin.x

		if x >= car.x0 and x <= car.x1:
			found.append(bay)

	return found


# A parked ship of that class, in the bay's frame (nose to +x).
func _draw_parked(cls: String, seed_value: int) -> void:
	if cls == "S":
		_draw_miner(seed_value)
	else:
		var ship_size: Vector2 = SHIP_SIZE[cls]
		_draw_hull(ship_size.x, ship_size.y, seed_value)


# Placeholder hull for the medium and large classes, in the Bucket's layout and plates.
func _draw_hull(length: float, width: float, seed_value: int) -> void:
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

	var x := -l * 0.1

	while x < l * 0.5:
		draw_rect(Rect2(x, w * 0.55, TEXEL * 2.0, w * 0.3), second.darkened(0.3))
		x += TEXEL * 5.0


# Ship, or green lights for the player's empty bay, or a red light for a taken one. Bay frame.
func _draw_bay_contents(bay: Dictionary, light_y: float = -1.0) -> void:
	var cls: String = bay.cls
	var slot: Vector2 = SLOT_SIZE[cls]
	var half := slot / 2.0

	if bay.is_player:
		for i in 7:
			var x := lerpf(-half.x + 20.0, half.x - 30.0, i / 6.0)
			var lit := i % 3 == 0
			var color := LIGHT_GREEN if lit else LIGHT_GREEN.darkened(0.6)
			draw_rect(Rect2(x, -half.y + 6.0, 8, 6), color)
			draw_rect(Rect2(x, half.y - 12.0, 8, 6), color)

		draw_circle(Vector2(-half.x + 8.0, -half.y + 8.0), 6.0, LIGHT_GREEN)
		draw_circle(Vector2(-half.x + 8.0, half.y - 8.0), 6.0, LIGHT_GREEN)
	else:
		_draw_parked(cls, bay.number)
		draw_circle(Vector2(-half.x + 8.0, light_y * (half.y - 8.0)), 5.0, LIGHT_RED.darkened(0.3))


func _in_bay(bay: Dictionary) -> void:
	draw_set_transform_matrix(bay.xform)


func _out_of_bay() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _bay_number(bay: Dictionary, offset: Vector2) -> void:
	var xform: Transform2D = bay.xform
	_stencil(xform.origin + offset, "%02d" % bay.number, 30)


func _draw_tug_engines(y: float, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		_draw_plume(Vector2(-130, side * y), 52.0, 320.0)
		_plate(Rect2(-10, side * y - 70.0, 300, 140), color, 0.6)
		_draw_bell(Vector2(-10, side * y), Vector2(-130, side * y), 36.0, 52.0)


# --- C1: flatbed freight


func _layout_flatbeds() -> void:
	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var middle: float = (car.x0 + car.x1) / 2.0

		match car.cls:
			"S":
				for column in 2:
					for side: float in [-1.0, 1.0]:
						var is_player := i == 0 and column == 1 and side < 0.0
						_add_bay(Transform2D(0.0, Vector2(x0 + 180.0 + column * 320.0, side * 82.0)), "S", is_player)
			"M":
				for side: float in [-1.0, 1.0]:
					_add_bay(Transform2D(0.0, Vector2(middle, side * 125.0)), "M", false)
			"L":
				_add_bay(Transform2D(0.0, Vector2(middle, 0.0)), "L", false)


func _draw_flatbeds() -> void:
	var frame := STRIPE.darkened(0.12)

	_draw_tug_engines(_prow_half + 40.0, ENGINE)

	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var x1: float = car.x1
		var half: float = car.half

		# Drawbar to the car ahead
		var ahead_x := _tug_back if i == 0 else float(_cars[i - 1].x0)
		_plate(Rect2(x1 - 10.0, -16, ahead_x - x1 + 20.0, 32), DARK, 0.2)
		draw_circle(Vector2((x1 + ahead_x) / 2.0, 0), 14.0, PIPE_DARK)

		# Open deck: cross members, then the girders. Space shows through
		var x := x0 + 30.0

		while x < x1 - 30.0:
			_plate(Rect2(x, -half, 12, half * 2.0), DARK, 0.1)
			x += 80.0

		_plate(Rect2(x0, -half, x1 - x0, 20), frame, 0.4)
		_plate(Rect2(x0, half - 20.0, x1 - x0, 20), frame, 0.4)

		if car.cls != "L":
			_plate(Rect2(x0, -10, x1 - x0, 20), DARK, 0.3)

		_plate(Rect2(x0, -half, 26, half * 2.0), DARK, 0.3)
		_plate(Rect2(x1 - 26.0, -half, 26, half * 2.0), DARK, 0.3)
		_stripes(Rect2(x0 + 4.0, -half, 18, half * 2.0), 16.0)

		# Saddles and clamps, then the ships
		for bay in _bays_in(car):
			var slot: Vector2 = SLOT_SIZE[bay.cls]
			_in_bay(bay)

			for saddle_x in [-slot.x * 0.28, slot.x * 0.22]:
				_plate(Rect2(saddle_x - 14.0, -slot.y / 2.0, 28, slot.y), PIPE_DARK, 0.2)

			_draw_bay_contents(bay)
			_out_of_bay()
			var bay_y: float = bay.xform.origin.y
			_bay_number(bay, Vector2(-slot.x / 2.0 + 10.0, -half - 12.0 - bay_y if bay_y <= 0.0 else half + 40.0 - bay_y))

		_stencil(Vector2(x0 + 40.0, half + 100.0), "%s-CLASS FLAT %d" % [car.cls, i + 1], 30)

	# Tug: rail yellow, cab at the back
	_panels(Rect2(_tug_back, -_prow_half + 60.0, _tug_front - _tug_back, (_prow_half - 60.0) * 2.0), frame, Vector2(150, 110))
	_stripes(Rect2(_tug_back, -_prow_half + 60.0, _tug_front - _tug_back, 14), 18.0)
	_stripes(Rect2(_tug_back, _prow_half - 74.0, _tug_front - _tug_back, 14), 18.0)
	_draw_bridge(Rect2(_tug_back + 40.0, -150, 260, 300))
	_draw_prow(_tug_front, _tug_front + 700.0, _prow_half)


# --- C2: hangar liner


func _layout_liner() -> void:
	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var half: float = car.half

		match car.cls:
			"S":
				for slot_index in 3:
					for side: float in [-1.0, 1.0]:
						var is_player := i == 0 and slot_index == 1 and side < 0.0
						_add_bay(Transform2D(0.0, Vector2(x0 + 170.0 + slot_index * 300.0, side * (half - 75.0))), "S", is_player)
			"M":
				for slot_index in 2:
					for side: float in [-1.0, 1.0]:
						_add_bay(Transform2D(0.0, Vector2(x0 + 260.0 + slot_index * 480.0, side * (half - 115.0))), "M", false)
			"L":
				for side: float in [-1.0, 1.0]:
					_add_bay(Transform2D(0.0, Vector2((car.x0 + car.x1) / 2.0, side * (half - 185.0))), "L", false)


func _draw_liner() -> void:
	_draw_tug_engines(_prow_half + 60.0, LINER_TEAL)

	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var x1: float = car.x1
		var half: float = car.half

		# Bellows gangway to the car ahead
		var ahead_x := _tug_back if i == 0 else float(_cars[i - 1].x0)
		var x := x1

		while x < ahead_x:
			draw_rect(Rect2(x, -70, 6, 140), DARK if int((x - x1) / 6.0) % 2 == 0 else GRAY)
			x += 6.0

		draw_rect(Rect2(x1, -72, ahead_x - x1, 2), OUTLINE)
		draw_rect(Rect2(x1, 70, ahead_x - x1, 2), OUTLINE)

		# Body in livery: cream, orange band, teal pinstripes
		_panels(Rect2(x0, -half, x1 - x0, half * 2.0), CREAM, Vector2(160, 120))
		_plate(Rect2(x0, -22, x1 - x0, 44), PRIMER, 0.3)
		draw_rect(Rect2(x0 + 2.0, -30, x1 - x0 - 4.0, 4), LINER_TEAL)
		draw_rect(Rect2(x0 + 2.0, 26, x1 - x0 - 4.0, 4), LINER_TEAL)

		if car.cls == "S":
			_stencil(Vector2(x0 + 60.0, 13), "BELT TRANSIT CO.", 34)

		# Hangar doors: most closed, a few open on a parked ship, one open for the player
		for bay in _bays_in(car):
			var slot: Vector2 = SLOT_SIZE[bay.cls]
			var door := Rect2(-slot / 2.0, slot)
			var is_open: bool = bay.is_player or bay.number % 3 == 0
			_in_bay(bay)

			if is_open:
				draw_rect(door, OUTLINE)
				draw_rect(door.grow(-TEXEL), DARK.darkened(0.45))
				_draw_bay_contents(bay)
			else:
				_plate(door, LINER_TEAL, 0.3)
				var seam := door.position.x + 40.0

				while seam < door.end.x - 10.0:
					draw_rect(Rect2(seam, door.position.y + 4.0, TEXEL, door.size.y - 8.0), LINER_TEAL.darkened(0.35))
					seam += 40.0

				draw_circle(Vector2(door.position.x + 14.0, 0), 6.0, LIGHT_RED.darkened(0.3))

			_out_of_bay()
			var outer_y: float = signf(bay.xform.origin.y) * (half + (36.0 if bay.xform.origin.y > 0.0 else 10.0))
			_stencil(Vector2(bay.xform.origin.x - 20.0, outer_y), "%02d" % bay.number, 30)

	# Tug in the same livery
	var tug_half := _prow_half - 50.0
	_panels(Rect2(_tug_back, -tug_half, _tug_front - _tug_back, tug_half * 2.0), CREAM, Vector2(160, 120))
	_plate(Rect2(_tug_back, -22, _tug_front - _tug_back, 44), PRIMER, 0.3)
	_plate(Rect2(_tug_back + 60.0, -tug_half + 40.0, 300, 120), LINER_TEAL, 0.3)
	draw_rect(Rect2(_tug_back + 80.0, -tug_half + 70.0, 260, 16), GLASS_DARK)
	draw_rect(Rect2(_tug_back + 80.0, -tug_half + 70.0, 260, 4), GLASS)
	_stencil(Vector2(_tug_back + 60.0, tug_half - 50.0), "BELT TRANSIT CO.", 44)
	_draw_prow(_tug_front, _tug_front + 700.0, _prow_half, LINER_TEAL, LINER_TEAL.lightened(0.12), PRIMER)


# --- C3: pod string


func _layout_pods() -> void:
	for i in _cars.size():
		var car := _cars[i]
		var hub := Vector2((car.x0 + car.x1) / 2.0, 0.0)

		match car.cls:
			"S":
				for degrees in [-135.0, -90.0, -45.0, 45.0, 90.0, 135.0]:
					var angle := deg_to_rad(degrees)
					var is_player: bool = i == 0 and degrees == -90.0
					_add_bay(Transform2D(angle + PI, hub + Vector2.from_angle(angle) * 225.0), "S", is_player, Vector2(-300, 0))
			"M":
				for degrees in [-120.0, -60.0, 60.0, 120.0]:
					var angle := deg_to_rad(degrees)
					_add_bay(Transform2D(angle + PI, hub + Vector2.from_angle(angle) * 320.0), "M", false)
			"L":
				for side: float in [-1.0, 1.0]:
					_add_bay(Transform2D(0.0, hub + Vector2(0, side * 200.0)), "L", false)


func _draw_pods() -> void:
	var spine_from: float = _cars[_cars.size() - 1].x0 - 60.0

	_draw_tug_engines(_prow_half - 120.0, TEAL_GRAY)

	# Truss spine, end to end
	for y in [-30.0, 22.0]:
		_plate(Rect2(spine_from, y, _tug_back - spine_from + 40.0, 8), PIPE_DARK, 0.0)

	var x := spine_from

	while x < _tug_back:
		draw_line(Vector2(x, -24), Vector2(x + 26.0, 24), PIPE, 4.0)
		draw_line(Vector2(x + 26.0, 24), Vector2(x + 52.0, -24), PIPE, 4.0)
		x += 52.0

	for i in _cars.size():
		var car := _cars[i]
		var hub := Vector2((car.x0 + car.x1) / 2.0, 0.0)
		var radius: float = car.half
		var shape: PackedVector2Array = _octagon(hub, radius) if car.cls != "L" else _chamfered(Rect2(car.x0, -radius, car.x1 - car.x0, radius * 2.0), 120.0)

		_polygon_plate(shape, TEAL_GRAY)
		var ring := Geometry2D.offset_polygon(shape, -26.0)

		if not ring.is_empty():
			_polygon_plate(ring[0], TEAL_GRAY.darkened(0.15))

		# Berth slots
		for bay in _bays_in(car):
			var slot: Vector2 = SLOT_SIZE[bay.cls]
			_in_bay(bay)
			draw_rect(Rect2(-slot / 2.0, slot), OUTLINE)
			draw_rect(Rect2(-slot / 2.0, slot).grow(-TEXEL), DARK.darkened(0.3))
			_stripes(Rect2(-slot.x / 2.0, -slot.y / 2.0, 10, slot.y), 12.0)
			_draw_bay_contents(bay)
			_out_of_bay()
			var outward: Vector2 = (bay.xform.origin - hub).normalized() if car.cls != "L" else Vector2(0, signf(bay.xform.origin.y))
			_stencil(bay.xform.origin + outward * (slot.x * 0.5 + 40.0) + Vector2(-18, 10), "%02d" % bay.number, 30)

		# Hub
		var core := _octagon(hub, 110.0 if car.cls != "L" else 90.0)
		_polygon_plate(core, BARE)
		_polygon_plate(_octagon(hub, 50.0), CABIN)
		draw_circle(hub, 16.0, GLASS_DARK)
		_stencil(hub + Vector2(-30, -130 if car.cls != "L" else -12), "POD %d" % (i + 1), 28)

	# Tug: slim, behind a wide plough
	_panels(Rect2(_tug_back, -170, _tug_front - _tug_back, 340), GRAY, Vector2(150, 113))
	_plate(Rect2(_tug_back, -12, _tug_front - _tug_back, 24), TEAL_GRAY, 0.2)
	_draw_bridge(Rect2(_tug_front - 360.0, -130, 260, 260))
	_draw_prow(_tug_front, _tug_front + 760.0, _prow_half, TEAL_GRAY.darkened(0.2), TEAL_GRAY, CREAM)


func _octagon(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()

	for k in 8:
		points.append(center + Vector2.from_angle(TAU * k / 8.0 + PI / 8.0) * radius)

	return points


func _chamfered(rect: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position + Vector2(cut, 0), Vector2(rect.end.x - cut, rect.position.y), Vector2(rect.end.x, rect.position.y + cut),
		Vector2(rect.end.x, rect.end.y - cut), Vector2(rect.end.x - cut, rect.end.y), Vector2(rect.position.x + cut, rect.end.y),
		Vector2(rect.position.x, rect.end.y - cut), Vector2(rect.position.x, rect.position.y + cut),
	])


# A plate that isn't a rectangle: fill, a lighter rim inside, rivets along the edges, outline.
func _polygon_plate(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var rim := Geometry2D.offset_polygon(points, -TEXEL * 2.0)

	if not rim.is_empty():
		var rim_line: PackedVector2Array = rim[0]
		rim_line.append(rim_line[0])
		draw_polyline(rim_line, color.lightened(0.15), TEXEL)

	for k in points.size():
		var from := points[k]
		var to := points[(k + 1) % points.size()]
		var steps := floori(from.distance_to(to) / 10.0)
		var inward := (to - from).orthogonal().normalized()

		for j in steps:
			var at := from.lerp(to, (j + 0.5) / steps) + inward * TEXEL * 3.0
			draw_rect(Rect2(at, Vector2(TEXEL, TEXEL)), color.darkened(0.35))

	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, OUTLINE, TEXEL * 2.0)


# --- C4: scrap convoy


func _layout_scrap() -> void:
	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var middle: float = (car.x0 + car.x1) / 2.0

		match car.cls:
			"S":
				for slot_index in 2:
					for side: float in [-1.0, 1.0]:
						var is_player := i == 0 and slot_index == 1 and side < 0.0
						_add_bay(Transform2D(0.0, Vector2(x0 + 200.0 + slot_index * 360.0, side * 215.0)), "S", is_player)
			"M":
				for side: float in [-1.0, 1.0]:
					_add_bay(Transform2D(0.0, Vector2(middle, side * 140.0)), "M", false)
			"L":
				_add_bay(Transform2D(0.0, Vector2(middle, 0.0)), "L", false)


func _draw_scrap() -> void:
	# Engines don't match: one big, one small
	_draw_plume(Vector2(-130, -_prow_half - 40.0), 56.0, 340.0)
	_draw_plume(Vector2(-100, _prow_half + 30.0), 36.0, 220.0)
	_plate(Rect2(-10, -_prow_half - 110.0, 300, 140), RUST, 1.2)
	_draw_bell(Vector2(-10, -_prow_half - 40.0), Vector2(-130, -_prow_half - 40.0), 40.0, 56.0)
	_plate(Rect2(-10, _prow_half - 20.0, 220, 100), BARE, 1.2)
	_draw_bell(Vector2(-10, _prow_half + 30.0), Vector2(-100, _prow_half + 30.0), 26.0, 36.0)

	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var x1: float = car.x1

		# Tow cables to the car ahead, with some slack
		var ahead_x := _tug_back if i == 0 else float(_cars[i - 1].x0)

		for y in [-50.0, 0.0, 50.0]:
			var cable := PackedVector2Array()

			for k in 13:
				var t := k / 12.0
				cable.append(Vector2(lerpf(x1, ahead_x, t), y + sin(t * PI) * 18.0 * signf(y + 0.1)))

			draw_polyline(cable, OUTLINE, 8.0)
			draw_polyline(cable, PIPE_DARK, 4.0)

		match car.cls:
			"S":
				_draw_tanker(car)
			"M":
				_draw_gutted_freighter(car)
			"L":
				_draw_barge(car)

		for bay in _bays_in(car):
			var slot: Vector2 = SLOT_SIZE[bay.cls]
			_in_bay(bay)
			_draw_bay_contents(bay)
			_out_of_bay()
			var bay_y: float = bay.xform.origin.y
			var label_y := -slot.y / 2.0 - 14.0 if bay_y <= 0.0 else slot.y / 2.0 + 40.0
			_stencil(bay.xform.origin + Vector2(-slot.x / 2.0, label_y), "%02d" % bay.number, 28)

	# Tug: patched everywhere, a bare replacement plough
	_rng.seed = 5
	_panels(Rect2(_tug_back, -_prow_half + 80.0, _tug_front - _tug_back, (_prow_half - 80.0) * 2.0), RUST, Vector2(110, 90))

	for k in 6:
		var patch := Rect2(_tug_back + _rng.randf_range(40, _tug_front - 160.0), _rng.randf_range(-_prow_half + 100.0, _prow_half - 180.0), _rng.randf_range(60, 140), _rng.randf_range(40, 90))
		_plate(patch, [PRIMER, BARE, GRAY][k % 3], 1.5)

	_draw_bridge(Rect2(_tug_back + 60.0, -140, 240, 280))
	draw_line(Vector2(_tug_back + 284.0, -80), Vector2(_tug_back + 292.0, -20), Color.WHITE.darkened(0.2), 2.0) # Cracked pane
	_draw_prow(_tug_front, _tug_front + 640.0, _prow_half, BARE.darkened(0.25), BARE, RUST)


# An old tanker hull: a capsule with ribs and valves, docking arms bolted to its sides.
func _draw_tanker(car: Dictionary) -> void:
	var x0: float = car.x0
	var x1: float = car.x1
	var body := _chamfered(Rect2(x0, -120, x1 - x0, 240), 60.0)

	_polygon_plate(body, RUST)

	# Docking arms bolted on, reaching under each ship
	for bay in _bays_in(car):
		var at: Vector2 = bay.xform.origin
		var side := signf(at.y)

		for dx in [-70.0, 60.0]:
			var from := Vector2(at.x + dx, side * 104.0)
			var to := Vector2(at.x + dx, at.y + side * 10.0)
			draw_line(from, to, OUTLINE, 22.0)
			draw_line(from, to, PIPE, 14.0)
			draw_line(from, to, PIPE_DARK, 4.0)
			_plate(Rect2(from + Vector2(-16, -10), Vector2(32, 20)), PIPE_DARK, 0.0)
	var x := x0 + 70.0

	while x < x1 - 60.0:
		draw_rect(Rect2(x, -112, 6, 224), RUST.darkened(0.25))
		x += 48.0

	for k in 3:
		var patch_x := x0 + 120.0 + k * 210.0
		draw_rect(Rect2(patch_x, -60 + k * 30.0, 70, 40), PRIMER)

	for valve_x in [x0 + 160.0, x1 - 180.0]:
		draw_circle(Vector2(valve_x, 0), 22.0, OUTLINE)
		draw_circle(Vector2(valve_x, 0), 18.0, PIPE_DARK)
		draw_rect(Rect2(valve_x - 18.0, -3, 36, 6), PIPE)


# A freighter stripped to its ribs: side girders, ribs (some missing), a tarp, ships inside.
func _draw_gutted_freighter(car: Dictionary) -> void:
	var x0: float = car.x0
	var x1: float = car.x1
	var half: float = car.half
	var rib_index := 0
	var x := x0 + 40.0

	while x < x1 - 40.0:
		if rib_index % 5 != 3:
			_plate(Rect2(x, -half, 14, half * 2.0), BARE.darkened(0.15), 0.6)

		x += 70.0
		rib_index += 1

	_plate(Rect2(x0, -half, x1 - x0, 26), BARE, 0.8)
	_plate(Rect2(x0, half - 26.0, x1 - x0, 26), BARE, 0.8)
	_plate(Rect2(x0, -half, 40, half * 2.0), RUST, 0.8)
	_plate(Rect2(x1 - 60.0, -half, 60, half * 2.0), RUST, 0.8)
	_plate(Rect2(x0 + 40.0, -24, x1 - x0 - 100.0, 48), DARK, 0.5)

	# Tarp lashed over the stern end
	var tarp := Rect2(x0 + 50.0, -half + 30.0, 140, half * 2.0 - 60.0)
	_plate(tarp, CANVAS, 1.0)

	for k in 4:
		var rope_y := tarp.position.y + (k + 0.5) * tarp.size.y / 4.0
		draw_line(Vector2(tarp.position.x - 6.0, rope_y), Vector2(tarp.end.x + 6.0, rope_y + 10.0), PIPE_DARK, 3.0)


# A flat barge deck with tie-down ropes and tarped crates in the corners.
func _draw_barge(car: Dictionary) -> void:
	var x0: float = car.x0
	var x1: float = car.x1
	var half: float = car.half
	_panels(Rect2(x0, -half, x1 - x0, half * 2.0), BARE.darkened(0.12), Vector2(120, 104))
	_stripes(Rect2(x0, -half, x1 - x0, 10), 20.0)
	_stripes(Rect2(x0, half - 10.0, x1 - x0, 10), 20.0)

	for corner in [Vector2(x0 + 20.0, -half + 20.0), Vector2(x1 - 120.0, half - 90.0)]:
		_plate(Rect2(corner, Vector2(100, 70)), CANVAS, 1.0)

	for bay in _bays_in(car):
		var at: Vector2 = bay.xform.origin
		var ship_size: Vector2 = SHIP_SIZE[bay.cls]

		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var deck_point := Vector2(at.x + corner.x * (ship_size.x / 2.0 + 20.0), corner.y * (half - 16.0))
			var hull_point: Vector2 = at + corner * ship_size * 0.35
			draw_line(deck_point, hull_point, PIPE_DARK, 4.0)
