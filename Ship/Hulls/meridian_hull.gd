@tool
class_name MeridianHull
extends HullArt

# Draws the Meridian Commuter: a corporate fleet hull, clean and symmetric, in two-tone paint.
# - The body: one chamfered outline built from the Outline exports, so its proportions can be tuned in
#   the inspector. Pale bow, slate stern (split at paint_split_x), darker pontoons along both flanks.
# - The pontoons: rivet rows, a navy pinstripe, and the registration plate on the left one.
# - The mouth: a recess in the nose, the hangar's hold, with navy and white stripes. Its size comes from
#   the hangar's intake rectangle, like on the Crab.
# - The bridge canopy, right behind the mouth.
# - A mount plate under every hardpoint.
# - The stern block, with one bell per main engine.
# Much less grime than the Garrow hulls: Meridian ships get serviced.
# Visuals only, like every HullArt: the collision shapes are set by hand in the scene.

@export var intake: Area2D # The hangar's hold. Its rectangle shape is the mouth
@export var hardpoints: Node2D # Each hardpoint gets a mount plate
@export var main_engines: Array[Node2D] = [] # Each one gets a bell from the stern

@export_group("Outline")
@export var nose_x: float = 112.0
@export var nose_half_width: float = 32.0
@export var shoulder_x: float = 96.0 # Where the nose's chamfer starts
@export var body_half_width: float = 42.0
@export var pontoon_front_x: float = 56.0
@export var pontoon_chamfer: float = 8.0
@export var pontoon_back_x: float = -88.0
@export var pontoon_half_width: float = 54.0
@export var stern_shoulder_x: float = -112.0
@export var stern_x: float = -122.0
@export var stern_half_width: float = 32.0

@export_group("Paint")
@export var bow_color: Color = Color(0.68, 0.74, 0.79)
@export var stern_color: Color = Color(0.33, 0.39, 0.46)
@export var paint_split_x: float = 12.0 # Bow colour ahead of this line, stern colour behind it
@export var pontoon_color: Color = Color(0.25, 0.3, 0.36)
@export var pinstripe_color: Color = Color(0.17, 0.3, 0.47)
@export var pinstripe_inset: float = 6.0 # From each pontoon's outer edge
@export var mouth_stripe_light_color: Color = Color(0.86, 0.89, 0.91)
@export var plate_rect: Rect2 = Rect2(-84, -52, 16, 6) # Registration plate, on the left pontoon
@export var plate_color: Color = Color(0.86, 0.89, 0.91)
@export var grime_density: float = 400.0 # px² of hull per grime texel. The Crab's plates use 120

@export_group("Stern")
@export var stern_block_rect: Rect2 = Rect2(-128, -24, 12, 48)
@export var engine_mount_half_width: float = 6.0
@export var engine_exit_half_width: float = 9.0

@export_group("Canopy")
@export var canopy_rect: Rect2 = Rect2(58, -12, 14, 24)
@export var canopy_chamfer: float = 4.0

@export_group("Hardpoint mounts")
@export var mount_length: float = 14.0 # Behind the hardpoint
@export var mount_half_height: float = 5.0


func _draw() -> void:
	_rng.seed = grime_seed

	_draw_bells()
	_draw_plate(stern_block_rect, dark_color)
	_draw_body()
	_draw_pontoons()
	_draw_plate(plate_rect, plate_color)
	_draw_mouth()
	_draw_canopy()
	_draw_mounts()
	_draw_nozzles()


func has_nozzle(thruster: Node2D) -> bool:
	return not main_engines.has(thruster)


# --- Body


# Clockwise from the stern's left corner, along the left flank to the nose, then back along the right.
func _get_outline() -> PackedVector2Array:
	var left_side := PackedVector2Array([
		Vector2(stern_x, -stern_half_width),
		Vector2(stern_shoulder_x, -body_half_width),
		Vector2(pontoon_back_x, -pontoon_half_width),
		Vector2(pontoon_front_x, -pontoon_half_width),
		Vector2(pontoon_front_x + pontoon_chamfer, -body_half_width),
		Vector2(shoulder_x, -body_half_width),
		Vector2(nose_x, -nose_half_width),
	])
	var outline := left_side.duplicate()

	for i in range(left_side.size() - 1, -1, -1):
		outline.append(Vector2(left_side[i].x, -left_side[i].y))

	return outline


# Outline, then the paint inside it: bow, stern and pontoons, each clipped to the inner outline.
func _draw_body() -> void:
	var outline := _get_outline()
	draw_colored_polygon(outline, outline_color)

	var insets := Geometry2D.offset_polygon(outline, -TEXEL, Geometry2D.JOIN_MITER)

	if insets.is_empty():
		return

	var inner: PackedVector2Array = insets[0]
	var height := pontoon_half_width * 2.0
	_fill_clipped(inner, Rect2(paint_split_x, -pontoon_half_width, nose_x - paint_split_x, height), bow_color)
	_fill_clipped(inner, Rect2(stern_x, -pontoon_half_width, paint_split_x - stern_x, height), stern_color)

	var pontoon_depth := pontoon_half_width - body_half_width - TEXEL
	var pontoon_length := pontoon_front_x + pontoon_chamfer - stern_shoulder_x
	_fill_clipped(inner, Rect2(stern_shoulder_x, -pontoon_half_width, pontoon_length, pontoon_depth), pontoon_color)
	_fill_clipped(inner, Rect2(stern_shoulder_x, body_half_width + TEXEL, pontoon_length, pontoon_depth), pontoon_color)

	# The seam where the two paints meet, and the light/dark edges of the nose's straight sides
	draw_rect(Rect2(paint_split_x - TEXEL, -body_half_width + TEXEL, TEXEL, body_half_width * 2.0 - TEXEL * 2.0), stern_color.darkened(0.3))

	var nose_from := pontoon_front_x + pontoon_chamfer
	draw_rect(Rect2(nose_from, -body_half_width + TEXEL, shoulder_x - nose_from, TEXEL), bow_color.lightened(0.2))
	draw_rect(Rect2(nose_from, body_half_width - TEXEL * 2.0, shoulder_x - nose_from, TEXEL), bow_color.darkened(0.3))

	var dirty := Rect2(pontoon_back_x, -body_half_width + TEXEL * 2.0, shoulder_x - pontoon_back_x, body_half_width * 2.0 - TEXEL * 4.0)
	_draw_grime(dirty, int(dirty.get_area() / grime_density))


func _fill_clipped(polygon: PackedVector2Array, rect: Rect2, color: Color) -> void:
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

	for piece in Geometry2D.intersect_polygons(polygon, corners):
		draw_colored_polygon(piece, color)


# Light outer edge on the left pontoon, dark on the right one (like every plate), rivets, pinstripes.
func _draw_pontoons() -> void:
	var from_x := pontoon_back_x
	var length := pontoon_front_x - pontoon_back_x
	draw_rect(Rect2(from_x, -pontoon_half_width + TEXEL, length, TEXEL), pontoon_color.lightened(0.2))
	draw_rect(Rect2(from_x, pontoon_half_width - TEXEL * 2.0, length, TEXEL), pontoon_color.darkened(0.3))

	var x := from_x + TEXEL

	while x < pontoon_front_x - TEXEL:
		draw_rect(Rect2(x, -pontoon_half_width + TEXEL * 2.0, TEXEL, TEXEL), pontoon_color.darkened(0.35))
		draw_rect(Rect2(x, pontoon_half_width - TEXEL * 3.0, TEXEL, TEXEL), pontoon_color.darkened(0.35))
		x += TEXEL * 4.0

	var stripe_from := plate_rect.end.x + TEXEL * 2.0
	var stripe_length := pontoon_front_x - TEXEL * 2.0 - stripe_from
	draw_rect(Rect2(stripe_from, -pontoon_half_width + pinstripe_inset, stripe_length, TEXEL), pinstripe_color)
	draw_rect(Rect2(stripe_from, pontoon_half_width - pinstripe_inset - TEXEL, stripe_length, TEXEL), pinstripe_color)


# --- Nose


# The hold, sunk into the nose. Dark floor, outlined, navy and white stripes along both walls.
func _draw_mouth() -> void:
	var hold := _get_hold_rect()

	if not hold.has_area():
		return

	var mouth := Rect2(hold.position.x, hold.position.y, nose_x - hold.position.x, hold.size.y)
	draw_rect(mouth.grow(TEXEL), outline_color)
	draw_rect(mouth, engine_inside_color)

	for side: float in [-1.0, 1.0]:
		var wall_y := mouth.position.y if side < 0.0 else mouth.end.y - TEXEL
		var x := mouth.position.x

		while x < mouth.end.x:
			var stripe := mouth_stripe_light_color if int(x / (TEXEL * 2.0)) % 2 == 0 else pinstripe_color
			draw_rect(Rect2(x, wall_y, TEXEL * 2.0, TEXEL), stripe)
			x += TEXEL * 2.0


# Same answer as Hangar.get_hold_rect(), in the editor too (Hangar isn't a @tool script).
func _get_hold_rect() -> Rect2:
	if intake == null:
		return Rect2()

	for child in intake.get_children():
		var collision := child as CollisionShape2D

		if collision == null:
			continue

		var rectangle := collision.shape as RectangleShape2D

		if rectangle != null:
			var center := intake.position + collision.position
			return Rect2(center - rectangle.size * 0.5, rectangle.size)

	return Rect2()


func _draw_canopy() -> void:
	draw_colored_polygon(_get_chamfered(canopy_rect.grow(TEXEL), canopy_chamfer + TEXEL * 0.5), outline_color)
	draw_colored_polygon(_get_chamfered(canopy_rect, canopy_chamfer), glass_dark_color)

	var glint_x := canopy_rect.end.x - TEXEL * 3.0
	draw_rect(Rect2(glint_x, canopy_rect.position.y + TEXEL * 2.0, TEXEL, canopy_rect.size.y - TEXEL * 4.0), glass_color)
	draw_rect(Rect2(glint_x + TEXEL, canopy_rect.position.y + TEXEL * 3.0, TEXEL, TEXEL * 2.0), glass_color)


# A plate under every hardpoint, reaching back mount_length into the hull.
func _draw_mounts() -> void:
	if hardpoints == null:
		return

	for child in hardpoints.get_children():
		var hardpoint := child as Node2D

		if hardpoint == null:
			continue

		var at := hardpoint.position
		var rect := Rect2(at.x - mount_length, at.y - mount_half_height, mount_length + TEXEL * 2.0, mount_half_height * 2.0)
		_draw_plate(rect, dark_color)
		draw_rect(Rect2(rect.position.x + TEXEL, at.y - TEXEL * 0.5, rect.size.x - TEXEL * 2.0, TEXEL), pinstripe_color)


# --- Stern


func _draw_bells() -> void:
	for engine in main_engines:
		if engine != null:
			_draw_bell(stern_x, engine.position, engine_mount_half_width, engine_exit_half_width)
