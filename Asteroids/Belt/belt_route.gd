class_name BeltRoute
extends RefCounted

# The mothership's route through the belt for one run, in belt km (see BeltSettings).
# It leaves the station's lane, heads deeper, loops around at the turnaround and comes back,
# crossing its own outbound leg on the way: a lasso. Same run seed, same route.
#
# A drop point anywhere on the map is reached from the nearest point of either leg: that leg is
# the cheaper one (the fare only depends on depth, the transfer on the distance to the line).

enum Leg { OUTBOUND, RETURN }

var outbound := PackedVector2Array()
var inbound := PackedVector2Array() # The return leg
var turnaround := Vector2.ZERO


# The nearest point of the route to `km`.
class Hop:
	var leg: Leg = Leg.OUTBOUND
	var point := Vector2.ZERO # km, on the route
	var heading := Vector2.RIGHT # Where the mothership travels there
	var distance: float = 0.0 # km from `km` to the route


static func create(settings: BeltSettings, run_seed: int) -> BeltRoute:
	var route := BeltRoute.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(run_seed, 4242))

	var deepest := rng.randf_range(settings.turnaround_depth.x, settings.turnaround_depth.y)
	var crossing := deepest * rng.randf_range(settings.crossing_ratio.x, settings.crossing_ratio.y)
	var half_width := rng.randf_range(settings.loop_half_width.x, settings.loop_half_width.y)
	var spread := rng.randf_range(settings.lane_spread.x, settings.lane_spread.y)
	var centre := rng.randf_range(-0.15, 0.15) * settings.width_km
	var side := 1.0 if rng.randf() < 0.5 else -1.0 # Which side the outbound leg takes around the loop
	var loop_depth := crossing + (deepest - crossing) * 0.45
	var tip_depth := deepest - half_width * 0.35

	var out_points: Array[Vector2] = [
		Vector2(0.0, centre + side * spread),
		Vector2(crossing * 0.35, centre + side * spread * 0.8),
		Vector2(crossing * 0.7, centre + side * spread * 0.4),
		Vector2(crossing, centre),
		Vector2(loop_depth, centre - side * half_width),
		Vector2(tip_depth, centre - side * half_width * 0.75),
		Vector2(deepest, centre),
	]
	var back_points: Array[Vector2] = [
		Vector2(deepest, centre),
		Vector2(tip_depth, centre + side * half_width * 0.75),
		Vector2(loop_depth, centre + side * half_width),
		Vector2(crossing, centre),
		Vector2(crossing * 0.7, centre - side * spread * 0.4),
		Vector2(crossing * 0.35, centre - side * spread * 0.8),
		Vector2(0.0, centre - side * spread),
	]

	# Bends: every point but the ends, the crossing and the tip, so the legs still meet there.
	for i in [1, 2, 4, 5]:
		out_points[i] += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * settings.wiggle
		back_points[i] += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * settings.wiggle

	route.outbound = _smooth(out_points, settings.route_steps)
	route.inbound = _smooth(back_points, settings.route_steps)
	route.turnaround = Vector2(deepest, centre)
	return route


func get_leg(leg: Leg) -> PackedVector2Array:
	return outbound if leg == Leg.OUTBOUND else inbound


# The nearest point of either leg. On a tie, the outbound leg.
func get_hop(km: Vector2) -> Hop:
	var best := _nearest_on(outbound, km)
	best.leg = Leg.OUTBOUND
	var back := _nearest_on(inbound, km)
	back.leg = Leg.RETURN

	return back if back.distance < best.distance else best


func _nearest_on(line: PackedVector2Array, km: Vector2) -> Hop:
	var hop := Hop.new()
	hop.distance = INF

	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var point := Geometry2D.get_closest_point_to_segment(km, a, b)
		var distance := point.distance_to(km)

		if distance < hop.distance:
			hop.distance = distance
			hop.point = point
			hop.heading = (b - a).normalized()

	return hop


# Catmull-Rom through the points, `steps` points per stretch.
static func _smooth(points: Array[Vector2], steps: int) -> PackedVector2Array:
	var line := PackedVector2Array()
	var padded: Array[Vector2] = [points[0]]
	padded.append_array(points)
	padded.append(points[-1])

	for i in range(1, padded.size() - 2):
		var p0 := padded[i - 1]
		var p1 := padded[i]
		var p2 := padded[i + 1]
		var p3 := padded[i + 2]

		for step in steps:
			var t := float(step) / steps
			var t2 := t * t
			var t3 := t2 * t
			line.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))

	line.append(points[-1])
	return line
