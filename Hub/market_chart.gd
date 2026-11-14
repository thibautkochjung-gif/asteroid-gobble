class_name MarketChart
extends Control

# The exchange's price curve for one ore: one point per run, today's on the right. Hovering the
# curve shows the price at that run.

const PAD_LEFT: float = 52.0
const PAD_RIGHT: float = 12.0
const PAD_TOP: float = 12.0
const PAD_BOTTOM: float = 22.0
const FONT_SIZE: int = 12
const BACKGROUND := Color(0.08, 0.09, 0.07)

var _prices: Array[float] = []
var _hover: int = -1 # Index of the hovered point, -1 for none


func _init() -> void:
	custom_minimum_size = Vector2(0, 170)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_prices(prices: Array[float]) -> void:
	_prices = prices
	_hover = -1
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion

	if motion == null or _prices.size() < 2:
		return

	var plot := _get_plot_rect()
	var ratio := clampf((motion.position.x - plot.position.x) / plot.size.x, 0.0, 1.0)
	var index := roundi(ratio * (_prices.size() - 1))

	if index != _hover:
		_hover = index
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	draw_rect(Rect2(Vector2.ZERO, size), CockpitPalette.OUTLINE, false, 2.0)

	if _prices.size() < 2:
		return

	var plot := _get_plot_rect()
	var font := get_theme_default_font()
	var low: float = _prices[0]
	var high: float = _prices[0]

	for price in _prices:
		low = minf(low, price)
		high = maxf(high, price)

	var margin := (high - low) * 0.12 + high * 0.02
	low = maxf(0.0, low - margin)
	high += margin

	# Scale: lowest and highest price on the left
	for value in [low, high]:
		var y := _get_y(value, low, high, plot)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(HubStyle.DIM, 0.25), 1.0)
		draw_string(font, Vector2(4, y + 4), "%.1f" % value, HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 10, FONT_SIZE, HubStyle.DIM)

	var points := PackedVector2Array()

	for i in _prices.size():
		points.append(_get_point(i, low, high, plot))

	draw_polyline(points, HubStyle.ACCENT, 2.0, true)
	draw_circle(points[-1], 3.5, HubStyle.ACCENT)

	var bottom := size.y - 6
	draw_string(font, Vector2(plot.position.x, bottom), "%d runs ago" % (_prices.size() - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HubStyle.DIM)
	draw_string(font, Vector2(plot.end.x - 60, bottom), "now", HORIZONTAL_ALIGNMENT_RIGHT, 60, FONT_SIZE, HubStyle.DIM)

	if _hover >= 0:
		_draw_hover(points[_hover], plot, font)


func _draw_hover(point: Vector2, plot: Rect2, font: Font) -> void:
	draw_line(Vector2(point.x, plot.position.y), Vector2(point.x, plot.end.y), Color(HubStyle.TEXT, 0.4), 1.0)
	draw_circle(point, 4.0, HubStyle.TEXT)

	var runs_ago := _prices.size() - 1 - _hover
	var when := "now" if runs_ago == 0 else "%d run%s ago" % [runs_ago, "" if runs_ago == 1 else "s"]
	var text := "%.1f cr/u, %s" % [_prices[_hover], when]
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var box := Rect2(point + Vector2(8, -text_size.y - 10), text_size + Vector2(8, 6))

	# Keep the label inside the chart
	if box.end.x > size.x - 2:
		box.position.x = point.x - 8 - box.size.x

	box.position.y = clampf(box.position.y, 2, size.y - box.size.y - 2)
	draw_rect(box, Color(BACKGROUND, 0.92))
	draw_rect(box, HubStyle.DIM, false, 1.0)
	draw_string(font, box.position + Vector2(4, text_size.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HubStyle.TEXT)


func _get_plot_rect() -> Rect2:
	return Rect2(PAD_LEFT, PAD_TOP, size.x - PAD_LEFT - PAD_RIGHT, size.y - PAD_TOP - PAD_BOTTOM)


func _get_y(value: float, low: float, high: float, plot: Rect2) -> float:
	return plot.end.y - (value - low) / (high - low) * plot.size.y


func _get_point(index: int, low: float, high: float, plot: Rect2) -> Vector2:
	var x := plot.position.x + plot.size.x * index / (_prices.size() - 1)
	return Vector2(x, _get_y(_prices[index], low, high, plot))
