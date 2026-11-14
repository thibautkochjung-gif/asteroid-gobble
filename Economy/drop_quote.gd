class_name DropQuote
extends RefCounted

# What a drop point costs, and how the player gets there: the mothership carries them along its
# route to the nearest point (the hop), then a transfer takes them to the drop point.
#   drop fee = line fare (exponential in depth) × transfer multiplier (1 + transfer_per_km × km off the line)
# The nearest leg is always the cheaper one: the fare only depends on the drop point's depth.

var point := Vector2.ZERO # km in the belt
var depth: float = 0.0 # km
var hop: BeltRoute.Hop
var fare: float = 0.0 # Credits, before the transfer
var multiplier: float = 1.0
var fee: int = 0 # Credits, all in


static func create(route: BeltRoute, km: Vector2) -> DropQuote:
	var quote := DropQuote.new()
	quote.point = km
	quote.depth = maxf(km.x, 0.0)
	quote.hop = route.get_hop(km)
	quote.fare = get_fare(quote.depth)
	quote.multiplier = get_multiplier(quote.hop.distance)
	quote.fee = roundi(quote.fare * quote.multiplier)
	return quote


# The line fare at this depth: drop_fare_top at 0 km, drop_fare_bottom at the belt's far edge.
static func get_fare(depth: float) -> float:
	var economy := GameState.ECONOMY
	var ratio := clampf(depth / economy.belt.depth_km, 0.0, 1.0)
	return economy.drop_fare_top * pow(economy.drop_fare_bottom / economy.drop_fare_top, ratio)


static func get_multiplier(distance: float) -> float:
	return 1.0 + GameState.ECONOMY.transfer_per_km * distance


func get_leg_text() -> String:
	return "outbound, heading deeper" if hop.leg == BeltRoute.Leg.OUTBOUND else "return leg, heading home"
