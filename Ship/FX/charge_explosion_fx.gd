class_name ChargeExplosionFx
extends Node2D

# One demolition charge going off: a white-hot flash, two shockwave rings, hot sparks thrown out
# of the crater, slower embers, and a cloud of rock dust. Built in code (Fx.spawn_explosion).
# Sized for the game's normal zoom (1): at that zoom, a 1 px particle is invisible.
# The flash, rings, sparks and embers blend additively: they light up what's behind them.
# Like VaporizeFx, the emitters use local coordinates and the whole effect drifts at the rock's
# velocity, so the cloud keeps the rock's momentum.

const FLASH_TIME: float = 0.3 # s
const FLASH_RADIUS: float = 30.0 # px
const RING_TIME: float = 0.6 # s
const RING_RADIUS: float = 95.0 # px
const FLASH_COLOR: Color = Color(1.0, 0.97, 0.85)
const FIRE_COLOR: Color = Color(1.0, 0.55, 0.15)

var _age: float = 0.0
var _drift_velocity: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	global_position += _drift_velocity * delta


func _process(delta: float) -> void:
	_age += delta

	# One frame past the ring too: that draw is empty and clears the last ring.
	if _age <= RING_TIME + 0.1:
		queue_redraw()


# direction: out of the rock, at the crater. dust_color: the rock's color there.
# base_velocity: the rock's velocity at the crater.
func play(direction: Vector2, dust_color: Color, base_velocity: Vector2) -> void:
	_drift_velocity = base_velocity
	z_index = 3 # Over the rock, the chunks and the charges' pulse
	material = _make_additive()

	# Smoke first: drawn under the sparks. Not additive: dust hides what's behind it.
	var smoke := _make_emitter(60, 4.0, direction, 100.0, 15.0, 70.0, 12.0, 25.0, 5.0, 9.0)
	var dark_dust := dust_color.darkened(0.15)
	smoke.color_ramp = _make_gradient([Color(dark_dust, 0.85), Color(dark_dust, 0.5), Color(dark_dust, 0.0)])

	var sparks := _make_emitter(120, 0.9, direction, 75.0, 120.0, 380.0, 150.0, 300.0, 2.0, 3.0)
	sparks.color_ramp = _make_gradient([FLASH_COLOR, Color(1.0, 0.8, 0.3), FIRE_COLOR, Color(0.8, 0.15, 0.05, 0.0)])
	sparks.material = _make_additive()

	var embers := _make_emitter(40, 2.0, direction, 110.0, 25.0, 100.0, 30.0, 60.0, 2.0, 3.0)
	embers.color_ramp = _make_gradient([Color(1.0, 0.7, 0.25), Color(0.9, 0.3, 0.08), Color(0.5, 0.1, 0.05, 0.0)])
	embers.material = _make_additive()

	get_tree().create_timer(smoke.lifetime * 1.5 + 0.2).timeout.connect(queue_free)


func _draw() -> void:
	if _age < FLASH_TIME:
		var t := _age / FLASH_TIME
		var fade := (1.0 - t) * (1.0 - t)

		# A soft glow: stacked circles, wide and faint to small and bright.
		for i in 4:
			var glow := FLASH_COLOR.lerp(FIRE_COLOR, t + i * 0.1)
			glow.a = 0.55 * fade
			draw_circle(Vector2.ZERO, FLASH_RADIUS * (1.0 - i * 0.22) * (0.7 + 0.5 * t), glow)

	_draw_ring(_age / RING_TIME, RING_RADIUS, 4.0, FIRE_COLOR)
	_draw_ring(_age / (RING_TIME * 0.6), RING_RADIUS * 0.55, 2.0, FLASH_COLOR) # Faster, smaller, white


# t: 0 -> 1 over the ring's life. Grows fast then slows (ease-out), and fades.
func _draw_ring(t: float, radius: float, width: float, color: Color) -> void:
	if t >= 1.0:
		return

	var ring := color
	ring.a = 0.9 * (1.0 - t)
	var ring_radius := radius * (1.0 - (1.0 - t) * (1.0 - t))
	draw_arc(Vector2.ZERO, maxf(ring_radius, 1.0), 0.0, TAU, 48, ring, width)


func _make_additive() -> CanvasItemMaterial:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return additive


# A one-shot burst. Spread in degrees, speeds in px/s, damping in px/s², scale in texels.
func _make_emitter(amount: int, lifetime: float, direction: Vector2, spread: float, min_speed: float, max_speed: float, min_damping: float, max_damping: float, min_scale: float, max_scale: float) -> CPUParticles2D:
	var emitter := CPUParticles2D.new()
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 0.95
	emitter.lifetime_randomness = 0.5
	emitter.local_coords = true
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	emitter.emission_sphere_radius = 3.0
	emitter.direction = direction
	emitter.spread = spread
	emitter.gravity = Vector2.ZERO
	emitter.initial_velocity_min = min_speed
	emitter.initial_velocity_max = max_speed
	emitter.damping_min = min_damping
	emitter.damping_max = max_damping
	emitter.scale_amount_min = min_scale
	emitter.scale_amount_max = max_scale
	add_child(emitter)
	emitter.emitting = true
	return emitter


# Colors spread evenly from start to end of the particle's life.
func _make_gradient(colors: Array[Color]) -> Gradient:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()

	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))

	gradient.offsets = offsets
	gradient.colors = PackedColorArray(colors)
	return gradient
