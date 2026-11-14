class_name CockpitPalette
extends RefCounted

# The cockpit's colours. Taken from the ship's own drawing code (ship_hull.gd, hangar.gd)
# so the HUD reads as part of the same machine. Change them here, not in the widgets.

const OUTLINE := Color(0.06, 0.055, 0.07)
const YELLOW := Color(0.83, 0.64, 0.16) # Hazard stripe yellow
const YELLOW_LIT := Color(0.96, 0.8, 0.36)
const YELLOW_DARK := Color(0.47, 0.35, 0.06)
const PRIMER := Color(0.67, 0.36, 0.18)
const RUST := Color(0.46, 0.24, 0.15)
const CREAM := Color(0.91, 0.87, 0.78)
const STEEL := Color(0.54, 0.5, 0.45)
const STEEL_DARK := Color(0.23, 0.22, 0.2)
const INK_DARK := Color(0.23, 0.16, 0.03) # Text printed on yellow
const ALARM := Color(0.89, 0.33, 0.11)
const READY := Color(0.2, 0.39, 0.48) # The cabin glass' dark blue: "armed, not in use"
const LED_OFF := Color(0.16, 0.15, 0.14)
const TILE_OFF := Color(0.15, 0.14, 0.13)
const TILE_OFF_TEXT := Color(0.36, 0.34, 0.31)
const BUTTON_DARK := Color(0.27, 0.21, 0.11)
const SCOPE := Color(0.62, 0.84, 0.48)
const SCOPE_GRID := Color(0.12, 0.23, 0.09)
const MARKER_INK := Color(0.12, 0.16, 0.35) # Felt pen on masking tape
const SHADOW := Color(0.0, 0.0, 0.0, 0.85)
