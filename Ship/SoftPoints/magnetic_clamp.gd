class_name MagneticClamp
extends SoftPoint

# Two magnet pads on the outer face. Tap with a rock against the pads to grip it, tap again to let go.
# Quicker than the rock bolter, but weaker, and picky:
# - It only grips a rock that holds ore somewhere inside, seen or not (Asteroid.has_ore_cells).
#   A refused grip means a barren rock: the clamp doubles as a crude ore detector.
#   It lets go by itself once the last ore cell is gone.
# - It holds with spring forces, pad by pad (SoftLink). Two pads stop the rock from pivoting.
#   Over grip_force, it slips: thrusting hard with a heavy rock in the clamp tears it loose.
#   Short on power, the grip weakens.
# The rock stays its own body: other things hit it, not the ship.

@export var reach: float = 16.0 # px from the pads to the rock's surface
@export var pad_spacing: float = 12.0 # Between the two pads, along the hull
@export var draw_in_speed: float = 20.0 # px/s: the gap closes this fast after gripping
@export var stiffness: float = 120.0 # 1/s². See SoftLink
@export var damping: float = 22.0 # 1/s
@export var grip_force: float = 4000.0 # mass * px/s², per pad
@export var power_per_second: float = 1.0
@export var ore_check_interval: float = 0.5 # s

@export_group("Look")
@export var pad_color: Color = Color(0.54, 0.5, 0.45)
@export var field_color: Color = Color(0.35, 0.6, 1.0, 0.8)
@export var refuse_color: Color = Color(1.0, 0.25, 0.2)

var target: Asteroid
var anchors: Array[BodyAnchor] = []

var _gaps: Array[float] = [] # Current rest length of each pad's spring
var _refuse_flash: float = 0.0
var _ore_check_timer: float = 0.0


func _init() -> void:
	footprint = Rect2(0, -10, 12, 20) # Deep enough that a big rock touches the pads before the hull's outriggers
	dry_mass = 2.0


func _process(delta: float) -> void:
	super(delta)

	if _refuse_flash > 0.0:
		_refuse_flash -= delta
		queue_redraw()


func _physics_process(delta: float) -> void:
	if ship == null or anchors.is_empty():
		return

	_ore_check_timer -= delta

	if _ore_check_timer <= 0.0:
		_ore_check_timer = ore_check_interval

		if not _still_has_ore():
			_let_go("Clamp: no ore left, the magnet lets go")
			return

	var strength := draw_ship_power(power_per_second * delta)
	var pads := _get_pad_points()

	for i in anchors.size():
		var anchor := anchors[i]

		if not anchor.resolve(get_tree()):
			_let_go("Clamp: lost its grip")
			return

		_gaps[i] = maxf(_gaps[i] - draw_in_speed * delta, 0.0)
		var force := SoftLink.apply_spring(ship, pads[i], anchor.body, anchor.get_global_position(), _gaps[i], stiffness, damping, false)

		if force > grip_force * strength:
			_let_go("Clamp: slipped!")
			return

	queue_redraw()


func get_status_text() -> String:
	return "gripping" if not anchors.is_empty() else "free"


func get_controls_text() -> String:
	return "tap: let go" if not anchors.is_empty() else "tap: grip"


func _on_tap() -> void:
	if anchors.is_empty():
		_try_grip()
	else:
		_let_go("Clamp: released")


func _on_detached() -> void:
	anchors.clear()
	target = null


func _try_grip() -> void:
	var tip := get_tip()
	var best: Asteroid = null
	var best_distance := reach

	for rock in Asteroid.find_near(get_tree(), tip, reach):
		if rock.freeze:
			continue

		var distance := rock.get_closest_point(tip).distance_to(tip)

		if distance <= best_distance:
			best_distance = distance
			best = rock

	if best == null:
		say("Clamp: no rock against the pads")
		return

	if not best.has_ore_cells():
		_refuse_flash = 0.6
		say("Clamp: no grip. Nothing magnetic in there")
		return

	target = best
	anchors.clear()
	_gaps.clear()

	for pad in _get_pad_points():
		var point := best.get_closest_point(pad)
		anchors.append(BodyAnchor.on_body(best, point))
		_gaps.append(pad.distance_to(point))

	_ore_check_timer = ore_check_interval
	say("Clamp: locked on")


func _let_go(text: String) -> void:
	anchors.clear()
	target = null
	queue_redraw()
	say(text)


# Every rock the pads hold (the rock may have been cut in two between the pads).
func _still_has_ore() -> bool:
	for anchor in anchors:
		var rock := anchor.get_asteroid()

		if is_instance_valid(rock) and rock.has_ore_cells():
			return true

	return false


func _get_pad_points() -> Array[Vector2]:
	var x := footprint.end.x
	var y := footprint.get_center().y
	var points: Array[Vector2] = [to_global(Vector2(x, y - pad_spacing * 0.5)), to_global(Vector2(x, y + pad_spacing * 0.5))]
	return points


# --- Look


func _draw_module() -> void:
	_draw_plate(footprint, body_color)

	var x := footprint.end.x - TEXEL * 2.0
	var y := footprint.get_center().y
	var is_gripping := not anchors.is_empty()
	var face := refuse_color if _refuse_flash > 0.0 else field_color if is_gripping else pad_color

	for offset: float in [-pad_spacing * 0.5, pad_spacing * 0.5]:
		var pad := Rect2(x, y + offset - TEXEL * 2.0, TEXEL * 2.0, TEXEL * 4.0)
		draw_rect(pad.grow(TEXEL * 0.5), outline_color)
		draw_rect(pad, face)

	if not is_gripping:
		return

	var pads := _get_pad_points()

	for i in anchors.size():
		draw_line(to_local(pads[i]), to_local(anchors[i].get_global_position()), field_color, TEXEL * 0.5)
