class_name AsteroidLook
extends RefCounted

# How an Asteroid looks, kept apart from how it behaves.
#
# Each 4 px cell is drawn as 2x2 texels of 2 px, the size of the ship's pixel art.
# Two textures feed asteroid.gdshader:
# - look: one pixel per texel. RGB = colour (material, flecks, facets, cracks). A = crater shade.
#   Painted once when the body is created (or copied from the parent, for a chunk), then only
#   touched where ore gets revealed.
# - cells: one pixel per cell. R = filled, G = in the core. Patched where cells changed: a giant
#   has ~72 000 cells, too many to loop over after every laser shot.
# The shader works out holes, the outline, the darker inner edge and the darker core from them,
# on the GPU, so a laser shot never repaints thousands of texels.
#
# Texel colours only depend on the texel's coordinates and the seed. Chunks keep the cell
# coordinates of their parent, so a chunk looks exactly like the part of the rock it was.

const SHADER: Shader = preload("res://Asteroids/asteroid.gdshader")
const TEXELS_PER_CELL: int = 2 # Keep equal to the shader's
const FLECK_DARKEN: float = 0.18
const FLECK_LIGHTEN: float = 0.14
const FACET_LIGHTEN: float = 0.09
const CRACK_DARKEN: float = 0.45
const CRACK_WIDTH: float = 0.04 # Noise band drawn as a crack. Wider = more, thicker cracks
const FACET_THRESHOLD: float = 0.15 # Noise above this is a lighter facet. Lower = more facets

var material: ShaderMaterial
var grid_origin: Vector2i # Cell under the grid's top-left pixel: one empty cell of margin, for the outline
var grid_size: Vector2i # In cells

var _seed: int
var _look_image: Image
var _look_texture: ImageTexture
var _cells_image: Image
var _cells_texture: ImageTexture
var _cells_data := PackedByteArray() # The cells image's bytes, kept so a cut only patches a few of them
var _facet_noise := FastNoiseLite.new()
var _crack_noise := FastNoiseLite.new()


# cell_list: every cell the body will ever have. A body only loses cells, so the grid is sized once.
# Only makes images: safe on a worker thread. Call create_gpu_resources() on the main thread
# before drawing.
func _init(cell_list: Array, look_seed: int) -> void:
	_seed = look_seed
	_facet_noise.seed = look_seed
	_facet_noise.frequency = 0.05
	_facet_noise.fractal_octaves = 2
	_crack_noise.seed = look_seed + 1
	_crack_noise.frequency = 0.09
	_crack_noise.fractal_octaves = 3

	var low: Vector2i = cell_list[0]
	var high: Vector2i = cell_list[0]

	for cell: Vector2i in cell_list:
		low = low.min(cell)
		high = high.max(cell)

	grid_origin = low - Vector2i.ONE
	grid_size = high - low + Vector2i(3, 3)

	_look_image = Image.create_empty(grid_size.x * TEXELS_PER_CELL, grid_size.y * TEXELS_PER_CELL, false, Image.FORMAT_RGBA8)
	_cells_data.resize(grid_size.x * grid_size.y * 2)
	_cells_data.fill(0)


# Textures and material, from the images as they are now. Main thread only.
func create_gpu_resources() -> void:
	_look_texture = ImageTexture.create_from_image(_look_image)
	_cells_image = Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_RG8, _cells_data)
	_cells_texture = ImageTexture.create_from_image(_cells_image)

	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("look", _look_texture)
	material.set_shader_parameter("cells", _cells_texture)


func set_shades(outline_color: Color, core_shade: float, edge_shade: float) -> void:
	material.set_shader_parameter("outline_color", outline_color)
	material.set_shader_parameter("core_shade", core_shade)
	material.set_shader_parameter("edge_shade", edge_shade)


func get_texture() -> Texture2D:
	return _look_texture


func get_look_image() -> Image:
	return _look_image


# Where to draw the texture, in the body's space.
func get_draw_rect(cell_size: float) -> Rect2:
	return Rect2(Vector2(grid_origin) * cell_size, Vector2(grid_size) * cell_size)


# Paints every cell, then the craters. Craters are in texels: x, y = centre, z = radius.
func paint_all(materials: Dictionary[Vector2i, int], revealed: Dictionary[Vector2i, bool], craters: Array[Vector3], floor_shade: float, rim_shade: float) -> void:
	for cell in materials:
		_paint_cell(cell, CellMaterials.get_display_id(materials[cell], revealed.has(cell)), false)

	for crater in craters:
		_stamp_crater(crater, floor_shade, rim_shade)

	_push_look()


# For a chunk: takes the parent's texels instead of painting them again (same coordinates).
func copy_from(parent: AsteroidLook) -> void:
	var source_position := (grid_origin - parent.grid_origin) * TEXELS_PER_CELL
	_look_image.blit_rect(parent.get_look_image(), Rect2i(source_position, _look_image.get_size()), Vector2i.ZERO)
	_push_look()


# Paints these cells again (their look changed: ore revealed). Keeps the crater shade.
func repaint(changed: Array[Vector2i], materials: Dictionary[Vector2i, int], revealed: Dictionary[Vector2i, bool]) -> void:
	if changed.is_empty():
		return

	for cell in changed:
		_paint_cell(cell, CellMaterials.get_display_id(materials[cell], revealed.has(cell)), true)

	_push_look()


# Which cells are filled, and which of them are in the core (not in the band). Every cell.
func fill_cells(materials: Dictionary[Vector2i, int], band: Dictionary[Vector2i, bool]) -> void:
	_cells_data.fill(0)

	for cell in materials:
		_set_cell_bytes(cell, materials, band)

	_push_cells()


# Same, only for these cells: the ones a cut removed or brought into the band.
func patch_cells(changed: Array[Vector2i], materials: Dictionary[Vector2i, int], band: Dictionary[Vector2i, bool]) -> void:
	if changed.is_empty():
		return

	for cell in changed:
		_set_cell_bytes(cell, materials, band)

	_push_cells()


func _set_cell_bytes(cell: Vector2i, materials: Dictionary[Vector2i, int], band: Dictionary[Vector2i, bool]) -> void:
	var position := cell - grid_origin
	var index := (position.y * grid_size.x + position.x) * 2

	if not materials.has(cell):
		_cells_data[index] = 0
		_cells_data[index + 1] = 0
		return

	_cells_data[index] = 255
	_cells_data[index + 1] = 0 if band.has(cell) else 255


# Sends the images to their textures, once they exist (not yet on a worker thread).
func _push_look() -> void:
	if _look_texture != null:
		_look_texture.update(_look_image)


func _push_cells() -> void:
	if _cells_texture == null:
		return

	_cells_image.set_data(grid_size.x, grid_size.y, false, Image.FORMAT_RG8, _cells_data)
	_cells_texture.update(_cells_image)


func _paint_cell(cell: Vector2i, display_id: int, keep_shade: bool) -> void:
	var first_pixel := (cell - grid_origin) * TEXELS_PER_CELL

	for y in TEXELS_PER_CELL:
		for x in TEXELS_PER_CELL:
			var offset := Vector2i(x, y)
			var pixel := first_pixel + offset
			var color := _get_texel_color(cell * TEXELS_PER_CELL + offset, display_id)

			if keep_shade:
				color.a = _look_image.get_pixelv(pixel).a

			_look_image.set_pixelv(pixel, color)


# texel: in the body's texel coordinates (cell * TEXELS_PER_CELL + position in the cell).
func _get_texel_color(texel: Vector2i, display_id: int) -> Color:
	var cell_material := CellMaterials.get_material(display_id)
	var roll := _get_roll(texel)

	if roll < cell_material.dark_chance:
		return cell_material.color.darkened(FLECK_DARKEN)

	if roll > 1.0 - cell_material.light_chance:
		return cell_material.color.lightened(FLECK_LIGHTEN)

	if cell_material.has_facets:
		if absf(_crack_noise.get_noise_2dv(Vector2(texel))) < CRACK_WIDTH:
			return cell_material.color.darkened(CRACK_DARKEN)

		if _facet_noise.get_noise_2dv(Vector2(texel)) > FACET_THRESHOLD:
			return cell_material.color.lightened(FACET_LIGHTEN)

	return cell_material.color


# A number from 0 to 1 that only depends on the texel and the seed.
func _get_roll(texel: Vector2i) -> float:
	return posmod(hash(Vector3i(texel.x, texel.y, _seed)), 10000) / 10000.0


# Darkens a disc of texels (the floor) and its edge (the rim), through the alpha channel.
# The shader only applies it in the core.
func _stamp_crater(crater: Vector3, floor_shade: float, rim_shade: float) -> void:
	var center := Vector2(crater.x, crater.y)
	var radius := crater.z
	var grid_texel := grid_origin * TEXELS_PER_CELL
	var image_size := _look_image.get_size()

	for y in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for x in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			var pixel := Vector2i(x, y) - grid_texel

			if pixel.x < 0 or pixel.y < 0 or pixel.x >= image_size.x or pixel.y >= image_size.y:
				continue

			var distance := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center)
			var shade := 1.0

			if distance < radius - 1.0:
				shade = floor_shade
			elif distance < radius:
				shade = rim_shade
			else:
				continue

			var color := _look_image.get_pixelv(pixel)
			color.a = minf(color.a, shade)
			_look_image.set_pixelv(pixel, color)
