extends Node

signal screenshake_requested(amount: float)
signal recoil_requested(amount: float, direction: Vector2)

const VAPORIZE_FX_SCENE: PackedScene = preload("res://Asteroids/FX/vaporize_fx.tscn")
const CHARGE_EXPLOSION_FX: GDScript = preload("res://Ship/FX/charge_explosion_fx.gd")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


#func spawn_hit_effect(pos: Vector2, direction: Vector2) -> void:
#    var effect = HIT_EFFECT_SCENE.instantiate()
#    get_tree().current_scene.add_child(effect)
#    effect.global_position = pos
#    effect.play(direction)


func shake(amount: float, direction: Vector2 = Vector2.ZERO) -> void:
	screenshake_requested.emit(amount, direction)


func recoil(amount: float, direction: Vector2 = Vector2.ZERO) -> void:
	recoil_requested.emit(amount, direction)


# points: global positions of the vaporized cells. direction: the beam direction.
# base_velocity: velocity of the vaporized material, so the debris keeps the asteroid's momentum.
func spawn_vaporize(points: PackedVector2Array, direction: Vector2, dust_color: Color, base_velocity: Vector2 = Vector2.ZERO) -> void:
	if points.is_empty():
		return

	var effect: Node2D = VAPORIZE_FX_SCENE.instantiate()
	get_tree().current_scene.add_child(effect)
	effect.global_position = points[0]
	effect.play(points, direction, dust_color, base_velocity)


# One demolition charge going off (ChargeExplosionFx). direction: out of the rock, at the crater.
# base_velocity: the rock's velocity there, so the cloud keeps the rock's momentum.
func spawn_explosion(at: Vector2, direction: Vector2, dust_color: Color, base_velocity: Vector2 = Vector2.ZERO) -> void:
	var effect: Node2D = CHARGE_EXPLOSION_FX.new()
	get_tree().current_scene.add_child(effect)
	effect.global_position = at
	effect.play(direction, dust_color, base_velocity)
