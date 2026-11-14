class_name MarketPanel
extends HubPanel

# Commodities exchange: one row per ore, with today's price, how it moved since the last run, what
# the station holds for the player, and a button to sell it all. Selling pushes the price down as
# it goes (see Market.get_sale_quote): the button shows what the sale would pay.
# Picking an ore shows its price curve, on the right. The panel is wide, so the hub centres it. Rumours of surges and slumps are listed at the bottom:
# they never say how far or how long.

const PANEL_WIDTH_WIDE: float = 940.0

var _rows: Dictionary[int, Dictionary] = {} # Ore id -> { pick, price, trend, held, sell }
var _selected_ore: int = CellMaterials.ORES[0]
var _chart_title: Label
var _chart: MarketChart
var _news_list: VBoxContainer
var _total_label: Label
var _sell_all: Button


func _init() -> void:
	super("COMMODITIES EXCHANGE")
	custom_minimum_size = Vector2(PANEL_WIDTH_WIDE, 0.0)
	size = custom_minimum_size


func _build() -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 24)
	body.add_child(columns)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 6)
	columns.add_child(grid)

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Centred against the ore table
	side.add_theme_constant_override(&"separation", 6)
	columns.add_child(side)

	for heading in ["ORE", "PRICE", "LAST RUN", "HELD", ""]:
		grid.add_child(HubStyle.label(heading, 13, HubStyle.DIM))

	var group := ButtonGroup.new()

	for ore_id in CellMaterials.ORES:
		var row := {
			"pick": HubStyle.choice(CellMaterials.get_material(ore_id).display_name, group),
			"price": HubStyle.label("", 16),
			"trend": HubStyle.label("", 16),
			"held": HubStyle.label("", 16),
			"sell": HubStyle.button("", 14),
		}
		row.pick.custom_minimum_size = Vector2(130, 32)
		row.pick.tooltip_text = "Show the price curve"
		row.pick.button_pressed = ore_id == _selected_ore
		row.pick.pressed.connect(_on_pick.bind(ore_id))
		grid.add_child(row.pick)
		grid.add_child(row.price)
		grid.add_child(row.trend)
		grid.add_child(row.held)
		grid.add_child(row.sell)
		row.sell.custom_minimum_size = Vector2(120, 32)
		row.sell.pressed.connect(_on_sell.bind(ore_id))
		_rows[ore_id] = row

	_chart_title = HubStyle.label("", 14, HubStyle.ACCENT)
	side.add_child(_chart_title)

	_chart = MarketChart.new()
	side.add_child(_chart)

	body.add_child(HubStyle.label("HEARD AT THE EXCHANGE", 13, HubStyle.DIM))
	_news_list = VBoxContainer.new()
	_news_list.add_theme_constant_override(&"separation", 2)
	body.add_child(_news_list)

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
		var price := GameState.get_price(ore_id)
		var previous := GameState.get_previous_price(ore_id)
		var change := roundi((price / previous - 1.0) * 100.0) if previous > 0.0 else 0
		var held := GameState.get_stored(ore_id)
		row.price.text = "%.1f cr/u" % price
		row.trend.text = "%+d%%" % change if change != 0 else "—"
		row.trend.add_theme_color_override(&"font_color", HubStyle.BAD if change < 0 else HubStyle.GOOD if change > 0 else HubStyle.DIM)
		row.held.text = "%d u" % floori(held)
		row.sell.disabled = held < 1.0
		row.sell.text = "SELL %s" % HubStyle.format_credits(GameState.get_sale_quote(ore_id, held).revenue) if held >= 1.0 else "—"

	_refresh_chart()
	_refresh_news()

	var total := GameState.get_storage_value()
	_total_label.text = "Held at the station: worth %s at today's prices. Wallet: %s" % [HubStyle.format_credits(total), HubStyle.format_credits(GameState.credits)]
	_sell_all.disabled = total <= 0


func _refresh_chart() -> void:
	var prices := GameState.get_price_history(_selected_ore)
	var ore_name := CellMaterials.get_material(_selected_ore).display_name.to_upper()
	_chart_title.text = "%s, LAST %d RUNS" % [ore_name, maxi(prices.size() - 1, 0)]
	_chart.set_prices(prices)


func _refresh_news() -> void:
	for child in _news_list.get_children():
		child.queue_free()

	if GameState.market.news.is_empty():
		_news_list.add_child(HubStyle.label("Nothing worth repeating.", 14, HubStyle.DIM))
		return

	for item in GameState.market.news:
		var line := HubStyle.label("Run %d: %s" % [item.run, item.text], 14)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_news_list.add_child(line)


func _on_pick(ore_id: int) -> void:
	_selected_ore = ore_id
	_refresh_chart()


func _on_sell(ore_id: int) -> void:
	GameState.sell(ore_id, GameState.get_stored(ore_id))


func _on_sell_all() -> void:
	GameState.sell_all()
