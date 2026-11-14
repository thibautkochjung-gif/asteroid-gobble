class_name TractorBeam
extends HardpointWeapon

# Hold the fire button: a cone of force opens ahead of the barrel. Every loose rock and prop inside
# it is pulled toward the emitter, or pushed away in push mode (the mode key, hardpoint_mode,
# flips between the two). The cone is fixed to the barrel: aim it with the ship.
# Each body in the cone gets the same fixed force, and the ship gets the sum the other way, at the
# emitter: a chunk lighter than the ship flies in, a rock heavier than the ship drags the ship
# toward it (and, the emitter being on a side, turns it a little). With many bodies in the cone the
# force is shared, so the total never goes past max_total_share times a single pull.
# The force stops on a body while the gap closes (or opens) faster than max_closing_speed, so a
# light chunk doesn't come in like a bullet. Let go and the momentum stays: this is space.
# Builds (set in the scene):
# - heavy: more force and range.
# - smart (guide_into_hangar): whatever it pulls, it keeps hold of, even after the button is
#   released, and the player can go on pulling more. Chunks that fit the hangar are guided in, like
#   the grabber does it: first to a point in front of the doors, then straight in along the
#   hangar's axis (with the doors shut, they wait at that point). Bigger bodies are brought close
#   and kept there, moving with the ship. The release key (tractor_release) lets go of everything.
#   A body that leaves the camera's view at its widest zoom is let go too.

enum Mode { PULL, PUSH }

const TEXEL: float = 2.0
const RELEASE_ACTION: StringName = &"tractor_release"
const CONE_ANGLE_STEPS: int = 8 # Cone drawing: wedges across
const CONE_RANGE_STEPS: int = 12 # Cone drawing: bands along

@export var force: float = 60.0 # mass * px/s², on each body. The starter ship weighs about 26
@export var max_range: float = 675.0
@export var cone_degrees: float = 25.0 # Full width
@export var max_closing_speed: float = 60.0 # px/s. Faster than this, the beam stops adding speed
@export var max_total_share: float = 2.0 # With many bodies, the total force stays under this many single pulls

@export_group("Smart")
@export var guide_into_hangar: bool = false
@export var staging_distance: float = 50.0 # px in front of the door line
@export var staging_tolerance: float = 10.0 # px from the staging point that counts as there
@export var guide_speed: float = 45.0 # px/s toward the waypoint, relative to the ship
@export var entry_speed: float = 25.0 # px/s into the hangar
@export var guide_gain: float = 3.0 # 1/s. How hard it corrects a held body's speed
@export var hold_gap: float = 40.0 # px between the emitter and the edge of a held body too big for the hangar
@export var fallback_min_zoom: float = 0.3 # If the camera has no min_zoom: its widest zoom, for the release distance

@export_group("Look")
@export var coil_count: int = 2
@export var body_color: Color = Color(0.54, 0.5, 0.45)
@export var coil_color: Color = Color(0.83, 0.64, 0.16)
@export var outline_color: Color = Color(0.06, 0.055, 0.07)
@export var pull_color: Color = Color(0.45, 0.85, 1.0)
@export var push_color: Color = Color(1.0, 0.55, 0.3)
@export var smart_light_color: Color = Color(0.4, 1.0, 0.5)
@export var cone_alpha: float = 0.13 # Fill, at its brightest
@export_range(0.0, 1.0) var fade_start: float = 0.55 # Share of the range where the cone starts fading out
@export var ring_count: int = 6
@export var ring_speed: float = 90.0 # px/s, rings travel toward the emitter (pull) or away (push)

var mode: Mode = Mode.PULL
var is_firing: bool = false
var caught: Array[RigidBody2D] = [] # Bodies in the cone this frame
var held: Array[RigidBody2D] = [] # Smart build: bodies it keeps pulling

var _staged: Dictionary[RigidBody2D, bool] = {} # Smart build: held chunks that reached the point in front of the doors
var _time: float = 0.0


func get_button_title() -> String:
	var title := "PULL BEAM" if mode == Mode.PULL else "PUSH BEAM"

	if not held.is_empty():
		title += " ×%d" % held.size()

	return title


func _process(delta: float) -> void:
	_time += delta

	if Input.is_action_just_pressed(MODE_ACTION):
		mode = Mode.PUSH if mode == Mode.PULL else Mode.PULL
		message.emit("push mode" if mode == Mode.PUSH else "pull mode")

	if guide_into_hangar and Input.is_action_just_pressed(RELEASE_ACTION) and not held.is_empty():
		message.emit("released %d" % held.size())
		_release_all()

	queue_redraw()


func _physics_process(delta: float) -> void:
	is_firing = Input.is_action_pressed(fire_action) and get_performance() > 0.0
	caught.clear()
	_prune_held()

	if not is_firing and held.is_empty():
		return

	var strength := get_performance() # Damaged: less force

	if is_firing:
		caught = _find_in_cone()

	var loose: Array[RigidBody2D] = [] # Pulled or pushed this frame only

	for body in caught:
		if guide_into_hangar and mode == Mode.PULL:
			if not held.has(body):
				held.append(body)
		elif not held.has(body):
			loose.append(body)

	if strength <= 0.0:
		return

	var share := minf(1.0, max_total_share / maxf(1.0, held.size() + loose.size()))
	var body_force := force * strength * share

	for body in loose:
		_push_or_pull(body, body_force)

	for body in held:
		if _fits_hangar(body):
			_guide(body, body_force)
		else:
			_hold(body, body_force)


# --- Targeting


# Every loose rock and prop that has some part inside the cone. Frozen bodies (welded to a ship,
# held by a buoy, carried by the grabber) are skipped: there's nothing to move.
func _find_in_cone() -> Array[RigidBody2D]:
	var found: Array[RigidBody2D] = []
	var from := muzzle.global_position
	var forward := get_forward()

	for rock in Asteroid.find_near(get_tree(), from + forward * max_range * 0.5, max_range * 0.5):
		if not rock.freeze and _is_in_cone(rock.get_global_center(), rock.get_bound_radius(), from, forward):
			found.append(rock)

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		var prop := node as SpaceProp

		if prop != null and not prop.freeze and _is_in_cone(prop.global_position, prop.radius, from, forward):
			found.append(prop)

	return found


# A circle (a body's bounds) overlaps the cone: in range, and within the cone's angle once its
# own width, seen from the emitter, is counted.
func _is_in_cone(center: Vector2, radius: float, from: Vector2, forward: Vector2) -> bool:
	var offset := center - from
	var distance := offset.length()

	if distance - radius > max_range:
		return false

	if distance <= radius:
		return true

	var widening := asin(radius / distance)
	return absf(forward.angle_to(offset)) - widening <= deg_to_rad(cone_degrees) * 0.5


func _fits_hangar(body: RigidBody2D) -> bool:
	var chunk := body as Asteroid
	return chunk != null and hangar != null and not hangar.is_too_big(chunk)


# Drops held bodies that are gone, frozen, aboard (the hangar takes chunks out of the asteroid
# group), or out of the camera's widest view.
func _prune_held() -> void:
	if held.is_empty():
		return

	var view := _get_widest_view()

	for body in held.duplicate():
		var is_gone: bool = not is_instance_valid(body) or body.is_queued_for_deletion() or body.freeze

		if not is_gone and body is Asteroid and not body.is_in_group(Asteroid.GROUP):
			is_gone = true

		if not is_gone and view.has_area() and not view.has_point(_get_center(body)):
			is_gone = true

		if is_gone:
			held.erase(body)
			_staged.erase(body)


# What the camera would show around its current centre, zoomed all the way out.
func _get_widest_view() -> Rect2:
	var camera := get_viewport().get_camera_2d()

	if camera == null:
		return Rect2()

	var min_zoom: Variant = camera.get(&"min_zoom")
	var zoom: float = min_zoom if min_zoom is float else fallback_min_zoom
	var size := get_viewport().get_visible_rect().size / zoom
	return Rect2(camera.get_screen_center_position() - size * 0.5, size)


func _release_all() -> void:
	held.clear()
	_staged.clear()


func _exit_tree() -> void:
	_release_all()


# --- Forces


# Along the line from the emitter to the body's centre. Both bodies get the force: Newton.
func _push_or_pull(body: RigidBody2D, amount: float) -> void:
	var from := muzzle.global_position
	var center := _get_center(body)
	var away := (center - from).normalized()
	var relative := SoftLink.velocity_at(body, center) - get_ship_velocity_at(from)
	var opening_speed := relative.dot(away)

	if mode == Mode.PULL and -opening_speed > max_closing_speed:
		return

	if mode == Mode.PUSH and opening_speed > max_closing_speed:
		return

	var direction := -away if mode == Mode.PULL else away
	_apply(body, direction * amount, from)


# Smart build: steers the chunk's speed (relative to the ship) toward the speed that brings it to
# the next waypoint. Capped by the beam's force, so a heavy chunk is slow to answer.
func _guide(body: RigidBody2D, amount: float) -> void:
	var center := _get_center(body)
	var mouth := hangar.to_global(Vector2(hangar.door_line_x, 0.0))
	var axis := hangar.global_transform.x.normalized() # Out of the hangar
	var staging := mouth + axis * staging_distance
	var goal := staging
	var speed := guide_speed

	if not _staged.has(body) and center.distance_to(staging) <= staging_tolerance:
		_staged[body] = true

	if _staged.has(body) and hangar.is_open:
		goal = mouth - axis * staging_distance # Through the doors and on
		speed = entry_speed

	_steer(body, goal, speed, amount)


# Smart build, bodies too big for the hangar: brought in until their edge is hold_gap from the
# emitter, on the line they're on, then kept there.
func _hold(body: RigidBody2D, amount: float) -> void:
	var from := muzzle.global_position
	var center := _get_center(body)
	var radius := _get_radius(body)
	var goal := from + (center - from).normalized() * (hold_gap + radius)
	_steer(body, goal, guide_speed, amount)


# Brings the body's speed, relative to the ship, toward the speed that takes it to goal.
func _steer(body: RigidBody2D, goal: Vector2, speed: float, amount: float) -> void:
	var center := _get_center(body)
	var to_goal := goal - center
	var wanted := to_goal.normalized() * minf(speed, to_goal.length() * 1.5)
	var correction := get_ship_velocity_at(center) + wanted - body.linear_velocity
	var wanted_force := correction * guide_gain * body.mass
	_apply(body, wanted_force.limit_length(amount), muzzle.global_position)


func _apply(body: RigidBody2D, target_force: Vector2, emitter: Vector2) -> void:
	body.apply_central_force(target_force)
	ship.apply_force(-target_force, emitter - ship.global_position)


func _get_center(body: RigidBody2D) -> Vector2:
	var rock := body as Asteroid
	return rock.get_global_center() if rock != null else body.global_position


func _get_radius(body: RigidBody2D) -> float:
	var rock := body as Asteroid

	if rock != null:
		return rock.get_bound_radius()

	var prop := body as SpaceProp
	return prop.radius if prop != null else 0.0


# --- Look


func _draw() -> void:
	var color := pull_color if mode == Mode.PULL else push_color

	if is_firing:
		_draw_cone(color)

	for body in caught:
		if is_instance_valid(body) and not held.has(body):
			_draw_lock(body, color, 0.35)

	for body in held:
		if is_instance_valid(body):
			_draw_lock(body, pull_color, 0.6)

	_draw_body()


# A soft cone that fades out toward the end of its range and toward its edges, with rings that
# travel toward the emitter when pulling, away from it when pushing.
func _draw_cone(color: Color) -> void:
	var tip := muzzle.position
	var half := deg_to_rad(cone_degrees) * 0.5

	for r in CONE_RANGE_STEPS:
		var near := max_range * r / CONE_RANGE_STEPS
		var far := max_range * (r + 1) / CONE_RANGE_STEPS

		for a in CONE_ANGLE_STEPS:
			var left := lerpf(-half, half, float(a) / CONE_ANGLE_STEPS)
			var right := lerpf(-half, half, float(a + 1) / CONE_ANGLE_STEPS)
			var points := PackedVector2Array([
				tip + Vector2.from_angle(left) * near,
				tip + Vector2.from_angle(left) * far,
				tip + Vector2.from_angle(right) * far,
				tip + Vector2.from_angle(right) * near,
			])
			var colors := PackedColorArray([
				_cone_color(color, near, left, half),
				_cone_color(color, far, left, half),
				_cone_color(color, far, right, half),
				_cone_color(color, near, right, half),
			])
			draw_polygon(points, colors)

	# Rings, wider and fainter far out.
	var spacing := max_range / ring_count
	var travel := fmod(_time * ring_speed, spacing)

	if mode == Mode.PULL:
		travel = spacing - travel

	for i in ring_count:
		var distance := travel + i * spacing

		if distance < 4.0:
			continue

		var ring := color
		ring.a = 0.55 * _get_fade(distance)
		draw_arc(tip, distance, -half * 0.92, half * 0.92, 10, ring, 1.5)

	# Edges, faint.
	for side in [-half, half]:
		var points := PackedVector2Array()
		var colors := PackedColorArray()

		for i in CONE_RANGE_STEPS + 1:
			var distance := max_range * i / CONE_RANGE_STEPS
			var edge := color
			edge.a = 0.3 * _get_fade(distance)
			points.append(tip + Vector2.from_angle(side) * distance)
			colors.append(edge)

		draw_polyline_colors(points, colors, 1.0)


# Fill colour at a point of the cone: brightest along the axis near the emitter.
func _cone_color(color: Color, distance: float, angle: float, half: float) -> Color:
	var across := 1.0 - pow(absf(angle) / half, 3.0) # Soft edges
	var shade := color
	shade.a = cone_alpha * _get_fade(distance) * lerpf(0.35, 1.0, across)
	return shade


# 1 up to fade_start of the range, then down to 0 at the end, eased.
func _get_fade(distance: float) -> float:
	var fade := clampf(inverse_lerp(max_range, max_range * fade_start, distance), 0.0, 1.0)
	return fade * fade


# A thin line from the emitter to a body the beam has, and a small ring on the body.
func _draw_lock(body: RigidBody2D, color: Color, alpha: float) -> void:
	var end := to_local(_get_center(body))
	var line := color
	line.a = alpha
	draw_dashed_line(muzzle.position, end, line, 1.0, 4.0)
	draw_arc(end, maxf(_get_radius(body) * 0.4, 4.0), 0.0, TAU, 16, line, 1.0)


func _draw_body() -> void:
	var plate := Rect2(-TEXEL * 2.0, -TEXEL * 3.0, TEXEL * 5.0, TEXEL * 6.0)
	draw_rect(plate, outline_color)
	draw_rect(plate.grow(-TEXEL * 0.5), body_color)

	var barrel := Rect2(TEXEL * 3.0, -TEXEL * 1.5, muzzle.position.x - TEXEL * 3.0, TEXEL * 3.0)
	draw_rect(barrel, outline_color)

	var lit := pull_color if mode == Mode.PULL else push_color
	var is_working := is_firing or not held.is_empty()

	for i in coil_count:
		var x := muzzle.position.x - TEXEL * (1.0 + i * 2.5)
		var coil := Rect2(x - TEXEL, -TEXEL * 2.5, TEXEL * 1.5, TEXEL * 5.0)
		draw_rect(coil, outline_color)
		draw_rect(coil.grow(-TEXEL * 0.25), lit if is_working else coil_color)

	if guide_into_hangar:
		var light := smart_light_color if not held.is_empty() else smart_light_color.darkened(0.6)
		draw_rect(Rect2(-TEXEL, -TEXEL * 0.5, TEXEL, TEXEL), light)
