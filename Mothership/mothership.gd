class_name Mothership
extends AnimatableBody2D

# The mothership is a train. A heavy locomotive (reactor, radiator paddles, engines on sponsons)
# pulls a chain of flatbed cars. Miners ride on the flatbeds, lashed down in slots sized for small,
# medium and large ships. A deflector at the front pushes rocks out of the way.
# It never stops: it flies straight at cruise_velocity. The cars don't swing, the whole train is
# one body.
#
# Docking: the player flies over their empty slot slowly enough (max_dock_speed, the rock bolter's
# rule). Rotation doesn't count. The decks don't collide (ships sit on top of them), so the slot
# can be reached from any side. The parked ships, the locomotive, the drawbars and the deflector
# ring do collide. Slot lights: green = slow enough, amber = too fast.
#
# Space: +x = the direction of travel. The locomotive's back is at x = 0, the cars trail behind.
# MothershipArt draws the parts that don't move, once. MothershipLights draws plumes and lights
# every frame.
#
# States:
# - CARRYING: drop-off. The player starts in their slot, pushed out sideways by the clamps; the
#   slot won't take them back. Leaving the slot ends the drop-off.
# - WAITING: pickup. The slot stays open for wait_time seconds.
# - LEAVING: out of time, or the drop-off is done. Disappears once it has been off screen for
#   despawn_delay seconds in a row. Until then a pickup train still takes the player: the driver
#   waits for the one running late.
# - DOCKING: the player is aboard and gets pulled into their slot.

signal player_left_bay # Drop-off done
signal docked # The player is aboard and lashed down
signal departed # Gone from the world, right before queue_free()
signal message(text: String) # For the cockpit terminal

enum State { CARRYING, WAITING, LEAVING, DOCKING }

const GROUP: StringName = &"motherships"
const SPAWN_MARGIN: float = 3500.0 # px. For spawning: a train centred this close to the screen could show

const LOCO_LENGTH: float = 1000.0
const CAR_GAP: float = 110.0
const FIRST_CAR_GAP: float = 560.0 # Locomotive to first car: past the end of the plumes (~480 px), so the player can reach the first car's slots
const CAR_LENGTH := { "S": 680.0, "M": 560.0, "L": 960.0 }
const CAR_HALF := { "S": 170.0, "M": 250.0, "L": 200.0 }
const SHIP_SIZE := { "S": Vector2(230, 100), "M": Vector2(420, 180), "L": Vector2(800, 320) }
const SLOT_SIZE := { "S": Vector2(300, 150), "M": Vector2(480, 230), "L": Vector2(870, 370) }

const ENGINE_Y: Array[float] = [-435.0, -325.0, 325.0, 435.0] # Outboard of the widest car: the exhaust misses the train
const ENGINE_EXIT_X: float = -100.0
const DEFLECTOR_CENTER := Vector2(1150, 0)
const DEFLECTOR_RADIUS: float = 420.0
const DEFLECTOR_ARC: float = PI * 0.42 # Half the arc
const FIELD_DEPTH: float = 120.0 # px ahead of the ring

@export var car_order: Array[String] = ["S", "M", "L", "M", "S"] # Front to back
@export var max_dock_speed: float = 40.0 # px/s between ship and train. Same as RockBolter.max_lock_speed
@export var wait_time: float = 600.0 # s the slot stays open for a pickup
@export var warning_time: float = 60.0 # s left when the terminal warns
@export var dock_time: float = 2.5 # s to pull the ship into its slot
@export var light_range: float = 900.0 # px from the slot. Closer: the slot lights react to the player
@export var too_fast_message_delay: float = 1.5 # s between two "too fast" messages
@export var despawn_delay: float = 60.0 # s off screen, in a row, before a leaving train disappears

@export_group("Deflector")
@export var push_side_speed: float = 160.0 # px/s. Rocks in the field are pushed sideways at least this fast...
@export var push_forward_speed: float = 30.0 # ...and kept moving ahead of the train at least this fast
@export var push_gain: float = 4.0 # How hard the field corrects a rock's speed, per second

var ship: RigidBody2D # Set by the dispatch before add_child()
var cruise_velocity: Vector2 = Vector2.ZERO # Set by the dispatch before add_child()
var state: State = State.WAITING
var can_pick_up: bool = true # False for the drop-off. Set before build()
var time_left: float = 0.0

var cars: Array[Dictionary] = [] # { "cls", "x0", "x1", "half" }, front to back
var slots: Array[Dictionary] = [] # { "xform", "cls", "number", "is_player" }
var player_slot: Dictionary = {}
var is_player_secured: bool = false # Docked and lashed down. MothershipArt draws the lashings then
var slot_light: Color = Color.TRANSPARENT # Read by MothershipLights
var extent := Rect2() # The whole train, local

var _dock_from: Transform2D # The ship in its slot's space when docking started
var _dock_angle: float = 0.0 # 0 or PI: the ship keeps the way it came in, nose first or tail first
var _dock_elapsed: float = 0.0
var _has_docked: bool = false
var _too_fast_cooldown: float = 0.0
var _has_warned: bool = false
var _off_screen_time: float = 0.0
var _field: Area2D
var _art: Node2D


# True if a train centred on point could show on this viewport's screen. For spawning.
static func is_visible_from(viewport: Viewport, point: Vector2) -> bool:
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	return view.grow(SPAWN_MARGIN).has_point(point)


# Lays out the cars and the slots, and picks the player's slot. Called by the dispatch before
# add_child(), so it can place the train around the player.
func build() -> void:
	cars.clear()
	slots.clear()
	var x := -FIRST_CAR_GAP

	for cls in car_order:
		var length: float = CAR_LENGTH[cls]
		var car := { "cls": cls, "x0": x - length, "x1": x, "half": CAR_HALF[cls] }
		cars.append(car)
		_add_slots(car)
		x -= length + CAR_GAP

	extent = Rect2(x - 60.0, -560, DEFLECTOR_CENTER.x + DEFLECTOR_RADIUS + FIELD_DEPTH + 100.0 - x, 1120)
	_pick_player_slot()


func _add_slots(car: Dictionary) -> void:
	var x0: float = car.x0
	var middle: float = (car.x0 + car.x1) / 2.0

	match car.cls:
		"S":
			for column in 2:
				for side: float in [-1.0, 1.0]:
					_add_slot(Vector2(x0 + 180.0 + column * 320.0, side * 82.0), "S")
		"M":
			for side: float in [-1.0, 1.0]:
				_add_slot(Vector2(middle, side * 125.0), "M")
		"L":
			_add_slot(Vector2(middle, 0.0), "L")


func _add_slot(at: Vector2, cls: String) -> void:
	slots.append({ "xform": Transform2D(0.0, at), "cls": cls, "number": slots.size() + 1, "is_player": false })


# The Bucket is a small ship: any S slot, picked at random, for the drop-off as for the pickup.
# S slots sit on the outer edge of their car, so the way out sideways is always clear.
func _pick_player_slot() -> void:
	var candidates: Array[Dictionary] = []

	for slot in slots:
		if slot.cls == "S":
			candidates.append(slot)

	if candidates.is_empty():
		candidates = slots

	player_slot = candidates.pick_random()
	player_slot.is_player = true


# Away from the train's axis, from the player's slot: the way the clamps push at the drop-off.
func get_player_exit_angle() -> float:
	var slot_xform: Transform2D = player_slot.xform
	return PI / 2.0 if slot_xform.origin.y >= 0.0 else -PI / 2.0


func get_player_slot_transform() -> Transform2D:
	return player_slot.xform


func _ready() -> void:
	assert(ship != null, "Mothership: the dispatch sets the ship before add_child()")

	add_to_group(GROUP)
	sync_to_physics = true
	time_left = wait_time

	if cars.is_empty():
		build()

	_add_collisions()
	_add_field()

	_art = MothershipArt.new()
	add_child(_art)
	add_child(MothershipLights.new())


func _physics_process(delta: float) -> void:
	global_position += cruise_velocity * delta
	_too_fast_cooldown = maxf(_too_fast_cooldown - delta, 0.0)
	_push_rocks(delta)

	match state:
		State.CARRYING:
			slot_light = Color.TRANSPARENT

			if not _is_in_slot(ship):
				state = State.LEAVING
				player_left_bay.emit()
		State.WAITING:
			_count_down(delta)
			_check_docking()
		State.LEAVING:
			if can_pick_up:
				_check_docking()

			if state == State.LEAVING:
				_count_off_screen(delta)
		State.DOCKING:
			_pull_ship(delta)


# For ShipDamage: the hull moves, it's not a wall at rest.
func get_velocity_at(_global_point: Vector2) -> Vector2:
	return cruise_velocity


# For the map markers and the radar: they point at the player's slot. Empty text = not shown.
func get_marker_text() -> String:
	if not can_pick_up or state == State.DOCKING:
		return ""

	if state == State.LEAVING:
		return "MOTHERSHIP  LEAVING"

	var seconds := ceili(time_left)
	return "MOTHERSHIP  %d:%02d" % [floori(seconds / 60.0), seconds % 60]


func get_marker_color() -> Color:
	return CockpitPalette.YELLOW_LIT


func get_marker_position() -> Vector2:
	return to_global(player_slot.xform.origin)


func _is_on_screen() -> bool:
	var viewport := get_viewport()
	var view := viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()
	return view.intersects(global_transform * extent)


func _is_in_slot(body: Node2D) -> bool:
	var slot_xform: Transform2D = player_slot.xform
	var local := slot_xform.affine_inverse() * to_local(body.global_position)
	var size: Vector2 = SLOT_SIZE[player_slot.cls]
	return Rect2(-size / 2.0, size).has_point(local)


# Back on screen restarts the count.
func _count_off_screen(delta: float) -> void:
	if _is_on_screen():
		_off_screen_time = 0.0
		return

	_off_screen_time += delta

	if _off_screen_time >= despawn_delay:
		departed.emit()
		queue_free()


func _count_down(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)

	if not _has_warned and time_left <= warning_time:
		_has_warned = true
		message.emit("Dispatch: mothership leaves in %d s" % ceili(time_left))

	if time_left <= 0.0:
		state = State.LEAVING
		message.emit("Dispatch: mothership leaving")


# --- Docking


func _check_docking() -> void:
	slot_light = Color.TRANSPARENT

	if ship.freeze:
		return

	var relative_speed := (ship.linear_velocity - cruise_velocity).length()
	var is_close := ship.global_position.distance_to(get_marker_position()) <= light_range

	if is_close:
		slot_light = MothershipArt.LIGHT_GREEN if relative_speed <= max_dock_speed else MothershipArt.LIGHT_AMBER

	if not _is_in_slot(ship):
		return

	if relative_speed <= max_dock_speed:
		_start_docking()
		return

	if _too_fast_cooldown <= 0.0:
		_too_fast_cooldown = too_fast_message_delay
		message.emit("Slot: too fast, %d m/s (max %d)" % [roundi(relative_speed), roundi(max_dock_speed)])


func _start_docking() -> void:
	state = State.DOCKING
	slot_light = MothershipArt.LIGHT_GREEN
	var slot_xform: Transform2D = player_slot.xform
	_dock_from = (global_transform * slot_xform).affine_inverse() * ship.global_transform
	_dock_angle = 0.0 if absf(angle_difference(_dock_from.get_rotation(), 0.0)) <= PI / 2.0 else PI
	_dock_elapsed = 0.0
	ship.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	ship.freeze = true
	message.emit("Slot %02d: docking" % player_slot.number)


# Eases the ship into the middle of its slot, in the slot's space, so it rides along.
func _pull_ship(delta: float) -> void:
	_dock_elapsed += delta
	var t := smoothstep(0.0, dock_time, _dock_elapsed)
	var at := _dock_from.origin.lerp(Vector2.ZERO, t)
	var angle := lerp_angle(_dock_from.get_rotation(), _dock_angle, t)
	var slot_xform: Transform2D = player_slot.xform
	ship.global_transform = global_transform * slot_xform * Transform2D(angle, at)

	if _dock_elapsed >= dock_time and not _has_docked:
		_has_docked = true
		is_player_secured = true
		slot_light = Color.TRANSPARENT
		_art.queue_redraw()
		docked.emit()


# --- Deflector


# Rocks in the field get their speed corrected: ahead of the train, and away from its axis.
# A rock too heavy to clear in time still hits the ring, which is solid.
func _push_rocks(delta: float) -> void:
	var forward := Vector2.from_angle(global_rotation)
	var gain := minf(push_gain * delta, 1.0)

	for body in _field.get_overlapping_bodies():
		var rock := body as Asteroid

		if rock == null or not is_instance_valid(rock) or rock.freeze:
			continue

		var side := forward.orthogonal() * (1.0 if to_local(rock.global_position).y >= 0.0 else -1.0)
		var relative := rock.linear_velocity - cruise_velocity
		var change := forward * maxf(0.0, push_forward_speed - relative.dot(forward))
		change += side * maxf(0.0, push_side_speed - relative.dot(side))
		rock.apply_central_impulse(change * rock.mass * gain)


func _add_field() -> void:
	_field = Area2D.new()
	_field.collision_layer = 0
	_field.monitorable = false
	var shape := CollisionPolygon2D.new()
	shape.polygon = get_field_polygon()
	_field.add_child(shape)
	add_child(_field)


static func get_field_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 24

	for k in steps + 1:
		points.append(DEFLECTOR_CENTER + Vector2.from_angle(lerpf(-DEFLECTOR_ARC, DEFLECTOR_ARC, float(k) / steps)) * (DEFLECTOR_RADIUS + FIELD_DEPTH))

	for k in range(steps, -1, -1):
		points.append(DEFLECTOR_CENTER + Vector2.from_angle(lerpf(-DEFLECTOR_ARC, DEFLECTOR_ARC, float(k) / steps)) * (DEFLECTOR_RADIUS + 16.0))

	return points


# --- Collision


func _add_collisions() -> void:
	# Locomotive
	_add_rect(Rect2(20, -110, 70, 220)) # Thrust frame
	_add_rect(Rect2(60, -70, LOCO_LENGTH - 230.0, 140)) # Boxed truss
	_add_circle(Vector2(340, 0), 140.0) # Reactor cage
	_add_rect(Rect2(LOCO_LENGTH - 230.0, -130, 220, 260)) # Cab
	_add_rect(Rect2(LOCO_LENGTH + 70.0, -150, 40, 300)) # Deflector yoke
	_add_polygon(PackedVector2Array([Vector2(70, -70), Vector2(0, -40), Vector2(-20, -20), Vector2(-20, 20), Vector2(0, 40), Vector2(70, 70)])) # Tow yoke

	for side: float in [-1.0, 1.0]:
		_add_rect(Rect2(10, side * 380.0 - 110.0, 120, 220)) # Sponson

		for paddle_x in [210.0, 470.0, 640.0]:
			_add_polygon(get_paddle(paddle_x, side))

	# Deflector ring, in segments
	var steps := 12

	for k in steps:
		var a0 := lerpf(-DEFLECTOR_ARC, DEFLECTOR_ARC, float(k) / steps)
		var a1 := lerpf(-DEFLECTOR_ARC, DEFLECTOR_ARC, float(k + 1) / steps)
		_add_polygon(PackedVector2Array([
			DEFLECTOR_CENTER + Vector2.from_angle(a0) * (DEFLECTOR_RADIUS - 12.0), DEFLECTOR_CENTER + Vector2.from_angle(a0) * (DEFLECTOR_RADIUS + 14.0),
			DEFLECTOR_CENTER + Vector2.from_angle(a1) * (DEFLECTOR_RADIUS + 14.0), DEFLECTOR_CENTER + Vector2.from_angle(a1) * (DEFLECTOR_RADIUS - 12.0),
		]))

	# Drawbars and parked ships
	for i in cars.size():
		var car := cars[i]
		var ahead_x := 0.0 if i == 0 else float(cars[i - 1].x0)
		var x1: float = car.x1
		_add_rect(Rect2(x1 - 10.0, -16, ahead_x - x1 + 20.0, 32))

	for slot in slots:
		if slot.is_player:
			continue

		var size: Vector2 = SHIP_SIZE[slot.cls]
		var slot_xform: Transform2D = slot.xform
		_add_rect(Rect2(slot_xform.origin - size / 2.0, size))


static func get_paddle(root_x: float, side: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(root_x - 46.0, side * 80.0), Vector2(root_x - 76.0, side * 330.0),
		Vector2(root_x - 30.0 + 46.0, side * 330.0), Vector2(root_x + 46.0, side * 80.0),
	])


func _add_rect(rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.get_center()
	add_child(collision)


func _add_circle(center: Vector2, radius: float) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = center
	add_child(collision)


func _add_polygon(points: PackedVector2Array) -> void:
	var collision := CollisionPolygon2D.new()
	collision.polygon = points
	add_child(collision)
