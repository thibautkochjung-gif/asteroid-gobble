class_name AsteroidField
extends Node2D

# Streams asteroids around the camera, sector by sector. AsteroidSectorPlanner works out what each
# sector holds; planning and building the rocks (AsteroidBlueprint) happen on worker threads.
# This node only spawns finished rocks, a few per frame, and frees the ones whose sector got far.
#
# Rocks are children of this node, so chunks cut off them land here too.
# Until saving exists:
# - a rock that was cut (Asteroid.was_cut) stays loaded for good, and so do all chunks;
# - an untouched rock is freed with its sector and comes back as new when the sector reloads;
# - a rock that left the field (cut and destroyed, grabbed, smelted) never comes back.
#
# Rocks far outside the view are parked: frozen, their drift and spin put aside, then given back
# when the view comes near. Nothing reaches that far, and moving bodies cost physics time.
# Chunks are parked too: they pile up as the player mines, and none of them ever leaves.

@export var profile: AsteroidFieldProfile
@export var asteroid_scene: PackedScene = preload("res://Asteroids/asteroid.tscn")
@export var world_seed: int = 1
@export var load_margin: float = 2048.0 # px around the camera's view (at the current zoom). Sectors there get planned and built
@export var unload_margin: float = 4096.0 # Sectors farther than this from the view are freed. Larger than load_margin: no flicker at the border
@export var spawn_budget_ms: float = 3.0 # Main thread time spent adding rocks, per frame
@export var awake_margin: float = 1200.0 # px around the view. Field rocks farther out are parked
@export var park_check_interval: float = 0.25 # s between two passes over the rocks
@export var debug_draw: bool = false # Outlines the loaded sectors, shaded by density

@export_group("Start")
@export var clear_center := Vector2.ZERO # No rock spawns within clear_radius of this point: the drop-off spot
@export var clear_radius: float = 700.0
@export var starter_cluster: AsteroidFormation # Always placed, for testing. Null = none
@export var starter_cluster_offset := Vector2(1700.0, 400.0) # From clear_center

var _sectors: Dictionary[Vector2i, SectorState] = {}
var _builds: Array[BuildJob] = [] # Blueprints being built on worker threads
var _to_spawn: Array[BuildJob] = [] # Built, waiting for their turn on the main thread
var _live: Dictionary[int, Asteroid] = {} # Field rocks in the tree, by Spec id
var _gone: Dictionary[int, bool] = {} # Field rocks that left the field: never spawned again
var _pinned: Array[AsteroidSectorPlanner.PinnedFormation] = []
var _cell_size: float = 4.0
var _debug_planner: AsteroidSectorPlanner
var _parked: Dictionary[Asteroid, Vector3] = {} # Parked rock -> its velocity (x, y) and spin (z)
var _park_timer: float = 0.0


class SectorState:
	var sector := Vector2i.ZERO
	var plan_task: int = -1 # WorkerThreadPool task, -1 once collected
	var planner: AsteroidSectorPlanner
	var specs: Array[AsteroidSectorPlanner.Spec] = []
	var rocks: Array[Asteroid] = []
	var dropped: bool = false # Unloaded while some of its work was still running

	func plan() -> void:
		specs = planner.plan_sector(sector)


class BuildJob:
	var task: int = -1
	var spec: AsteroidSectorPlanner.Spec
	var blueprint: AsteroidBlueprint
	var state: SectorState


func _ready() -> void:
	var probe := asteroid_scene.instantiate() as Asteroid
	_cell_size = probe.cell_size
	probe.free()

	if starter_cluster != null:
		var pin := AsteroidSectorPlanner.PinnedFormation.new()
		pin.formation = starter_cluster
		pin.center = clear_center + starter_cluster_offset
		pin.formation_seed = hash(world_seed + 7)
		_pinned.append(pin)

	_debug_planner = _make_planner()


func _process(delta: float) -> void:
	if profile == null:
		return

	var view := _get_view_rect()

	if view.size == Vector2.ZERO:
		return

	_load_sectors_around(view)
	_unload_sectors_away_from(view)
	_collect_plans(view)
	_collect_builds()
	_spawn_some()

	_park_timer -= delta

	if _park_timer <= 0.0:
		_park_timer = park_check_interval
		_park_far_rocks(view)

	if debug_draw:
		queue_redraw()


func _exit_tree() -> void:
	# Worker tasks must be waited for before their data goes away.
	for state: SectorState in _sectors.values():
		if state.plan_task != -1:
			WorkerThreadPool.wait_for_task_completion(state.plan_task)
			state.plan_task = -1

	for job in _builds:
		WorkerThreadPool.wait_for_task_completion(job.task)

	_builds.clear()


# What the field holds right now. For tests and tuning.
func get_stats() -> Dictionary:
	var planning := 0

	for state: SectorState in _sectors.values():
		if state.plan_task != -1:
			planning += 1

	return {
		"sectors": _sectors.size(),
		"planning": planning,
		"building": _builds.size(),
		"waiting": _to_spawn.size(),
		"rocks": _live.size(),
	}


# A planner with this field's settings. Each worker task gets its own: planners own a noise object.
func _make_planner() -> AsteroidSectorPlanner:
	var planner := AsteroidSectorPlanner.new(profile, world_seed, _cell_size)
	planner.pinned = _pinned
	planner.clear_center = clear_center
	planner.clear_radius = clear_radius
	return planner


# The part of the world the camera shows, in this node's space.
func _get_view_rect() -> Rect2:
	var camera := get_viewport().get_camera_2d()

	if camera == null:
		return Rect2()

	var size := get_viewport_rect().size / camera.zoom
	var center := to_local(camera.get_screen_center_position())
	return Rect2(center - size * 0.5, size)


func _get_sectors_in(area: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var first := Vector2i((area.position / profile.sector_size).floor())
	var last := Vector2i((area.end / profile.sector_size).floor())

	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			found.append(Vector2i(x, y))

	return found


# Starts planning the sectors around the view that aren't loaded yet, nearest first.
func _load_sectors_around(view: Rect2) -> void:
	var missing: Array[Vector2i] = []

	for sector in _get_sectors_in(view.grow(load_margin)):
		if not _sectors.has(sector):
			missing.append(sector)

	if missing.is_empty():
		return

	var center := view.get_center()
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _sector_distance(a, center) < _sector_distance(b, center))

	for sector in missing:
		var state := SectorState.new()
		state.sector = sector
		state.planner = _make_planner()
		state.plan_task = WorkerThreadPool.add_task(state.plan, false, "Plan asteroid sector")
		_sectors[sector] = state


func _unload_sectors_away_from(view: Rect2) -> void:
	var keep := view.grow(unload_margin)

	for sector: Vector2i in _sectors.keys():
		var state := _sectors[sector]

		if keep.intersects(state.planner.get_sector_rect(sector)):
			continue

		for rock in state.rocks:
			if is_instance_valid(rock) and not rock.was_cut:
				_live.erase(rock.field_id) # Before freeing: leaving now is not "gone"
				_parked.erase(rock)
				rock.queue_free()

		state.dropped = true
		_sectors.erase(sector)

		if state.plan_task != -1:
			# Can't cancel a running task: leave it be and collect it with the dropped builds.
			var job := BuildJob.new()
			job.task = state.plan_task
			job.state = state
			_builds.append(job)
			state.plan_task = -1


# Sectors whose plan is ready: start building their rocks, nearest to the view first.
func _collect_plans(view: Rect2) -> void:
	var center := view.get_center()

	for state: SectorState in _sectors.values():
		if state.plan_task == -1 or not WorkerThreadPool.is_task_completed(state.plan_task):
			continue

		WorkerThreadPool.wait_for_task_completion(state.plan_task)
		state.plan_task = -1
		state.specs.sort_custom(func(a: AsteroidSectorPlanner.Spec, b: AsteroidSectorPlanner.Spec) -> bool: return a.position.distance_squared_to(center) < b.position.distance_squared_to(center))

		for spec in state.specs:
			if _live.has(spec.id) or _gone.has(spec.id):
				continue

			var job := BuildJob.new()
			job.spec = spec
			job.state = state
			job.blueprint = _make_blueprint(spec)
			job.task = WorkerThreadPool.add_task(job.blueprint.build, false, "Build asteroid")
			_builds.append(job)


func _make_blueprint(spec: AsteroidSectorPlanner.Spec) -> AsteroidBlueprint:
	var plan := AsteroidBlueprint.new()
	plan.generation_seed = spec.generation_seed
	plan.radius_in_cells = spec.radius_in_cells
	plan.ore_type = spec.ore_type
	plan.ore_ratio = spec.ore_ratio
	plan.ore_reference_radius = profile.ore_reference_radius
	plan.ore_cluster_growth = profile.ore_cluster_growth
	plan.ore_share_growth = profile.ore_share_growth
	plan.max_ore_share = profile.max_ore_share
	return plan


func _collect_builds() -> void:
	var still_building: Array[BuildJob] = []

	for job in _builds:
		if not WorkerThreadPool.is_task_completed(job.task):
			still_building.append(job)
			continue

		WorkerThreadPool.wait_for_task_completion(job.task)

		if job.spec != null and not job.state.dropped:
			_to_spawn.append(job)

	_builds = still_building


# Adds finished rocks until the frame's budget is spent. Textures and shapes: ~0.1 ms for a
# pebble, ~30 ms for a giant, so a giant may take a frame on its own.
func _spawn_some() -> void:
	var start := Time.get_ticks_usec()

	while not _to_spawn.is_empty() and Time.get_ticks_usec() - start < spawn_budget_ms * 1000.0:
		var job: BuildJob = _to_spawn.pop_front()

		if job.state.dropped or _live.has(job.spec.id) or _gone.has(job.spec.id):
			continue

		_spawn(job)


func _spawn(job: BuildJob) -> void:
	var spec := job.spec
	var rock := asteroid_scene.instantiate() as Asteroid
	rock.blueprint = job.blueprint
	rock.field_id = spec.id
	rock.position = spec.position
	rock.rotation = spec.rotation
	rock.linear_velocity = spec.linear_velocity
	rock.angular_velocity = spec.angular_velocity
	rock.tree_exited.connect(_on_rock_left.bind(rock, spec.id))
	add_child(rock)

	_live[spec.id] = rock
	job.state.rocks.append(rock)
	rock.can_sleep = false # Its drift and spin are below the sleep thresholds: asleep, it would stop for good


# Freezes the field rocks far outside the view and wakes up the ones it comes near.
# Only touches rocks it parked itself: other systems freeze rocks too (the rock bolter, the
# grabber), and those must stay as they set them.
func _park_far_rocks(view: Rect2) -> void:
	var awake := view.grow(awake_margin)
	_forget_lost_parked()

	for child in get_children():
		var rock := child as Asteroid

		if rock == null:
			continue

		var bound := rock.get_bound_radius()
		var reach := Rect2(to_local(rock.get_global_center()) - Vector2.ONE * bound, Vector2.ONE * bound * 2.0)
		var is_near := awake.intersects(reach)

		if is_near and _parked.has(rock):
			var motion := _parked[rock]
			_parked.erase(rock)
			rock.freeze = false
			rock.linear_velocity = Vector2(motion.x, motion.y)
			rock.angular_velocity = motion.z
		elif not is_near and not _parked.has(rock) and not rock.freeze:
			_parked[rock] = Vector3(rock.linear_velocity.x, rock.linear_velocity.y, rock.angular_velocity)
			rock.freeze = true


# Parked chunks aren't tracked by _on_rock_left: drop the ones that were freed. One taken out of
# the field while parked (can't happen today: nothing reaches that far) gets its motion back.
# Rebuilt rather than erased from: a freed object can't be passed around safely.
func _forget_lost_parked() -> void:
	var kept: Dictionary[Asteroid, Vector3] = {}

	for key in _parked:
		if not is_instance_valid(key):
			continue

		var rock := key as Asteroid
		var motion := _parked[rock]

		if rock.get_parent() == self:
			kept[rock] = motion
		else:
			rock.freeze = false
			rock.linear_velocity = Vector2(motion.x, motion.y)
			rock.angular_velocity = motion.z

	_parked = kept


# A field rock left the tree. Unloading erases it from _live first, so if it's still listed,
# something else took it (destroyed, grabbed, smelted): it must not come back.
func _on_rock_left(rock: Asteroid, id: int) -> void:
	_parked.erase(rock)

	if _live.get(id) == rock:
		_live.erase(id)
		_gone[id] = true


func _sector_distance(sector: Vector2i, point: Vector2) -> float:
	var sector_center := (Vector2(sector) + Vector2(0.5, 0.5)) * profile.sector_size
	return sector_center.distance_to(point)


func _draw() -> void:
	if not debug_draw or profile == null:
		return

	for sector: Vector2i in _sectors:
		var rect := _debug_planner.get_sector_rect(sector)
		var density := _debug_planner.get_density(rect.get_center())
		draw_rect(rect, Color(0.3, 0.8, 1.0, density * 0.12), true)
		draw_rect(rect, Color(0.3, 0.8, 1.0, 0.4), false, 4.0)
