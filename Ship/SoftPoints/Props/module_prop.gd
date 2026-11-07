class_name ModuleProp
extends SpaceProp

# A whole soft point module floating loose: jettisoned, or torn off by a hit.
# The module node itself rides inside (hold() before add_child), with everything it held:
# a drop tank keeps its fuel, a rack its items. Its collision is its footprint.
# Touch it gently with the hull and it goes back on the nearest empty mount.

var module: SoftPoint


# Call before add_child().
func hold(new_module: SoftPoint) -> void:
	module = new_module
	add_child(module)
	module.transform = Transform2D.IDENTITY
	mass = maxf(module.get_mass(), 0.1)
	radius = module.footprint.size.length() * 0.5


# Hands the module over (to a mount). The prop is empty afterwards: free it.
func release_module() -> SoftPoint:
	var released := module
	remove_child(released)
	module = null
	return released


func get_marker_text() -> String:
	if module == null:
		return ""

	return "Lost %s" % module.get_type_name().to_lower()


# Collision on the footprint, the same rectangle the module had on the ship.
func _build_shape() -> void:
	var rectangle := RectangleShape2D.new()
	rectangle.size = module.footprint.size
	var collision := CollisionShape2D.new()
	collision.shape = rectangle
	collision.position = module.footprint.get_center()
	add_child(collision)


# The module draws itself.
func _draw_prop() -> void:
	pass
