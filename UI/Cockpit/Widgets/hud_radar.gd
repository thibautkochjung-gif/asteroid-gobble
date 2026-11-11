class_name HudRadar
extends Control

# The radar scope: asteroids and props around the ship, north up, with a sweep that refreshes
# the blips like an old phosphor screen. The bezel and the dark glass are in the panel art.
# Centred in its rect; draws inside `radius`.

const SWEEP_TRAIL: float = 0.9 # Radians of fading glow behind the sweep line
const SWEEP_TRAIL_STEPS: int = 12

@export var radius: float = 86.0
@export var world_range: float = 1600.0 # px of world from the centre to the edge of the scope
@export var sweep_period: float = 3.0 # Seconds per turn
@export var blip_size: float = 5.0
@export var prop_size: float = 3.0
@export var mothership_size: float = 9.0
@export var faded_alpha: float = 0.3 # A blip's brightness just before the sweep comes round again
@export_range(0.0, 1.0) var interference: float = 0.0 # Set by Cockpit after a hit: static, lost and jumpy blips
@export var max_static_specks: int = 80
@export var refresh_rate: float = 20.0 # Redraws per second. A phosphor scope doesn't need every frame, and each redraw walks every rock

var ship: Node2D # Set by Cockpit

var _sweep_angle: float = 0.0
var _redraw_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_sweep_angle = fmod(_sweep_angle + TAU * delta / sweep_period, TAU)
	_redraw_timer -= delta

	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / refresh_rate
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0

	_draw_grid(center)
	_draw_sweep(center)

	if interference > 0.0:
		_draw_static(center)

	if ship == null:
		return

	for node in get_tree().get_nodes_in_group(Asteroid.GROUP):
		_draw_blip(center, (node as Node2D).global_position, blip_size, CockpitPalette.SCOPE)

	for node in get_tree().get_nodes_in_group(SpaceProp.GROUP):
		_draw_blip(center, (node as Node2D).global_position, prop_size, CockpitPalette.CREAM)

	for node in get_tree().get_nodes_in_group(Mothership.GROUP):
		var mothership := node as Mothership

		if not mothership.get_marker_text().is_empty():
			_draw_pinned_blip(center, mothership.get_marker_position(), mothership_size, CockpitPalette.YELLOW_LIT)

	_draw_ship_marker(center)


func _draw_grid(center: Vector2) -> void:
	draw_arc(center, radius * 0.5, 0.0, TAU, 48, CockpitPalette.SCOPE_GRID, 2.0)
	draw_line(center + Vector2(0.0, -radius), center + Vector2(0.0, radius), CockpitPalette.SCOPE_GRID, 2.0)
	draw_line(center + Vector2(-radius, 0.0), center + Vector2(radius, 0.0), CockpitPalette.SCOPE_GRID, 2.0)


# The sweep: a bright line and a fan of thin wedges fading out behind it.
func _draw_sweep(center: Vector2) -> void:
	for step in SWEEP_TRAIL_STEPS:
		var end_angle := _sweep_angle - SWEEP_TRAIL * step / SWEEP_TRAIL_STEPS
		var start_angle := end_angle - SWEEP_TRAIL / SWEEP_TRAIL_STEPS
		var alpha := 0.16 * (1.0 - float(step) / SWEEP_TRAIL_STEPS)
		var wedge := PackedVector2Array([center, center + Vector2.from_angle(start_angle) * radius, center + Vector2.from_angle(end_angle) * radius])
		draw_colored_polygon(wedge, Color(CockpitPalette.SCOPE, alpha))

	draw_line(center, center + Vector2.from_angle(_sweep_angle) * radius, Color(CockpitPalette.SCOPE, 0.5), 1.5)


func _draw_blip(center: Vector2, world_position: Vector2, blip: float, color: Color) -> void:
	var offset := (world_position - ship.global_position) / world_range * radius

	if interference > 0.0:
		if randf() < interference * 0.6:
			return # Lost in the static this frame

		offset += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * interference * 8.0

	if offset.length() > radius - blip:
		return

	# Freshly swept blips are bright, then fade until the sweep comes round again.
	var since_swept := fposmod(_sweep_angle - offset.angle(), TAU) / TAU
	var alpha := lerpf(1.0, faded_alpha, since_swept)
	var at := center + offset
	draw_rect(Rect2(at - Vector2.ONE * blip / 2.0, Vector2.ONE * blip), Color(color, alpha))


# Always shown: out of range, it sits on the rim, hollow, in its direction. Not swept, not jammed.
func _draw_pinned_blip(center: Vector2, world_position: Vector2, blip: float, color: Color) -> void:
	var offset := (world_position - ship.global_position) / world_range * radius
	var rim := radius - blip
	var is_out := offset.length() > rim

	if is_out:
		offset = offset.normalized() * rim

	var rect := Rect2(center + offset - Vector2.ONE * blip / 2.0, Vector2.ONE * blip)
	draw_rect(rect, color, not is_out, 2.0 if is_out else -1.0)


func _draw_static(center: Vector2) -> void:
	for i in roundi(interference * max_static_specks):
		var at := center + Vector2.from_angle(randf() * TAU) * radius * sqrt(randf())
		draw_rect(Rect2(at, Vector2(2.0, 2.0)), Color(CockpitPalette.SCOPE, randf() * 0.6))


func _draw_ship_marker(center: Vector2) -> void:
	var forward := Vector2.from_angle(ship.global_rotation)
	var side := forward.orthogonal()
	var marker := PackedVector2Array([center + forward * 8.0, center - forward * 5.0 + side * 5.0, center - forward * 2.0, center - forward * 5.0 - side * 5.0])
	draw_colored_polygon(marker, CockpitPalette.YELLOW)
