class_name SkyTile
extends Sprite2D
## Repeats its texture over the part of the parent SkyLayer that is on screen.
## Used for stars and dust: random dots hide the repetition.

@export var texel_size := 2.0 ## Layer units per texture pixel. 2 matches the asteroids' pixel size


func _ready() -> void:
	centered = false
	region_enabled = true
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(texel_size, texel_size)
	(get_parent() as SkyLayer).visible_rect_changed.connect(_on_visible_rect_changed)


func _on_visible_rect_changed(rect: Rect2) -> void:
	# Snapped to whole texels so the pattern stays anchored to the layer instead of sliding
	var first_texel := (rect.position / texel_size).floor()
	var last_texel := (rect.end / texel_size).ceil()
	position = first_texel * texel_size
	region_rect = Rect2(first_texel, last_texel - first_texel)
