class_name BreachingLance
extends HardpointWeapon

# Press to aim: a preview line shows where the lance would land. Release to fire. Like the
# projectile launcher, but the shot is a lance: it drives into the rock, as deep as the rock lets
# it (soft rock lets it further), then goes off by itself after a short fuse and breaks the rock
# into a few big pieces along its weak seams (LanceRound). No say in how many: that's the lance.
# Lances are big: the launcher carries its own stock of stock_capacity, refilled at the station
# (restock), not from the ship's ammo.
# The lance leaves with the ship's velocity at the muzzle (inertia), and kicks the ship back.
# Aiming: the tube follows the mouse inside its arc (aim_arc_degrees) while the button is held.
# A released lance waits for the tube to reach the mouse.

const TEXEL: float = 2.0

@export var muzzle_speed: float = 900.0 # px/s, relative to the ship
@export var max_range: float = 800.0 # Also the preview length
@export var stock_capacity: int = 12
@export var reload_time: float = 3.0 # s between two lances
@export var lance_mass: float = 0.1 # For the kick on the ship

@export_group("Lance")
@export var penetration_budget: float = 40.0 # Soft-rock cells. Each cell costs its hardness
@export var max_depth: float = 200.0 # px, whatever the rock
@export var fuse_time: float = 1.5 # s between sticking and going off
@export var min_pieces: int = 3
@export var max_pieces: int = 4
@export var crater_cells: int = 10
@export var blast_speed: float = 30.0 # px/s given to a piece of reference size, away from the blast
@export var blast_shake: float = 0.7

@export_group("Look")
@export var preview_width: float = 2.0
@export var preview_color: Color = Color(1.0, 0.35, 0.2, 0.4)
@export var range_fade: float = 200.0
@export var body_color: Color = Color(0.67, 0.36, 0.18)
@export var tube_color: Color = Color(0.31, 0.3, 0.31)
@export var outline_color: Color = Color(0.06, 0.055, 0.07)

var stock: int = 0
var is_aiming: bool = false

var _fire_queued: bool = false # Released before the tube reached the mouse: fires when it does

@onready var preview: Line2D = $Muzzle/Preview
@onready var reload_timer: Timer = $ReloadTimer


func _ready() -> void:
	stock = stock_capacity
	preview.visible = false
	preview.width = preview_width
	reload_timer.one_shot = true


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		_on_fire_pressed()

	_update_aim_for_state(delta)

	if is_aiming:
		_update_preview()

		if Input.is_action_just_released(fire_action):
			_fire_queued = true

		if _fire_queued and is_on_target():
			_fire()

	queue_redraw()


func get_button_title() -> String:
	return "LANCE %d" % stock


func get_cooldown_ratio() -> float:
	if reload_timer.is_stopped():
		return 0.0

	return reload_timer.time_left / reload_timer.wait_time


func is_out_of_ammo() -> bool:
	return stock <= 0


func restock() -> void:
	stock = stock_capacity


func _on_fire_pressed() -> void:
	if is_aiming:
		return # Clicking again while a lance is queued

	if not reload_timer.is_stopped():
		cooldown_blocked.emit(reload_timer.time_left)
		return

	if stock <= 0:
		message.emit("no lances left")
		return

	if get_performance() <= 0.0:
		return

	is_aiming = true
	preview.visible = true


func _update_aim_for_state(delta: float) -> void:
	if is_aiming:
		update_aim(delta)
	else:
		reset_aim(delta)


func _update_preview() -> void:
	var from := muzzle.global_position
	var hits := Asteroid.find_hits_on_ray(get_tree(), from, from + get_forward() * max_range, 1)
	var length := max_range

	if not hits.is_empty():
		length = hits[0]["distance"]

	set_range_line(preview, length, preview_color, max_range, range_fade)


func _fire() -> void:
	is_aiming = false
	_fire_queued = false
	preview.visible = false

	var lance := LanceRound.new()
	lance.weapon = self
	lance.velocity = get_ship_velocity_at(muzzle.global_position) + get_forward() * muzzle_speed
	lance.lifetime = max_range / muzzle_speed
	get_tree().current_scene.add_child(lance) # Not under the ship: it must not follow the ship
	lance.global_position = muzzle.global_position
	lance.rotation = get_forward().angle()

	ship.apply_impulse(-get_forward() * muzzle_speed * lance_mass, muzzle.global_position - ship.global_position)
	stock -= 1
	reload_timer.start(reload_time / maxf(get_performance(), PartHealth.BROKEN_RATIO))
	message.emit("lance away, %d left" % stock)


# --- Look


# A long tube with the next lance's tip showing, when there's one.
func _draw() -> void:
	var tube := Rect2(-TEXEL * 2.0, -TEXEL * 2.0, muzzle.position.x + TEXEL * 2.0, TEXEL * 4.0)
	draw_rect(tube.grow(TEXEL * 0.5), outline_color)
	draw_rect(tube, tube_color)
	draw_rect(Rect2(tube.position, Vector2(TEXEL * 3.0, tube.size.y)), body_color)

	if stock > 0 and reload_timer.is_stopped():
		var tip := muzzle.position
		draw_colored_polygon(PackedVector2Array([tip + Vector2(TEXEL * 2.0, 0.0), tip + Vector2(0.0, -TEXEL), tip + Vector2(0.0, TEXEL)]), Color(0.84, 0.82, 0.77))
