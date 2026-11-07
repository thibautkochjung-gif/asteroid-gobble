extends Node

# Dev tool: runs main.tscn, then saves a few screenshots to _tools/ and quits.
# Run this scene (not main) to refresh the captures.

const MAIN_SCENE: PackedScene = preload("res://main.tscn")

# Camera position (global) and zoom for each shot.
var shots: Array[Dictionary] = [
	{ "name": "wide", "at": Vector2(300, 100), "zoom": 0.8 },
	{ "name": "ship", "at": Vector2(0, 0), "zoom": 3.0 },
	{ "name": "asteroid", "at": Vector2(450, 0), "zoom": 3.0 },
	{ "name": "big_asteroid", "at": Vector2(750, 320), "zoom": 2.0 },
	{ "name": "mockup_base", "at": Vector2(150, 0), "zoom": 2.0, "clean": true }, # No asteroids, no HUD
]


func _ready() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child(main)

	var camera := Camera2D.new()
	main.add_child(camera)
	camera.make_current()

	for _i in 20:
		await get_tree().process_frame

	_cut_tunnel(main.get_node("Asteroid3") as Asteroid)
	_slice(main.get_node("Asteroid") as Asteroid)

	for _i in 5:
		await get_tree().process_frame

	var player := main.get_node("Player") as Node2D

	for shot in shots:
		var at: Vector2 = shot["at"]

		if shot["name"] == "ship":
			at = player.global_position

		if shot.get("clean", false):
			at = player.global_position + at
			main.get_node("HUD").visible = false

			for asteroid in get_tree().get_nodes_in_group(Asteroid.GROUP):
				asteroid.visible = false

		camera.global_position = at
		camera.zoom = Vector2.ONE * shot["zoom"]

		for _i in 3:
			await get_tree().process_frame

		var image := get_viewport().get_texture().get_image()
		image.save_png("res://_tools/capture_%s.png" % shot["name"])

	get_tree().quit()


# A horizontal tunnel, two cells high, from the left edge to the centre, like a laser cut.
func _cut_tunnel(asteroid: Asteroid) -> void:
	var cells: Array[Vector2i] = []
	cells.assign(asteroid.cells.keys())

	for cell in cells:
		if cell.x < 0 and cell.y >= 2 and cell.y <= 3:
			asteroid.remove_cell(cell)


# A vertical cut right through the asteroid: the right part breaks off as a chunk.
func _slice(asteroid: Asteroid) -> void:
	var cells: Array[Vector2i] = []
	cells.assign(asteroid.cells.keys())

	for cell in cells:
		if cell.x >= 8 and cell.x <= 9:
			asteroid.remove_cell(cell)
