class_name AmmoBox
extends SoftPoint

# An external ammo box. The launcher reloads from it before the stores inside (ShipHardpoints
# asks ShipSoftPoints first), so its weight goes first. Hold the key to jettison it: it floats
# away with the rounds it had left. Touch it gently to bolt it back on.

@export var capacity: int = 80
@export var start_full: bool = true

@export_group("Look")
@export var shell_color: Color = Color(0.78, 0.6, 0.25)
@export var gauge_color: Color = Color(0.16, 0.17, 0.12)
@export var lid_color: Color = Color(0.29, 0.31, 0.2)

var rounds: int = 0

var _drawn_ratio: float = -1.0


func _init() -> void:
	footprint = Rect2(0, -10, 10, 20)
	dry_mass = 0.8
	can_jettison = true
	body_color = Color(0.36, 0.38, 0.25) # Olive drab


func _ready() -> void:
	if start_full:
		rounds = capacity


func draw_ammo(count: int) -> int:
	var granted := mini(count, rounds)

	if granted <= 0:
		return 0

	rounds -= granted
	_redraw_if_changed()
	return granted


func get_ammo() -> int:
	return rounds


func get_ammo_capacity() -> int:
	return capacity


func restock() -> void:
	rounds = capacity
	_redraw_if_changed()


func get_status_text() -> String:
	return "%d / %d rounds" % [rounds, capacity]


func _on_tap() -> void:
	say("Ammo box: hold the key to jettison it")


func _get_load_mass() -> float:
	return rounds * ShipHardpoints.AMMO_MASS_PER_ROUND


# A crate with a lid band at the outer end, latches, and a gauge of shell tips.
func _draw_module() -> void:
	_draw_plate(footprint, body_color)

	var inner := footprint.grow(-TEXEL)
	draw_rect(Rect2(inner.end.x - TEXEL * 2.0, inner.position.y, TEXEL * 2.0, inner.size.y), lid_color)

	for y in [inner.position.y + TEXEL, inner.end.y - TEXEL * 2.0]:
		draw_rect(Rect2(inner.end.x - TEXEL * 2.0, y, TEXEL, TEXEL), accent_color)

	var gauge := Rect2(inner.position.x + TEXEL, inner.position.y + TEXEL * 2.0, TEXEL * 2.0, inner.size.y - TEXEL * 4.0)
	_draw_gauge(gauge, float(rounds) / capacity, shell_color, gauge_color)


# The gauge is a few texels tall: only redraw when it shows a different level.
func _redraw_if_changed() -> void:
	var ratio := snappedf(float(rounds) / capacity, 0.05)

	if ratio != _drawn_ratio:
		_drawn_ratio = ratio
		queue_redraw()
