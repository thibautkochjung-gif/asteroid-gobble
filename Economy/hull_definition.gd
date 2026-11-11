class_name HullDefinition
extends Resource

# A hull the ship yard sells (or the one the player starts with). The scene must follow the hull
# layout described in ShipLoadout.
# The scene is stored as a path and loaded on demand: economy.tres is preloaded by GameState at
# startup, and a PackedScene here would drag every hull and its scripts into that preload.

@export var id: StringName = &"bucket"
@export var display_name: String = "The Bucket"
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String = ""
@export var price: int = 8000


func get_scene() -> PackedScene:
	return load(scene_path)
