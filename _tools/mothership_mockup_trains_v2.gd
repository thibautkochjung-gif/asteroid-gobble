extends "res://_tools/mothership_mockup_trains.gd"

# Round 3: the C1 flatbeds (now lashed down) and the C2 liner wagons, with locomotives that
# aren't wedges. Same small / medium / large car classes as before. Mockup only.
# - D1 flatbed freight + dozer blade: a wide curved blade on hydraulic rams
# - D2 flatbed freight + gobbler: crusher jaws that eat the rocks and spit gravel
# - D3 hangar liner + drum cutters: mining-shearer drums that grind a lane
# - D4 hangar liner + deflector: emitters projecting a field that shoves rocks aside

const SKY := Color(0.55, 0.85, 0.95)
const HOT := Color(1.0, 0.55, 0.2)
const STRAP := Color(0.78, 0.45, 0.12)
const FIN := Color(0.59, 0.38, 0.27)

var _body_color := GRAY
var _trim_color := DARK
var _accent_color := STRIPE
var _loco_half: float = 200.0
var _loco_name: String = ""


func _ready() -> void:
	match concept:
		"D1", "D2":
			_build({ "S": 680.0, "M": 560.0, "L": 960.0 }, { "S": 170.0, "M": 250.0, "L": 200.0 }, 110.0, 900.0)
			_layout_flatbeds()
			_body_color = STRIPE.darkened(0.12)
			_trim_color = DARK
			_accent_color = STRIPE
			_loco_half = 200.0
			_loco_name = "HAULER 7" if concept == "D1" else "GOBBLER 2"
		"D3", "D4":
			_build({ "S": 940.0, "M": 1000.0, "L": 980.0 }, { "S": 210.0, "M": 270.0, "L": 420.0 }, 90.0, 960.0)
			_layout_liner()
			_body_color = CREAM
			_trim_color = LINER_TEAL
			_accent_color = PRIMER
			_loco_half = 240.0
			_loco_name = "BT-07 MERIDIAN" if concept == "D3" else "BT-12 HALCYON"

	_extent = _extent.expand(Vector2(_tug_front + 900.0, 0))


func _draw() -> void:
	_rng.seed = 11

	if concept == "D1" or concept == "D2":
		_draw_lashed_flatbeds()
	else:
		_draw_liner_cars()

	_draw_loco()

	match concept:
		"D1":
			_draw_dozer()
		"D2":
			_draw_gobbler()
		"D3":
			_draw_drums()
		"D4":
			_draw_deflector()


# --- Wagons


func _draw_lashed_flatbeds() -> void:
	var frame := STRIPE.darkened(0.12)

	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var x1: float = car.x1
		var half: float = car.half

		var ahead_x := _tug_back if i == 0 else float(_cars[i - 1].x0)
		_plate(Rect2(x1 - 10.0, -16, ahead_x - x1 + 20.0, 32), DARK, 0.2)
		draw_circle(Vector2((x1 + ahead_x) / 2.0, 0), 14.0, PIPE_DARK)

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

		for bay in _bays_in(car):
			var slot: Vector2 = SLOT_SIZE[bay.cls]
			_in_bay(bay)

			for saddle_x in [-slot.x * 0.28, slot.x * 0.22]:
				_plate(Rect2(saddle_x - 14.0, -slot.y / 2.0, 28, slot.y), PIPE_DARK, 0.2)

			_draw_bay_contents(bay)
			_draw_lashing(bay)
			_out_of_bay()
			var bay_y: float = bay.xform.origin.y
			_bay_number(bay, Vector2(-slot.x / 2.0 + 10.0, -half - 12.0 - bay_y if bay_y <= 0.0 else half + 40.0 - bay_y))

		_stencil(Vector2(x0 + 40.0, half + 100.0), "%s-CLASS FLAT %d" % [car.cls, i + 1], 30)


# Winches on the frame, cables to the hull, ratchet straps over it, clamp pads on its flanks.
# The player's empty bay: clamps open, straps hanging loose, cables reeled in.
func _draw_lashing(bay: Dictionary) -> void:
	var slot: Vector2 = SLOT_SIZE[bay.cls]
	var ship: Vector2 = SHIP_SIZE[bay.cls]
	var half_slot := slot / 2.0
	var half_ship := ship / 2.0
	var is_empty: bool = bay.is_player
	var scale_factor := ship.x / 230.0

	# Clamp arms from the frame to the flanks
	for x_ratio in [-0.3, 0.12]:
		for side: float in [-1.0, 1.0]:
			var x: float = ship.x * x_ratio
			var reach := half_ship.y * 0.92 if not is_empty else half_slot.y - 16.0
			var from_y := side * half_slot.y
			var to_y := side * reach
			_plate(Rect2(x - 7.0, minf(from_y, to_y), 14, absf(to_y - from_y)), PIPE_DARK, 0.0)
			_plate(Rect2(x - 16.0, to_y - (0.0 if side > 0.0 else 8.0), 32, 8), DARK, 0.0)

	# Winches at the corners, cables to the hull
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

	# Ratchet straps over the hull, or hanging off one side when empty
	for x_ratio in [-0.08, 0.3]:
		var x: float = ship.x * x_ratio
		var width := 8.0 * clampf(scale_factor, 1.0, 2.0)

		if is_empty:
			draw_rect(Rect2(x - width / 2.0, -half_slot.y, width, 26), OUTLINE)
			draw_rect(Rect2(x - width / 2.0 + 2.0, -half_slot.y, width - 4.0, 24), STRAP)
		else:
			draw_rect(Rect2(x - width / 2.0, -half_slot.y + 4.0, width, slot.y - 8.0), OUTLINE)
			draw_rect(Rect2(x - width / 2.0 + 2.0, -half_slot.y + 4.0, width - 4.0, slot.y - 8.0), STRAP)
			draw_rect(Rect2(x - width / 2.0 - 2.0, half_ship.y + 4.0, width + 4.0, 10), STRIPE_DARK)
			draw_rect(Rect2(x - width / 2.0, half_ship.y + 6.0, width, 6), STRIPE)


func _draw_liner_cars() -> void:
	for i in _cars.size():
		var car := _cars[i]
		var x0: float = car.x0
		var x1: float = car.x1
		var half: float = car.half

		var ahead_x := _tug_back if i == 0 else float(_cars[i - 1].x0)
		var x := x1

		while x < ahead_x:
			draw_rect(Rect2(x, -70, 6, 140), DARK if int((x - x1) / 6.0) % 2 == 0 else GRAY)
			x += 6.0

		draw_rect(Rect2(x1, -72, ahead_x - x1, 2), OUTLINE)
		draw_rect(Rect2(x1, 70, ahead_x - x1, 2), OUTLINE)

		_panels(Rect2(x0, -half, x1 - x0, half * 2.0), CREAM, Vector2(160, 120))
		_plate(Rect2(x0, -22, x1 - x0, 44), PRIMER, 0.3)
		draw_rect(Rect2(x0 + 2.0, -30, x1 - x0 - 4.0, 4), LINER_TEAL)
		draw_rect(Rect2(x0 + 2.0, 26, x1 - x0 - 4.0, 4), LINER_TEAL)

		if car.cls == "S":
			_stencil(Vector2(x0 + 60.0, 13), "BELT TRANSIT CO.", 34)

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


# --- Locomotive body: one hull, big plates and machinery, in the train's livery


func _draw_loco() -> void:
	var length := _tug_front - _tug_back
	var half := _loco_half
	var nacelle_y := _prow_half - 40.0

	# Engine nacelles outboard, so the plumes pass beside the cars
	for side: float in [-1.0, 1.0]:
		var y := side * nacelle_y
		_draw_plume(Vector2(-110, y), 50.0, 340.0)

		# Pylon: two beams and a brace
		for beam_x in [200.0, 330.0]:
			_plate(Rect2(beam_x, minf(side * half * 0.8, y), 22, absf(y - side * half * 0.8)), _trim_color, 0.2)

		draw_line(Vector2(222, side * half * 0.85), Vector2(330, y - side * 50.0), PIPE, 6.0)

		var nacelle := Rect2(20, y - 62.0, 460, 124)
		_smooth_plate(nacelle, _trim_color)
		draw_rect(Rect2(nacelle.position.x + 30.0, y - 4.0, nacelle.size.x - 80.0, 8), _accent_color)
		_draw_intake(Vector2(nacelle.end.x, y), 58.0)
		_draw_bell(Vector2(20, y), Vector2(-110, y), 40.0, 56.0)

		for k in 5:
			draw_rect(Rect2(nacelle.position.x + 60.0 + k * 22.0, y - 52.0 if side < 0.0 else y + 40.0, 12, 12), _trim_color.darkened(0.4))

	# Hull: chamfered outline, a few long plates, no brickwork
	var hull := PackedVector2Array([
		Vector2(0, -half * 0.72), Vector2(70, -half), Vector2(length - 140.0, -half), Vector2(length, -half * 0.74),
		Vector2(length, half * 0.74), Vector2(length - 140.0, half), Vector2(70, half), Vector2(0, half * 0.72),
	])
	draw_colored_polygon(hull, _body_color)

	for seam_y in [-half * 0.5, half * 0.5]:
		draw_rect(Rect2(40, seam_y - 1.0, length - 80.0, TEXEL), _body_color.darkened(0.25))
		_rivet_row(Vector2(60, seam_y - 6.0), Vector2(length - 60.0, seam_y - 6.0), _body_color)

	for seam_x in [length * 0.22, length * 0.47, length * 0.66]:
		draw_rect(Rect2(seam_x, -half + 6.0, TEXEL, half * 2.0 - 12.0), _body_color.darkened(0.25))

	_grime(Rect2(80, -half * 0.9, length - 240.0, half * 1.8), int(length * half / 500.0))

	# A couple of replaced plates
	_plate(Rect2(length * 0.24, half * 0.12, 120, 70), _body_color.darkened(0.1), 0.6)
	_plate(Rect2(length * 0.49, -half * 0.45, 90, 60), _body_color.lightened(0.06), 0.6)

	# Spine trench with a pipe bundle
	_smooth_plate(Rect2(30, -24, length - 220.0, 48), _trim_color)

	for k in 3:
		var pipe_y := -14.0 + k * 12.0
		draw_rect(Rect2(36, pipe_y, length - 232.0, 8), OUTLINE)
		draw_rect(Rect2(36, pipe_y + 2.0, length - 232.0, 4), [PIPE, NOZZLE, PIPE_DARK][k])

	var clamp_x := 70.0

	while clamp_x < length - 200.0:
		draw_rect(Rect2(clamp_x, -24, 6, 48), OUTLINE)
		clamp_x += 70.0

	# Reactor dome
	var dome := Vector2(length * 0.33, -half * 0.5)
	draw_circle(dome, 74.0, OUTLINE)
	draw_circle(dome, 70.0, _trim_color)
	draw_circle(dome, 54.0, _trim_color.lightened(0.12))
	draw_circle(dome, 30.0, OUTLINE)
	draw_circle(dome, 26.0, SKY.darkened(0.3))
	draw_circle(dome, 14.0, SKY)

	for k in 12:
		draw_rect(Rect2(dome + Vector2.from_angle(TAU * k / 12.0) * 62.0 - Vector2(2, 2), Vector2(4, 4)), _trim_color.darkened(0.4))

	# Radiator banks
	for bank_x in [length * 0.1, length * 0.4]:
		var bank := Rect2(bank_x, half * 0.56, length * 0.22, half * 0.36)
		draw_rect(bank, OUTLINE)
		draw_rect(bank.grow(-TEXEL), DARK)
		var fin_x := bank.position.x + 6.0

		while fin_x < bank.end.x - 6.0:
			draw_rect(Rect2(fin_x, bank.position.y + 4.0, TEXEL * 2.0, bank.size.y - 8.0), FIN)
			fin_x += TEXEL * 5.0

	# Tanks
	for tank_y in [-half * 0.86, -half * 0.62]:
		_draw_tank(Rect2(length * 0.5, tank_y, length * 0.16, 40), _trim_color.lightened(0.2))

	# Vents with hazard frames near the back
	for k in 3:
		var vent := Rect2(40 + k * 50.0, -half * 0.42, 34, 56)
		_stripes(vent, 8.0)
		draw_rect(vent.grow(-6), DARK.darkened(0.3))

	# Cab up front: window band facing forward, side windows, mast and dish
	var cab := Rect2(length - 260.0, -half * 0.56, 190, half * 1.12)
	_smooth_plate(cab, _trim_color)
	var glass := Rect2(cab.end.x - 22.0, cab.position.y + 16.0, 14, cab.size.y - 32.0)
	draw_rect(glass.grow(TEXEL), OUTLINE)
	draw_rect(glass, GLASS_DARK)
	draw_rect(Rect2(glass.position.x, glass.position.y, TEXEL * 2.0, glass.size.y), GLASS)

	for k in 4:
		draw_rect(Rect2(cab.position.x + 20.0 + k * 34.0, cab.position.y + 8.0, 20, 8), GLASS_DARK)
		draw_rect(Rect2(cab.position.x + 20.0 + k * 34.0, cab.end.y - 16.0, 20, 8), GLASS_DARK)

	var mast := Vector2(cab.position.x + 50.0, 0)
	draw_line(mast, mast + Vector2(-80, -40), PIPE, 4.0)
	draw_circle(mast + Vector2(-80, -40), 6.0, LIGHT_RED)
	draw_arc(Vector2(cab.position.x + 110.0, half * 0.18), 30.0, -PI * 0.2, PI * 1.2, 12, NOZZLE, 6.0)

	# Name, lights, outline
	_stencil(Vector2(length * 0.5, half * 0.42), _loco_name, 40)
	var outline := hull.duplicate()
	outline.append(hull[0])
	draw_polyline(outline, OUTLINE, TEXEL * 2.0)

	for corner in [Vector2(70, -half), Vector2(70, half)]:
		draw_circle(corner + Vector2(10, 10 * -signf(corner.y)), 7.0, LIGHT_RED)


func _smooth_plate(rect: Rect2, color: Color) -> void:
	draw_rect(rect, OUTLINE)
	var inner := rect.grow(-TEXEL)
	draw_rect(inner, color)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, TEXEL)), color.lightened(0.2))
	draw_rect(Rect2(inner.position.x, inner.end.y - TEXEL, inner.size.x, TEXEL), color.darkened(0.3))
	_rivet_row(inner.position + Vector2(TEXEL, TEXEL), Vector2(inner.end.x - TEXEL, inner.position.y + TEXEL), color)
	_rivet_row(Vector2(inner.position.x + TEXEL, inner.end.y - TEXEL * 2.0), Vector2(inner.end.x - TEXEL, inner.end.y - TEXEL * 2.0), color)


func _rivet_row(from: Vector2, to: Vector2, color: Color) -> void:
	var x := from.x

	while x < to.x:
		draw_rect(Rect2(x, from.y, TEXEL, TEXEL), color.darkened(0.35))
		x += TEXEL * 6.0


func _draw_tank(rect: Rect2, color: Color) -> void:
	var radius := rect.size.y / 2.0
	draw_circle(Vector2(rect.position.x, rect.get_center().y), radius + TEXEL, OUTLINE)
	draw_circle(Vector2(rect.end.x, rect.get_center().y), radius + TEXEL, OUTLINE)
	draw_rect(rect.grow(TEXEL), OUTLINE)
	draw_circle(Vector2(rect.position.x, rect.get_center().y), radius, color)
	draw_circle(Vector2(rect.end.x, rect.get_center().y), radius, color)
	draw_rect(rect, color)
	draw_rect(Rect2(rect.position.x, rect.position.y + 6.0, rect.size.x, 4), color.lightened(0.25))

	for k in 3:
		draw_rect(Rect2(rect.position.x + rect.size.x * (k + 1) / 4.0, rect.position.y, TEXEL * 2.0, rect.size.y), color.darkened(0.3))


func _draw_intake(center: Vector2, radius: float) -> void:
	draw_rect(Rect2(center.x - 10.0, center.y - radius, 20, radius * 2.0), OUTLINE)
	draw_rect(Rect2(center.x - 8.0, center.y - radius + TEXEL, 16, radius * 2.0 - TEXEL * 2.0), NOZZLE)
	draw_rect(Rect2(center.x - 4.0, center.y - radius * 0.7, 8, radius * 1.4), ENGINE_INSIDE)


# --- D1: dozer blade


func _draw_dozer() -> void:
	var front := _tug_front
	var half := _prow_half + 20.0
	var face := PackedVector2Array()
	var back := PackedVector2Array()

	for k in 25:
		var y := lerpf(-half, half, k / 24.0)
		var bulge := 380.0 - 170.0 * pow(y / half, 2.0)
		face.append(Vector2(front + bulge, y))
		back.append(Vector2(front + bulge - 56.0, y))

	# Hydraulic rams from the cab front to the blade
	for ram_y in [-half * 0.7, -half * 0.25, half * 0.25, half * 0.7]:
		var blade_x := front + 380.0 - 170.0 * pow(ram_y / half, 2.0) - 56.0
		var mount_y := clampf(ram_y, -_loco_half * 0.7, _loco_half * 0.7)
		draw_line(Vector2(front - 10.0, mount_y), Vector2(blade_x, ram_y), OUTLINE, 26.0)
		draw_line(Vector2(front - 10.0, mount_y), Vector2(blade_x, ram_y), PIPE_DARK, 20.0)
		var middle := Vector2(front - 10.0, mount_y).lerp(Vector2(blade_x, ram_y), 0.55)
		draw_line(middle, Vector2(blade_x, ram_y), NOZZLE, 10.0)

	var blade := face.duplicate()
	back.reverse()
	blade.append_array(back)
	draw_colored_polygon(blade, _trim_color)

	# Wear plates along the cutting edge, hazard band behind it
	for k in 24:
		var a := face[k]
		var b := face[k + 1]
		var inward := Vector2(-18, 0)
		var plate := PackedVector2Array([a, b, b + inward, a + inward])
		draw_colored_polygon(plate, NOZZLE if k % 2 == 0 else BARE)

		var stripe := PackedVector2Array([a + Vector2(-26, 0), b + Vector2(-26, 0), b + Vector2(-38, 0), a + Vector2(-38, 0)])
		draw_colored_polygon(stripe, STRIPE if k % 2 == 0 else STRIPE_DARK)

	for k in range(2, 23, 4):
		draw_line(face[k] + Vector2(-44, 0), face[k] + Vector2(-56, 0), OUTLINE, 6.0)

	blade.append(blade[0])
	draw_polyline(blade, OUTLINE, TEXEL * 2.0)

	# End plates
	for side: float in [-1.0, 1.0]:
		var end := face[0] if side < 0.0 else face[24]
		_smooth_plate(Rect2(end.x - 70.0, end.y - (20.0 if side < 0.0 else 0.0), 80, 20), _trim_color.darkened(0.2))
		draw_circle(end + Vector2(-30, side * -10.0), 6.0, LIGHT_RED if side < 0.0 else LIGHT_GREEN)


# --- D2: gobbler


func _draw_gobbler() -> void:
	var front := _tug_front
	var half := _prow_half + 10.0

	# Gravel chute on the flank, spitting crushed rock to the side
	var chute_from := Vector2(_tug_front * 0.62, _loco_half)
	draw_line(chute_from, chute_from + Vector2(-60, 120), OUTLINE, 34.0)
	draw_line(chute_from, chute_from + Vector2(-60, 120), PIPE_DARK, 26.0)

	for k in 40:
		var t := _rng.randf()
		var at := chute_from + Vector2(-60, 120) + Vector2(-t * 260.0, t * 200.0) + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30)) * t
		draw_rect(Rect2(at, Vector2(4, 4) * (1.0 + _rng.randf())), BARE.darkened(_rng.randf() * 0.4))

	# Conveyor from the crusher into the hopper
	var belt := Rect2(front - 240.0, -44, 330, 88)
	draw_rect(belt, OUTLINE)
	draw_rect(belt.grow(-4), DARK)
	var x := belt.position.x + 6.0

	while x < belt.end.x - 10.0:
		draw_line(Vector2(x, -40), Vector2(x + 14.0, 40), PIPE_DARK, 4.0)
		x += 20.0

	for k in 6:
		var chunk := Vector2(belt.position.x + 40.0 + k * 48.0, _rng.randf_range(-24, 24))
		draw_rect(Rect2(chunk, Vector2(14, 10)), [BARE, GRAY, RUST][k % 3])

	# Hopper with the furnace glow
	var hopper := Rect2(front - 420.0, -110, 170, 220)
	_smooth_plate(hopper, _trim_color)

	for k in 4:
		draw_rect(Rect2(hopper.position.x + 20.0 + k * 36.0, -70, 18, 140), OUTLINE)
		draw_rect(Rect2(hopper.position.x + 22.0 + k * 36.0, -66, 14, 132), HOT if k % 2 == 0 else HOT.darkened(0.3))

	# Jaws, opening forward
	for side: float in [-1.0, 1.0]:
		var jaw := PackedVector2Array([
			Vector2(front - 20.0, side * _loco_half * 0.55), Vector2(front + 520.0, side * half),
			Vector2(front + 560.0, side * (half - 50.0)), Vector2(front + 60.0, side * _loco_half * 0.25),
		])
		_polygon_plate(jaw, _trim_color)
		var stripe_from := Vector2(front + 120.0, side * (_loco_half * 0.36))
		var stripe_to := Vector2(front + 520.0, side * (half - 30.0))
		var along := (stripe_to - stripe_from) / 14.0

		for k in 14:
			var a := stripe_from + along * k
			draw_line(a, a + along, STRIPE if k % 2 == 0 else STRIPE_DARK, 10.0)

		# Teeth on the inner edge
		var inner_from := Vector2(front + 60.0, side * _loco_half * 0.25)
		var inner_to := Vector2(front + 560.0, side * (half - 50.0))

		for k in 10:
			var base := inner_from.lerp(inner_to, (k + 0.5) / 10.0)
			var tooth := PackedVector2Array([base + Vector2(-10, 0), base + Vector2(0, -side * 22.0), base + Vector2(10, 0)])
			draw_colored_polygon(tooth, NOZZLE)

	# Crusher rollers at the throat
	for side: float in [-1.0, 1.0]:
		var hub := Vector2(front + 150.0, side * 70.0)
		draw_circle(hub, 76.0, OUTLINE)
		draw_circle(hub, 72.0, ENGINE)

		for k in 14:
			var direction := Vector2.from_angle(TAU * k / 14.0 + (0.1 if side > 0.0 else 0.0))
			draw_line(hub + direction * 56.0, hub + direction * 84.0, NOZZLE, 8.0)

		draw_circle(hub, 40.0, ENGINE.lightened(0.15))
		draw_circle(hub, 14.0, OUTLINE)

	# A rock going in
	for k in 7:
		var bit := Vector2(front + 320.0 + _rng.randf_range(-50, 80), _rng.randf_range(-60, 60))
		draw_rect(Rect2(bit, Vector2(16, 16) * (0.6 + _rng.randf())), BARE.darkened(0.2))


# --- D3: drum cutters


func _draw_drums() -> void:
	var front := _tug_front
	var half := _prow_half + 20.0
	var drums := [
		Rect2(front + 300.0, -half * 0.56, 110, half * 1.12),
		Rect2(front + 150.0, -half, 110, half * 0.5),
		Rect2(front + 150.0, half * 0.5, 110, half * 0.5),
	]

	# Booms from the hull to the drum hubs
	for drum: Rect2 in drums:
		var hub := Vector2(drum.position.x + 20.0, drum.get_center().y)
		var mount := Vector2(front - 30.0, clampf(hub.y, -_loco_half * 0.6, _loco_half * 0.6))
		draw_line(mount, hub, OUTLINE, 44.0)
		draw_line(mount, hub, _trim_color, 36.0)
		draw_line(mount, hub, _accent_color, 6.0)

	# Dust kicked up ahead
	for k in 60:
		var at := Vector2(front + _rng.randf_range(260, 560), _rng.randf_range(-half, half))
		draw_rect(Rect2(at, Vector2(3, 3) * (1.0 + _rng.randf() * 2.0)), Color(BARE, 0.5))

	for drum: Rect2 in drums:
		draw_rect(drum.grow(TEXEL * 2.0), OUTLINE)
		draw_rect(drum, ENGINE)
		draw_rect(Rect2(drum.position.x, drum.position.y, drum.size.x, 6), ENGINE.lightened(0.15))

		# Helical pick lines, picks sticking out at the front edge
		var y := drum.position.y - drum.size.x

		while y < drum.end.y:
			var from := Vector2(drum.position.x, maxf(y, drum.position.y))
			var to := Vector2(drum.end.x, minf(y + drum.size.x, drum.end.y))
			draw_line(from, to, NOZZLE.darkened(0.2), 6.0)
			y += 48.0

		var pick_y := drum.position.y + 12.0

		while pick_y < drum.end.y - 6.0:
			var tip := PackedVector2Array([Vector2(drum.end.x, pick_y - 7.0), Vector2(drum.end.x + 18.0, pick_y), Vector2(drum.end.x, pick_y + 7.0)])
			draw_colored_polygon(tip, NOZZLE)
			pick_y += 32.0

		# Gearbox caps at both ends, in livery
		for cap_y in [drum.position.y - 26.0, drum.end.y + 2.0]:
			_smooth_plate(Rect2(drum.position.x - 10.0, cap_y, drum.size.x + 20.0, 24), _trim_color)
			draw_rect(Rect2(drum.position.x + 10.0, cap_y + 8.0, drum.size.x - 20.0, 8), _accent_color)


# --- D4: deflector


func _draw_deflector() -> void:
	var front := _tug_front
	var half := _prow_half + 40.0
	var center := Vector2(front + 40.0, 0)
	var radius := half * 1.05
	var arc_from := -PI * 0.42
	var arc_to := PI * 0.42

	# The field: a soft band ahead of the emitter ring, with a brighter rim
	var field := PackedVector2Array()
	var steps := 40

	for k in steps + 1:
		var angle := lerpf(arc_from, arc_to, float(k) / steps)
		field.append(center + Vector2.from_angle(angle) * (radius + 120.0))

	for k in range(steps, -1, -1):
		var angle := lerpf(arc_from, arc_to, float(k) / steps)
		field.append(center + Vector2.from_angle(angle) * (radius + 10.0))

	draw_colored_polygon(field, Color(SKY, 0.16))
	var rim := PackedVector2Array()

	for k in steps + 1:
		rim.append(center + Vector2.from_angle(lerpf(arc_from, arc_to, float(k) / steps)) * (radius + 120.0))

	draw_polyline(rim, Color(SKY, 0.7), 4.0)

	for k in range(0, steps, 3):
		var angle := lerpf(arc_from, arc_to, float(k) / steps)
		draw_line(center + Vector2.from_angle(angle) * (radius + 30.0), center + Vector2.from_angle(angle) * (radius + 110.0), Color(SKY, 0.25), 2.0)

	# Emitter ring: a curved truss with seven pylons
	var ring := PackedVector2Array()

	for k in steps + 1:
		ring.append(center + Vector2.from_angle(lerpf(arc_from, arc_to, float(k) / steps)) * radius)

	draw_polyline(ring, OUTLINE, 22.0)
	draw_polyline(ring, _trim_color, 16.0)
	draw_polyline(ring, _accent_color, 4.0)

	for k in 7:
		var angle := lerpf(arc_from, arc_to, k / 6.0)
		var at := center + Vector2.from_angle(angle) * radius
		var out := Vector2.from_angle(angle)
		draw_line(at - out * 10.0, at + out * 34.0, OUTLINE, 22.0)
		draw_line(at - out * 10.0, at + out * 30.0, _body_color, 16.0)
		draw_circle(at + out * 36.0, 14.0, OUTLINE)
		draw_circle(at + out * 36.0, 11.0, SKY.darkened(0.2))
		draw_circle(at + out * 36.0, 6.0, Color.WHITE)

	# Struts back to the cab
	for k in [1, 3, 5]:
		var angle := lerpf(arc_from, arc_to, k / 6.0)
		var at := center + Vector2.from_angle(angle) * radius
		var mount := Vector2(front - 20.0, clampf(at.y, -_loco_half * 0.6, _loco_half * 0.6))
		draw_line(mount, at, OUTLINE, 18.0)
		draw_line(mount, at, _trim_color, 12.0)

	# Rock fragments being pushed off the field's edge
	for k in 5:
		var angle := lerpf(arc_from, arc_to, _rng.randf())
		var at := center + Vector2.from_angle(angle) * (radius + 140.0 + _rng.randf() * 60.0)
		draw_rect(Rect2(at, Vector2(18, 14)), BARE.darkened(0.2))
		draw_line(at, at + Vector2.from_angle(angle) * 40.0, Color(SKY, 0.4), 2.0)
