class_name ProjectileLauncher
extends HardpointWeapon

# Press to aim: a preview line shows where the shot would land. Release to fire. No windup.
# The projectile inherits the ship's velocity at the muzzle (inertia), so when the ship drifts
# sideways the shot drifts too. The preview ignores that: it shows the barrel's line.

@export var projectile_scene: PackedScene
@export var muzzle_speed: float = 2500.0 # px/s, relative to the ship. ~40 px per physics frame: projectile.gd checks the whole segment, so it can't skip a chunk
@export var max_range: float = 900.0 # Also the preview length
@export var cooldown_time: float = 2.0 # Half the laser's

@export_group("Visuals")
@export var preview_width: float = 2.0
@export var preview_color: Color = Color(1.0, 0.75, 0.2, 0.4)

var is_aiming: bool = false

@onready var preview: Line2D = $Muzzle/Preview
@onready var cooldown_timer: Timer = $CooldownTimer


func _ready() -> void:
	preview.visible = false
	preview.width = preview_width
	preview.default_color = preview_color
	cooldown_timer.one_shot = true


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(fire_action):
		_on_fire_pressed()

	if not is_aiming:
		return

	_update_preview()

	if Input.is_action_just_released(fire_action):
		_fire()


func _on_fire_pressed() -> void:
	if not cooldown_timer.is_stopped():
		cooldown_blocked.emit(cooldown_timer.time_left)
		return

	is_aiming = true
	preview.visible = true


func _update_preview() -> void:
	var from := muzzle.global_position
	var hits := Asteroid.find_hits_on_ray(get_tree(), from, from + get_forward() * max_range, 1)
	var length := max_range

	if not hits.is_empty():
		length = hits[0]["distance"]

	preview.points = PackedVector2Array([Vector2.ZERO, Vector2(length, 0.0)])


func _fire() -> void:
	is_aiming = false
	preview.visible = false

	var projectile: Projectile = projectile_scene.instantiate()
	projectile.velocity = get_ship_velocity_at(muzzle.global_position) + get_forward() * muzzle_speed
	projectile.lifetime = max_range / muzzle_speed
	get_tree().current_scene.add_child(projectile) # Not under the ship: it must not follow the ship
	projectile.global_position = muzzle.global_position
	projectile.rotation = projectile.velocity.angle()

	cooldown_timer.start(cooldown_time)
