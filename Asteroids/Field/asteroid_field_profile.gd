class_name AsteroidFieldProfile
extends Resource

# How a region of the belt is filled with asteroids: density, formations, lone rocks, ore odds.
# The AsteroidField uses one profile for now. Regions will each get their own later.
#
# Density comes from a slow noise over the whole belt: below empty_below there are no formations
# at all (the empty swathes), above full_above the density is at its maximum.

@export var sector_size: float = 2048.0 # px. The unit of loading. Formations must fit within one sector of reach

@export_group("Density")
@export var density_frequency: float = 0.00007 # Lower = bigger busy regions and bigger empty swathes
@export var density_octaves: int = 2
@export_range(-1.0, 1.0) var empty_below: float = -0.12 # Noise value under which space is empty. The noise mostly stays within ±0.5
@export_range(-1.0, 1.0) var full_above: float = 0.2 # Noise value over which density is at its maximum

@export_group("Formations")
@export var formations_per_sector: float = 2.0 # At full density. Each is kept with a chance equal to the density where it lands
@export var formations: Array[AsteroidFormation] = []

@export_group("Lone rocks")
@export var lone_rocks_per_sector: float = 5.0 # At full density
@export var lone_rocks_in_empty_space: float = 0.4 # Per sector, wherever the density is zero: emptiness is never perfect
@export var min_lone_radius: float = 2.0 # Cells
@export var max_lone_radius: float = 30.0
@export var lone_size_skew: float = 2.2

@export_group("Ore outside clusters")
@export_range(0.0, 1.0) var lone_valuable_chance: float = 0.06 # Rocks outside ore clusters that still hold ore cells
@export_range(0.0, 1.0) var lone_min_ore_ratio: float = 0.04
@export_range(0.0, 1.0) var lone_max_ore_ratio: float = 0.08

@export_group("Ore in big rocks")
@export var ore_reference_radius: float = 24.0 # Cells. Rocks up to this size keep the base ore rules
@export var ore_cluster_growth: float = 0.75 # Ore clusters × (radius / reference) ^ this
@export var ore_share_growth: float = 0.3 # Ore share × (radius / reference) ^ this
@export_range(0.0, 1.0) var max_ore_share: float = 0.25

@export_group("Motion")
@export var max_spin: float = 0.8 # rad/s for a one-cell pebble. Divided by sqrt(radius): giants barely turn
@export_range(0.0, 1.0) var spinning_chance: float = 0.15 # Share of rocks that spin at all. The others only drift
@export var drift_jitter: float = 0.5 # px/s, each rock's own drift on top of its formation's

@export_group("Spacing")
@export var rock_gap: float = 8.0 # px kept free between the outlines of two rocks
@export var bound_factor: float = 1.3 # Outer radius of a rock / its radius_in_cells × cell size. Covers the lumps and the stretch


# 0 (empty) to 1 (full), at a point. `noise` comes from make_density_noise().
func get_density(noise: FastNoiseLite, point: Vector2) -> float:
	return clampf(inverse_lerp(empty_below, full_above, noise.get_noise_2dv(point)), 0.0, 1.0)


# One per thread: noise objects aren't shared between threads.
func make_density_noise(world_seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = world_seed
	noise.frequency = density_frequency
	noise.fractal_octaves = density_octaves
	return noise
