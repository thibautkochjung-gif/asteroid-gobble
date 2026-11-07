class_name PlasmaGun
extends HardpointWeapon

# Continuous beam, on while the fire button is held.
# Windup first: for windup_time the beam is pale and harmless. Then it engages (a flash at the
# muzzle and a short width pulse) and starts burning.
# Once active, it stops on the first cell on its line and burns it: vaporize_time of contact,
# times the cell's hardness, vaporizes it. Then the beam reaches the next cell behind.
# Damage is stored on the cell (Asteroid.add_damage): if the beam slips off and comes back within
# Asteroid.damage_memory_time, the cell picks up where it left off.
# Releasing the button ends the shot: the next one winds up again.

enum State { IDLE, WINDING_UP, ACTIVE }

@export_group("Beam")
@export var max_range: float = 600.0
@export var vaporize_time: float = 0.5 # Contact time to vaporize a soft-rock cell. Times the hardness
@export var windup_time: float = 0.8 # Harmless, pale beam before it engages

@export_group("Power")
@export var power_per_second: float = 5.0 # Drawn during windup too. Short on power = slower windup and burn

@export_group("Visuals")
@export var beam_width: float = 4.0 # Twice the laser's
@export var beam_color: Color = Color(0.25, 0.55, 1.0, 0.85)
@export var windup_color: Color = Color(0.6, 0.8, 1.0, 0.65) # Lighter, see-through: not burning yet
@export_range(0.0, 1.0) var windup_start_alpha: float = 0.6 # Share of windup_color's opacity at the start of the windup
@export var core_width: float = 1.5
@export var core_color: Color = Color(0.85, 0.95, 1.0, 1.0)
@export_range(0.0, 1.0) var flicker: float = 0.25 # Share of the width that wobbles each frame
@export_range(0.0, 1.0) var min_power_alpha: float = 0.3 # Beam opacity with no power at all
@export var engage_pulse_time: float = 0.15 # The beam starts wider when it engages, then settles
@export var engage_pulse_scale: float = 1.0 # Extra width at the start of the pulse (1 = twice as wide)

var state: State = State.IDLE

var _windup_left: float = 0.0
var _pulse_left: float = 0.0

@onready var beam: Line2D = $Muzzle/Beam
@onready var core: Line2D = $Muzzle/Beam/Core
@onready var engage_flash: CPUParticles2D = $Muzzle/EngageFlash
@onready var sparks: CPUParticles2D = $Sparks
@onready var smoke: CPUParticles2D = $Smoke
@onready var dust: CPUParticles2D = $Dust


func _ready() -> void:
	beam.visible = false
	core.default_color = core_color
	_set_burn_effects(false)


func _physics_process(delta: float) -> void:
	if not Input.is_action_pressed(fire_action):
		_stop()
		return

	if state == State.IDLE:
		_start_windup()

	var power_ratio := draw_power(power_per_second * delta)

	if state == State.WINDING_UP:
		_windup_left -= delta * power_ratio

		if _windup_left <= 0.0:
			_engage()

	_update_look(delta, power_ratio)

	var hits := _get_hits()

	if hits.is_empty():
		_set_beam_length(max_range)
		_set_burn_effects(false)
		return

	var hit: Dictionary = hits[0]
	_set_beam_length(hit["distance"])

	var is_burning := state == State.ACTIVE and power_ratio > 0.0
	_set_burn_effects(is_burning)

	if not is_burning:
		return

	_update_burn_effects(hit)
	_burn(hit, delta * power_ratio)


func _start_windup() -> void:
	state = State.WINDING_UP
	_windup_left = windup_time
	beam.visible = true
	core.visible = false


func _engage() -> void:
	state = State.ACTIVE
	_pulse_left = engage_pulse_time
	core.visible = true
	engage_flash.restart()


func _stop() -> void:
	state = State.IDLE
	beam.visible = false
	_set_burn_effects(false)


func _get_hits() -> Array[Dictionary]:
	var from := muzzle.global_position
	var to := from + get_forward() * max_range
	return Asteroid.find_hits_on_ray(get_tree(), from, to, 1)


func _burn(hit: Dictionary, burn_time: float) -> void:
	var asteroid: Asteroid = hit["asteroid"]
	var cell: Vector2i = hit["cell"]

	if not asteroid.add_damage(cell, burn_time / (vaporize_time * asteroid.get_hardness(cell))):
		return

	var point := asteroid.get_cell_global_position(cell) # Before removal
	var dust_color := asteroid.get_cell_color(cell)
	Fx.spawn_vaporize(PackedVector2Array([point]), get_forward(), dust_color, asteroid.get_velocity_at(point))
	asteroid.remove_cell(cell)


# --- Visuals


func _update_look(delta: float, power_ratio: float) -> void:
	var wobble := randf_range(1.0 - flicker, 1.0)
	beam.modulate.a = lerpf(min_power_alpha, 1.0, power_ratio)

	if state == State.WINDING_UP:
		var color := windup_color
		color.a *= lerpf(windup_start_alpha, 1.0, 1.0 - _windup_left / windup_time) # Fades in as it winds up
		beam.default_color = color
		beam.width = beam_width * wobble
		return

	_pulse_left = maxf(_pulse_left - delta, 0.0)
	var pulse := 1.0

	if engage_pulse_time > 0.0:
		pulse += engage_pulse_scale * _pulse_left / engage_pulse_time

	beam.default_color = beam_color
	beam.width = beam_width * wobble * pulse
	core.width = core_width * wobble * pulse


func _set_burn_effects(is_on: bool) -> void:
	sparks.emitting = is_on
	smoke.emitting = is_on
	dust.emitting = is_on


# Emitters use world coordinates (local_coords off): particles stay where they were emitted.
# Sparks and dust spray back toward the gun, smoke takes the cell's colour.
func _update_burn_effects(hit: Dictionary) -> void:
	var asteroid: Asteroid = hit["asteroid"]
	var cell_color := asteroid.get_cell_color(hit["cell"])
	var distance: float = hit["distance"]
	var contact_point := muzzle.global_position + get_forward() * distance
	var backward := get_forward().angle() + PI

	var emitters: Array[CPUParticles2D] = [sparks, smoke, dust]

	for emitter in emitters:
		emitter.global_position = contact_point
		emitter.global_rotation = backward

	smoke.color = cell_color.lightened(0.2)
	dust.color = cell_color


func _set_beam_length(length: float) -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2(length, 0.0)])
	beam.points = points
	core.points = points
