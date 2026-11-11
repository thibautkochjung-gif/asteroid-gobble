class_name NetPrompt
extends Control

# Key prompts over the net launcher's bundles, in screen space:
# - over the bundle on the winch, while it can go in tow: PRESS [T] TO TOW;
# - over the last bundle put in tow: PRESS [Y] TO RELEASE.
# The keys are read from the InputMap, so a rebinding shows up here. Lives on a CanvasLayer under
# the launcher, so it goes away with it.

const KEY_PADDING := Vector2(5.0, 2.0)
const GAP: float = 5.0 # Between the words and the key cap
const LIFT: float = 14.0 # Screen px between the top of the bundle and the prompt

@export var font_size: int = 12
@export var text_color: Color = CockpitPalette.CREAM
@export var key_color: Color = CockpitPalette.YELLOW
@export var key_text_color: Color = CockpitPalette.INK_DARK
@export var dim_alpha: float = 0.65 # The release prompt is a reminder: a bit fainter

var launcher: NetLauncher


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if launcher == null:
		return

	if launcher.can_tow():
		_draw_prompt(launcher.tether["bundle"], NetLauncher.TOW_ACTION, "TO TOW", 1.0)

	if not launcher.tows.is_empty():
		_draw_prompt(launcher.tows.back()["bundle"], NetLauncher.RELEASE_ACTION, "TO RELEASE", dim_alpha)


# PRESS [key] what, centred above the bundle.
func _draw_prompt(bundle: NetBundle, action: StringName, what: String, alpha: float) -> void:
	if not is_instance_valid(bundle):
		return

	var canvas := get_viewport().get_canvas_transform()
	var zoom := canvas.get_scale().x
	var top := canvas * bundle.global_position - Vector2(0.0, bundle.get_radius() * zoom + LIFT)

	var font := get_theme_default_font()
	var key := NetLauncher.get_key_label(action)
	var press_width := font.get_string_size("PRESS", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var key_width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + KEY_PADDING.x * 2.0
	var what_width := font.get_string_size(what, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var total := press_width + GAP + key_width + GAP + what_width
	var baseline := top.y
	var x := top.x - total * 0.5

	var text := Color(text_color, text_color.a * alpha)
	var shadow := Color(CockpitPalette.SHADOW, CockpitPalette.SHADOW.a * alpha)
	_draw_text(font, Vector2(x, baseline), "PRESS", text, shadow)
	x += press_width + GAP

	var cap := Rect2(x, baseline - font_size - KEY_PADDING.y + 2.0, key_width, font_size + KEY_PADDING.y * 2.0)
	draw_rect(Rect2(cap.position + Vector2(0.0, 2.0), cap.size), shadow)
	draw_rect(cap, Color(key_color, alpha))
	draw_rect(cap, Color(CockpitPalette.OUTLINE, alpha), false, 1.0)
	draw_string(font, Vector2(x + KEY_PADDING.x, baseline), key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(key_text_color, alpha))
	x += key_width + GAP

	_draw_text(font, Vector2(x, baseline), what, text, shadow)


func _draw_text(font: Font, at: Vector2, text: String, color: Color, shadow: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, shadow)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
