@tool
class_name HudHardpointButton
extends Control

# The big push-button of one hardpoint, sized to its socket in the panel art (76 x 60).
# Yellow when ready, brighter while firing, dark and refilling from the bottom during a cooldown.

enum State { EMPTY, READY, FIRING, COOLDOWN, BROKEN }

const FACE := Rect2(3.0, 3.0, 70.0, 50.0)
const BASE := Rect2(3.0, 6.0, 70.0, 52.0) # The button's side, showing under the face

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

@export_group("Text")
@export var title_font: Font
@export var key_font: Font
@export var title_size: int = 12
@export var key_size: int = 16


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var face_color := CockpitPalette.YELLOW
	var base_color := CockpitPalette.YELLOW_DARK
	var text_color := CockpitPalette.INK_DARK
	var shadow := Color.TRANSPARENT
	var shine := 0.45
	var shown_title := title

	match state:
		State.FIRING:
			face_color = CockpitPalette.YELLOW_LIT
			draw_circle(FACE.get_center(), 46.0, Color(CockpitPalette.YELLOW_LIT, 0.12))
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

	draw_rect(BASE, base_color)
	draw_rect(FACE, face_color)

	if state == State.COOLDOWN:
		var refill_height := FACE.size.y * (1.0 - cooldown)
		draw_rect(Rect2(FACE.position.x, FACE.end.y - refill_height, FACE.size.x, refill_height), CockpitPalette.PRIMER)

	draw_rect(Rect2(FACE.position + Vector2(4.0, 2.0), Vector2(FACE.size.x - 8.0, 3.0)), Color(1.0, 1.0, 1.0, shine))

	var title_rect := Rect2(FACE.position.x + 3.0, FACE.position.y + 8.0, FACE.size.x - 6.0, 16.0)
	var key_rect := Rect2(FACE.position.x + 3.0, FACE.position.y + 27.0, FACE.size.x - 6.0, 18.0)
	HudText.draw_centered(self, _font_or_default(title_font), shown_title, title_rect, title_size, text_color, shadow)
	HudText.draw_centered(self, _font_or_default(key_font), key_text, key_rect, key_size, text_color, shadow)


func _font_or_default(font: Font) -> Font:
	return font if font != null else get_theme_default_font()
