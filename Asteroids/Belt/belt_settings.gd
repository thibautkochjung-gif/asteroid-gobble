class_name BeltSettings
extends Resource

# The whole belt, at the scale of the undock map (km). Each run draws a new belt from its run seed:
# the mothership's route (BeltRoute) and a slow "richness" noise. What a sector holds then depends
# on where it sits in the belt (BeltSampler): deeper rocks are bigger, more numerous, more often
# ore-bearing and carry rarer ores; richer areas hold more ore clusters.
# The undock map shows an estimate of the same thing (get_value_estimate), blurred by the survey.
#
# Belt space: x = depth (0 at the station's lane), y = across the belt. 1 km = 1,000 px in the field
# (1 px = 1 m), and the field's axes are the belt's: +x in the field is deeper.

const PX_PER_KM: float = 1000.0

@export var depth_km: float = 100.0 # The far edge of the belt (and of the map)
@export var width_km: float = 76.0 # Across the belt, centred on 0

@export_group("Richness")
@export var richness_frequency: float = 0.06 # Per km. Lower = bigger rich and poor areas
@export var richness_octaves: int = 2
@export var richness_contrast: float = 1.8 # Pushes the noise toward clearly rich or clearly poor
@export var poor_factor: float = 0.3 # Ore clusters and lone ore-bearing rocks × this where richness is 0
@export var rich_factor: float = 2.2 # … and × this where it is 1

@export_group("Depth")
## Each value is the multiplier at depth_km. It grows linearly from ×1 at depth 0.
@export var density_at_bottom: float = 1.6 # Formations and lone rocks per sector
@export var size_at_bottom: float = 1.4 # Largest rock radius (cores of giants excepted)
@export var valuable_at_bottom: float = 2.0 # Share of rocks that hold ore
@export var ore_ratio_at_bottom: float = 1.5 # Ore share inside ore-bearing rocks

@export_group("Ores")
## Ore weights at depth 0 and at depth_km, keyed by CellMaterials.Id. Linear in between.
@export var ore_weights_top: Dictionary[int, float] = { 2: 50.0, 3: 30.0, 4: 15.0, 5: 2.0, 6: 0.0 }
@export var ore_weights_bottom: Dictionary[int, float] = { 2: 15.0, 3: 25.0, 4: 25.0, 5: 10.0, 6: 5.0 }
## No ore of this kind above this depth (km). Its weight ramps up from there to ore_weights_bottom.
@export var ore_min_depth: Dictionary[int, float] = { 6: 33.0 }

@export_group("Mothership route")
@export var turnaround_depth: Vector2 = Vector2(80.0, 95.0) # km, deepest point of the route
@export var crossing_ratio: Vector2 = Vector2(0.38, 0.55) # Where the legs cross, as a share of the turnaround depth
@export var loop_half_width: Vector2 = Vector2(9.0, 15.0) # km, half the loop's width
@export var lane_spread: Vector2 = Vector2(3.0, 9.0) # km between the legs near the station
@export var wiggle: float = 3.0 # km of random bend on each control point
@export var route_steps: int = 16 # Points per stretch of curve

@export_group("Survey")
## What the map shows at each survey level (crew will raise it). x: error in km (the bands are
## shifted by up to this much), y: blur in km, z: number of contour bands.
@export var survey_levels: Array[Vector3] = [Vector3(8.0, 9.0, 5.0), Vector3(3.0, 4.0, 8.0), Vector3(0.0, 1.5, 10.0)]


# One per thread: noise objects aren't shared between threads.
func make_richness_noise(run_seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = run_seed
	noise.frequency = richness_frequency
	noise.fractal_octaves = richness_octaves
	return noise


# 0 (poor) to 1 (rich), at a point of the belt in km.
func get_richness(noise: FastNoiseLite, km: Vector2) -> float:
	return clampf(0.5 + noise.get_noise_2dv(km) * richness_contrast, 0.0, 1.0)


func get_richness_factor(richness: float) -> float:
	return lerpf(poor_factor, rich_factor, richness)


# 0 at the station's lane, 1 at the far edge.
func get_depth_ratio(depth: float) -> float:
	return clampf(depth / depth_km, 0.0, 1.0)


func get_density_factor(depth: float) -> float:
	return lerpf(1.0, density_at_bottom, get_depth_ratio(depth))


func get_size_factor(depth: float) -> float:
	return lerpf(1.0, size_at_bottom, get_depth_ratio(depth))


func get_valuable_factor(depth: float) -> float:
	return lerpf(1.0, valuable_at_bottom, get_depth_ratio(depth))


func get_ore_ratio_factor(depth: float) -> float:
	return lerpf(1.0, ore_ratio_at_bottom, get_depth_ratio(depth))


# Weight of each ore at this depth, in CellMaterials.ORES order.
func get_ore_weights(depth: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()

	for ore in CellMaterials.ORES:
		var top: float = ore_weights_top.get(ore, 0.0)
		var bottom: float = ore_weights_bottom.get(ore, 0.0)
		var start: float = ore_min_depth.get(ore, 0.0)

		if depth < start:
			weights.append(0.0)
		else:
			weights.append(lerpf(top, bottom, clampf(inverse_lerp(start, depth_km, depth), 0.0, 1.0)))

	return weights


# Credits of ore an area at this depth and richness should hold, relative to other areas: what the
# undock map draws. Follows the same factors as the field (BeltSampler, AsteroidSectorPlanner).
func get_value_estimate(depth: float, richness: float) -> float:
	return get_depth_value(depth) * get_richness_factor(richness)


# The depth's part of get_value_estimate(): ore mix, ore-bearing share, ore ratio, density.
func get_depth_value(depth: float) -> float:
	var weights := get_ore_weights(depth)
	var total := 0.0
	var value := 0.0

	for i in CellMaterials.ORES.size():
		total += weights[i]
		value += weights[i] * CellMaterials.get_material(CellMaterials.ORES[i]).value

	var ore_value := value / total if total > 0.0 else 0.0
	return ore_value * get_valuable_factor(depth) * get_ore_ratio_factor(depth) * get_density_factor(depth)
