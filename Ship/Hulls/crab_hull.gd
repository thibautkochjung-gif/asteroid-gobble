@tool
class_name CrabHull
extends HullArt

# Draws "The Crab": army surplus, a wide flat slab that walks sideways better than it flies straight.
# - The slab: one wide plate with chamfered corners. The rooms sit on it (drawn by the rooms).
# - The mouth: a recess in the nose, the hangar's hold, with hazard stripes. Its size comes from the
#   hangar's intake rectangle, so resizing the intake reshapes the mouth. Read from the intake's own
#   shape: Hangar isn't a @tool script, so its methods can't run in the editor.
# - A mount under each hardpoint that sits ahead of the nose.
# - Two small eyes (cockpit windows) on either side of the mouth.
# - The tail stub carrying the rear jets, and one bell per main engine.
# - The wingtip pods, one on each flank, holding the turning jets that fire fore and aft.
# Visuals only, like every HullArt: the collision shapes are set by hand in the scene.

@export var intake: Area2D # The hangar's hold. Its rectangle shape is the mouth
@export var hardpoints: Node2D # Each hardpoint ahead of the nose gets a mount
@export var main_engines: Array[Node2D] = [] # Each one gets a bell from the slab's back edge

@export_group("Slab")
@export var body_rect: Rect2 = Rect2(-40, -98, 80, 196)
@export var body_chamfer: float = 8.0
@export var body_color: Color = Color(0.46, 0.24, 0.15)
@export var seam_xs: PackedFloat32Array = PackedFloat32Array([-2.0]) # Plate seams across the slab

@export_group("Tail")
@export var tail_rect: Rect2 = Rect2(-74, -16, 34, 32)
@export var tail_color: Color = Color(0.32, 0.35, 0.2)
@export var engine_mount_half_width: float = 6.0
@export var engine_exit_half_width: float = 10.0

@export_group("Wingtips")
@export var wingtip_from_x: float = -16.0
@export var wingtip_to_x: float = 8.0
@export var wingtip_depth: float = 10.0 # How far each pod sticks out of the flank
@export var wingtip_color: Color = Color(0.38, 0.42, 0.24)

@export_group("Nose")
@export var eye_offset_y: float = 25.0 # From the centreline to each eye's centre
@export var eye_size: float = 6.0
@export var mount_half_height: float = 6.0


func _draw() -> void:
	_rng.seed = grime_seed

	_draw_bells()
	_draw_plate(tail_rect, tail_color)
	_draw_wingtips()
	_draw_slab()
	_draw_mouth()
	_draw_mounts()
	_draw_eyes()
	_draw_nozzles()


func has_nozzle(thruster: Node2D) -> bool:
	return not main_engines.has(thruster)


# --- Slab


# Same recipe as _draw_plate, on a chamfered outline.
func _draw_slab() -> void:
	draw_colored_polygon(_get_chamfered(body_rect, body_chamfer), outline_color)

	var inner := body_rect.grow(-TEXEL)
	draw_colored_polygon(_get_chamfered(inner, body_chamfer - TEXEL * 0.5), body_color)

	var straight_x := inner.position.x + body_chamfer
	var straight_width := inner.size.x - body_chamfer * 2.0
	draw_rect(Rect2(straight_x, inner.position.y, straight_width, TEXEL), body_color.lightened(0.2))
	draw_rect(Rect2(straight_x, inner.end.y - TEXEL, straight_width, TEXEL), body_color.darkened(0.3))

	var x := straight_x

	while x < straight_x + straight_width - TEXEL:
		draw_rect(Rect2(x, inner.position.y + TEXEL, TEXEL, TEXEL), body_color.darkened(0.35))
		draw_rect(Rect2(x, inner.end.y - TEXEL * 2.0, TEXEL, TEXEL), body_color.darkened(0.35))
		x += TEXEL * 4.0

	for seam_x in seam_xs:
		draw_rect(Rect2(seam_x, inner.position.y + TEXEL * 2.0, TEXEL, inner.size.y - TEXEL * 4.0), body_color.darkened(0.3))

	var dirty := inner.grow(-body_chamfer * 0.5)
	_draw_grime(dirty, int(dirty.get_area() / 120.0))


# The hold, sunk into the nose. Dark floor, outlined, hazard stripes along both walls.
func _draw_mouth() -> void:
	var hold := _get_hold_rect()

	if not hold.has_area():
		return

	var mouth := Rect2(hold.position.x, hold.position.y, body_rect.end.x - hold.position.x, hold.size.y)
	draw_rect(mouth.grow(TEXEL), outline_color)
	draw_rect(mouth, engine_inside_color)

	for side: float in [-1.0, 1.0]:
		var wall_y := mouth.position.y if side < 0.0 else mouth.end.y - TEXEL
		var x := mouth.position.x

		while x < mouth.end.x:
			var stripe := stripe_color if int(x / (TEXEL * 2.0)) % 2 == 0 else stripe_dark_color
			draw_rect(Rect2(x, wall_y, TEXEL * 2.0, TEXEL), stripe)
			x += TEXEL * 2.0


# Same answer as Hangar.get_hold_rect(), in the editor too.
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


# A short plate under every hardpoint that sits ahead of the slab's nose.
func _draw_mounts() -> void:
	if hardpoints == null:
		return

	var front_x := body_rect.end.x

	for child in hardpoints.get_children():
		var hardpoint := child as Node2D

		if hardpoint == null or hardpoint.position.x <= front_x:
			continue

		var rect := Rect2(front_x - TEXEL, hardpoint.position.y - mount_half_height, hardpoint.position.x - front_x + TEXEL * 3.0, mount_half_height * 2.0)
		_draw_plate(rect, dark_color)
		draw_rect(Rect2(rect.position.x + TEXEL, hardpoint.position.y - TEXEL * 0.5, rect.size.x - TEXEL * 2.0, TEXEL), stripe_color)


func _draw_eyes() -> void:
	for side: float in [-1.0, 1.0]:
		var center := Vector2(body_rect.end.x - eye_size * 0.5 - TEXEL * 2.0, eye_offset_y * side)
		var eye := Rect2(center - Vector2.ONE * eye_size * 0.5, Vector2.ONE * eye_size)
		draw_rect(eye.grow(TEXEL), outline_color)
		draw_rect(eye, glass_dark_color)
		draw_rect(Rect2(eye.position.x + TEXEL, eye.position.y, TEXEL, eye.size.y - TEXEL), glass_color)


# --- Tail and flanks


func _draw_bells() -> void:
	for engine in main_engines:
		if engine != null:
			_draw_bell(body_rect.position.x, engine.position, engine_mount_half_width, engine_exit_half_width)


func _draw_wingtips() -> void:
	var width := wingtip_to_x - wingtip_from_x

	for side: float in [-1.0, 1.0]:
		var top := body_rect.position.y - wingtip_depth if side < 0.0 else body_rect.end.y - TEXEL # Tucks one texel under the slab
		var pod := Rect2(wingtip_from_x, top, width, wingtip_depth + TEXEL)
		_draw_plate(pod, wingtip_color)
