class_name BallastPod
extends SoftPoint

# A dense block bolted on one side. It does nothing but weigh: it moves the centre of mass toward
# its side, to balance a lopsided ship (cargo pools at the back, a full drop tank on the other
# side...). Hold the key to drop it, when you'd rather be light than balanced.
# The balance view (B) shows what it does to the centre of mass and to each thruster's lever arm.

@export_group("Look")
@export var block_color: Color = Color(0.24, 0.23, 0.26)


func _init() -> void:
	footprint = Rect2(0, -10, 10, 20)
	dry_mass = 8.0
	can_jettison = true
	break_impulse = 2500.0 # Solid lump, solid bolts


func get_status_text() -> String:
	return "%.0f mass" % dry_mass


func _on_tap() -> void:
	say("Ballast: hold the key to drop it")


func _draw_module() -> void:
	_draw_plate(footprint, block_color)

	var inner := footprint.grow(-TEXEL * 2.0)
	var y := inner.position.y

	while y < inner.end.y:
		draw_rect(Rect2(inner.position.x, y, inner.size.x, TEXEL), block_color.darkened(0.35))
		y += TEXEL * 3.0

	draw_rect(Rect2(inner.end.x - TEXEL, inner.position.y, TEXEL, inner.size.y), accent_color)
