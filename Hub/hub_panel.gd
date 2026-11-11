class_name HubPanel
extends PanelContainer

# Base for the station's screens: a plate with a hazard stripe, a title, a close button and a body.
# Subclasses fill `body` in _build() and update it in refresh().

signal closed

const PANEL_WIDTH: float = 440.0

var body: VBoxContainer

var _title_label: Label


func _init(title: String) -> void:
	add_theme_stylebox_override(&"panel", HubStyle.box(HubStyle.PANEL_BG, CockpitPalette.OUTLINE, 4, 0))
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	size = Vector2(PANEL_WIDTH, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	add_child(column)

	var stripe := ColorRect.new()
	stripe.color = CockpitPalette.YELLOW
	stripe.custom_minimum_size = Vector2(0, 8)
	column.add_child(stripe)

	var margin := MarginContainer.new()

	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 16)

	column.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 10)
	margin.add_child(inner)

	var header := HBoxContainer.new()
	inner.add_child(header)

	_title_label = HubStyle.label(title, 26, HubStyle.ACCENT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close := HubStyle.button("X", 16)
	close.custom_minimum_size = Vector2(40, 40)
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(close_panel)
	header.add_child(close)

	body = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	inner.add_child(body)


func _ready() -> void:
	_build()
	refresh()


func set_title(title: String) -> void:
	_title_label.text = title


func close_panel() -> void:
	closed.emit()
	queue_free()


func _build() -> void:
	pass


func refresh() -> void:
	pass
