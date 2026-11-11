extends Control

# The station screen: Union Ring Four, seen from above. Each service is a part of the station the
# player hovers and clicks: the exchange (market), the repair hangar (mechanic), the drydock (ship
# yard), the guild tower and the hub at the centre (undock). Callout tags name each one and show
# something useful.
#
# The ring spins for gravity, but it's drawn still: the sky, the traffic and the hub at the centre
# (which doesn't spin, so ships can dock at its axis) turn around it instead.
# Everything is laid out on a 1280x720 stage, scaled to fit the window. The station art is drawn at
# one image pixel per stage pixel, the sky at two (Hub/Art, made by _tools/station_art: regenerate
# rather than paint over). The art goes through smooth_pixels.gdshader, so its pixels stay even
# whatever the window size.
#
# Debug builds: F9 gives 10,000 cr and every licence, F10 starts a new game.

const STAGE_SIZE := Vector2(1280.0, 720.0)
const SKY_SCALE: float = 2.0 # Stage px per sky image pixel. The station art is 1:1
const CENTER := Vector2(640.0, 360.0)
const SPIN_PERIOD: float = 240.0 # s per turn. A real ring this size turns in about a minute: slowed so the screen stays calm
const PANEL_POSITION := Vector2(816.0, 70.0)

const SKY_TEXTURE: Texture2D = preload("res://Hub/Art/sky.png")
const HUB_CORE_TEXTURE: Texture2D = preload("res://Hub/Art/hub_core.png")
const SMOOTH_PIXELS: Shader = preload("res://Hub/smooth_pixels.gdshader")

# Lift cars run along the six spokes, between the hub collar and the ring. Slow on purpose.
const SPOKE_ANGLES: Array[float] = [30.0, 90.0, 150.0, 210.0, 270.0, 330.0]
const LIFT_NEAR: float = 72.0 # px from the centre
const LIFT_FAR: float = 196.0
const LIFT_TRAVEL_TIME: float = 38.0 # s one way
const LIFT_STOP_TIME: float = 10.0 # s at each end

# Nav lights on the rim and welding sparks in the drydock, in stage px.
const NAV_LIGHTS: Array[Vector2] = [
	Vector2(908, 412), Vector2(868, 510), Vector2(792, 586), Vector2(694, 628), Vector2(588, 628), Vector2(488, 588),
	Vector2(412, 512), Vector2(372, 414), Vector2(370, 308), Vector2(412, 208), Vector2(486, 132), Vector2(584, 92),
	Vector2(692, 90), Vector2(790, 132), Vector2(866, 206), Vector2(908, 304),
]
const SPARKS: Array[Vector2] = [Vector2(962, 346), Vector2(1004, 378), Vector2(944, 372), Vector2(1030, 352)]

# The clickable parts. `tag` is the callout's box, `anchor` the point it marks on the station.
const AREAS := {
	&"market": { "name": "COMMODITIES EXCHANGE", "tag": Rect2(24, 112, 330, 58), "anchor": Vector2(404, 247) },
	&"mechanic": { "name": "MECHANIC", "tag": Rect2(24, 600, 330, 58), "anchor": Vector2(423, 529) },
	&"shipyard": { "name": "SHIP YARD", "tag": Rect2(930, 470, 330, 58), "anchor": Vector2(954, 360) },
	&"guild": { "name": "MINING GUILD", "tag": Rect2(930, 96, 330, 58), "anchor": Vector2(803, 156) },
	&"undock": { "name": "UNDOCK", "tag": Rect2(880, 630, 330, 58), "anchor": Vector2(660, 380) },
}

var _ui: Dictionary[StringName, Dictionary] = {} # Area id -> { highlight, tag, line, status }
var _hovered: StringName = &""
var _open_id: StringName = &""
var _panel: HubPanel
var _time: float = 0.0
var _lights: Array[ColorRect] = []
var _sparks: Array[ColorRect] = []
var _credits_label: Label
var _pixel_material := ShaderMaterial.new()

@onready var stage: Control = $Stage
@onready var spin: Control = $Stage/Spin
@onready var details: Control = $Stage/Details
@onready var highlights: Control = $Stage/Highlights
@onready var areas: Control = $Stage/Areas
@onready var callouts: Control = $Stage/Callouts
@onready var header: Control = $Stage/Header
@onready var panels: Control = $Stage/Panels
@onready var station: TextureRect = $Stage/Station


func _ready() -> void:
	_pixel_material.shader = SMOOTH_PIXELS
	_use_smooth_pixels(station)
	_fit_stage()
	get_viewport().size_changed.connect(_fit_stage)

	_build_spin()
	_build_details()
	_build_areas()
	_build_header()

	GameState.credits_changed.connect(_refresh_status)
	GameState.storage_changed.connect(_refresh_status)
	GameState.prices_changed.connect(_refresh_status)
	GameState.loadout_changed.connect(_refresh_status)
	_refresh_status()

	if not GameState.last_report.is_empty():
		_show_panel(&"report", ReportPanel.new(GameState.last_report))
		GameState.last_report = {}


func _process(delta: float) -> void:
	_time += delta
	spin.rotation += TAU / SPIN_PERIOD * delta

	for i in _lights.size():
		_lights[i].visible = fmod(_time + i * 0.37, 1.8) < 1.0

	for i in _sparks.size():
		_sparks[i].visible = fmod(_time * (1.0 + i * 0.13) + i * 0.4, 1.1) < 0.25


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _panel != null:
		_panel.close_panel()
		get_viewport().set_input_as_handled()
		return

	var key := event as InputEventKey

	if not OS.is_debug_build() or key == null or not key.pressed or key.echo:
		return

	if key.keycode == KEY_F9:
		GameState.earn(10000)
		GameState.licence_tier = 3
		GameState.save_game()
		_refresh_status()
	elif key.keycode == KEY_F10:
		GameState.new_game()
		get_tree().reload_current_scene()


func _fit_stage() -> void:
	var view := get_viewport_rect().size
	var scale_factor := minf(view.x / STAGE_SIZE.x, view.y / STAGE_SIZE.y)
	stage.scale = Vector2(scale_factor, scale_factor)
	stage.position = (view - STAGE_SIZE * scale_factor) * 0.5


# --- Building the screen


# The sky, the traffic and the hub, on a pivot at the centre of the ring.
func _build_spin() -> void:
	var sky := _texture_rect(SKY_TEXTURE, SKY_SCALE)
	sky.position = -sky.size * 0.5
	spin.add_child(sky)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	for i in 14:
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var angle := rng.randf() * TAU
		holder.position = Vector2.from_angle(angle) * rng.randf_range(330.0, 760.0)
		holder.rotation = rng.randf() * TAU
		spin.add_child(holder)
		var ship := _ship_rect([CockpitPalette.PRIMER, CockpitPalette.READY, CockpitPalette.STEEL, CockpitPalette.CREAM, CockpitPalette.RUST][rng.randi() % 5], [8.0, 10.0, 14.0, 22.0][rng.randi() % 4])
		holder.add_child(ship)
		var tween := create_tween().set_loops()
		tween.tween_property(ship, "position:x", 24.0, rng.randf_range(9.0, 20.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(ship, "position:x", -24.0, rng.randf_range(9.0, 20.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var hub_core := _texture_rect(HUB_CORE_TEXTURE)
	hub_core.position = -hub_core.size * 0.5
	spin.add_child(hub_core)

	# Departures: ships leaving the hub along three lanes.
	for i in 3:
		var lane := Control.new()
		lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lane.rotation = deg_to_rad(45.0 + i * 120.0)
		spin.add_child(lane)
		var ship := _ship_rect(CockpitPalette.READY if i % 2 == 0 else CockpitPalette.PRIMER, 10.0)
		lane.add_child(ship)
		ship.modulate.a = 0.0
		var tween := create_tween().set_loops()
		tween.tween_interval(i * 3.0)
		tween.tween_callback(func() -> void: ship.position.x = 70.0)
		tween.tween_property(ship, "modulate:a", 1.0, 0.6)
		tween.parallel().tween_property(ship, "position:x", 330.0, 9.0)
		tween.tween_property(ship, "modulate:a", 0.0, 0.5)
		tween.tween_interval(9.0 - i * 3.0)


# Nav lights, lift cars and sparks: they belong to the ring, so they don't turn.
func _build_details() -> void:
	for point in NAV_LIGHTS:
		var light := _square(point, 4.0, CockpitPalette.ALARM if _lights.size() % 2 else CockpitPalette.SCOPE)
		details.add_child(light)
		_lights.append(light)

	for point in SPARKS:
		var spark := _square(point, 4.0, Color.WHITE)
		details.add_child(spark)
		_sparks.append(spark)

	for i in SPOKE_ANGLES.size():
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = CENTER
		holder.rotation = deg_to_rad(SPOKE_ANGLES[i])
		details.add_child(holder)

		var car := ColorRect.new()
		car.mouse_filter = Control.MOUSE_FILTER_IGNORE
		car.color = CockpitPalette.YELLOW
		car.size = Vector2(10.0, 8.0)
		car.position = Vector2(lerpf(LIFT_NEAR, LIFT_FAR, float(i % 3) / 2.0), -4.0)
		holder.add_child(car)

		# Each car starts somewhere along its run, so they don't move in step.
		var tween := create_tween().set_loops()
		tween.tween_interval(i * 4.0)
		tween.tween_property(car, "position:x", LIFT_FAR, LIFT_TRAVEL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_interval(LIFT_STOP_TIME)
		tween.tween_property(car, "position:x", LIFT_NEAR, LIFT_TRAVEL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_interval(LIFT_STOP_TIME)


func _build_areas() -> void:
	for id in AREAS:
		var data: Dictionary = AREAS[id]

		var highlight := _texture_rect(load("res://Hub/Art/highlight_%s.png" % id))
		highlight.visible = false
		highlights.add_child(highlight)

		var area := HubArea.new()
		area.setup(id, load("res://Hub/Art/area_%s.png" % id), STAGE_SIZE, 1.0)
		area.entered.connect(_on_hover)
		area.exited.connect(_on_unhover)
		area.pressed.connect(_open)
		areas.add_child(area)

		var tag_rect: Rect2 = data.tag
		var anchor: Vector2 = data.anchor
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = HubStyle.GOOD
		var edge := Vector2(tag_rect.position.x if anchor.x < tag_rect.position.x else tag_rect.end.x, tag_rect.position.y + 22.0)
		var elbow := Vector2(anchor.x, edge.y) if absf(anchor.y - edge.y) > 40.0 else Vector2((anchor.x + edge.x) * 0.5, edge.y)
		line.points = PackedVector2Array([anchor, elbow, edge])
		callouts.add_child(line)

		var marker := Line2D.new()
		marker.width = 2.0
		marker.default_color = HubStyle.GOOD
		marker.closed = true
		marker.points = PackedVector2Array([anchor + Vector2(-4, -4), anchor + Vector2(4, -4), anchor + Vector2(4, 4), anchor + Vector2(-4, 4)])
		callouts.add_child(marker)

		var tag := Button.new()
		tag.position = tag_rect.position
		tag.size = tag_rect.size
		tag.add_theme_stylebox_override(&"normal", HubStyle.box(HubStyle.TAG_BG, HubStyle.GOOD, 2, 6))
		tag.add_theme_stylebox_override(&"hover", HubStyle.box(HubStyle.TAG_BG, HubStyle.ACCENT, 2, 6))
		tag.add_theme_stylebox_override(&"pressed", HubStyle.box(HubStyle.TAG_BG, HubStyle.ACCENT, 2, 6))
		tag.add_theme_stylebox_override(&"focus", HubStyle.box(Color.TRANSPARENT, HubStyle.ACCENT, 2, 6))
		tag.mouse_entered.connect(_on_hover.bind(id))
		tag.mouse_exited.connect(_on_unhover.bind(id))
		tag.pressed.connect(_open.bind(id))
		callouts.add_child(tag)

		var text := VBoxContainer.new()
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.position = Vector2(12.0, 5.0)
		text.add_theme_constant_override(&"separation", 0)
		tag.add_child(text)
		var title := HubStyle.label(data.name, 20, HubStyle.GOOD)
		text.add_child(title)
		var status := HubStyle.label("", 15, HubStyle.TEXT)
		text.add_child(status)

		_ui[id] = { "highlight": highlight, "tag": tag, "lines": [line, marker], "title": title, "status": status }


func _build_header() -> void:
	var title := HubStyle.label("UNION RING FOUR", 34, CockpitPalette.CREAM)
	title.position = Vector2(24.0, 14.0)
	title.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	title.add_theme_constant_override(&"shadow_offset_x", 3)
	title.add_theme_constant_override(&"shadow_offset_y", 3)
	header.add_child(title)

	var subtitle := HubStyle.label("Berth 6 · ring spin 1 rpm · 0.9 g on the rim", 16, HubStyle.DIM)
	subtitle.position = Vector2(26.0, 58.0)
	header.add_child(subtitle)

	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override(&"panel", HubStyle.box(Color(0.07, 0.07, 0.05, 0.92), CockpitPalette.OUTLINE, 3, 8))
	plate.position = Vector2(1060.0, 18.0)
	plate.custom_minimum_size = Vector2(196.0, 0.0)
	header.add_child(plate)
	_credits_label = HubStyle.label("", 24, HubStyle.GOOD)
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	plate.add_child(_credits_label)

	if OS.is_debug_build():
		var hint := HubStyle.label("Debug: F9 +10,000 cr and all licences · F10 new game", 13, HubStyle.DIM)
		hint.position = Vector2(26.0, 690.0)
		header.add_child(hint)


# --- State


func _refresh_status() -> void:
	_credits_label.text = HubStyle.format_credits(GameState.credits)
	_credits_label.add_theme_color_override(&"font_color", HubStyle.BAD if GameState.credits < 0 else HubStyle.GOOD)

	var held := GameState.get_storage_value()
	var cobalt := CellMaterials.Id.COBALT
	var market_text := "Your bay: worth %s" % HubStyle.format_credits(held) if held > 0 else "Cobalt %.1f cr · gold %.1f cr" % [GameState.get_price(cobalt), GameState.get_price(CellMaterials.Id.GOLD)]
	var hull_text := "Hull %d%%" % roundi(GameState.hull_ratio * 100.0)

	if GameState.needs_repair():
		hull_text += ", repairs advised"
	elif not GameState.spares.is_empty():
		hull_text += " · spares in storage"

	var open_fields := 0

	for i in GameState.ECONOMY.fields.size():
		if GameState.is_field_open(i):
			open_fields += 1

	_ui[&"market"].status.text = market_text
	_ui[&"mechanic"].status.text = hull_text
	_ui[&"mechanic"].status.add_theme_color_override(&"font_color", HubStyle.BAD if GameState.needs_repair() else HubStyle.TEXT)
	_ui[&"shipyard"].status.text = "Closed for refit"
	_ui[&"guild"].status.text = "Opening soon"
	_ui[&"undock"].status.text = "Hub lift · %d fields open" % open_fields


func _on_hover(id: StringName) -> void:
	_hovered = id
	_update_highlights()


func _on_unhover(id: StringName) -> void:
	if _hovered == id:
		_hovered = &""

	_update_highlights()


func _update_highlights() -> void:
	for id in _ui:
		var is_lit := id == _hovered or id == _open_id
		var color := HubStyle.ACCENT if is_lit else HubStyle.GOOD
		_ui[id].highlight.visible = is_lit
		_ui[id].title.add_theme_color_override(&"font_color", color)

		for line in _ui[id].lines:
			(line as Line2D).default_color = color


func _open(id: StringName) -> void:
	var title: String = AREAS[id].name

	match id:
		&"market":
			_show_panel(id, MarketPanel.new())
		&"undock":
			_show_panel(id, UndockPanel.new())
		&"mechanic":
			_show_panel(id, MechanicPanel.new())
		_:
			_show_panel(id, ServicePanel.new(id, title))


func _show_panel(id: StringName, panel: HubPanel) -> void:
	if _panel != null:
		_panel.close_panel()

	_panel = panel
	_open_id = id
	# Wide panels (the mechanic) sit in the middle of the stage, the others on the right.
	var is_wide := panel.custom_minimum_size.x > HubPanel.PANEL_WIDTH
	panel.position = Vector2((STAGE_SIZE.x - panel.custom_minimum_size.x) * 0.5, PANEL_POSITION.y) if is_wide else PANEL_POSITION
	panel.closed.connect(_on_panel_closed.bind(panel))
	panels.add_child(panel)
	_update_highlights()


func _on_panel_closed(panel: HubPanel) -> void:
	if _panel != panel:
		return

	_panel = null
	_open_id = &""
	_update_highlights()
	_refresh_status()


# --- Helpers


# `scale_factor`: stage px per image pixel.
func _texture_rect(texture: Texture2D, scale_factor: float = 1.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = texture.get_size() * scale_factor
	_use_smooth_pixels(rect)
	return rect


func _use_smooth_pixels(item: CanvasItem) -> void:
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	item.material = _pixel_material


func _square(center: Vector2, side: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.size = Vector2(side, side)
	rect.position = center - rect.size * 0.5
	return rect


# A distant ship: a hull, an outline and an engine glow behind it. Nose toward +x.
func _ship_rect(color: Color, length: float) -> Control:
	var ship := Control.new()
	ship.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := _square(Vector2.ZERO, 1.0, CockpitPalette.OUTLINE)
	outline.size = Vector2(length + 4.0, 8.0)
	outline.position = Vector2(-2.0, -4.0)
	ship.add_child(outline)
	var hull := _square(Vector2.ZERO, 1.0, color)
	hull.size = Vector2(length, 4.0)
	hull.position = Vector2(0.0, -2.0)
	ship.add_child(hull)
	var glow := _square(Vector2(-4.0, 0.0), 2.0, CockpitPalette.YELLOW_LIT)
	glow.size = Vector2(3.0, 2.0)
	ship.add_child(glow)
	return ship
