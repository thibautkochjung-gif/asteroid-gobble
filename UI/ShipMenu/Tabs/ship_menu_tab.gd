class_name ShipMenuTab
extends HBoxContainer

# Base for the ship menu's tabs. A tab builds its content from scratch in refresh(): the game is
# paused while the menu is open, so a tab only changes when the menu opens, when the tab is picked,
# or after the player does something in it.

var menu: ShipMenu


func _init() -> void:
	add_theme_constant_override("separation", 18)
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func get_title() -> String:
	return ""


func refresh() -> void:
	pass


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


# A column of cards: a fixed width, or 0 to take the space left.
func add_column(width: float = 0.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)

	if width > 0.0:
		column.custom_minimum_size.x = width
	else:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	add_child(column)
	return column


func add_card(parent: Control) -> VectorCard:
	var card := VectorCard.new()
	parent.add_child(card)
	return card


# Label on the left, value on the right.
func make_line(text: String, value: String, value_color: Color = VectorStyle.TEXT) -> HBoxContainer:
	return VectorStyle.make_row(VectorStyle.make_label(text, &"VectorSmall"), VectorStyle.make_label(value, &"VectorValue", value_color))
