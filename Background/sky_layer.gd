class_name SkyLayer
extends CanvasLayer
## One depth of the background. It moves at a fraction of the camera's speed
## and reacts to zoom the way a far plane would if the camera went up or down:
## far layers barely change size, near layers follow the world.
## Children draw in "layer units" and listen to visible_rect_changed.

signal visible_rect_changed(rect: Rect2)

@export_range(0.0, 1.0, 0.001) var scroll_scale := 0.1 ## 0 = infinitely far (never moves), 1 = moves with the world
@export var reference_zoom := 1.0 ## Camera zoom at which the layer shows at its authored size

## Part of the layer that is on screen, in layer units
var visible_rect := Rect2()


func _ready() -> void:
	# Run after the camera has moved and zoomed this frame, or the layers lag one frame behind the world
	process_priority = 100


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var screen_size := get_viewport().get_visible_rect().size
	var layer_scale := get_depth_scale(camera.zoom.x)
	var scroll := get_sky_camera_position(camera) * scroll_scale
	transform = Transform2D(0.0, Vector2(layer_scale, layer_scale), 0.0, screen_size / 2.0 - scroll * layer_scale)

	visible_rect = Rect2(scroll - screen_size / 2.0 / layer_scale, screen_size / layer_scale)
	visible_rect_changed.emit(visible_rect)


## On-screen scale of this layer for a given camera zoom.
## Zoom is read as camera height: diving towards the asteroids barely enlarges a far nebula.
func get_depth_scale(zoom: float) -> float:
	var relative_zoom := zoom / reference_zoom
	return reference_zoom / (scroll_scale / relative_zoom + 1.0 - scroll_scale)


## The one place to change when the world gets a floating origin
## (add the origin's accumulated shift here so the sky doesn't jump).
func get_sky_camera_position(camera: Camera2D) -> Vector2:
	return camera.get_screen_center_position()
