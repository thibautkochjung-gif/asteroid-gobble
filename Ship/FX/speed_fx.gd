class_name SpeedFx
extends Node2D

# Makes the ship's speed visible, and high speed read as dangerous.
# - Dust: faint motes fixed in the world. At rest they are dots. Moving, each one gets a short
#   streak: the distance it really moves on screen during shutter_time, like a camera's motion blur.
# - Near dust: layers of motes between the camera and the world (screen space, parallax). A layer at
#   depth k slides past the screen k times faster than the world, so speed reads as motes rushing
#   by, not as long lines drifting slowly. Same motion-blur rule. They fade in with the speed.
# - Blur and vignette follow the square of the speed: barely there when cruising, strong close to
#   lethal speed.
# - Blur: speed_blur.gdshader smears the edges of the view along the velocity and darkens the rim.
# - Danger: once a head-on hit would be heavy (ShipDamage.get_speed_danger), the dust warms up,
#   the camera rumbles and short alerts go off: the screen rim flashes orange, and so does the
#   cockpit's speed readout (it reads `alert`). Alerts come closer together as the danger grows.
#
# Speeds are the ship's own, in the world frame. Asteroids drift slowly, so that stays close to
# the speed of a hit against them.
#
# Lives in the world at the origin (child of the main scene's root), so it draws in world units.
# z_index -1 keeps the dust behind the ship and the asteroids.

const BLUR_SHADER: Shader = preload("res://Ship/FX/speed_blur.gdshader")
const OVERLAY_LAYER: int = 1 # Above the world, under the HUD (layer 2), so the HUD never blurs

@export var ship: RigidBody2D
@export var ship_damage: ShipDamage # Speed scale (lethal_speed) and danger thresholds

@export_group("Dust")
@export var dust_cell_size: float = 160.0 # World px. A given cell always holds the same motes
@export var motes_per_cell: int = 1
@export var max_visible_cells: int = 500 # Zoomed far out, only some cells get motes: the draw cost stays flat
@export var shutter_time: float = 0.05 # s. Streak = how far a mote moves on screen in this time
@export var dot_size: float = 2.0 # World px. Matches the asteroids' 2x2 cells
@export var rest_alpha: float = 0.08
@export var speed_alpha: float = 0.4 # At lethal speed
@export var dust_color: Color = Color(0.78, 0.74, 0.68)
@export var danger_tint: float = 0.5 # How far the dust turns to danger_color at full danger

@export_group("Near dust")
@export var near_depths: Array[float] = [2.5, 5.0] # Screen speed, in times the world's. One layer each
@export var near_cell_sizes: Array[float] = [200.0, 320.0] # Screen px. One mote per cell. Same order as near_depths
@export var near_dot_sizes: Array[float] = [2.0, 3.0] # Screen px. Closer = bigger
@export var near_alpha: float = 0.45 # At lethal speed. Grows linearly with the speed from 0
@export var max_near_trail: float = 160.0 # Screen px. Caps a very close mote's streak

@export_group("Blur")
@export var max_blur: float = 24.0 # Screen px, at lethal speed
@export var clear_radius: float = 0.2 # Share of screen height around the middle that never blurs
@export var vignette_strength: float = 0.3 # Rim darkening at lethal speed

@export_group("Danger")
@export var danger_color: Color = CockpitPalette.ALARM
@export var glow_strength: float = 0.25 # Rim glow at the peak of an alert
@export var slow_alert_period: float = 3.0 # s between alerts when a hit just gets heavy
@export var fast_alert_period: float = 2.4 # s between alerts at lethal speed (was 1.2)
@export var alert_duration: float = 0.45 # s. One alert fades in and out over this
@export var rumble: float = 0.2 # Camera trauma at full danger (1 = max)

var alert: float = 0.0 # 0..1. Peaks in the middle of each alert, 0 between them

var _overlay_material: ShaderMaterial
var _overlay: ColorRect
var _near_canvas: Node2D # Draws the near dust in screen space, under the blur
var _alert_clock: float = 0.0
var _intensity: float = 0.0 # Square of speed / lethal_speed
var _danger: float = 0.0


func _ready() -> void:
	z_index = -1
	_build_overlay()


func _process(delta: float) -> void:
	if ship == null or ship_damage == null:
		return

	var speed := ship.linear_velocity.length()
	var speed_ratio := clampf(speed / ship_damage.lethal_speed, 0.0, 1.0)
	_intensity = speed_ratio * speed_ratio
	_danger = ship_damage.get_speed_danger(speed)

	_update_alert(delta)
	_update_overlay()
	_update_camera()
	queue_redraw()
	_near_canvas.queue_redraw()


# First alert as soon as the danger starts, then one every period
func _update_alert(delta: float) -> void:
	if _danger <= 0.0:
		_alert_clock = 0.0
		alert = 0.0
		return

	var period := lerpf(slow_alert_period, fast_alert_period, _danger)
	_alert_clock = fmod(_alert_clock + delta, period)
	alert = sin(PI * _alert_clock / alert_duration) if _alert_clock < alert_duration else 0.0


# --- Screen overlay


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)

	# Added before the overlay: the blur draws over it
	_near_canvas = Node2D.new()
	_near_canvas.draw.connect(_draw_near_dust)
	layer.add_child(_near_canvas)

	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = BLUR_SHADER

	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = _overlay_material
	_overlay.visible = false
	layer.add_child(_overlay)


func _update_overlay() -> void:
	# Hidden when nothing would show: the screen copy isn't free
	_overlay.visible = _intensity > 0.01
	if not _overlay.visible:
		return

	var screen_size := get_viewport().get_visible_rect().size
	var blur_pixels := max_blur * _intensity

	_overlay_material.set_shader_parameter("blur_vector", ship.linear_velocity.normalized() * blur_pixels / screen_size)
	_overlay_material.set_shader_parameter("speed_ratio", _intensity)
	_overlay_material.set_shader_parameter("danger", alert)
	_overlay_material.set_shader_parameter("pulse", 1.0)
	_overlay_material.set_shader_parameter("clear_radius", clear_radius)
	_overlay_material.set_shader_parameter("vignette_strength", vignette_strength)
	_overlay_material.set_shader_parameter("glow_strength", glow_strength)
	_overlay_material.set_shader_parameter("danger_color", danger_color)


func _update_camera() -> void:
	var camera := get_viewport().get_camera_2d()

	if camera != null and camera.has_method("set_ambient_trauma"):
		camera.set_ambient_trauma(_danger * rumble)


# --- Dust


func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or ship == null:
		return

	var zoom := camera.zoom.x
	var view_size := get_viewport().get_visible_rect().size / zoom
	var smear := ship.linear_velocity * shutter_time
	var view := Rect2(camera.get_screen_center_position() - view_size / 2.0, view_size).grow(smear.length())

	var first_cell := Vector2i((view.position / dust_cell_size).floor())
	var last_cell := Vector2i((view.end / dust_cell_size).floor())
	var cell_count := (last_cell.x - first_cell.x + 1) * (last_cell.y - first_cell.y + 1)

	# Zoomed out: keep one cell in 2x2, then 4x4... The kept cells' motes don't move
	var stride := 1
	while cell_count > max_visible_cells * stride * stride:
		stride *= 2

	var width := maxf(dot_size, 1.0 / zoom) # Never thinner than one screen pixel
	var alpha := lerpf(rest_alpha, speed_alpha, _intensity)
	var color := dust_color.lerp(danger_color, _danger * danger_tint)
	var is_streak := smear.length() > width

	for cell_y in range(first_cell.y, last_cell.y + 1):
		if posmod(cell_y, stride) != 0:
			continue

		for cell_x in range(first_cell.x, last_cell.x + 1):
			if posmod(cell_x, stride) != 0:
				continue

			for i in motes_per_cell:
				var h := _hash(cell_x, cell_y, i)
				var local := Vector2(h & 0xFFFF, (h >> 16) & 0xFFFF) / 65536.0
				var mote := (Vector2(cell_x, cell_y) + local) * dust_cell_size
				var brightness := 0.4 + 0.6 * float((h >> 32) & 0xFF) / 255.0
				var mote_color := Color(color, alpha * brightness)

				if is_streak:
					draw_line(mote - smear * 0.5, mote + smear * 0.5, mote_color, width)
				else:
					draw_rect(Rect2(mote - Vector2(width, width) / 2.0, Vector2(width, width)), mote_color)


# Screen-space layers. Each one scrolls with the ship's position times its depth, so it slides past
# the screen at depth x the ship's speed. Motes trail behind their motion (towards the velocity).
func _draw_near_dust() -> void:
	if ship == null or ship_damage == null:
		return

	var speed := ship.linear_velocity.length()
	if speed < 1.0:
		return

	var screen := get_viewport().get_visible_rect()
	var direction := ship.linear_velocity / speed
	var speed_ratio := clampf(speed / ship_damage.lethal_speed, 0.0, 1.0)
	var color := dust_color.lerp(danger_color, _danger * danger_tint)
	var alpha := near_alpha * speed_ratio

	for layer_index in near_depths.size():
		var depth := near_depths[layer_index]
		var cell_size := near_cell_sizes[mini(layer_index, near_cell_sizes.size() - 1)]
		var dot := near_dot_sizes[mini(layer_index, near_dot_sizes.size() - 1)]
		var trail := direction * minf(depth * speed * shutter_time, max_near_trail)
		var scroll := ship.global_position * depth
		var view := Rect2(scroll, screen.size).grow(trail.length())

		var first_cell := Vector2i((view.position / cell_size).floor())
		var last_cell := Vector2i((view.end / cell_size).floor())

		for cell_y in range(first_cell.y, last_cell.y + 1):
			for cell_x in range(first_cell.x, last_cell.x + 1):
				var h := _hash(cell_x, cell_y, 100 + layer_index)
				var local := Vector2(h & 0xFFFF, (h >> 16) & 0xFFFF) / 65536.0
				var at := (Vector2(cell_x, cell_y) + local) * cell_size - scroll + screen.position
				var brightness := 0.4 + 0.6 * float((h >> 32) & 0xFF) / 255.0
				var mote_color := Color(color, alpha * brightness)

				_near_canvas.draw_line(at, at + trail, mote_color, dot)


# Cheap integer hash: same cell and index, same mote, every frame and every run
func _hash(x: int, y: int, i: int) -> int:
	var h := x * 73856093 ^ y * 19349663 ^ i * 83492791
	h = (h ^ h >> 13) * 1274126177
	return h ^ h >> 16
