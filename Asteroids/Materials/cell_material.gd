class_name CellMaterial
extends Resource

# What one asteroid cell is made of. One .tres file per material, in this folder.
# Cells don't hold this resource: they hold an id (CellMaterials.Id), and CellMaterials maps ids to
# these files. Open a .tres in the inspector to tune it.

@export var display_name: String = ""
@export var color: Color = Color.GRAY
@export_range(1.0, 10.0) var hardness: float = 1.0 # 1 = soft rock. Laser budget per cell, drill time per cell, resistance to breaking off
@export var is_ore: bool = false
@export var value: float = 0.0 # Credits per refined unit. Not used yet: there's no market
@export var spawn_weight: float = 0.0 # Ores only: how often an asteroid carries this ore, relative to the other ores

@export_group("Texture")
# Each cell is drawn as 2×2 texels. These pick how often a texel is a darker or lighter fleck.
@export_range(0.0, 1.0) var dark_chance: float = 0.07
@export_range(0.0, 1.0) var light_chance: float = 0.0
@export var has_facets: bool = false # Lighter patches and thin cracks, for hard rock
