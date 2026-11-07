extends Node2D

# One-shot burst for a laser shot: one effect per shot, not one per cell.
# Particles are emitted from the centres of the vaporized cells.
# The emitters use local coordinates and the whole effect drifts at the asteroid's velocity,
# so the debris cloud keeps the rock's momentum. Damping then slows particles relative to the cloud.

@export var sparks_per_cell: float = 2.0
@export var dust_per_cell: float = 3.0
@export var max_particles_per_emitter: int = 200

@onready var sparks: CPUParticles2D = $Sparks
@onready var dust: CPUParticles2D = $Dust

var _drift_velocity: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	global_position += _drift_velocity * delta


# points: global positions of the vaporized cells. direction: the beam's direction.
# base_velocity: velocity of the vaporized material, usually the asteroid's velocity at the hit point.
func play(points: PackedVector2Array, direction: Vector2, dust_color: Color, base_velocity: Vector2 = Vector2.ZERO) -> void:
	_drift_velocity = base_velocity

	var local_points := PackedVector2Array()

	for point in points:
		local_points.append(point - global_position)

	sparks.direction = -direction # Sprays back toward the shooter
	dust.color = dust_color
	_emit(sparks, local_points, sparks_per_cell)
	_emit(dust, local_points, dust_per_cell)

	var longest_life := maxf(sparks.lifetime, dust.lifetime)
	get_tree().create_timer(longest_life + 0.2).timeout.connect(queue_free)


func _emit(emitter: CPUParticles2D, points: PackedVector2Array, per_cell: float) -> void:
	emitter.emission_points = points
	emitter.amount = clampi(roundi(points.size() * per_cell), 1, max_particles_per_emitter)
	emitter.emitting = true
