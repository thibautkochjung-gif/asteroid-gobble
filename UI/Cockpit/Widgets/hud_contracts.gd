class_name HudContracts
extends Control

# The guild contracts, under the speed readout: one line each, with how far the player has got.
# Field contracts light up green once done. Deliveries show the ore aboard against what's still owed.
# ContractTracker makes it, gives it the contracts and the ore aboard, and asks for redraws.

const LINE_HEIGHT: float = 17.0
const PADDING: float = 7.0
const WIDTH: float = 300.0
const TOP_LEFT := Vector2(16.0, 64.0) # Viewport px: under the speed and spin readout

@export var font_size: int = 13

var contracts: Array[Contract] = []
var aboard: Dictionary[int, float] = {} # Ore aboard, for deliveries


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = TOP_LEFT


func _process(_delta: float) -> void:
	queue_redraw() # Speed trials move every frame. The panel is a few lines: cheap


func _draw() -> void:
	if contracts.is_empty():
		return

	var font := get_theme_default_font()
	var height := PADDING * 2.0 + LINE_HEIGHT * (contracts.size() + 1)
	size = Vector2(WIDTH, height)
	draw_rect(Rect2(Vector2.ZERO, size), Color(CockpitPalette.SHADOW, 0.7))
	draw_rect(Rect2(0.0, 0.0, 3.0, height), CockpitPalette.YELLOW) # A strip of hazard tape
	var baseline := PADDING + LINE_HEIGHT - 4.0
	draw_string(font, Vector2(PADDING + 4.0, baseline), "GUILD CONTRACTS", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, CockpitPalette.YELLOW_LIT)

	for contract in contracts:
		baseline += LINE_HEIGHT
		var done := contract.is_done()
		var text := "%s  %s" % [contract.get_title().to_upper(), _get_status(contract)]
		var color := CockpitPalette.SCOPE if done else CockpitPalette.CREAM
		draw_string(font, Vector2(PADDING + 4.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PADDING * 2.0, font_size, color)


func _get_status(contract: Contract) -> String:
	if contract.is_delivery():
		var owed := contract.target - contract.progress
		var held: float = aboard.get(contract.ore_id, 0.0)
		var ore_name := CellMaterials.get_material(contract.ore_id).display_name.to_lower()
		return "%d/%d u %s aboard" % [floori(held), roundi(owed), ore_name]

	if contract.is_done():
		return "DONE · " + contract.get_progress_text()

	return contract.get_progress_text()
