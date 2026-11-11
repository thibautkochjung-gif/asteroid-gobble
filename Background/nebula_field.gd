class_name NebulaField
extends Node2D
## Streams nebulas on a SkyLayer, sector by sector.
## A sector's content only depends on its coordinates and sky_seed,
## so a given place in the belt always shows the same sky.

@export var textures: Array[Texture2D] = []
@export var sky_seed := 1
@export var sector_size := 3072.0 ## Layer units
@export var texel_size := 2.0 ## Layer units per texture pixel
@export_range(0.0, 1.0) var empty_sector_chance := 0.3
@export var max_per_sector := 2

var _sectors: Dictionary[Vector2i, Array] = {}
var _load_margin := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# A nebula centred near a sector's edge sticks out by up to half its diagonal:
	# load sectors that far around the screen so nothing pops in
	for texture in textures:
		_load_margin = maxf(_load_margin, texture.get_size().length() * texel_size / 2.0)

	(get_parent() as SkyLayer).visible_rect_changed.connect(_on_visible_rect_changed)


func _on_visible_rect_changed(rect: Rect2) -> void:
	var area := rect.grow(_load_margin)
	var first := Vector2i((area.position / sector_size).floor())
	var last := Vector2i((area.end / sector_size).floor())

	var wanted: Dictionary[Vector2i, bool] = {}
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var sector := Vector2i(x, y)
			wanted[sector] = true
			if not _sectors.has(sector):
				_sectors[sector] = _spawn_sector(sector)

	for sector: Vector2i in _sectors.keys():
		if not wanted.has(sector):
			for sprite: Sprite2D in _sectors[sector]:
				sprite.queue_free()
			_sectors.erase(sector)


func _spawn_sector(sector: Vector2i) -> Array:
	var sprites: Array = []
	if textures.is_empty():
		return sprites

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(sector.x, sector.y, sky_seed))
	if rng.randf() < empty_sector_chance:
		return sprites

	for _i in rng.randi_range(1, max_per_sector):
		var sprite := Sprite2D.new()
		sprite.texture = textures[rng.randi_range(0, textures.size() - 1)]
		sprite.scale = Vector2(texel_size, texel_size)
		# 4 rotations x 2 flips: 8 looks per texture
		sprite.rotation = rng.randi_range(0, 3) * PI / 2.0
		sprite.flip_h = rng.randf() < 0.5
		var spot := Vector2(rng.randf(), rng.randf()) * sector_size
		sprite.position = (Vector2(sector) * sector_size + spot).snapped(Vector2(texel_size, texel_size))
		add_child(sprite)
		sprites.append(sprite)

	return sprites
