class_name InsurancePlan
extends Resource

# Cover for one run. The premium is a share of the insured value, paid when undocking. If the ship
# is lost, the payout is a share of the same value. Cargo is never covered.

@export var display_name: String = "None"
@export_multiline var description: String = ""
@export_range(0.0, 1.0) var premium_ratio: float = 0.0
@export_range(0.0, 1.0) var payout_ratio: float = 0.0
@export var covers_modules: bool = false # false: the hull only
