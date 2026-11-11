class_name DemolitionCharge
extends SpaceProp

# A sticky charge, thrown from a ChargeRack. It flies with the momentum it was thrown with and
# sticks to the first rock it touches, where it touched, however long it flew. Thrown into a
# laser tunnel or a drill hole, it sticks deep inside the rock. A rock welded to a ship (RockBolter)
# counts: its collisions are on the ship's body, through shapes the rock owns.
# Stuck, it rides on its cell (BodyAnchor): if the rock is cut, it follows its piece. If its cell
# is destroyed, it falls off and drifts, and won't stick again.
# A charge still flying after stick_time, or fallen off, can be taken back (touch it gently).
# The rack detonates its charges (ChargeRack.detonate).
# Armed (stuck on a rock, ready to blow), it pulses: a red flash and a radar ring spreading out,
# every pulse_period. The first pulse fires the moment it sticks.

enum State { FLYING, STUCK, LOOSE }

@export var stick_time: float = 3.0 # s. Still flying after this: it's a loose charge, which can be taken back. It still sticks to rocks

@export_group("Armed pulse")
@export var pulse_period: float = 1.2 # s
@export var pulse_radius: float = 22.0 # px. How far the ring spreads
@export var pulse_color: Color = Color(1.0, 0.18, 0.12, 0.85)

var state: State = State.FLYING
var anchor: BodyAnchor
var order: int = 0 # Set by the rack: throw order, for the det-cord

var _armed_age: float = 0.0 # s since it stuck. Drives the pulse
var _has_stuck: bool = false # Once fallen off, a charge doesn't stick again


func _init() -> void:
	super()
	radius = 2.5
	recover_delay = 0.0
	body_color = Color(0.67, 0.36, 0.18)
	z_index = 2 # The pulse shows over the rock, and over chunks spawned after the charge


func _prop_process(delta: float) -> void:
	match state:
		State.FLYING:
			_try_stick()

			if state == State.FLYING and _age > stick_time:
				state = State.LOOSE
		State.LOOSE:
			if not _has_stuck:
				_try_stick()
		State.STUCK:
			_armed_age += delta
			_follow()


func can_recover() -> bool:
	return state == State.LOOSE


func is_stuck() -> bool:
	return state == State.STUCK


func get_rock() -> Asteroid:
	return anchor.get_asteroid() if anchor != null else null


func _try_stick() -> void:
	for rock in _get_touched_rocks():
		var point := rock.get_closest_point(global_position)
		anchor = BodyAnchor.on_body(rock, point)

		if not anchor.has_cell:
			continue

		state = State.STUCK
		_has_stuck = true
		_armed_age = 0.0
		collision_layer = 0
		collision_mask = 0
		freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = true
		global_position = point
		return


# Rocks this charge touches. Usually the body it touches is the rock. A rock welded to a ship
# has its collisions off, and copies of its shapes on the ship's body (RockBolter): the contact is
# with the ship, through a shape whose owner is the rock.
func _get_touched_rocks() -> Array[Asteroid]:
	var rocks: Array[Asteroid] = []
	var state := PhysicsServer2D.body_get_direct_state(get_rid())

	if state == null:
		return rocks

	for i in state.get_contact_count():
		var body := state.get_contact_collider_object(i) as CollisionObject2D

		if body == null:
			continue

		var rock := body as Asteroid

		if rock == null:
			var owner_id := body.shape_find_owner(state.get_contact_collider_shape(i))
			rock = body.shape_owner_get_owner(owner_id) as Asteroid

		if rock != null and rock.is_in_group(Asteroid.GROUP) and not rocks.has(rock):
			rocks.append(rock)

	return rocks


func _follow() -> void:
	if not anchor.resolve(get_tree()):
		_fall_off()
		return

	global_position = anchor.get_global_position()
	rotation = anchor.body.rotation


func _fall_off() -> void:
	state = State.LOOSE
	anchor = null
	freeze = false
	collision_layer = 1
	collision_mask = 1


func _draw_prop() -> void:
	var pulse := fmod(_armed_age, pulse_period) / pulse_period # 0 -> 1 over each pulse

	if state == State.STUCK:
		_draw_pulse(pulse)

	draw_rect(Rect2(-TEXEL * 1.5, -TEXEL * 1.5, TEXEL * 3.0, TEXEL * 3.0), outline_color)
	draw_rect(Rect2(-TEXEL, -TEXEL, TEXEL * 2.0, TEXEL * 2.0), body_color)

	if state == State.STUCK:
		_draw_light(Vector2.ZERO, pulse < 0.25)


# A flash at the start of each pulse, fading fast, and a ring spreading out and fading.
func _draw_pulse(pulse: float) -> void:
	var fade := 1.0 - pulse

	for i in 3:
		var glow := pulse_color
		glow.a *= 0.12 * (i + 1) * fade * fade * fade
		draw_circle(Vector2.ZERO, pulse_radius * 0.4 * (1.0 - i * 0.3), glow)

	var ring := pulse_color
	ring.a *= fade
	var ring_radius := pulse_radius * (1.0 - fade * fade) # Fast at first, slowing down: ease-out
	draw_arc(Vector2.ZERO, maxf(ring_radius, TEXEL), 0.0, TAU, 32, ring, TEXEL * 0.5)
