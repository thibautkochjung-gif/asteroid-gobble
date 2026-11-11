class_name AsteroidFormation
extends Resource

# One kind of group of asteroids an AsteroidFieldProfile can roll: a pocket of mixed rocks, a rich
# ore cluster, a long field of gravel, a giant with its debris... They only differ by these values.
#
# A formation is an area (a disc, or an ellipse when stretched) with rocks scattered inside, denser
# toward the middle when concentration > 1. It can have a core rock in the middle (a giant).
# Its rocks drift together, so the group holds its shape.

@export var name: String = ""
@export var weight: float = 1.0 # How often this formation comes up, against the others in the profile

@export_group("Area")
@export var min_area_radius: float = 300.0 # px
@export var max_area_radius: float = 700.0 # px. Area radius × sqrt(max_area_stretch) must stay under the sector size
@export var max_area_stretch: float = 1.0 # Length / width of the area. 1 = disc
@export var concentration: float = 1.5 # 1 = even spread. Higher = rocks bunch up in the middle

@export_group("Rocks")
@export var min_count: int = 6
@export var max_count: int = 16
@export var min_rock_radius: float = 3.0 # Cells (4 px). The ship is ~50 cells long
@export var max_rock_radius: float = 35.0
@export var size_skew: float = 2.0 # 1 = sizes spread evenly (on a log scale). Higher = small rocks much more common

@export_group("Core rock")
@export var min_core_radius: float = 0.0 # Cells. 0 = no core rock
@export var max_core_radius: float = 0.0

@export_group("Ore")
@export var min_ore_types: int = 0 # 0 = no shared ores: rocks follow the profile's lone rock odds
@export var max_ore_types: int = 0 # The cluster picks this many ores; each rock holds one of them
@export_range(0.0, 1.0) var valuable_chance: float = 0.0 # Share of the rocks that hold ore cells (when the formation has ores)
@export_range(0.0, 1.0) var min_ore_ratio: float = 0.04
@export_range(0.0, 1.0) var max_ore_ratio: float = 0.08

@export_group("Motion")
@export var max_drift: float = 1.5 # px/s, shared by the whole formation


func has_core() -> bool:
	return max_core_radius > 0.0


func has_shared_ores() -> bool:
	return max_ore_types > 0
