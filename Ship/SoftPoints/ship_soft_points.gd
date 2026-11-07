class_name ShipSoftPoints
extends Node2D

# Owns the soft point mounts (the SoftPointMount children) and what's bolted on them.
# Mount N is used with the input action "soft_point_N" (keys 1-4). Tap and hold are worked out by
# each module (SoftPoint).
# Other systems go through this node, never through a module type: the thrusters ask it for fuel
# (drop tanks first), the generator for power (capacitors first), ShipMass for mass, the HUD and
# the pause menu for text and layout.
#
# Tearing off: the ship's body reports contacts (contact_monitor, turned on here). When a body
# hits a module's own collision shape, the hit's strength is measured from how much the ship's
# velocity jumped during that physics step, times its mass: the impulse the ship took. Above the
# module's break_impulse, the module comes off and floats away (ModuleProp).
# Thrust alone changes the velocity by a few px/s per step, far below that.
#
# Recovering: a SpaceProp touching the hull slowly enough calls try_recover(). A ModuleProp goes
# back on the empty mount closest to where it touched. Any other prop goes back in the nearest
# module that takes it (a rack of the right kind, with room).

signal layout_changed
signal message(mount_index: int, text: String)

const META_KEY: StringName = &"soft_points" # On the ship's body, so props can find this node

# Paths + load(), like the hardpoints and the rooms: no preload cycle with the module scripts.
const SCENE_PATHS := {
	SoftPoint.Type.DROP_TANK: "res://Ship/SoftPoints/drop_tank.tscn",
	SoftPoint.Type.TETHER: "res://Ship/SoftPoints/tether.tscn",
	SoftPoint.Type.BEACON_RACK: "res://Ship/SoftPoints/beacon_rack.tscn",
	SoftPoint.Type.HARPOON: "res://Ship/SoftPoints/harpoon_winch.tscn",
	SoftPoint.Type.CHARGE_RACK: "res://Ship/SoftPoints/charge_rack.tscn",
	SoftPoint.Type.MAGNETIC_CLAMP: "res://Ship/SoftPoints/magnetic_clamp.tscn",
	SoftPoint.Type.BALLAST: "res://Ship/SoftPoints/ballast_pod.tscn",
	SoftPoint.Type.CAPACITOR: "res://Ship/SoftPoints/capacitor_pack.tscn",
	SoftPoint.Type.PROBE_RACK: "res://Ship/SoftPoints/probe_rack.tscn",
	SoftPoint.Type.FLARE_RACK: "res://Ship/SoftPoints/flare_rack.tscn",
	SoftPoint.Type.CACHE_BUOY: "res://Ship/SoftPoints/cache_buoy_rack.tscn",
	SoftPoint.Type.CARGO_CANISTER: "res://Ship/SoftPoints/canister_rack.tscn",
}

@export var ship: RigidBody2D
@export var rooms: ShipRooms # The cargo canister takes ore from the cargo rooms and puts it back
@export var generator: Generator # Modules that use power (harpoon reel, clamp) draw from it
@export var starting_layout: Array[SoftPoint.Type] = [SoftPoint.Type.HARPOON, SoftPoint.Type.DROP_TANK, SoftPoint.Type.TETHER, SoftPoint.Type.BEACON_RACK]
@export var recover_speed: float = 40.0 # px/s. Props touching the hull slower than this are taken back
@export var tear_off_enabled: bool = true

var mounts: Array[SoftPointMount] = []
var modules: Array[SoftPoint] = [] # Same index as mounts. null = empty mount

var _last_velocity: Vector2 = Vector2.ZERO # Ship's velocity before the last physics step
# Bodies the ship doesn't collide with for a while: instance id -> seconds left.
# Keyed by id, not by the body: a typed dictionary can't even erase a key once its body is freed.
var _ignored: Dictionary[int, float] = {}


func _ready() -> void:
	ship.set_meta(META_KEY, self)
	ship.contact_monitor = true
	ship.max_contacts_reported = maxi(ship.max_contacts_reported, 16)
	ship.body_shape_entered.connect(_on_ship_body_shape_entered)

	for child in get_children():
		if child is SoftPointMount:
			mounts.append(child)

	modules.resize(mounts.size())

	for i in mini(mounts.size(), starting_layout.size()):
		install(i, starting_layout[i])

	_last_velocity = ship.linear_velocity


func _physics_process(delta: float) -> void:
	_last_velocity = ship.linear_velocity
	_tick_ignored(delta)


# --- Layout


func install(mount_index: int, type: SoftPoint.Type) -> void:
	var old_module := modules[mount_index]

	if old_module != null:
		if old_module.soft_point_type == type:
			return

		_take_off(mount_index)
		old_module.queue_free()

	var module: SoftPoint = load(SCENE_PATHS[type]).instantiate()
	module.soft_point_type = type
	_put_on(mount_index, module)


func clear_mount(mount_index: int) -> void:
	var module := modules[mount_index]

	if module != null:
		_take_off(mount_index)
		module.queue_free()


func get_mount_count() -> int:
	return mounts.size()


func get_module(mount_index: int) -> SoftPoint:
	return modules[mount_index]


func get_action(mount_index: int) -> StringName:
	return StringName("soft_point_%d" % [mount_index + 1])


func get_mount_name(mount_index: int) -> String:
	return mounts[mount_index].display_name


# --- Leaving the ship


# Throws the module away from its mount, gently, with whatever it holds.
func jettison(module: SoftPoint) -> void:
	var index := modules.find(module)

	if index < 0:
		return

	var push := module.get_outward() * module.jettison_speed
	_release_as_prop(index, push, 0.0)
	message.emit(index, "%s jettisoned" % module.get_type_name())


# A hard hit: the module comes off and tumbles away.
func tear_off(module: SoftPoint) -> void:
	var index := modules.find(module)

	if index < 0:
		return

	var push := module.get_outward() * module.jettison_speed * 1.5
	_release_as_prop(index, push, randf_range(-3.0, 3.0))
	message.emit(index, "%s torn off!" % module.get_type_name())
	Fx.shake(0.3)


# --- Coming back


# Called by a prop touching the hull slowly. Returns true if it was taken back (the prop is freed).
func try_recover(prop: SpaceProp) -> bool:
	if prop is ModuleProp:
		return _recover_module(prop as ModuleProp)

	var best: SoftPoint = null
	var best_distance := INF

	for module in modules:
		if module == null or not module.accepts_prop(prop):
			continue

		var distance := module.global_position.distance_to(prop.global_position)

		if distance < best_distance:
			best_distance = distance
			best = module

	if best == null:
		return false

	# recover_prop() frees the prop at the end of the frame: its mass and velocity can still be read.
	if not best.recover_prop(prop):
		return false

	_absorb_momentum(prop)
	return true


# The ship doesn't collide with this body for a while. Things just thrown out start overlapping
# the hull's edge, or would bounce straight back.
func ignore_collisions_for(body: RigidBody2D, seconds: float) -> void:
	if not is_instance_valid(body):
		return

	var id := body.get_instance_id()
	ship.add_collision_exception_with(body)
	_ignored[id] = maxf(_ignored.get(id, 0.0), seconds)


# --- Resources, for the ship's systems


# Drop tanks, in mount order. Returns how much fuel was given.
func draw_fuel(amount: float) -> float:
	var granted := 0.0

	for module in modules:
		if granted >= amount:
			break

		if module != null:
			granted += module.draw_fuel(amount - granted)

	return granted


func get_fuel() -> float:
	var total := 0.0

	for module in modules:
		if module != null:
			total += module.get_fuel()

	return total


func get_fuel_capacity() -> float:
	var total := 0.0

	for module in modules:
		if module != null:
			total += module.get_fuel_capacity()

	return total


# Capacitors, in mount order. Returns how much power was given.
func draw_power(amount: float) -> float:
	var granted := 0.0

	for module in modules:
		if granted >= amount:
			break

		if module != null:
			granted += module.draw_power(amount - granted)

	return granted


# Generator surplus. Returns how much was stored.
func store_power(amount: float) -> float:
	var stored := 0.0

	for module in modules:
		if stored >= amount:
			break

		if module != null:
			stored += module.store_power(amount - stored)

	return stored


func get_power() -> float:
	var total := 0.0

	for module in modules:
		if module != null:
			total += module.get_power()

	return total


func get_power_capacity() -> float:
	var total := 0.0

	for module in modules:
		if module != null:
			total += module.get_power_capacity()

	return total


func restock() -> void:
	for module in modules:
		if module != null:
			module.restock()


# --- Mass, for ShipMass


func get_total_mass() -> float:
	var total := 0.0

	for module in modules:
		if module != null:
			total += module.get_mass()

	return total


# Sum of mass * position over every module, in the ship's space. ShipMass divides by the total.
func get_weighted_position_sum() -> Vector2:
	var total := Vector2.ZERO

	for module in modules:
		if module != null:
			total += ship.to_local(module.get_mass_center()) * module.get_mass()

	return total


# --- Messages


func relay_message(module: SoftPoint, text: String) -> void:
	message.emit(modules.find(module), text)


# --- Internals


func _put_on(mount_index: int, module: SoftPoint) -> void:
	if module.get_parent() != null:
		module.get_parent().remove_child(module)

	mounts[mount_index].add_child(module)
	module.transform = Transform2D.IDENTITY
	modules[mount_index] = module
	module.attach(ship, self, mounts[mount_index], get_action(mount_index))
	layout_changed.emit()


func _take_off(mount_index: int) -> SoftPoint:
	var module := modules[mount_index]
	module.detach()
	mounts[mount_index].remove_child(module)
	modules[mount_index] = null
	layout_changed.emit()
	return module


func _release_as_prop(mount_index: int, push: Vector2, spin: float) -> void:
	var module := modules[mount_index]
	var at := module.global_transform
	var velocity := SoftLink.velocity_at(ship, module.get_mass_center()) + push
	var mass := module.get_mass()

	_take_off(mount_index)

	var prop := ModuleProp.new()
	prop.hold(module)
	ship.get_parent().add_child(prop)
	prop.global_transform = at
	prop.linear_velocity = velocity
	prop.angular_velocity = ship.angular_velocity + spin

	# Newton: what pushes the module out pushes the ship back.
	ship.apply_impulse(-push * mass, at.origin - ship.global_position)
	ignore_collisions_for(prop, 1.0)


func _recover_module(prop: ModuleProp) -> bool:
	var best := -1
	var best_distance := INF

	for i in mounts.size():
		if modules[i] != null:
			continue

		var distance := mounts[i].global_position.distance_to(prop.global_position)

		if distance < best_distance:
			best_distance = distance
			best = i

	if best < 0:
		return false

	_absorb_momentum(prop)
	var module := prop.release_module()
	_put_on(best, module)
	prop.queue_free()
	message.emit(best, "%s recovered" % module.get_type_name())
	return true


# The prop becomes part of the ship: momentum is conserved, like the hangar's catch.
# ShipMass adds the prop's mass on the next frame.
func _absorb_momentum(prop: RigidBody2D) -> void:
	var total_mass := ship.mass + prop.mass
	ship.linear_velocity = (ship.linear_velocity * ship.mass + prop.linear_velocity * prop.mass) / total_mass


func _tick_ignored(delta: float) -> void:
	for id in _ignored.keys():
		var body := instance_from_id(id) as RigidBody2D

		if body == null:
			_ignored.erase(id)
			continue

		_ignored[id] -= delta

		if _ignored[id] <= 0.0:
			_ignored.erase(id)
			ship.remove_collision_exception_with(body)


func _on_ship_body_shape_entered(_body_rid: RID, _body: Node, _body_shape_index: int, local_shape_index: int) -> void:
	if not tear_off_enabled or local_shape_index < 0:
		return

	var owner_id := _find_shape_owner(local_shape_index)

	if owner_id < 0:
		return

	var module := ship.shape_owner_get_owner(owner_id) as SoftPoint

	if module == null or module.ship != ship:
		return

	var impulse := (ship.linear_velocity - _last_velocity).length() * ship.mass

	if impulse >= module.break_impulse:
		tear_off.call_deferred(module) # Not while the physics server is reporting contacts


# shape_find_owner() errors on an index that no longer exists (shapes change between the
# physics step and this report: the tether rebuilds its shapes, modules come and go).
func _find_shape_owner(shape_index: int) -> int:
	var count := 0

	for owner_id in ship.get_shape_owners():
		count += ship.shape_owner_get_shape_count(owner_id)

	if shape_index >= count:
		return -1

	return ship.shape_find_owner(shape_index)
