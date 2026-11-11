class_name ScanOverlay
extends Node2D

# The basic scanner's heat map, drawn over every rock that holds heat cells (Asteroid.heat_cells).
# Blurry on purpose: the cells are counted in blocks of BLOCK × BLOCK, and each block that holds
# some becomes a soft glow, brighter the more ore it holds. The player learns roughly where the ore
# is, not which cells. The precision scanner reveals the cells themselves instead.
# A single overlay for the whole world, in world space, created by the first scanner (ensure()). It
# stays when the scanner is swapped out: what was scanned stays scanned.

const BLOCK: int = 4 # Cells per side of a heat block
const GLOW_RADIUS: float = 0.85 # Times a block's width
const FULL_BLOCK_CELLS: float = 6.0 # Ore cells in a block for full brightness
const MIN_STRENGTH: float = 0.3

static var _instance: ScanOverlay

@export var outer_color: Color = Color(1.0, 0.35, 0.08, 0.16)
@export var middle_color: Color = Color(1.0, 0.6, 0.15, 0.2)
@export var core_color: Color = Color(1.0, 0.9, 0.5, 0.28)
@export var pulse_speed: float = 2.5 # rad/s
@export_range(0.0, 1.0) var pulse_depth: float = 0.2

var _time: float = 0.0
var _blocks_by_rock: Dictionary[int, Dictionary] = {} # Rock instance id -> { "count": heat cells counted, "blocks": Dictionary[Vector2i, int] }


static func ensure(tree: SceneTree) -> void:
	if is_instance_valid(_instance):
		return

	_instance = ScanOverlay.new()
	tree.current_scene.add_child.call_deferred(_instance) # The scene may still be setting up


func _ready() -> void:
	z_index = 3 # Over the rocks and their chunks
	top_level = true


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 - pulse_depth * 0.5 * (1.0 + sin(_time * pulse_speed))
	var seen: Dictionary[int, bool] = {}

	for node in get_tree().get_nodes_in_group(Asteroid.HEAT_GROUP):
		var rock := node as Asteroid

		if rock == null or rock.heat_cells.is_empty():
			continue

		var id := rock.get_instance_id()
		seen[id] = true
		var blocks := _get_blocks(rock, id)
		draw_set_transform_matrix(rock.global_transform)

		var block_width := BLOCK * rock.cell_size
		var radius := block_width * GLOW_RADIUS

		for block: Vector2i in blocks:
			var strength := clampf(blocks[block] / FULL_BLOCK_CELLS, MIN_STRENGTH, 1.0) * pulse
			var center := (Vector2(block) + Vector2(0.5, 0.5)) * block_width
			draw_circle(center, radius, _faded(outer_color, strength))
			draw_circle(center, radius * 0.6, _faded(middle_color, strength))
			draw_circle(center, radius * 0.3, _faded(core_color, strength))

	draw_set_transform_matrix(Transform2D.IDENTITY)

	for id in _blocks_by_rock.keys():
		if not seen.has(id):
			_blocks_by_rock.erase(id)


# Recounted only when the rock's heat changed (scanned further, or cut).
func _get_blocks(rock: Asteroid, id: int) -> Dictionary:
	var cached: Dictionary = _blocks_by_rock.get(id, {})

	if cached.get("count", -1) == rock.heat_cells.size():
		return cached["blocks"]

	var blocks: Dictionary[Vector2i, int] = {}

	for cell in rock.heat_cells:
		var block := Vector2i(floori(cell.x / float(BLOCK)), floori(cell.y / float(BLOCK)))
		blocks[block] = blocks.get(block, 0) + 1

	_blocks_by_rock[id] = { "count": rock.heat_cells.size(), "blocks": blocks }
	return blocks


func _faded(color: Color, strength: float) -> Color:
	var faded := color
	faded.a *= strength
	return faded
