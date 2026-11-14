@tool
class_name ShipHull
extends HullArt

# Draws the "Bucket" hull in code: a starter ship welded together from whatever was lying around.
# Plates, grime, nozzle housings and colours come from HullArt, shared with the other hulls.
# - One plate section around each room slot (the slot grown by hull_padding), so resizing a slot
#   reshapes the hull. The biggest section is drawn last, on top: it bulges over its neighbours.
# - The hangar prongs at the nose, shaped from the hangar's door line and doorway width.
# - The generator housing and the main engine bell at the back. The bell ends on the main thruster.
# - A nozzle housing on every other thruster, wherever it's placed.
# - Bolted-on extras: crew cabin, radiator fins beside one slot, rear outriggers, an exposed fuel line.
# Visuals only, like every HullArt: the collision shapes are set by hand in the scene.

@export var main_engine: Node2D # The bell is drawn ending here. Gets no nozzle housing

@export_group("Sections")
@export var hull_padding: float = 6.0 # Hull around each slot, in px
@export var section_colors: Array[Color] = [Color(0.31, 0.3, 0.31), Color(0.46, 0.24, 0.15), Color(0.31, 0.3, 0.31)] # One per slot; the last one repeats
@export var patch_rect: Rect2 = Rect2(-40, 24, 16, 12) # Primer patch over an old breach

@export_group("Prongs")
@export var prong_back_x: float = 72.0
@export var prong_outer_y: float = 32.0
@export var prong_chamfer: float = 8.0
@export var left_prong_color: Color = Color(0.48, 0.47, 0.45) # The replacement: bare, unpainted
@export var right_prong_color: Color = Color(0.46, 0.24, 0.15)

@export_group("Tail")
@export var tail_rect: Rect2 = Rect2(-96, -18, 20, 36) # Generator housing
@export var engine_mount_half_width: float = 12.0
@export var engine_exit_half_width: float = 18.0

@export_group("Extras")
@export var cabin_rect: Rect2 = Rect2(-30, -50, 36, 14) # Bolted on the left flank
@export var radiator_slot: int = 0 # Fins on both sides of this slot (the smelter's)
@export var radiator_depth: float = 14.0
@export var outrigger_x: float = -82.0
@export var outrigger_reach: float = 42.0 # From the centreline to the end of each strut
@export var fuel_line_y: float = 38.0
@export var fuel_line_from_x: float = -56.0
@export var fuel_line_to_x: float = 72.0


func _draw() -> void:
	_rng.seed = grime_seed
	var slots := _get_slots()

	_draw_outriggers()
	_draw_engine()
	_draw_plate(tail_rect, dark_color)
	_draw_cabin()
	_draw_sections(slots)
	_draw_patch()
	_draw_prongs()
	_draw_fuel_line()
	_draw_radiators(slots)
	_draw_nozzles()


# The main engine gets the big bell instead of a nozzle housing.
func has_nozzle(thruster: Node2D) -> bool:
	return thruster != main_engine


func _get_section_rect(slot: RoomSlot) -> Rect2:
	return Rect2(slot.position - slot.size * 0.5, slot.size).grow(hull_padding)


func _draw_sections(slots: Array[RoomSlot]) -> void:
	var order := range(slots.size())
	order.sort_custom(func(a: int, b: int) -> bool: return slots[a].size.x * slots[a].size.y < slots[b].size.x * slots[b].size.y)

	for i: int in order:
		var color: Color = section_colors[mini(i, section_colors.size() - 1)] if not section_colors.is_empty() else dark_color
		_draw_plate(_get_section_rect(slots[i]), color)


func _draw_patch() -> void:
	if patch_rect.has_area():
		draw_rect(patch_rect, primer_color)
		draw_rect(Rect2(patch_rect.position.x + TEXEL, patch_rect.get_center().y, patch_rect.size.x - TEXEL * 2.0, TEXEL), primer_color.darkened(0.25))


# --- Nose


func _draw_prongs() -> void:
	if hangar == null:
		return

	for side: float in [-1.0, 1.0]:
		var front_x := hangar.door_line_x + TEXEL
		var inner_y := hangar.doorway_half_width * side
		var outer_y := prong_outer_y * side
		var points := PackedVector2Array([
			Vector2(prong_back_x, outer_y),
			Vector2(front_x - prong_chamfer, outer_y),
			Vector2(front_x, outer_y - prong_chamfer * side),
			Vector2(front_x, inner_y),
			Vector2(prong_back_x, inner_y),
		])
		var color := left_prong_color if side < 0.0 else right_prong_color
		draw_colored_polygon(points, color)

		points.append(points[0])
		draw_polyline(points, outline_color, TEXEL)

		# Hazard stripe along the mouth
		var stripe_y := inner_y - TEXEL if side > 0.0 else inner_y
		var x := prong_back_x

		while x < front_x - TEXEL:
			var stripe := stripe_color if int(x / (TEXEL * 2.0)) % 2 == 0 else stripe_dark_color
			draw_rect(Rect2(x, stripe_y + side * TEXEL, TEXEL * 2.0, TEXEL), stripe)
			x += TEXEL * 2.0

		_draw_grime(Rect2(prong_back_x, minf(inner_y, outer_y), front_x - prong_chamfer - prong_back_x, absf(outer_y - inner_y)), 12)


# --- Tail


# Bell from the generator housing back to the main thruster.
func _draw_engine() -> void:
	if main_engine == null:
		return

	_draw_bell(tail_rect.position.x, main_engine.position, engine_mount_half_width, engine_exit_half_width)


# Struts from the generator housing out to the rear side thrusters.
func _draw_outriggers() -> void:
	var tail_half := tail_rect.size.y * 0.5
	var y_center := tail_rect.get_center().y

	for side: float in [-1.0, 1.0]:
		var from_y := y_center + tail_half * side
		var to_y := y_center + outrigger_reach * side
		var strut := Rect2(outrigger_x - TEXEL * 2.0, minf(from_y, to_y), TEXEL * 4.0, absf(to_y - from_y))
		draw_rect(strut, outline_color)
		draw_rect(Rect2(outrigger_x - TEXEL, strut.position.y, TEXEL * 2.0, strut.size.y), pipe_dark_color)
		draw_rect(Rect2(outrigger_x - TEXEL, strut.position.y, TEXEL, strut.size.y), pipe_color)


# --- Extras


func _draw_cabin() -> void:
	if not cabin_rect.has_area():
		return

	_draw_plate(cabin_rect, cabin_color)

	var window := Rect2(cabin_rect.position.x + TEXEL * 3.0, cabin_rect.position.y + TEXEL * 2.0, cabin_rect.size.x - TEXEL * 6.0, TEXEL * 3.0)
	draw_rect(window, glass_dark_color)
	draw_rect(Rect2(window.position.x + TEXEL, window.position.y + TEXEL, window.size.x - TEXEL * 2.0, TEXEL), glass_color)


func _draw_radiators(slots: Array[RoomSlot]) -> void:
	if radiator_slot < 0 or radiator_slot >= slots.size():
		return

	var section := _get_section_rect(slots[radiator_slot])

	for side: float in [-1.0, 1.0]:
		var edge_y := section.position.y if side < 0.0 else section.end.y
		var fins := Rect2(section.position.x + TEXEL * 3.0, minf(edge_y, edge_y + radiator_depth * side), section.size.x - TEXEL * 6.0, radiator_depth)
		draw_rect(fins, outline_color)

		var inside := fins.grow(-TEXEL)
		draw_rect(inside, dark_color)

		var x := inside.position.x + TEXEL

		while x < inside.end.x:
			draw_rect(Rect2(x, inside.position.y, TEXEL, inside.size.y), fin_color)
			x += TEXEL * 2.0


# Two-texel pipe: light top, dark bottom, with a bend into the hull at the back.
func _draw_fuel_line() -> void:
	if fuel_line_to_x <= fuel_line_from_x:
		return

	var length := fuel_line_to_x - fuel_line_from_x
	draw_rect(Rect2(fuel_line_from_x - TEXEL, fuel_line_y - TEXEL, length + TEXEL * 2.0, TEXEL * 4.0), outline_color)
	draw_rect(Rect2(fuel_line_from_x, fuel_line_y, length, TEXEL), pipe_color)
	draw_rect(Rect2(fuel_line_from_x, fuel_line_y + TEXEL, length, TEXEL), pipe_dark_color)

	var x := fuel_line_from_x + TEXEL * 6.0

	while x < fuel_line_to_x:
		draw_rect(Rect2(x, fuel_line_y - TEXEL, TEXEL, TEXEL * 4.0), outline_color) # Clamps
		x += TEXEL * 12.0
