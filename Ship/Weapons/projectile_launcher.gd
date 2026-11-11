class_name ProjectileLauncher
extends HardpointWeapon

# Press to aim: a preview line shows where the shot would land. Release to fire. No windup.
# The projectile inherits the ship's velocity at the muzzle (inertia), so when the ship drifts
# sideways the shot drifts too. The preview ignores that: it shows the barrel's line.
#
# Magazine: it fires up to magazine_size shots, at most fire_rate per second, then reloads for
# reload_time. The rounds come out of the ship's ammo (ShipHardpoints.draw_ammo) when the
# magazine is filled, so a round in the magazine is no longer in storage: the ship's total stays
# what its storage holds.
# Released between two shots: the shot waits for the gap to end, then fires (input buffer), so
# clicking a bit too fast doesn't lose shots. The preview stays up until it goes.

@export var projectile_scene: PackedScene
@export var muzzle_speed: float = 2500.0 # px/s, relative to the ship. ~40 px per physics frame: projectile.gd checks the whole segment, so it can't skip a chunk
@export var max_range: float = 900.0 # Also the preview length

@export_group("Magazine")
@export var magazine_size: int = 8
@export var fire_rate: float = 2.0 # Shots per second, inside a magazine
@export var reload_time: float = 4.0 # s

@export_group("Visuals")
@export var preview_width: float = 2.0
@export var preview_color: Color = Color(1.0, 0.75, 0.2, 0.4)
@export var range_fade: float = 200.0 # px. The preview fades out over this stretch before max_range

var is_aiming: bool = false
var rounds_loaded: int = 0

var _shot_queued: bool = false # Released during the gap between two shots: fires when it ends

@onready var preview: Line2D = $Muzzle/Preview
@onready var shot_timer: Timer = $ShotTimer
@onready var reload_timer: Timer = $ReloadTimer


func _ready() -> void:
	preview.visible = false
	preview.width = preview_width
	shot_timer.one_shot = true
	reload_timer.one_shot = true
	reload_timer.timeout.connect(_on_reload_finished)

	# Deferred: the ship's ammo stores may not be ready yet when the hardpoints install us.
	_fill_magazine.call_deferred()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		_on_fire_pressed()

	if not is_aiming:
		return

	_update_preview()

	if Input.is_action_just_released(fire_action):
		_shot_queued = true

	if _shot_queued and shot_timer.is_stopped():
		_fire()


# The reload only: the short gap between two shots would make the button flicker.
func get_cooldown_ratio() -> float:
	if reload_timer.is_stopped():
		return 0.0

	return reload_timer.time_left / reload_timer.wait_time


func get_loaded_ammo() -> int:
	return rounds_loaded


func get_magazine_size() -> int:
	return magazine_size


func is_out_of_ammo() -> bool:
	return rounds_loaded <= 0 and reload_timer.is_stopped() and _get_stored_ammo() <= 0


func _on_fire_pressed() -> void:
	if is_aiming:
		return # Clicking again while a shot is buffered

	if not reload_timer.is_stopped():
		cooldown_blocked.emit(reload_timer.time_left)
		return

	if rounds_loaded <= 0:
		_start_reload() # After a restock, or if the last reload found nothing
		return

	if get_performance() <= 0.0:
		return

	is_aiming = true
	preview.visible = true


func _update_preview() -> void:
	var from := muzzle.global_position
	var hits := Asteroid.find_hits_on_ray(get_tree(), from, from + get_forward() * max_range, 1)
	var length := max_range

	if not hits.is_empty():
		length = hits[0]["distance"]

	set_range_line(preview, length, preview_color, max_range, range_fade)


func _fire() -> void:
	is_aiming = false
	_shot_queued = false
	preview.visible = false

	if rounds_loaded <= 0:
		return

	var projectile: Projectile = projectile_scene.instantiate()
	projectile.velocity = get_ship_velocity_at(muzzle.global_position) + get_forward() * muzzle_speed
	projectile.lifetime = max_range / muzzle_speed
	get_tree().current_scene.add_child(projectile) # Not under the ship: it must not follow the ship
	projectile.global_position = muzzle.global_position
	projectile.rotation = projectile.velocity.angle()
	rounds_loaded -= 1

	if rounds_loaded > 0:
		shot_timer.start(1.0 / fire_rate * _get_slowdown())
	else:
		_start_reload()


func _start_reload() -> void:
	if _get_stored_ammo() <= 0:
		message.emit("out of ammo")
		return

	reload_timer.start(reload_time * _get_slowdown())
	message.emit("reloading")


func _on_reload_finished() -> void:
	_fill_magazine()

	if rounds_loaded <= 0:
		message.emit("out of ammo") # The ammo box was jettisoned during the reload


func _fill_magazine() -> void:
	var missing := magazine_size - rounds_loaded

	if ammo_source == null:
		rounds_loaded = magazine_size # No ship (test scenes): unlimited
		return

	rounds_loaded += ammo_source.draw_ammo(missing)


func _get_stored_ammo() -> int:
	if ammo_source == null:
		return magazine_size

	return ammo_source.get_ammo()


# Damaged: slower to fire and to reload. Floored, in case it broke mid-magazine.
func _get_slowdown() -> float:
	return 1.0 / maxf(get_performance(), PartHealth.BROKEN_RATIO)
