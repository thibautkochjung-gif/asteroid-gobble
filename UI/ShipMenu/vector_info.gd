class_name VectorInfo
extends Button

# The small "i" next to a heading. Hovering it shows its text in a box under it.
# Not Godot's own tooltip: that one opens in a window of its own, outside the menu's theme.
# The box is top_level, so the menu's containers don't lay it out, and drawn over the rest.

const TIP_WIDTH: float = 280.0
const TIP_OFFSET := Vector2(-10.0, 6.0) # From the icon's bottom-left corner

var tip_text: String = ""

var _tip: PanelContainer


func _init(tip: String = "") -> void:
	tip_text = tip
	theme_type_variation = &"VectorInfo"
	text = "i"
	custom_minimum_size = Vector2(18.0, 18.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_HELP


func _ready() -> void:
	mouse_entered.connect(_show_tip)
	mouse_exited.connect(_hide_tip)


func _exit_tree() -> void:
	_hide_tip()


func _show_tip() -> void:
	if tip_text.is_empty() or _tip != null:
		return

	_tip = PanelContainer.new()
	_tip.top_level = true
	_tip.z_as_relative = false
	_tip.z_index = 100
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_stylebox_override("panel", VectorStyle.make_tooltip_box())

	var label := Label.new()
	label.text = tip_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TIP_WIDTH
	label.add_theme_font_size_override("font_size", 13)
	_tip.add_child(label)
	add_child(_tip)
	_place_tip.call_deferred() # Its size is known once it has been laid out


# Under the icon, kept inside the screen.
func _place_tip() -> void:
	if _tip == null:
		return

	var screen := get_viewport_rect().size
	var at := global_position + Vector2(0.0, size.y) + TIP_OFFSET
	at.x = clampf(at.x, 8.0, screen.x - _tip.size.x - 8.0)

	if at.y + _tip.size.y > screen.y - 8.0:
		at.y = global_position.y - _tip.size.y - TIP_OFFSET.y

	_tip.global_position = at


func _hide_tip() -> void:
	if _tip != null:
		_tip.queue_free()
		_tip = null
