@tool
class_name MeridianHarvesterHull
extends HullArt

# Draws the Meridian Harvester: a long-haul processor built around three drums in a row.
# - The hammer head: a wide bow with the mouth in the middle and a cockpit canopy near each tip.
#   Pale paint, pontoon bands on the tips, rivets and two Meridian emblems.
# - Three drums on a spine. The front one houses the fixed smelter, the other two the ingot holds.
#   Every drum is the same chamfered octagon, ringed in pontoon paint and a navy pinstripe, with
#   portholes around the rim.
# - Radiator fins in the gaps between the drums (the smelter's heat goes out there), and a pipe over
#   each joint.
# - The engine block at the stern, with one bell per main engine and the registration plate.
# - Navigation lights: red on the port tip, green on the starboard tip. Static for now.
# Same paint as the Commuter (MeridianHull). Visuals only, like every HullArt: the collision shapes
# are set by hand in the scene.

@export var intake: Area2D # The hangar's hold. Its rectangle shape is the mouth
@export var hardpoints: Node2D # Each hardpoint gets a mount plate
@export var main_engines: Array[Node2D] = [] # Each one gets a bell from the engine block

@export_group("Head")
@export var head_back_x: float = 120.0
@export var head_shoulder_x: float = 128.0 # Where the tips reach their full width
@export var head_tip_front_x: float = 188.0 # Where the front chamfer of each tip starts
@export var nose_x: float = 208.0
@export var head_back_half_width: float = 60.0
@export var head_half_width: float = 88.0
@export var nose_half_width: float = 68.0
@export var tip_band: float = 20.0 # Pontoon paint along the outer edge of each tip
@export var canopy_rects: Array[Rect2] = [Rect2(136, -86, 18, 12), Rect2(136, 74, 18, 12)]
@export var canopy_chamfer: float = 4.0
@export var emblem_positions: Array[Vector2] = [Vector2(182, -58), Vector2(182, 58)]

@export_group("Body")
@export var drum_rects: Array[Rect2] = [Rect2(44, -52, 80, 104), Rect2(-44, -52, 76, 104), Rect2(-128, -52, 76, 104)] # Front to back
@export var drum_chamfer: float = 24.0
@export var porthole_spacing: float = 12.0
@export var spine_rect: Rect2 = Rect2(-164, -20, 292, 40)
@export var fin_rects: Array[Rect2] = [Rect2(32, -72, 12, 54), Rect2(32, 18, 12, 54), Rect2(-52, -72, 8, 54), Rect2(-52, 18, 8, 54)] # From the spine out, between the drums
@export var engine_block_rect: Rect2 = Rect2(-200, -42, 44, 84)
@export var engine_block_chamfer: float = 10.0
@export var engine_mount_half_width: float = 6.0
@export var engine_exit_half_width: float = 8.0
@export var plate_rect: Rect2 = Rect2(-194, -38, 16, 6) # Registration plate, on the engine block

@export_group("Paint")
@export var bow_color: Color = Color(0.68, 0.74, 0.79)
@export var stern_color: Color = Color(0.33, 0.39, 0.46)
@export var pontoon_color: Color = Color(0.25, 0.3, 0.36)
@export var pinstripe_color: Color = Color(0.17, 0.3, 0.47)
@export var mouth_stripe_light_color: Color = Color(0.86, 0.89, 0.91)
@export var plate_color: Color = Color(0.86, 0.89, 0.91)
@export var radiator_color: Color = Color(0.55, 0.61, 0.67)
@export var radiator_root_color: Color = Color(0.59, 0.24, 0.12) # Hot end, where the fin meets the hull
@export var port_light_color: Color = Color(0.84, 0.23, 0.19)
@export var starboard_light_color: Color = Color(0.27, 0.77, 0.43)
@export var port_light_position: Vector2 = Vector2(122, -68)
@export var starboard_light_position: Vector2 = Vector2(122, 64)
@export var grime_density: float = 400.0 # px² of hull per grime texel

@export_group("Hardpoint mounts")
@export var mount_length: float = 14.0 # Behind the hardpoint
@export var mount_half_height: float = 5.0


func _draw() -> void:
	_rng.seed = grime_seed

	_draw_bells()
	_draw_fins()
	_draw_slab(_get_chamfered(engine_block_rect, engine_block_chamfer), engine_block_rect, engine_block_chamfer, pontoon_color)
	_draw_plate(plate_rect, plate_color)
	_draw_spine()

	for rect in drum_rects:
		_draw_drum(rect)

	_draw_joint_pipes()
	_draw_head()
	_draw_mouth()

	for rect in canopy_rects:
		_draw_canopy(rect)

	_draw_mounts()
	_draw_nav_light(port_light_position, port_light_color)
	_draw_nav_light(starboard_light_position, starboard_light_color)
	_draw_nozzles()


func has_nozzle(thruster: Node2D) -> bool:
	return not main_engines.has(thruster)


# --- Shared bits


# Outline, then the paint one texel in, with a light top edge and a dark bottom edge along the
# straight parts (between the chamfers). Some dirt, Meridian-light.
func _draw_slab(polygon: PackedVector2Array, rect: Rect2, chamfer: float, color: Color) -> void:
	draw_colored_polygon(polygon, outline_color)
	var insets := Geometry2D.offset_polygon(polygon, -TEXEL, Geometry2D.JOIN_MITER)

	if insets.is_empty():
		return

	draw_colored_polygon(insets[0], color)
	_draw_edges(rect, chamfer, color)

	var dirty := rect.grow(-TEXEL * 2.0)
	_draw_grime(dirty, int(dirty.get_area() / grime_density))


func _draw_edges(rect: Rect2, chamfer: float, color: Color) -> void:
	var from_x := rect.position.x + chamfer
	var length := rect.size.x - chamfer * 2.0
	draw_rect(Rect2(from_x, rect.position.y + TEXEL, length, TEXEL), color.lightened(0.2))
	draw_rect(Rect2(from_x, rect.end.y - TEXEL * 2.0, length, TEXEL), color.darkened(0.3))


func _fill_clipped(polygon: PackedVector2Array, rect: Rect2, color: Color) -> void:
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

	for piece in Geometry2D.intersect_polygons(polygon, corners):
		draw_colored_polygon(piece, color)


# One texel every `spacing` px along the polygon's edges, snapped to the texel grid.
func _draw_dots(polygon: PackedVector2Array, spacing: float, color: Color) -> void:
	var travelled := spacing * 0.5

	for i in polygon.size():
		var from := polygon[i]
		var to := polygon[(i + 1) % polygon.size()]
		var length := from.distance_to(to)

		while travelled < length:
			var at := from.lerp(to, travelled / length)
			draw_rect(Rect2((at / TEXEL).floor() * TEXEL, Vector2(TEXEL, TEXEL)), color)
			travelled += spacing

		travelled -= length


# --- Body


func _draw_spine() -> void:
	var rect := spine_rect
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	_draw_slab(corners, rect, 0.0, stern_color)
	draw_rect(Rect2(rect.position.x + TEXEL * 2.0, rect.position.y + TEXEL * 3.0, rect.size.x - TEXEL * 4.0, TEXEL), pinstripe_color)
	draw_rect(Rect2(rect.position.x + TEXEL * 2.0, rect.end.y - TEXEL * 4.0, rect.size.x - TEXEL * 4.0, TEXEL), pinstripe_color)


# Nested insets of the same octagon: outline, pontoon band, navy pinstripe, slate band, pale centre.
# Portholes run around the middle of the pontoon band.
func _draw_drum(rect: Rect2) -> void:
	var outline := _get_chamfered(rect, drum_chamfer)
	draw_colored_polygon(outline, outline_color)

	var rings := [[TEXEL, pontoon_color], [TEXEL * 4.0, pinstripe_color], [TEXEL * 5.0, stern_color], [TEXEL * 10.0, bow_color]]

	for ring: Array in rings:
		var insets := Geometry2D.offset_polygon(outline, -ring[0], Geometry2D.JOIN_MITER)

		if not insets.is_empty():
			draw_colored_polygon(insets[0], ring[1])

	_draw_edges(rect, drum_chamfer, pontoon_color)

	var porthole_line := Geometry2D.offset_polygon(outline, -TEXEL * 2.5, Geometry2D.JOIN_MITER)

	if not porthole_line.is_empty():
		_draw_dots(porthole_line[0], porthole_spacing, glass_dark_color)

	var dirty := rect.grow(-TEXEL * 5.0)
	_draw_grime(dirty, int(dirty.get_area() / grime_density))


# Ribbed fins, hot (rust-red) where they meet the hull: the end nearer the ship's axis.
func _draw_fins() -> void:
	for rect in fin_rects:
		draw_rect(rect, outline_color)
		var inner := rect.grow(-TEXEL)
		draw_rect(inner, radiator_color)

		var x := inner.position.x + TEXEL

		while x < inner.end.x - TEXEL:
			draw_rect(Rect2(x, inner.position.y, TEXEL, inner.size.y), radiator_color.darkened(0.25))
			x += TEXEL * 2.0

		var root_y := inner.end.y - TEXEL * 2.0 if rect.position.y < 0.0 else inner.position.y
		draw_rect(Rect2(inner.position.x, root_y, inner.size.x, TEXEL * 2.0), radiator_root_color)


# A pipe over each gap between two drums, with a flange every 8 px.
func _draw_joint_pipes() -> void:
	for i in drum_rects.size() - 1:
		var from_x := drum_rects[i + 1].end.x - TEXEL * 4.0
		var to_x := drum_rects[i].position.x + TEXEL * 4.0
		var pipe := Rect2(from_x, -TEXEL * 2.0, to_x - from_x, TEXEL * 4.0)
		draw_rect(pipe, outline_color)
		draw_rect(Rect2(pipe.position.x, -TEXEL, pipe.size.x, TEXEL), pipe_color)
		draw_rect(Rect2(pipe.position.x, 0.0, pipe.size.x, TEXEL), pipe_dark_color)

		var x := from_x + TEXEL * 2.0

		while x < to_x - TEXEL:
			draw_rect(Rect2(x, -TEXEL, TEXEL, TEXEL * 2.0), pipe_color.lightened(0.2))
			x += TEXEL * 4.0


# --- Head


# Clockwise from the back of the port tip, to the nose, then back along the starboard side.
func _get_head_outline() -> PackedVector2Array:
	var left_side := PackedVector2Array([
		Vector2(head_back_x, -head_back_half_width),
		Vector2(head_shoulder_x, -head_half_width),
		Vector2(head_tip_front_x, -head_half_width),
		Vector2(nose_x, -nose_half_width),
	])
	var outline := left_side.duplicate()

	for i in range(left_side.size() - 1, -1, -1):
		outline.append(Vector2(left_side[i].x, -left_side[i].y))

	return outline


func _draw_head() -> void:
	var outline := _get_head_outline()
	draw_colored_polygon(outline, outline_color)
	var insets := Geometry2D.offset_polygon(outline, -TEXEL, Geometry2D.JOIN_MITER)

	if insets.is_empty():
		return

	var inner: PackedVector2Array = insets[0]
	var length := nose_x - head_back_x
	var band_y := head_half_width - tip_band
	_fill_clipped(inner, Rect2(head_back_x, -band_y, length, band_y * 2.0), bow_color)
	_fill_clipped(inner, Rect2(head_back_x, -head_half_width, length, tip_band), pontoon_color)
	_fill_clipped(inner, Rect2(head_back_x, band_y, length, tip_band), pontoon_color)

	var edge_from := head_shoulder_x
	var edge_length := head_tip_front_x - head_shoulder_x
	draw_rect(Rect2(edge_from, -head_half_width + TEXEL, edge_length, TEXEL), pontoon_color.lightened(0.2))
	draw_rect(Rect2(edge_from, head_half_width - TEXEL * 2.0, edge_length, TEXEL), pontoon_color.darkened(0.3))

	# Rivets along each tip, and the navy pinstripe where the tip paint meets the bow paint
	var x := edge_from + TEXEL * 2.0

	while x < head_tip_front_x - TEXEL * 2.0:
		draw_rect(Rect2(x, -head_half_width + TEXEL * 2.0, TEXEL, TEXEL), pontoon_color.darkened(0.35))
		draw_rect(Rect2(x, head_half_width - TEXEL * 3.0, TEXEL, TEXEL), pontoon_color.darkened(0.35))
		x += TEXEL * 4.0

	draw_rect(Rect2(edge_from + TEXEL * 2.0, -band_y, edge_length - TEXEL * 2.0, TEXEL), pinstripe_color)
	draw_rect(Rect2(edge_from + TEXEL * 2.0, band_y - TEXEL, edge_length - TEXEL * 2.0, TEXEL), pinstripe_color)

	for at in emblem_positions:
		_draw_emblem(at)

	var dirty := Rect2(head_back_x + TEXEL * 4.0, -band_y, length - TEXEL * 8.0, band_y * 2.0)
	_draw_grime(dirty, int(dirty.get_area() / grime_density))


# Meridian's mark: a navy disc with a white meridian and equator. Radius 3 texels.
func _draw_emblem(center: Vector2) -> void:
	for row in range(-4, 4):
		for column in range(-4, 4):
			var offset := Vector2(column + 0.5, row + 0.5)
			var distance := offset.length()

			if distance > 3.6:
				continue

			var color := pinstripe_color

			if distance > 2.7:
				color = outline_color
			elif column == 0 or row == 0:
				color = mouth_stripe_light_color

			draw_rect(Rect2(center + Vector2(column, row) * TEXEL, Vector2(TEXEL, TEXEL)), color)


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


func _draw_canopy(rect: Rect2) -> void:
	draw_colored_polygon(_get_chamfered(rect.grow(TEXEL), canopy_chamfer + TEXEL * 0.5), outline_color)
	draw_colored_polygon(_get_chamfered(rect, canopy_chamfer), glass_dark_color)

	var glint_x := rect.end.x - TEXEL * 3.0
	draw_rect(Rect2(glint_x, rect.position.y + TEXEL * 2.0, TEXEL, rect.size.y - TEXEL * 4.0), glass_color)
	draw_rect(Rect2(glint_x + TEXEL, rect.position.y + TEXEL * 3.0, TEXEL, TEXEL * 2.0), glass_color)


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


# A 2×2 texel lamp with a bright corner.
func _draw_nav_light(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at - Vector2(TEXEL, TEXEL), Vector2(TEXEL, TEXEL) * 4.0), outline_color)
	draw_rect(Rect2(at, Vector2(TEXEL, TEXEL) * 2.0), color)
	draw_rect(Rect2(at, Vector2(TEXEL, TEXEL)), color.lightened(0.45))


# --- Stern


func _draw_bells() -> void:
	for engine in main_engines:
		if engine != null:
			_draw_bell(engine_block_rect.position.x, engine.position, engine_mount_half_width, engine_exit_half_width)
