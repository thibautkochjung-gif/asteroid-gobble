class_name Laser
extends HardpointWeapon

enum State { IDLE, CHARGING, FIRING }

@export_group("Shot")
@export var max_range: float = 900.0
# Penetration is a budget in soft-rock cells. Each cell costs its hardness (CellMaterial),
# so a full charge goes 60 cells through soft rock but about 20 through tough rock.
@export var min_penetration: int = 10 # Budget at minimal windup
@export var max_penetration: int = 60 # Budget at full charge
@export var fire_duration: float = 0.2

@export_group("Timing")
@export var windup_time: float = 0.8 # Minimal charge before the laser can fire at all
@export var full_charge_time: float = 4.0 # Extra charge after windup_time to reach max_penetration
@export var cooldown_time: float = 4.0

@export_group("Visuals")
@export var beam_width: float = 2.0 # Same for the preview and the shot
@export var preview_color: Color = Color(0.3, 0.6, 1.0, 0.4) # Blue: still charging
@export var charged_color: Color = Color(0.3, 1.0, 0.4, 0.6) # Green: minimal windup reached
@export var full_charge_color: Color = Color(1.0, 0.55, 0.1, 0.7) # Orange: full charge
@export var beam_color: Color = Color(1.0, 0.15, 0.1, 1.0)
@export var range_fade: float = 200.0 # px. The preview and the shot fade out over this stretch before max_range

var state: State = State.IDLE
var charge_time: float = 0.0

@onready var beam: Line2D = $Muzzle/Beam
@onready var fire_timer: Timer = $FireTimer
@onready var cooldown_timer: Timer = $CooldownTimer


func _ready() -> void:
	beam.visible = false
	beam.width = beam_width
	fire_timer.one_shot = true
	cooldown_timer.one_shot = true
	fire_timer.timeout.connect(_on_fire_timer_timeout)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		_on_fire_pressed()

	_update_aim_for_state(delta)

	if state != State.CHARGING:
		return

	charge_time += delta * get_performance() # Damaged: slower charge
	_set_beam(_get_preview_length(_get_hits(1)), _get_preview_color())

	if Input.is_action_just_released(fire_action):
		_on_fire_released()


func is_on_cooldown() -> bool:
	return not cooldown_timer.is_stopped()


func get_cooldown_ratio() -> float:
	if cooldown_timer.is_stopped():
		return 0.0

	return cooldown_timer.time_left / cooldown_timer.wait_time


func is_charged() -> bool:
	return charge_time >= windup_time


# 0 at minimal windup, 1 at full charge.
func get_charge_ratio() -> float:
	if full_charge_time <= 0.0:
		return 1.0

	return clampf((charge_time - windup_time) / full_charge_time, 0.0, 1.0)


func get_penetration() -> int:
	return roundi(lerpf(min_penetration, max_penetration, get_charge_ratio()))


func _on_fire_pressed() -> void:
	if is_on_cooldown():
		cooldown_blocked.emit(cooldown_timer.time_left)
		return

	if state == State.IDLE:
		_start_charging()


func _on_fire_released() -> void:
	if is_charged():
		_fire()
	else:
		_cancel_charge()


# Aims while charging, holds still during the shot (the beam stays where it hit), swings back when idle.
func _update_aim_for_state(delta: float) -> void:
	if state == State.CHARGING:
		update_aim(delta)
	elif state == State.IDLE:
		reset_aim(delta)


func _start_charging() -> void:
	state = State.CHARGING
	charge_time = 0.0
	beam.visible = true # _process() draws it this same frame


func _get_preview_color() -> Color:
	if is_charged():
		return charged_color.lerp(full_charge_color, get_charge_ratio())

	var color := preview_color
	color.a *= lerpf(0.25, 1.0, charge_time / windup_time)
	return color


func _cancel_charge() -> void:
	state = State.IDLE
	beam.visible = false


func _fire() -> void:
	var penetration := get_penetration()
	var hits := _get_hits(penetration) # Hardness is at least 1: never more cells than the budget
	var vaporized := _spend_budget(hits, penetration)
	_set_beam(_get_beam_length(hits, vaporized, penetration), beam_color)

	var vaporized_points := PackedVector2Array()
	var cloud_velocity := Vector2.ZERO
	var dust_color := Color.GRAY

	if not vaporized.is_empty():
		var first_asteroid: Asteroid = vaporized[0]["asteroid"]
		var first_point := first_asteroid.get_cell_global_position(vaporized[0]["cell"])
		cloud_velocity = first_asteroid.get_velocity_at(first_point) # Before removal
		dust_color = first_asteroid.get_cell_color(vaporized[0]["cell"])

	for hit in vaporized:
		var asteroid: Asteroid = hit["asteroid"]
		vaporized_points.append(asteroid.get_cell_global_position(hit["cell"])) # Before removal
		asteroid.remove_cell(hit["cell"])

	Fx.spawn_vaporize(vaporized_points, get_forward(), dust_color, cloud_velocity)

	state = State.FIRING
	fire_timer.start(fire_duration)
	cooldown_timer.start(cooldown_time)


func _get_hits(max_count: int) -> Array[Dictionary]:
	var from := muzzle.global_position
	var to := from + get_forward() * max_range
	return Asteroid.find_hits_on_ray(get_tree(), from, to, max_count)


# The preview stops at the first cell it touches: it shows where the shot lands, not how deep it goes.
func _get_preview_length(hits: Array[Dictionary]) -> float:
	if hits.is_empty():
		return max_range

	return hits.front()["distance"]


# The hits the shot vaporizes, nearest first: each costs its cell's hardness, and the shot stops
# at the first cell it can no longer afford.
func _spend_budget(hits: Array[Dictionary], budget: float) -> Array[Dictionary]:
	var vaporized: Array[Dictionary] = []

	for hit in hits:
		var asteroid: Asteroid = hit["asteroid"]
		var hardness := asteroid.get_hardness(hit["cell"])

		if hardness > budget:
			break

		budget -= hardness
		vaporized.append(hit)

	return vaporized


# Full range if the shot went through everything on its line. Otherwise it ends where it stopped:
# after the last vaporized cell, or on the surface of the first cell if it couldn't cut any.
func _get_beam_length(hits: Array[Dictionary], vaporized: Array[Dictionary], penetration: int) -> float:
	if vaporized.size() == hits.size() and hits.size() < penetration:
		return max_range

	if vaporized.is_empty():
		return hits.front()["distance"]

	return vaporized.back()["exit"]


func _set_beam(length: float, color: Color) -> void:
	set_range_line(beam, length, color, max_range, range_fade)


func _on_fire_timer_timeout() -> void:
	state = State.IDLE
	beam.visible = false
