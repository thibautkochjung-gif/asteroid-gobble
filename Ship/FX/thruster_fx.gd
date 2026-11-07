class_name ThrusterFX
extends Sprite2D

# The flame is drawn by thruster_flame.gdshader on this sprite. Particle emitters are child nodes.
# Emitters use world coordinates and inherit the ship's velocity (inherit_velocity_ratio in their
# process material), so the exhaust leaves the nozzle at ship speed + exhaust speed, like real gas.

@export var ramp_speed: float = 15.0 # How fast the flame grows and shrinks, in strength per second
@export var burn_up_time: float = 0.0 # Seconds of continuous firing to reach full burn. 0 disables burn
@export var burn_down_time: float = 1.0 # Seconds for a full burn to cool back down to 0
@export var trail_emitters: Array[GPUParticles2D] = [] # Emit while the flame is lit, density follows strength
@export var ignition_emitters: Array[GPUParticles2D] = [] # One-shot bursts when the thruster lights up

var _shown_strength: float = 0.0
var _burn: float = 0.0
var _was_firing: bool = false
var _flame_material: ShaderMaterial


func _ready() -> void:
	_flame_material = material as ShaderMaterial
	_flame_material.set_shader_parameter("time_offset", randf() * 100.0) # Desyncs the flicker between thrusters
	_flame_material.set_shader_parameter("strength", 0.0)

	# The sprite stays visible: hiding it would also hide the particles, which must outlive the flame.
	# At strength 0 the shader draws nothing.


func update_strength(target_strength: float, delta: float) -> void:
	var firing := target_strength > 0.0

	_shown_strength = move_toward(_shown_strength, target_strength, ramp_speed * delta)
	_update_burn(firing, delta)
	_update_particles(firing)
	_was_firing = firing

	_flame_material.set_shader_parameter("strength", _shown_strength)
	_flame_material.set_shader_parameter("burn", _burn)


func _update_burn(firing: bool, delta: float) -> void:
	if burn_up_time <= 0.0:
		return

	if firing:
		_burn = move_toward(_burn, 1.0, delta / burn_up_time)
	else:
		_burn = move_toward(_burn, 0.0, delta / maxf(burn_down_time, 0.01))


func _update_particles(firing: bool) -> void:
	if firing and not _was_firing:
		for emitter in ignition_emitters:
			emitter.restart()

	var lit := _shown_strength > 0.0

	for emitter in trail_emitters:
		emitter.emitting = lit
		emitter.amount_ratio = _shown_strength
