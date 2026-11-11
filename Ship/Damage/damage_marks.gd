class_name DamageMarks
extends Node2D

# Wear drawn on damaged parts: scorch marks, rust and cracks around each part's damage points
# (get_damage_points()), more of them as the part loses points. Cracks only show past the first
# couple of marks, so a scratched part looks dirty and a badly hit one looks cracked.
# Broken parts (PartHealth.is_broken()) also throw sparks.
# Pixel art like the hull: 2 px texels, flat colours, on the ship's texel grid.
# Sits at the ship's origin, last child of the ship, so it draws over the hull and the modules.
# Each part's marks come from a random generator seeded with the part: they stay put, and a new
# hit adds marks instead of reshuffling the old ones.

enum Mark { SCORCH, RUST, CRACK }

const TEXEL: float = 2.0
const FIRST_CRACK: int = 2 # Marks before this index are never cracks

@export var ship_damage: ShipDamage
@export var max_marks: int = 9 # Per damage point, once the part is at 0 points
@export var spread: float = 7.0 # px around a damage point
@export_range(0.0, 1.0) var spark_chance: float = 0.15 # Per damage point and frame, on broken parts

@export_group("Colors")
@export var scorch_color: Color = Color(0.09, 0.08, 0.08, 0.9)
@export var soot_color: Color = Color(0.16, 0.14, 0.13, 0.6)
@export var rust_color: Color = Color(0.58, 0.29, 0.12)
@export var rust_dark_color: Color = Color(0.37, 0.19, 0.1)
@export var crack_color: Color = Color(0.04, 0.035, 0.045)
@export var spark_colors: Array[Color] = [Color(1.0, 0.9, 0.5), Color(1.0, 0.6, 0.2), Color(1.0, 1.0, 0.9)]

var _rng := RandomNumberGenerator.new() # Reseeded for each part: same marks every frame
var _shape_rng := RandomNumberGenerator.new() # Reseeded for each mark: same shape every frame
var _spark_rng := RandomNumberGenerator.new() # Never reseeded: sparks flicker


func _process(_delta: float) -> void:
	queue_redraw() # The arms move and the sparks flicker


func _draw() -> void:
	if ship_damage == null:
		return

	for part in ship_damage.get_parts():
		var health := ShipDamage.get_health(part)
		var wear := 1.0 - health.get_ratio()

		if wear <= 0.0:
			continue

		var points := ShipDamage.get_damage_points(part)

		for i in points.size():
			var center := _snap(to_local(points[i]))
			_rng.seed = part.get_instance_id() + i * 7919
			_draw_wear(center, ceili(sqrt(wear) * max_marks)) # sqrt: the first hits already show

			if health.is_broken() and _spark_rng.randf() < spark_chance:
				_draw_sparks(center)


# Rolls every mark, drawn or not, so the rolls of mark N don't depend on how many are shown.
func _draw_wear(center: Vector2, count: int) -> void:
	for i in max_marks:
		var mark := _rng.randi_range(0, Mark.size() - 1)
		var offset := Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))
		var shape_seed := _rng.randi()

		if i >= count:
			continue

		if mark == Mark.CRACK and i < FIRST_CRACK:
			mark = Mark.SCORCH

		_shape_rng.seed = shape_seed
		var at := _snap(center + offset)

		match mark:
			Mark.SCORCH:
				_draw_scorch(at)
			Mark.RUST:
				_draw_rust(at)
			Mark.CRACK:
				_draw_crack(at)


# A dark burn with a ragged halo of soot.
func _draw_scorch(at: Vector2) -> void:
	for i in _shape_rng.randi_range(3, 6):
		_draw_texel(at + _random_step() * TEXEL, soot_color)

	_draw_texel(at, scorch_color)


# A short streak of rust, bright at its start.
func _draw_rust(at: Vector2) -> void:
	var cell := at
	_draw_texel(cell, rust_color)

	for i in _shape_rng.randi_range(1, 2):
		cell += _random_step() * TEXEL
		_draw_texel(cell, rust_dark_color)


# A jagged line: mostly one direction, with a kink now and then.
func _draw_crack(at: Vector2) -> void:
	var direction := _random_step()
	var cell := at
	_draw_texel(cell, soot_color)

	for i in _shape_rng.randi_range(3, 5):
		var step := direction

		if _shape_rng.randf() < 0.35:
			step = _random_step()

		cell += step * TEXEL
		_draw_texel(cell, crack_color)


func _draw_sparks(center: Vector2) -> void:
	for i in _spark_rng.randi_range(1, 3):
		var offset := Vector2(_spark_rng.randf_range(-spread, spread), _spark_rng.randf_range(-spread, spread)) * 0.6
		var color := spark_colors[_spark_rng.randi_range(0, spark_colors.size() - 1)]
		_draw_texel(_snap(center + offset), color)


# One of the 8 neighbouring cells, as a unit grid step.
func _random_step() -> Vector2:
	var step := Vector2.ZERO

	while step == Vector2.ZERO:
		step = Vector2(_shape_rng.randi_range(-1, 1), _shape_rng.randi_range(-1, 1))

	return step


func _draw_texel(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(TEXEL, TEXEL)), color)


func _snap(point: Vector2) -> Vector2:
	return point.snapped(Vector2(TEXEL, TEXEL))
