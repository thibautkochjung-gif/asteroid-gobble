extends Camera2D

var target_zoom = Vector2(1.0, 1.0)
@export var min_zoom = 0.3
@export var max_zoom = 2
@export var zoom_sensitivity = 0.1

@export var max_jitter_offset := 20.0
@export var jitter_decay_speed := 1.2 # Trauma lost per second. At 1.2, a full shake lasts ~0.8 s
@export var noise_gain := 2.0 # The noise mostly stays within ±0.3: this brings the jitter closer to max_jitter_offset
@export var max_decay_step := 1.0 / 30.0 # s. A long frame (a big explosion being built) doesn't eat the shake
@export var kick_decay_speed := 8.0
@export var noise_frequency := 4.0
@export var kick_relative_force := 0.1
@export var recoil_strength := 0.7
@export var recoil_stiffness := 300.0
@export var recoil_damping := 20.0


var trauma := 0.0
var kick_offset := Vector2.ZERO
var noise := FastNoiseLite.new()
var noise_seed_x := 0.0
var noise_seed_y := 100.0  # offset so X and Y don't move in lockstep
var recoil_offset := Vector2.ZERO
var recoil_velocity := Vector2.ZERO


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	noise.frequency = noise_frequency
	Fx.screenshake_requested.connect(_on_screenshake_requested)
	Fx.recoil_requested.connect(_on_recoil_requested)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	target_zoom.x = clamp(target_zoom.x, min_zoom, max_zoom)
	target_zoom.y = clamp(target_zoom.y, min_zoom, max_zoom)

	zoom = lerp(zoom, target_zoom, zoom_sensitivity)
	
	trauma = max(trauma - jitter_decay_speed * minf(delta, max_decay_step), 0.0)
	
	kick_offset = kick_offset.lerp(Vector2.ZERO, kick_decay_speed * delta)
	var spring_force = -recoil_stiffness * recoil_offset
	var damping_force = -recoil_damping * recoil_velocity
	recoil_velocity += (spring_force + damping_force) * delta
	recoil_offset += recoil_velocity * delta
	
	# Jitter: noise-driven, scaled by trauma squared
	var shake_amount = trauma * trauma * 4
	noise_seed_x += delta * 60.0
	noise_seed_y += delta * 60.0
	var jitter_x = clampf(noise.get_noise_1d(noise_seed_x) * noise_gain, -1.0, 1.0) * max_jitter_offset * shake_amount
	var jitter_y = clampf(noise.get_noise_1d(noise_seed_y) * noise_gain, -1.0, 1.0) * max_jitter_offset * shake_amount
	
	offset = Vector2(jitter_x, jitter_y) + kick_offset + recoil_offset

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom += Vector2(zoom_sensitivity, zoom_sensitivity)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom -= Vector2(zoom_sensitivity, zoom_sensitivity)


func _on_screenshake_requested(amount: float, direction: Vector2) -> void:
	trauma = clamp(trauma + amount, 0.0, 1.0)
	kick_offset += direction * (max_jitter_offset * kick_relative_force) * amount
	
func _on_recoil_requested(amount: float, direction: Vector2) -> void:
	recoil_velocity += direction * (max_jitter_offset * kick_relative_force) * amount * recoil_strength
