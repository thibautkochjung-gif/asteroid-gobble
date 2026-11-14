class_name FieldShip
extends RefCounted

# Puts the right hull in the field scene before it starts.
# main.tscn has a Bucket as "Player", and many nodes point into it through exported references
# (the HUD, the pause menu, the dispatch, RunLink...). swap() replaces it with another hull scene and
# moves every one of those references to the node with the same path in the new ship: hull scenes
# all share the same layout (see ShipLoadout), so "Rooms" or "Thrusters/Back Main" exist in each.
# Call it on a freshly instantiated field scene, before it enters the tree: the nodes' _ready()
# then see the new ship as if it had always been there.

const PLAYER_NAME: StringName = &"Player"


static func swap(field: Node, hull_scene: PackedScene) -> void:
	var old_ship := field.get_node(NodePath(PLAYER_NAME)) as Node2D

	if old_ship.scene_file_path == hull_scene.resource_path:
		return # Already the right hull

	old_ship.name = &"OldPlayer" # Frees the name: two siblings can't share it, Godot would rename the new ship
	var new_ship := hull_scene.instantiate() as Node2D
	new_ship.name = PLAYER_NAME
	new_ship.transform = old_ship.transform
	var parent := old_ship.get_parent()
	parent.add_child(new_ship)
	parent.move_child(new_ship, old_ship.get_index())

	var missing: PackedStringArray = []

	for node in _get_all_nodes(field):
		if node == old_ship or old_ship.is_ancestor_of(node) or node == new_ship or new_ship.is_ancestor_of(node):
			continue

		for property in node.get_property_list():
			if not property.usage & PROPERTY_USAGE_STORAGE:
				continue

			var value: Variant = node.get(property.name)

			if value is Node:
				var target := _remap(value, old_ship, new_ship, missing)

				if target != value:
					node.set(property.name, target)
			elif value is Array and property.type == TYPE_ARRAY:
				var changed := false
				var items: Array = value.duplicate()

				for i in items.size():
					if items[i] is Node:
						var target := _remap(items[i], old_ship, new_ship, missing)
						changed = changed or target != items[i]
						items[i] = target

				if changed:
					node.set(property.name, items)

	for path in missing:
		push_warning("FieldShip: the new hull has no %s" % path)

	parent.remove_child(old_ship)
	old_ship.free()

	_restore_ready_order(parent, new_ship)


# Godot readies siblings in the order they were *added*, not their index in the tree: move_child()
# doesn't change it. The new ship was added last, so it would get its _ready() after the HUD, the
# pause menu... which read it in theirs. Re-adding the siblings that come after it puts them back
# behind it. Only safe here, before the field enters the tree (no exit/enter notifications).
static func _restore_ready_order(parent: Node, new_ship: Node) -> void:
	var after: Array[Node] = []

	for child in parent.get_children():
		if child.get_index() > new_ship.get_index():
			after.append(child)

	for child in after:
		var child_owner := child.owner
		child.owner = null # Godot warns if a node is re-added with its owner still set
		parent.remove_child(child)
		parent.add_child(child)
		child.owner = child_owner


# The node with the same path in the new ship, or `node` itself if it isn't in the old ship.
static func _remap(node: Node, old_ship: Node, new_ship: Node, missing: PackedStringArray) -> Node:
	if node != old_ship and not old_ship.is_ancestor_of(node):
		return node

	var path := old_ship.get_path_to(node)
	var target := new_ship.get_node_or_null(path)

	if target == null and not missing.has(str(path)):
		missing.append(str(path))

	return target


static func _get_all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]

	for child in root.get_children():
		out.append_array(_get_all_nodes(child))

	return out
