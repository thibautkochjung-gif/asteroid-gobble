class_name VectorStyle
extends RefCounted

# The ship menu's look, "Vector": an old vector display. Black, cyan lines, corner brackets,
# segmented bars, one hot colour for warnings. The menu belongs to the captain, not to a hull,
# so it looks the same on every ship (the cockpit HUD is the one that changes).
# get_theme() builds the Theme once, in code: the palette and the fonts live here, in one place.
# The make_...() helpers build the small pieces every tab uses.

const ACCENT := Color("46e6ff")
const TEXT := Color("c8f6ff")
const DIM := Color("6fb3c0")
const LINE := Color("1c5560")
const FRAME := Color("1f6f7c")
const BACKGROUND := Color(0.008, 0.035, 0.03, 0.97)
const TRACK := Color("06191c")
const WARN := Color("ffb347")
const BAD := Color("ff5c7a")
const ON_ACCENT := Color("021012")

const HEADING_FONT_PATH := "res://UI/Fonts/tektur_medium.ttf"
const BODY_FONT_PATH := "res://UI/Fonts/ibm_plex_mono_regular.ttf"
const BOLD_FONT_PATH := "res://UI/Fonts/ibm_plex_mono_bold.ttf"

const BODY_SIZE: int = 14
const SMALL_SIZE: int = 12
const HEADING_SIZE: int = 14
const TITLE_SIZE: int = 22

static var _theme: Theme
static var _swatches: Dictionary[Color, ImageTexture] = {}


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()

	return _theme


# Cyan when fine, amber when worn, red under the 20 % where parts stop working (PartHealth).
static func get_health_color(ratio: float) -> Color:
	if ratio >= 0.6:
		return ACCENT

	if ratio >= 0.2:
		return WARN

	return BAD


# "4 200 cr", negative amounts with a minus sign.
static func format_credits(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""

	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += " "

		grouped += digits[i]

	return "%s%s cr" % ["-" if amount < 0 else "", grouped]


# --- Pieces


static func make_label(text: String, variation: StringName = &"", color: Variant = null) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation

	if color != null:
		label.add_theme_color_override("font_color", color)

	return label


static func make_heading(text: String) -> Label:
	var label := make_label(text, &"VectorHeading")
	label.uppercase = true
	return label


# Heading, optional info icon, and an optional control pushed to the right.
static func make_heading_row(text: String, tip: String = "", right: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(make_heading(text))

	if not tip.is_empty():
		row.add_child(VectorInfo.new(tip))

	if right != null:
		row.add_child(make_spacer())
		row.add_child(right)

	return row


static func make_row(left: Control, right: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(left)
	row.add_child(make_spacer())
	row.add_child(right)
	return row


static func make_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


static func make_key(text: String) -> Label:
	return make_label(text, &"VectorKey")


static func make_lamp(color: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var light := ColorRect.new()
	light.color = color
	light.custom_minimum_size = Vector2(9.0, 9.0)
	light.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(light)
	var label := make_label(text, &"VectorValue")
	label.uppercase = true
	row.add_child(label)
	return row


static func make_bar(ratio: float, color: Color = ACCENT, height: float = 10.0) -> VectorBar:
	var bar := VectorBar.new()
	bar.ratio = ratio
	bar.color = color
	bar.custom_minimum_size.y = height
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


# A small square of the material's colour, for buttons and tables.
static func get_swatch(color: Color) -> ImageTexture:
	if not _swatches.has(color):
		var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		image.fill(ON_ACCENT)
		image.fill_rect(Rect2i(1, 1, 10, 10), color)
		_swatches[color] = ImageTexture.create_from_image(image)

	return _swatches[color]


static func make_swatch(color: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = get_swatch(color)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.custom_minimum_size = Vector2(14.0, 14.0)
	return rect


static func make_tooltip_box() -> StyleBoxFlat:
	return _box(ON_ACCENT, ACCENT, 1, 10.0, 7.0)


# --- Theme


static func _build_theme() -> Theme:
	var theme := Theme.new()
	var body: Font = load(BODY_FONT_PATH)
	var bold: Font = load(BOLD_FONT_PATH)
	var heading: Font = load(HEADING_FONT_PATH)
	theme.default_font = body
	theme.default_font_size = BODY_SIZE

	theme.set_color(&"font_color", &"Label", TEXT)
	_add_label(theme, &"VectorHeading", heading, HEADING_SIZE, DIM)
	_add_label(theme, &"VectorTitle", heading, TITLE_SIZE, ACCENT)
	_add_label(theme, &"VectorSmall", body, SMALL_SIZE, DIM)
	_add_label(theme, &"VectorValue", bold, BODY_SIZE, TEXT)
	_add_label(theme, &"VectorKey", bold, SMALL_SIZE, TEXT)
	theme.set_stylebox(&"normal", &"VectorKey", _box(Color.TRANSPARENT, DIM, 1, 5.0, 0.0))
	_add_label(theme, &"VectorTag", bold, 11, DIM)
	theme.set_stylebox(&"normal", &"VectorTag", _box(Color.TRANSPARENT, LINE, 1, 6.0, 1.0))

	# Buttons: thin outline, cyan on hover.
	_set_button_boxes(theme, &"Button", _box(Color.TRANSPARENT, LINE), _box(Color(ACCENT, 0.08), ACCENT), _box(Color(ACCENT, 0.18), ACCENT))
	theme.set_stylebox(&"disabled", &"Button", _box(Color.TRANSPARENT, Color(LINE, 0.5)))
	_set_button_colors(theme, &"Button", TEXT, ACCENT)

	# Tabs: underlined when picked.
	theme.set_type_variation(&"VectorTab", &"Button")
	var tab_normal := _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 12.0, 6.0)
	tab_normal.border_width_bottom = 2
	var tab_hover := tab_normal.duplicate() as StyleBoxFlat
	tab_hover.border_color = LINE
	var tab_on := tab_normal.duplicate() as StyleBoxFlat
	tab_on.bg_color = Color(ACCENT, 0.08)
	tab_on.border_color = ACCENT
	_set_button_boxes(theme, &"VectorTab", tab_normal, tab_hover, tab_on)
	_set_button_colors(theme, &"VectorTab", DIM, ACCENT)
	theme.set_font(&"font", &"VectorTab", heading)
	theme.set_font_size(&"font_size", &"VectorTab", 15)

	# List items (module list): a bar on the left when picked.
	theme.set_type_variation(&"VectorListItem", &"Button")
	var item_normal := _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 10.0, 6.0)
	item_normal.border_width_left = 3
	item_normal.border_color = LINE
	var item_hover := item_normal.duplicate() as StyleBoxFlat
	item_hover.bg_color = Color(ACCENT, 0.05)
	var item_on := item_normal.duplicate() as StyleBoxFlat
	item_on.bg_color = Color(ACCENT, 0.1)
	item_on.border_color = ACCENT
	_set_button_boxes(theme, &"VectorListItem", item_normal, item_hover, item_on)
	_set_button_colors(theme, &"VectorListItem", TEXT, ACCENT)
	theme.set_constant(&"h_separation", &"VectorListItem", 10)

	# Chips (material filters): dim when off, cyan when on.
	theme.set_type_variation(&"VectorChip", &"Button")
	_set_button_boxes(theme, &"VectorChip", _box(Color.TRANSPARENT, LINE, 1, 10.0, 6.0), _box(Color(ACCENT, 0.05), DIM, 1, 10.0, 6.0), _box(Color(ACCENT, 0.12), ACCENT, 1, 10.0, 6.0))
	_set_button_colors(theme, &"VectorChip", DIM, ACCENT)
	theme.set_color(&"font_hover_color", &"VectorChip", TEXT)
	theme.set_constant(&"h_separation", &"VectorChip", 8)

	# Danger (dump): red outline.
	theme.set_type_variation(&"VectorDanger", &"Button")
	_set_button_boxes(theme, &"VectorDanger", _box(Color.TRANSPARENT, Color(BAD, 0.5), 1, 8.0, 2.0), _box(Color(BAD, 0.1), BAD, 1, 8.0, 2.0), _box(Color(BAD, 0.25), BAD, 1, 8.0, 2.0))
	_set_button_colors(theme, &"VectorDanger", BAD, BAD)
	theme.set_font(&"font", &"VectorDanger", bold)
	theme.set_font_size(&"font_size", &"VectorDanger", SMALL_SIZE)

	# The big call button.
	theme.set_type_variation(&"VectorBig", &"Button")
	_set_button_boxes(theme, &"VectorBig", _box(Color(ACCENT, 0.08), ACCENT, 2, 16.0, 12.0), _box(Color(ACCENT, 0.2), ACCENT, 2, 16.0, 12.0), _box(Color(ACCENT, 0.35), ACCENT, 2, 16.0, 12.0))
	theme.set_stylebox(&"disabled", &"VectorBig", _box(Color.TRANSPARENT, LINE, 2, 16.0, 12.0))
	_set_button_colors(theme, &"VectorBig", ACCENT, TEXT)
	theme.set_font(&"font", &"VectorBig", heading)
	theme.set_font_size(&"font_size", &"VectorBig", 20)

	# Info icons: a small ring with an "i".
	theme.set_type_variation(&"VectorInfo", &"Button")
	var ring := _box(Color.TRANSPARENT, DIM, 1, 0.0, 0.0)
	ring.set_corner_radius_all(9)
	var ring_hover := ring.duplicate() as StyleBoxFlat
	ring_hover.border_color = ACCENT
	_set_button_boxes(theme, &"VectorInfo", ring, ring_hover, ring_hover)
	_set_button_colors(theme, &"VectorInfo", DIM, ACCENT)
	theme.set_font(&"font", &"VectorInfo", bold)
	theme.set_font_size(&"font_size", &"VectorInfo", 11)

	# Panels: cards are outlines; the frame is the dark screen.
	theme.set_stylebox(&"panel", &"PanelContainer", _box(Color.TRANSPARENT, LINE, 1, 14.0, 12.0))
	theme.set_type_variation(&"VectorFrame", &"PanelContainer")
	theme.set_stylebox(&"panel", &"VectorFrame", _box(BACKGROUND, FRAME, 1, 22.0, 16.0))

	var separator := StyleBoxLine.new()
	separator.color = LINE
	theme.set_stylebox(&"separator", &"HSeparator", separator)

	# Thin scroll bars.
	var track := _box(TRACK, Color.TRANSPARENT, 0, 3.0, 0.0)
	var grabber := _box(Color(ACCENT, 0.4), Color.TRANSPARENT, 0, 3.0, 0.0)
	var grabber_on := _box(ACCENT, Color.TRANSPARENT, 0, 3.0, 0.0)
	theme.set_stylebox(&"scroll", &"VScrollBar", track)
	theme.set_stylebox(&"grabber", &"VScrollBar", grabber)
	theme.set_stylebox(&"grabber_highlight", &"VScrollBar", grabber_on)
	theme.set_stylebox(&"grabber_pressed", &"VScrollBar", grabber_on)
	return theme


static func _add_label(theme: Theme, variation: StringName, font: Font, font_size: int, color: Color) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font(&"font", variation, font)
	theme.set_font_size(&"font_size", variation, font_size)
	theme.set_color(&"font_color", variation, color)


static func _set_button_boxes(theme: Theme, type: StringName, normal: StyleBox, hover: StyleBox, pressed: StyleBox) -> void:
	theme.set_stylebox(&"normal", type, normal)
	theme.set_stylebox(&"hover", type, hover)
	theme.set_stylebox(&"pressed", type, pressed)
	theme.set_stylebox(&"hover_pressed", type, pressed)
	theme.set_stylebox(&"focus", type, StyleBoxEmpty.new())


static func _set_button_colors(theme: Theme, type: StringName, normal: Color, active: Color) -> void:
	theme.set_color(&"font_color", type, normal)
	theme.set_color(&"font_focus_color", type, normal)
	theme.set_color(&"font_hover_color", type, active)
	theme.set_color(&"font_pressed_color", type, active)
	theme.set_color(&"font_hover_pressed_color", type, active)
	theme.set_color(&"font_disabled_color", type, Color(DIM, 0.45))


static func _box(background: Color, border: Color, border_width: int = 1, margin_x: float = 10.0, margin_y: float = 5.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box
