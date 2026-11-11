class_name ComputerModule
extends Resource

# A ship computer model: what the flight computer (ShipComputer) can do, and how it flies.
# Every ship carries one. basic_computer.tres is the starter; better computers are other
# .tres files of this type with more abilities switched on or sharper tuning.

@export var display_name: String = "Basic computer"

@export_group("Abilities")
@export var can_kill_momentum: bool = true # X: speed and spin to zero
@export var can_read_rocks: bool = true # Mouse over a rock: its speed relative to the ship
@export var can_match_velocity: bool = true # F on a hovered rock: the ship takes the rock's speed (not its spin)
@export var can_settle: bool = true # Speed or spin almost zero: brought to zero automatically

@export_group("Tuning")
@export var response_time: float = 0.35 # s. Asks to close the gap in about this time. Shorter = harder burns near the goal
@export var settle_speed: float = 8.0 # px/s. Slower drift gets stopped automatically
@export var settle_spin: float = 0.1 # rad/s (about 6°/s). Same, for spin
@export var done_speed: float = 0.3 # px/s. Below this, the speed counts as reached
@export var done_spin: float = 0.004 # rad/s (about 0.2°/s)
@export var hover_radius: float = 14.0 # Screen px around the mouse in which a rock counts as hovered
