class_name HubArea
extends Control

# One clickable part of the station map. It covers the whole map, but only reacts where its mask
# image is opaque: the part's own shape, so the gaps around it don't catch clicks.
# The mask is drawn at texel scale (1 texel = texel_size px), like the station art.

signal entered(area_id: StringName)
signal exited(area_id: StringName)
signal pressed(area_id: StringName)

var area_id: StringName
var texel_size: float = 2.0

var _mask: Image


func setup(id: StringName, mask: Texture2D, map_size: Vector2, texel: float) -> void:
	area_id = id
	_mask = mask.get_image()
	texel_size = texel
	size = map_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: entered.emit(area_id))
	mouse_exited.connect(func() -> void: exited.emit(area_id))


func _has_point(point: Vector2) -> bool:
	if _mask == null:
		return false

	var pixel := Vector2i(point / texel_size)

	if pixel.x < 0 or pixel.y < 0 or pixel.x >= _mask.get_width() or pixel.y >= _mask.get_height():
		return false

	return _mask.get_pixelv(pixel).a > 0.5


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton

	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(area_id)
		accept_event()
