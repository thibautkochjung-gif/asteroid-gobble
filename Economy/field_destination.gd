class_name FieldDestination
extends Resource

# A mining field the mothership can drop the player in. Farther fields cost more to reach, need a
# better mining licence, and hold more and better rock (hazards come later).
# For now every field uses the same belt profile: each one gets its own profile once the regions are
# tuned (see AsteroidFieldProfile).

@export var display_name: String = "Near scatter"
@export_multiline var description: String = ""
@export var ores_hint: String = "" # Shown on the undock screen, e.g. "Water ice, nickel-iron"
@export var licence_tier: int = 1
@export var drop_fee: int = 250 # Credits. The pickup call costs drop_fee × EconomyConfig.pickup_fee_multiplier
@export var profile: AsteroidFieldProfile
@export var world_seed: int = 1 # Each run adds the run count, so the rocks change between runs
