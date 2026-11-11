class_name MothershipLights
extends Node2D

# The moving parts of the mothership's look, redrawn every frame: engine plumes, the player's
# slot lights, the deflector emitters. MothershipArt has the rest.

const FLAME := Color(1.0, 0.6, 0.25, 0.8)
const FLAME_CORE := Color(1.0, 0.92, 0.7)

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var train := get_parent() as Mothership

	if train == null:
		return

	_draw_plumes()
	_draw_emitters()
	_draw_slot_lights(train)


func _draw_plumes() -> void:
	for y in Mothership.ENGINE_Y:
		var flicker := 1.0 + 0.12 * sin(_time * 31.0 + y) + 0.06 * sin(_time * 53.0 + y * 0.3)
		var exit := Vector2(Mothership.ENGINE_EXIT_X, y)
		var length := 320.0 * flicker
		draw_colored_polygon(PackedVector2Array([exit + Vector2(0, -35), exit + Vector2(-length, 0), exit + Vector2(0, 35)]), FLAME)
		draw_colored_polygon(PackedVector2Array([exit + Vector2(0, -18), exit + Vector2(-length * 0.45, 0), exit + Vector2(0, 18)]), FLAME_CORE)


func _draw_emitters() -> void:
	var points := MothershipArt.get_emitters()

	for k in points.size():
		var pulse := 0.5 + 0.5 * sin(_time * 4.0 + k * 0.9)
		draw_circle(points[k], 14.0 + pulse * 6.0, Color(MothershipArt.SKY, 0.2 * pulse))
		draw_circle(points[k], 6.0, Color.WHITE)


# Green: a chase running toward the front. Amber: blinking. Off: nothing.
func _draw_slot_lights(train: Mothership) -> void:
	var color := train.slot_light

	if color.a <= 0.0 or train.player_slot.is_empty():
		return

	var size: Vector2 = Mothership.SLOT_SIZE[train.player_slot.cls]
	var half := size / 2.0
	draw_set_transform_matrix(train.player_slot.xform)

	for i in 7:
		var x := lerpf(-half.x + 20.0, half.x - 30.0, i / 6.0)
		var lit := color

		if color == MothershipArt.LIGHT_GREEN:
			lit = color if posmod(i - floori(_time * 8.0), 3) == 0 else color.darkened(0.6)
		elif fmod(_time, 0.5) >= 0.25:
			lit = color.darkened(0.6)

		draw_rect(Rect2(x, -half.y + 6.0, 8, 6), lit)
		draw_rect(Rect2(x, half.y - 12.0, 8, 6), lit)

	draw_circle(Vector2(-half.x + 8.0, -half.y + 8.0), 6.0, color)
	draw_circle(Vector2(-half.x + 8.0, half.y - 8.0), 6.0, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)
