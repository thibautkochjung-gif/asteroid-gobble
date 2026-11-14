class_name ShipDamage
extends Node

# Collision damage: the hull's points, and wear on the parts close to each impact.
#
# Impacts: the ship's body reports its contacts (contact_monitor). A body that touches the ship now
# but didn't on the last frame is one impact. Contacts on the arm tools' shapes don't count, and
# contacts on a shield's shapes (DeflectorProw) go to its absorb_impact() instead. A body that stays in contact (resting, scraping,
# being pushed) does no more damage.
#
# Impact energy, the kinetic energy the hit can take out of the two bodies:
#   E = 1/2 * mu * v^2
# v: closing speed along the contact normal, at the contact point (spin included).
# mu: the pair's effective mass there, 1 / (1/m_ship + 1/m_other). Each 1/m also counts rotation
# (+ lever^2 / inertia): a glancing hit far from the centre of mass spins the body more than it
# stops it, so it takes less energy out. A static body has 1/m = 0, so mu is the ship's own mass.
# The velocities are those from before the hit: when Godot reports a contact, the bodies have
# already bounced. So every frame, this node records the velocities of the ship and of the bodies
# around it, to use if they hit it during the next physics step.
#
# Hull: loses E. Its max is the energy of a head-on hit at lethal_speed against something immovable,
# with the ship's starting mass. E grows with the square of the speed: a hit at a tenth of
# lethal_speed takes 1/100 of the hull. A loaded ship carries more energy, so it takes more.
#
# Parts: anything under the ship with get_part_health() (see PartHealth). Their damage grows with
# the square root of E (so, like the impact speed), not with E: on an energy scale, a part that
# survives 4-5 slow bumps would also survive 2 medium ones easily. A standard part (toughness 1) is
# destroyed by one head-on hit at part_break_speed. Parts away from the contact point get less:
# full damage up to full_damage_radius, then less and less, none past damage_radius.
#
# Destroyed (hull at 0): every part breaks, so nothing works any more.
#
# Keep this node below ShipMass in the tree: its _ready() reads the ship's starting mass.

signal hull_changed
signal destroyed

@export var ship: RigidBody2D
@export var lethal_speed: float = 400.0 # px/s. One head-on hit at this speed destroys the hull. Hull points grow with its square (was 283: hull damage halved)
@export var part_break_speed: float = 180.0 # px/s. One head-on hit at this speed destroys a standard part (was 90: part damage halved)
@export var heavy_hit_share: float = 0.25 # Share of the hull a head-on hit must take to count as heavy. Start of the speed danger
@export var min_impact_speed: float = 4.0 # px/s. Slower contacts are settling, not hits
@export var full_damage_radius: float = 12.0 # px from the contact point to a part
@export var damage_radius: float = 40.0
@export var record_radius: float = 320.0 # px. Bodies closer than this get their velocity recorded
@export var shake_strength: float = 0.75 # Camera trauma for a lethal hit (1 = max). Grows with the impact speed
@export var log_impacts: bool = true # Prints each hit to the Output panel, for tuning

var max_hull: float
var hull: float
var is_destroyed: bool = false

var _reference_mass: float # Ship's mass at start
var _ship_velocity: Vector2 = Vector2.ZERO # Recorded before the physics step
var _ship_spin: float = 0.0
var _body_velocities: Dictionary[int, Vector2] = {} # Instance id -> velocity before the step
var _body_spins: Dictionary[int, float] = {}
var _touching: Dictionary[int, bool] = {} # Instance ids of the bodies in contact on the last frame
var _shield_touching: Dictionary[int, bool] = {} # Same, for the bodies on a shield (absorb_impact())
var _parts: Array[Node] = [] # get_parts() result for _parts_frame
var _parts_frame: int = -1
var _nearby: Dictionary[RigidBody2D, bool] = {} # Bodies within record_radius, kept by _nearby_area's signals


func _ready() -> void:
	ship.contact_monitor = true
	ship.max_contacts_reported = maxi(ship.max_contacts_reported, 16)

	_reference_mass = ship.mass

	_add_nearby_area.call_deferred() # The ship is still adding its children
	max_hull = _get_head_on_energy(lethal_speed)
	hull = max_hull


## How dangerous a head-on hit at this speed would be: 0 while it would take less than
## heavy_hit_share of the hull, 1 at lethal_speed (the ship is destroyed). Hull damage grows with
## the square of the speed, so with a share of 0.25 the danger starts at half of lethal_speed.
## Drives SpeedFx and the cockpit's speed readout.
func get_speed_danger(speed: float) -> float:
	return smoothstep(lethal_speed * sqrt(heavy_hit_share), lethal_speed, speed)


# Runs before this frame's physics step: the contacts are those of the last step, and the
# velocities recorded on the last frame are from before it.
func _physics_process(_delta: float) -> void:
	var state := PhysicsServer2D.body_get_direct_state(ship.get_rid())

	if state == null:
		return

	_detect_impacts(state)
	_record_velocities(state)


func get_hull_ratio() -> float:
	if max_hull <= 0.0:
		return 0.0

	return hull / max_hull


# Every part on the ship. Found by method, because thrusters, weapons, soft point modules and the
# hangar don't share a base class. Searched once per frame (the search walks the whole ship, and
# several widgets ask every frame), and again if a part left the ship meanwhile: swapped modules
# are always included. Read-only: the array is shared between callers.
func get_parts() -> Array[Node]:
	var frame := Engine.get_process_frames()

	if frame == _parts_frame and _are_parts_aboard():
		return _parts

	_parts_frame = frame
	_parts.clear()

	for node in ship.find_children("*", "", true, false):
		if node.has_method(&"get_part_health"):
			_parts.append(node)

	return _parts


func _are_parts_aboard() -> bool:
	for part in _parts:
		if not is_instance_valid(part) or not ship.is_ancestor_of(part):
			return false

	return true


# Parts share methods, not a class: call() reaches them whatever their script.
static func get_health(part: Node) -> PartHealth:
	return part.call(&"get_part_health")


static func get_part_name(part: Node) -> String:
	return part.call(&"get_part_name")


static func get_damage_points(part: Node) -> PackedVector2Array:
	return part.call(&"get_damage_points")


func repair_all() -> void:
	hull = max_hull
	is_destroyed = false
	hull_changed.emit()

	for part in get_parts():
		get_health(part).repair()


# --- Impacts


func _detect_impacts(state: PhysicsDirectBodyState2D) -> void:
	var touching: Dictionary[int, bool] = {}
	var shield_touching: Dictionary[int, bool] = {}

	for i in state.get_contact_count():
		var collider_id := state.get_contact_collider_id(i)
		var shape_owner := _get_contact_owner(state, i)

		# Arm tools (drill, grabber, splitter) are made to touch rock: a rock on one isn't a hit.
		# It only counts once it touches the hull itself.
		if shape_owner is RobotArm:
			continue

		# Shields (the deflector prow) take the hit in the hull's place: absorb_impact() decides what
		# it does to them. Tracked apart, so a rock that slides off a shield onto the hull still hits it.
		if shape_owner != null and shape_owner.has_method(&"absorb_impact"):
			if shield_touching.has(collider_id):
				continue

			shield_touching[collider_id] = true

			if not _shield_touching.has(collider_id) and not is_destroyed:
				var impact := _measure_impact(state, i)

				if not impact.is_empty():
					shape_owner.call(&"absorb_impact", impact)

			continue

		# Several contact points on one body make one hit, measured at the first of them.
		if touching.has(collider_id):
			continue

		touching[collider_id] = true

		if not _touching.has(collider_id) and not is_destroyed:
			_on_impact(state, i)

	_touching = touching
	_shield_touching = shield_touching


# What owns the ship's side of this contact: a hull CollisionShape2D, a RobotArm (its links and
# head), a DeflectorProw...
func _get_contact_owner(state: PhysicsDirectBodyState2D, contact: int) -> Object:
	var owner_id := ship.shape_find_owner(state.get_contact_local_shape(contact))
	return ship.shape_owner_get_owner(owner_id)


func _on_impact(state: PhysicsDirectBodyState2D, contact: int) -> void:
	var impact := _measure_impact(state, contact)

	if impact.is_empty():
		return

	var energy: float = impact.energy
	_damage_parts(energy, impact.point)
	_damage_hull(energy)
	_shake_camera(energy)

	if log_impacts:
		print("Impact: %.0f px/s, energy %.0f = %.1f%% of the hull. Hull at %.0f%%" % [impact.speed, energy, 100.0 * energy / max_hull, 100.0 * get_hull_ratio()])


# One contact, from the velocities before the hit: { speed, energy, other_mass, point }.
# other_mass is INF for anything immovable (static, frozen, the mothership).
# Empty if the bodies closed too slowly for a hit.
func _measure_impact(state: PhysicsDirectBodyState2D, contact: int) -> Dictionary:
	var collider_id := state.get_contact_collider_id(contact)
	var point := state.get_contact_local_position(contact) # Global, despite the name
	var normal := state.get_contact_local_normal(contact)

	var ship_offset := point - (state.transform.origin + state.center_of_mass)
	var ship_velocity := _get_velocity_at(_ship_velocity, _ship_spin, ship_offset)
	var inverse_mass := _get_inverse_mass_at(state, ship_offset, normal)
	var other_velocity := Vector2.ZERO
	var other_mass := INF
	var collider := state.get_contact_collider_object(contact)
	var body := collider as RigidBody2D
	var mothership := collider as Mothership

	# The mothership: infinite mass, but moving. Anything else (static, frozen) counts as immovable:
	# no velocity, infinite mass.
	if mothership != null:
		other_velocity = mothership.get_velocity_at(point)
	elif body != null and not body.freeze:
		var other_state := PhysicsServer2D.body_get_direct_state(body.get_rid())
		var other_offset := point - (other_state.transform.origin + other_state.center_of_mass)
		var linear: Vector2 = _body_velocities.get(collider_id, body.linear_velocity)
		var spin: float = _body_spins.get(collider_id, body.angular_velocity)
		other_velocity = _get_velocity_at(linear, spin, other_offset)
		other_mass = body.mass
		inverse_mass += _get_inverse_mass_at(other_state, other_offset, normal)

	# New contact: the bodies were closing in, whichever way the normal points.
	var speed := absf((ship_velocity - other_velocity).dot(normal))

	if speed < min_impact_speed or inverse_mass <= 0.0:
		return {}

	return {
		"speed": speed,
		"energy": 0.5 * speed * speed / inverse_mass,
		"other_mass": other_mass,
		"point": point,
	}


func _damage_hull(energy: float) -> void:
	hull = maxf(hull - energy, 0.0)
	hull_changed.emit()

	if hull <= 0.0:
		_destroy()


func _damage_parts(energy: float, point: Vector2) -> void:
	var damage := PartHealth.BASE_POINTS * sqrt(energy / _get_head_on_energy(part_break_speed))

	for part in get_parts():
		var distance: float = part.call(&"get_hit_distance", point)
		var share := _get_falloff(distance)

		if share <= 0.0:
			continue

		get_health(part).take_damage(damage * share)


func _destroy() -> void:
	is_destroyed = true

	for part in get_parts():
		get_health(part).take_damage(INF)

	destroyed.emit()
	print("Ship destroyed")


# 1 within full_damage_radius, down to 0 at damage_radius.
func _get_falloff(distance: float) -> float:
	if distance <= full_damage_radius:
		return 1.0

	return clampf(inverse_lerp(damage_radius, full_damage_radius, distance), 0.0, 1.0)


# A low bump barely shakes; a lethal hit shakes all the way.
func _shake_camera(energy: float) -> void:
	var amount := clampf(sqrt(energy / max_hull) * shake_strength, 0.0, 1.0)

	if amount >= 0.05:
		Fx.shake(amount)


# --- Physics helpers


# Energy of a head-on hit at that speed, by the ship at its starting mass, on something immovable.
func _get_head_on_energy(speed: float) -> float:
	return 0.5 * _reference_mass * speed * speed


# Velocity of the body's material at offset (from its centre of mass): linear + the part due to spin.
func _get_velocity_at(linear: Vector2, spin: float, offset: Vector2) -> Vector2:
	return linear + Vector2(-spin * offset.y, spin * offset.x)


# How easily a push along normal, at offset, changes the body's speed there: 1/m for a push through
# the centre of mass, more when the push also turns the body.
func _get_inverse_mass_at(state: PhysicsDirectBodyState2D, offset: Vector2, normal: Vector2) -> float:
	var lever := offset.cross(normal)
	return state.inverse_mass + lever * lever * state.inverse_inertia


func _record_velocities(state: PhysicsDirectBodyState2D) -> void:
	_ship_velocity = state.linear_velocity
	_ship_spin = state.angular_velocity
	_body_velocities.clear()
	_body_spins.clear()

	# Only the bodies around the ship. Walking every rock in the field (or querying a shape each
	# frame) cost milliseconds per frame, and grew with the field.
	for body in _nearby.keys():
		if not is_instance_valid(body):
			_nearby.erase(body) # Freed without leaving the circle first
			continue

		var id: int = body.get_instance_id()
		_body_velocities[id] = body.linear_velocity
		_body_spins[id] = body.angular_velocity


# A circle that rides with the ship. The physics server tracks what enters and leaves it, so the
# list of nearby bodies costs nothing to keep.
func _add_nearby_area() -> void:
	var circle := CircleShape2D.new()
	circle.radius = record_radius
	var shape := CollisionShape2D.new()
	shape.shape = circle

	var area := Area2D.new()
	area.name = "DamageNearby"
	area.collision_layer = 0
	area.collision_mask = ship.collision_mask
	area.monitorable = false
	area.add_child(shape)
	area.body_entered.connect(_on_nearby_entered)
	area.body_exited.connect(_on_nearby_exited)
	ship.add_child(area)


func _on_nearby_entered(body: Node2D) -> void:
	var rigid := body as RigidBody2D

	if rigid != null and rigid != ship:
		_nearby[rigid] = true


func _on_nearby_exited(body: Node2D) -> void:
	var rigid := body as RigidBody2D # Static and animatable bodies (the mothership) were never kept

	if rigid != null:
		_nearby.erase(rigid)
