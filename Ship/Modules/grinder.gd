class_name Grinder
extends Node2D

# Grinds down chunks in the hold (behind the hangar doors) that are too big for every room that
# takes chunks (Hangar.is_too_big), and throws out what the player doesn't want (triage).
# Each physics step it does one of these, in this order of priority:
# 1. Discard: a chunk made only of discarded materials (discarded_materials, set in the ship menu)
#    is blown out the back as dust, whole, in discard_time. No need to grind rock nobody wants.
# 2. Mill: with an ore bin aboard, a too-big chunk of mill_threshold cells or less is eaten one cell
#    at a time (mill_rate cells per second), from the end nearest the drum. Kept cells go straight
#    into the ore bins, discarded ones go out as dust.
# 3. Cut: the largest too-big chunk is cut into two halves every cut_time seconds
#    (Asteroid.split_in_halves). It repeats as often as needed.
# The hangar hands every piece that fits to a room by itself, but never a piece the grinder will discard.
# Grinding opens the rock up: the chunk being worked on shows all its ore. Triage always goes by
# what the cells really are, seen or not.
# When the ore bins are full (and there's no smelter to feed), the grinder stops cutting and milling.
# It still throws out unwanted chunks.
# With no room taking chunks, nothing is too big, and the grinder stays idle.
# A chunk only needs to be partly in the hold, like a log in a woodchipper.
# Rocks over max_grind_cells are ignored: a whole asteroid nudging the open doors isn't ground.
# Feed rollers pull every chunk in the hold toward the back (feed_acceleration), so cut pieces and
# chunks waiting for a free room don't drift back out of the doors. The rollers are part of the
# ship, so the ship gets the opposite force: the pull alone doesn't move the ship.
# Visuals: a toothed drum on the back wall of the hold. Seen from above, each tooth comes out and
# goes back in as the drum turns. It only turns while grinding.
# The chunk being ground shakes a little (Asteroid.draw_offset: visual only, the body doesn't move),
# more and more as the cut gets near.
# This node sits at the ship's origin, so its local space is the ship's space.

enum Mode { IDLE, DISCARDING, MILLING, CUTTING, BIN_FULL }

const TEXEL: float = 2.0

@export var ship: RigidBody2D
@export var hangar: Hangar
@export var cut_time: float = 5.0 # Seconds of work per cut. The starter ship's grinder is small and slow
@export var mill_threshold: int = 12 # Chunks this small are milled cell by cell (with an ore bin aboard)
@export var mill_rate: float = 2.0 # Cells per second
@export var discard_time: float = 0.5 # Seconds to throw out an unwanted chunk, whatever its size
@export var separation_speed: float = 6.0 # px/s between the two halves
@export var max_grind_cells: int = 300 # Bigger rocks touching the hold are left alone
@export var feed_acceleration: float = 30.0 # px/s², toward the back of the hold
@export var discarded_materials: Array[int] = [CellMaterials.Id.SOFT_ROCK, CellMaterials.Id.TOUGH_ROCK] # CellMaterials.Id. Set from the ship's loadout (triage)

@export_group("Visuals")
@export var drum_depth: float = 4.0 # px, from the back wall of the hold
@export var tooth_pitch: float = 4.0 # px between two teeth, across the hold
@export var tooth_max_length: float = 8.0 # px, a tooth fully out
@export var spin_speed: float = 12.0 # rad/s of the drum
@export var shake_amplitude: float = 1.0 # px, the chunk's shake when a cut starts
@export var shake_build_up: float = 1.0 # px added by the time the cut is done
@export var drum_color: Color = Color(0.09, 0.09, 0.13)
@export var tooth_color: Color = Color(0.59, 0.59, 0.63)
@export var tooth_shade_color: Color = Color(0.36, 0.34, 0.31)
@export var tooth_tip_color: Color = Color(0.86, 0.86, 0.89)

var mode: Mode = Mode.IDLE
var is_working: bool = false # True while the drum turns: discarding, milling or cutting
var progress: float = 0.0 # 0..1 toward the next cut, milled cell or discard

var _target: Asteroid # The chunk being worked on. Null when idle
var _shaken: Asteroid # The chunk whose draw_offset we moved, to put it back
var _drum_angle: float = 0.0
var _was_drawn_working: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 1 # Over the chunks, which are drawn over the ship: the teeth bite into the rock
	hangar.grinder = self # So the hangar never hands a room a chunk we're about to throw out


func _physics_process(delta: float) -> void:
	_feed()

	var previous := _target
	mode = _pick_work()
	is_working = mode == Mode.DISCARDING or mode == Mode.MILLING or mode == Mode.CUTTING

	if _target != previous:
		progress = 0.0

		if _target != null:
			_reveal(_target)

	if not is_working:
		return

	match mode:
		Mode.DISCARDING:
			progress += delta / discard_time

			if progress >= 1.0:
				progress = 0.0
				_discard(_target)
		Mode.MILLING:
			progress += delta * mill_rate

			if progress >= 1.0:
				progress -= 1.0
				_mill(_target)
		Mode.CUTTING:
			progress += delta / cut_time

			if progress >= 1.0:
				progress = 0.0
				_cut(_target)


func _process(delta: float) -> void:
	_update_shake()

	if is_working:
		_drum_angle = wrapf(_drum_angle + spin_speed * delta, 0.0, TAU)
		queue_redraw()
	elif _was_drawn_working:
		queue_redraw() # One last time, so the teeth stop where they are

	_was_drawn_working = is_working


func _draw() -> void:
	if hangar == null:
		return

	var hold := hangar.get_hold_rect()

	if not hold.has_area():
		return

	_draw_drum(hold)


func get_status_text() -> String:
	match mode:
		Mode.DISCARDING:
			return "discarding"
		Mode.MILLING:
			return "milling %d%%" % roundi(progress * 100.0)
		Mode.CUTTING:
			return "grinding %d%%" % roundi(progress * 100.0)
		Mode.BIN_FULL:
			return "stopped, ore bins full"

	return "idle"


func is_discarded(material_id: int) -> bool:
	return discarded_materials.has(material_id)


# True if every cell of the chunk is a discarded material. Goes by what the cells really are.
func should_discard(chunk: Asteroid) -> bool:
	if discarded_materials.is_empty():
		return false

	for cell in chunk.cells:
		if not is_discarded(chunk.cells[cell]):
			return false

	return true


# Pulls the chunks in the hold toward the back wall. The hangar sits at the ship's origin,
# so its -x is the ship's backward direction.
# apply_central_force lasts one physics step, so this runs every frame.
func _feed() -> void:
	var inward := hangar.global_transform.basis_xform(Vector2.LEFT).normalized()

	for chunk in hangar.get_chunks_inside():
		if chunk.cells.size() > max_grind_cells:
			continue

		var force := inward * feed_acceleration * chunk.mass
		chunk.apply_central_force(force)
		ship.apply_force(-force, chunk.get_global_center() - ship.global_position)


# Picks what to do this step, and the chunk to do it on (_target).
func _pick_work() -> Mode:
	_target = null

	if not hangar.rooms.has_chunk_receivers():
		return Mode.IDLE

	var chunks := hangar.get_chunks_inside()

	for chunk in chunks:
		if chunk.cells.size() <= max_grind_cells and should_discard(chunk):
			_target = chunk
			return Mode.DISCARDING

	var largest := _find_largest_too_big(chunks)

	if largest == null:
		return Mode.IDLE

	_target = largest

	if _is_ore_bin_full():
		return Mode.BIN_FULL

	if hangar.rooms.has_ore_bin() and largest.cells.size() <= mill_threshold:
		return Mode.MILLING

	return Mode.CUTTING


# The largest chunk in the hold, if any chunk there is too big. Null otherwise.
# Rocks over max_grind_cells don't count, either way.
func _find_largest_too_big(chunks: Array[Asteroid]) -> Asteroid:
	var is_any_too_big := false
	var largest: Asteroid = null

	for chunk in chunks:
		if chunk.cells.size() > max_grind_cells:
			continue

		if hangar.is_too_big(chunk):
			is_any_too_big = true

		if largest == null or chunk.cells.size() > largest.cells.size():
			largest = chunk

	return largest if is_any_too_big else null


# Full ore bins and no smelter: whatever we grind would have nowhere to go.
func _is_ore_bin_full() -> bool:
	var rooms := hangar.rooms
	return rooms.has_ore_bin() and rooms.get_free_ore_bin_cells() <= 0 and rooms.get_smelter_capacity() == 0


func _reveal(chunk: Asteroid) -> void:
	var all_cells: Array[Vector2i] = []
	all_cells.assign(chunk.cells.keys())
	chunk.reveal_ore_cells(all_cells)


func _discard(chunk: Asteroid) -> void:
	_puff(chunk.get_global_center(), chunk.get_cell_color(chunk.cells.keys()[0]), chunk.linear_velocity)
	chunk.remove_from_group(Asteroid.GROUP) # No more laser hits or capture this frame
	chunk.queue_free()


# Eats the cell nearest the drum. A kept cell goes into the ore bins, the others go out as dust.
func _mill(chunk: Asteroid) -> void:
	var cell := _find_cell_nearest_drum(chunk)
	var material_id: int = chunk.cells[cell]

	if is_discarded(material_id):
		_puff(chunk.get_cell_global_position(cell), chunk.get_cell_color(cell), chunk.linear_velocity)
	elif not hangar.rooms.store_ore_cell(material_id, chunk.ore_type):
		return # Filled up since _pick_work(): try again next step

	chunk.remove_cell(cell)


# The cell with the smallest x in the ship's space (this node's space): the drum is at the back.
func _find_cell_nearest_drum(chunk: Asteroid) -> Vector2i:
	var nearest: Vector2i = chunk.cells.keys()[0]
	var best_x := INF

	for cell in chunk.cells:
		var x := to_local(chunk.get_cell_global_position(cell)).x

		if x < best_x:
			best_x = x
			nearest = cell

	return nearest


func _cut(chunk: Asteroid) -> void:
	var dust_color := chunk.get_cell_color(chunk.cells.keys()[0])
	var half := chunk.split_in_halves(separation_speed)

	if half == null:
		return

	# A puff of dust between the two halves.
	var between := (chunk.get_global_center() + half.get_global_center()) * 0.5
	var direction := (half.get_global_center() - chunk.get_global_center()).normalized()
	Fx.spawn_vaporize(PackedVector2Array([between]), direction.orthogonal(), dust_color, chunk.linear_velocity)


# Dust blown toward the back of the ship.
# A puff out the back, for cells the player dumps from the ship menu.
func puff_dust(dust_color: Color) -> void:
	_puff(global_position, dust_color, ship.linear_velocity if ship != null else Vector2.ZERO)


func _puff(global_point: Vector2, dust_color: Color, base_velocity: Vector2) -> void:
	var backward := global_transform.basis_xform(Vector2.LEFT).normalized()
	Fx.spawn_vaporize(PackedVector2Array([global_point]), backward, dust_color, base_velocity)


# --- Visuals


# Jitters the chunk being worked on, in whole pixels. Puts back the one we shook before
# when the target changes or the grinder stops.
func _update_shake() -> void:
	var target: Asteroid = _target if is_working and is_instance_valid(_target) else null

	if _shaken != target:
		if is_instance_valid(_shaken):
			_shaken.draw_offset = Vector2.ZERO

		_shaken = target

	if target == null:
		return

	var amplitude := (shake_amplitude + shake_build_up * progress)
	var offset := Vector2(_rng.randf_range(-amplitude, amplitude), _rng.randf_range(-amplitude, amplitude))
	target.draw_offset = offset.round()


# The drum against the back wall, and its row of teeth pointing out of the hold.
func _draw_drum(hold: Rect2) -> void:
	draw_rect(Rect2(hold.position, Vector2(drum_depth, hold.size.y)), drum_color)

	var front_x := hold.position.x + drum_depth
	var tooth_count := floori(hold.size.y / tooth_pitch)
	var first_y := hold.get_center().y - tooth_count * tooth_pitch * 0.5

	for i in tooth_count:
		# Neighbours are out of step, so the row ripples instead of pumping all at once.
		var reach := sin(_drum_angle + i * 2.3) * 0.5 + 0.5
		var length := snappedf(lerpf(TEXEL, tooth_max_length, reach), TEXEL)
		_draw_tooth(Vector2(front_x, first_y + i * tooth_pitch), length)


# A sawtooth: lit top row ending in a bright tip, shaded bottom row one texel shorter.
func _draw_tooth(base: Vector2, length: float) -> void:
	draw_rect(Rect2(base.x, base.y + TEXEL, length - TEXEL, TEXEL), tooth_shade_color)
	draw_rect(Rect2(base.x, base.y, length - TEXEL, TEXEL), tooth_color)
	draw_rect(Rect2(base.x + length - TEXEL, base.y, TEXEL, TEXEL), tooth_tip_color)
