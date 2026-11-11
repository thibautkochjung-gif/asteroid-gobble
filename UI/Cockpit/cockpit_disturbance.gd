class_name CockpitDisturbance
extends Node

# Makes the cockpit react to hits: the panel rattles, lights and screens flicker, and `level`
# tells the radar, needles and terminal how badly to misbehave. A hit adds a spike that fades;
# a badly damaged hull glitches on its own now and then; a destroyed ship loses power.
# Cockpit feeds it (hit, set_hull_ratio, lose_power) and passes `level` on to the widgets.

const DIM_LIGHT := Color(0.4, 0.4, 0.4) # A light during a flicker
const DIM_SCREEN := Color(1.0, 1.0, 1.0, 0.12) # A screen during a flicker: almost blank

@export var fade_speed: float = 2.5 # Higher = a hit's effects settle sooner
@export var max_shake: float = 6.0 # px on the 1280 x 720 design canvas, at full strength
@export var flickers_per_second: float = 14.0 # Per light or screen, at full strength
@export var flicker_time_min: float = 0.03 # s
@export var flicker_time_max: float = 0.14 # s

@export_group("Damaged hull")
@export var glitch_below_hull: float = 0.5 # Below this hull ratio, the cockpit glitches on its own
@export var glitches_per_second: float = 0.6 # At zero hull
@export var glitch_strength: float = 0.35

@export_group("Power failure")
@export var dead_blinks_per_second: float = 1.5 # Dead lights still blink on, now and then

var level: float = 0.0 # 0 = calm, 1 = full disturbance

var _spike: float = 0.0
var _hull_ratio: float = 1.0
var _has_power: bool = true
var _targets: Array[Dictionary] = [] # { "item": CanvasItem, "dim": Color, "time_left": float }


func setup(lights: Array[CanvasItem], screens: Array[CanvasItem]) -> void:
	for item in lights:
		_targets.append({ "item": item, "dim": DIM_LIGHT, "time_left": 0.0 })

	for item in screens:
		_targets.append({ "item": item, "dim": DIM_SCREEN, "time_left": 0.0 })


# strength 0..1. Overlapping hits don't add up: the strongest one sets the level.
func hit(strength: float) -> void:
	_spike = clampf(maxf(_spike, strength), 0.0, 1.0)


func set_hull_ratio(ratio: float) -> void:
	_hull_ratio = ratio


func lose_power() -> void:
	_has_power = false


func get_shake_offset() -> Vector2:
	var amount := max_shake * _spike * _spike # Eased: small bumps barely rattle

	if amount <= 0.01:
		return Vector2.ZERO

	return Vector2(randf_range(-amount, amount), randf_range(-amount, amount))


func _process(delta: float) -> void:
	_spike *= exp(-fade_speed * delta)

	if _has_power:
		_add_glitches(delta)
		level = _spike
	else:
		level = 1.0

	for target in _targets:
		_update_flicker(target, delta)


func _add_glitches(delta: float) -> void:
	if _hull_ratio >= glitch_below_hull:
		return

	var damage := 1.0 - _hull_ratio / glitch_below_hull # 0 at the threshold, 1 at zero hull

	if randf() < glitches_per_second * damage * delta:
		hit(glitch_strength * randf_range(0.5, 1.0))


# With power, a target is normally on and drops out for a moment; without, it's normally off
# and blinks on for a moment.
func _update_flicker(target: Dictionary, delta: float) -> void:
	var item: CanvasItem = target["item"]
	var rate := flickers_per_second * level if _has_power else dead_blinks_per_second
	target["time_left"] -= delta

	if target["time_left"] <= 0.0 and randf() < rate * delta:
		target["time_left"] = randf_range(flicker_time_min, flicker_time_max)

	var is_flickering: bool = target["time_left"] > 0.0
	var is_on := not is_flickering if _has_power else is_flickering
	item.modulate = Color.WHITE if is_on else target["dim"]
