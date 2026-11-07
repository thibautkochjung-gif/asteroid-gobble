@tool
class_name RoomSlot
extends Marker2D

# Where a room goes, and how big it is. ShipRooms hands the size to the room it installs here,
# and the room works out its capacity from it: a bigger slot means a bigger hold, tank or chamber.
# In px, centred on this marker. Keep both numbers even: the art is drawn on 2 px texels.
# The hull (ShipHull) is drawn around the slots, so resizing a slot reshapes the hull too.
# In the editor, the slot draws its outline so the layout can be seen without running the game.

@export var size: Vector2 = Vector2(34, 48):
	set(value):
		size = value
		queue_redraw()

@export var editor_outline_color: Color = Color(0.4, 0.9, 1.0, 0.7)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	draw_rect(Rect2(-size * 0.5, size), editor_outline_color, false, 1.0)
