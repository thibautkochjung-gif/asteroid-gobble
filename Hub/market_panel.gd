class_name MarketPanel
extends HubPanel

# Commodities exchange: one row per ore, with today's price, how far it is from the base price,
# what the station holds for the player, and a button to sell it all. Selling pushes the price
# down as it goes (see GameState.get_sale_quote): the button shows what the sale would pay.

var _rows: Dictionary[int, Dictionary] = {} # Ore id -> { price, trend, held, sell }
var _total_label: Label
var _sell_all: Button


func _init() -> void:
	super("COMMODITIES EXCHANGE")


func _build() -> void:
	var note := HubStyle.label("Prices freeze while you're out, and recover a little after each run.", 14, HubStyle.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 6)
	body.add_child(grid)

	for heading in ["ORE", "PRICE", "VS BASE", "HELD", ""]:
		grid.add_child(HubStyle.label(heading, 13, HubStyle.DIM))

	for ore_id in CellMaterials.ORES:
		var row := {
			"price": HubStyle.label("", 16),
			"trend": HubStyle.label("", 16),
			"held": HubStyle.label("", 16),
			"sell": HubStyle.button("", 14),
		}
		grid.add_child(HubStyle.label(CellMaterials.get_material(ore_id).display_name, 16))
		grid.add_child(row.price)
		grid.add_child(row.trend)
		grid.add_child(row.held)
		grid.add_child(row.sell)
		row.sell.custom_minimum_size = Vector2(120, 32)
		row.sell.pressed.connect(_on_sell.bind(ore_id))
		_rows[ore_id] = row

	_total_label = HubStyle.label("", 16)
	_total_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_total_label)

	_sell_all = HubStyle.button("SELL EVERYTHING", 18)
	_sell_all.pressed.connect(_on_sell_all)
	body.add_child(_sell_all)

	GameState.storage_changed.connect(refresh)
	GameState.prices_changed.connect(refresh)


func refresh() -> void:
	for ore_id in _rows:
		var row: Dictionary = _rows[ore_id]
		var factor := GameState.get_price_factor(ore_id)
		var held := GameState.get_stored(ore_id)
		var change := roundi((factor - 1.0) * 100.0)
		row.price.text = "%.1f cr/u" % GameState.get_price(ore_id)
		row.trend.text = "%+d%%" % change if change != 0 else "—"
		row.trend.add_theme_color_override(&"font_color", HubStyle.BAD if change < 0 else HubStyle.GOOD if change > 0 else HubStyle.DIM)
		row.held.text = "%d u" % floori(held)
		row.sell.disabled = held < 1.0
		row.sell.text = "SELL %s" % HubStyle.format_credits(GameState.get_sale_quote(ore_id, held).revenue) if held >= 1.0 else "—"

	var total := GameState.get_storage_value()
	_total_label.text = "Held at the station: worth %s at today's prices. Wallet: %s" % [HubStyle.format_credits(total), HubStyle.format_credits(GameState.credits)]
	_sell_all.disabled = total <= 0


func _on_sell(ore_id: int) -> void:
	GameState.sell(ore_id, GameState.get_stored(ore_id))


func _on_sell_all() -> void:
	GameState.sell_all()
