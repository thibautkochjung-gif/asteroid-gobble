@tool
class_name HudHardpointButton
extends Control

# The big push-button of one hardpoint, sized to its socket in the panel art (76 x 60).
# Yellow when ready, brighter while firing, dark and refilling from the bottom during a cooldown.
# Ships with more than two hardpoints split the sockets: the buttons are then short (COMPACT_HEIGHT
# or less) and show the title and the key on one row.
# Hardpoints work in pairs: the buttons of the pairs that aren't active are drawn unlit (selected = false).

enum State { EMPTY, READY, FIRING, COOLDOWN, BROKEN }

const COMPACT_HEIGHT: float = 40.0

@export var state: State = State.READY:
	set(value):
		if state == value:
			return

		state = value
		queue_redraw()
@export_range(0.0, 1.0) var cooldown: float = 0.0: # 1 = just fired, 0 = ready again
	set(value):
		if cooldown == value:
			return

		cooldown = value
		queue_redraw()
@export var title: String = "DRILL":
	set(value):
		if title == value:
			return

		title = value
		queue_redraw()
@export var key_text: String = "LMB":
	set(value):
		if key_text == value:
			return

		key_text = value
		queue_redraw()

@export var selected: bool = true:
	set(value):
		if selected == value:
			return

		selected = value
		queue_redraw()
@export var pair_marker: bool = false: # Ships with several pairs: a lit strip under the active pair
	set(value):
		if pair_marker == value:
			return

		pair_marker = value
		queue_redraw()

@export_group("Text")
@export var title_font: Font
@export var key_font: Font
@export var title_size: int = 12
@export var key_size: int = 16


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var face := Rect2(3.0, 3.0, size.x - 6.0, size.y - 10.0)
	var base := Rect2(3.0, 6.0, size.x - 6.0, size.y - 8.0) # The button's side, showing under the face
	var face_color := CockpitPalette.YELLOW
	var base_color := CockpitPalette.YELLOW_DARK
	var text_color := CockpitPalette.INK_DARK
	var shadow := Color.TRANSPARENT
	var shine := 0.45
	var shown_title := title

	match state:
		State.FIRING:
			face_color = CockpitPalette.YELLOW_LIT
			draw_circle(face.get_center(), face.size.x * 0.65, Color(CockpitPalette.YELLOW_LIT, 0.12))
		State.COOLDOWN:
			face_color = CockpitPalette.BUTTON_DARK
			base_color = CockpitPalette.OUTLINE
			text_color = CockpitPalette.CREAM
			shadow = CockpitPalette.SHADOW
			shine = 0.12
		State.BROKEN:
			face_color = CockpitPalette.ALARM.darkened(0.55)
			base_color = CockpitPalette.OUTLINE
			text_color = CockpitPalette.CREAM
			shadow = CockpitPalette.SHADOW
			shine = 0.12
			shown_title = "BROKEN"
		State.EMPTY:
			face_color = CockpitPalette.LED_OFF
			base_color = CockpitPalette.OUTLINE
			text_color = CockpitPalette.TILE_OFF_TEXT
			shine = 0.06
			shown_title = "EMPTY"

	if not selected:
		# Unlit: the pair isn't active, LMB and RMB fire the other one
		face_color = face_color.lerp(CockpitPalette.OUTLINE, 0.6)
		base_color = base_color.lerp(CockpitPalette.OUTLINE, 0.6)
		text_color = text_color.lerp(CockpitPalette.CREAM, 0.35)
		text_color.a = 0.6
		shadow = Color.TRANSPARENT
		shine *= 0.3

	draw_rect(base, base_color)
	draw_rect(face, face_color)

	if state == State.COOLDOWN:
		var refill_height := face.size.y * (1.0 - cooldown)
		draw_rect(Rect2(face.position.x, face.end.y - refill_height, face.size.x, refill_height), CockpitPalette.PRIMER)

	draw_rect(Rect2(face.position + Vector2(4.0, 2.0), Vector2(face.size.x - 8.0, 3.0)), Color(1.0, 1.0, 1.0, shine))

	if pair_marker and selected:
		draw_rect(Rect2(base.position.x, base.end.y, base.size.x, 2.0), CockpitPalette.YELLOW_LIT)

	if size.y <= COMPACT_HEIGHT:
		# One row: the title on the left two thirds, the key on the right
		var split := face.size.x * 0.64
		var title_rect := Rect2(face.position.x + 2.0, face.position.y + 3.0, split - 2.0, face.size.y - 4.0)
		var key_rect := Rect2(face.position.x + split, face.position.y + 3.0, face.size.x - split - 2.0, face.size.y - 4.0)
		HudText.draw_centered(self, _font_or_default(title_font), shown_title, title_rect, title_size - 3, text_color, shadow)
		HudText.draw_centered(self, _font_or_default(key_font), key_text, key_rect, title_size - 2, text_color, shadow)
		return

	var title_rect := Rect2(face.position.x + 3.0, face.position.y + 8.0, face.size.x - 6.0, 16.0)
	var key_rect := Rect2(face.position.x + 3.0, face.position.y + 27.0, face.size.x - 6.0, 18.0)
	HudText.draw_centered(self, _font_or_default(title_font), shown_title, title_rect, title_size, text_color, shadow)
	HudText.draw_centered(self, _font_or_default(key_font), key_text, key_rect, key_size, text_color, shadow)


func _font_or_default(font: Font) -> Font:
	return font if font != null else get_theme_default_font()
