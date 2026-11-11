extends Node

# Visual mockups of the mothership concepts, drawn around the real Bucket in the real level.
# A: rack carrier. C: road train. C1-C4: four looks for the road train, with cars for small,
# medium and large ships. The game is paused once set up.
# Keys: Page Down / Page Up = next / previous view. Each concept has a close and a wide view.

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const MockupDrawing := preload("res://_tools/mothership_mockup_drawing.gd")
const MockupTrains := preload("res://_tools/mothership_mockup_trains.gd")
const MockupTrainsV2 := preload("res://_tools/mothership_mockup_trains_v2.gd")
const MockupTrainsV3 := preload("res://_tools/mothership_mockup_trains_v3.gd")
const MockupTrainsV4 := preload("res://_tools/mothership_mockup_trains_v4.gd")
const MockupTrainsV5 := preload("res://_tools/mothership_mockup_trains_v5.gd")
const MockupTrainsV6 := preload("res://_tools/mothership_mockup_trains_v6.gd")
const CONCEPTS := {
	"A": "A: rack carrier",
	"C": "C: road train",
	"C1": "C1: flatbed freight",
	"C2": "C2: hangar liner",
	"C3": "C3: pod string",
	"C4": "C4: scrap convoy",
	"D1": "D1: flatbeds + dozer blade",
	"D2": "D2: flatbeds + gobbler",
	"D3": "D3: liner + drum cutters",
	"D4": "D4: liner + deflector",
	"E1": "E1: deflector",
	"E2": "E2: spoon bow",
	"E3": "E3: Thyssen-Waas bow",
	"E4": "E4: ice knife + bubbler",
	"F1": "F1: catamaran",
	"F2": "F2: reactor spine",
	"F3": "F3: road locomotive",
	"F4": "F4: heavy tug",
	"G1": "G1: swept",
	"G2": "G2: tandem",
	"G3": "G3: ring",
	"G4": "G4: heavy",
	"H1": "H1: gunmetal and red",
	"H2": "H2: black and yellow",
	"H3": "H3: oxblood",
	"H4": "H4: olive drab",
}

var _main: Node2D
var _ship: RigidBody2D
var _camera: Camera2D
var _hud: CanvasLayer
var _drawings: Dictionary = {}
var _views: Array[Array] = [] # [concept, is_wide]
var _view_index: int = 0
var _label := Label.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.03)) # Space past the placeholder background
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_ship = _main.get_node("Player")
	_camera = _ship.get_node("Camera2D")
	_hud = _main.get_node("HUD")

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_label.position = Vector2(24, 16)
	_label.add_theme_font_size_override(&"font_size", 28)
	_label.add_theme_color_override(&"font_color", Color(0.96, 0.8, 0.36))
	_label.add_theme_color_override(&"font_outline_color", Color(0.06, 0.055, 0.07))
	_label.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(_label)

	_setup.call_deferred()


func _setup() -> void:
	await get_tree().create_timer(0.3).timeout

	for node in get_tree().get_nodes_in_group(Mothership.GROUP):
		node.queue_free()

	for concept in CONCEPTS:
		var drawing: Node2D

		if concept == "A" or concept == "C":
			drawing = MockupDrawing.new()
		elif concept.begins_with("H"):
			drawing = MockupTrainsV6.new()
		elif concept.begins_with("G"):
			drawing = MockupTrainsV5.new()
		elif concept.begins_with("F"):
			drawing = MockupTrainsV4.new()
		elif concept.begins_with("E"):
			drawing = MockupTrainsV3.new()
		elif concept.begins_with("D"):
			drawing = MockupTrainsV2.new()
		else:
			drawing = MockupTrains.new()

		drawing.concept = concept
		drawing.z_index = -1
		drawing.visible = false
		_main.add_child(drawing)
		_main.move_child(drawing, _main.get_node("Background_proto").get_index() + 1) # Over the background
		_drawings[concept] = drawing
		_views.append([concept, false])
		_views.append([concept, true])

	_ship.linear_velocity = Vector2.ZERO
	_ship.angular_velocity = 0.0
	await get_tree().physics_frame

	_camera.top_level = true
	_camera.set(&"min_zoom", 0.05) # The camera script clamps its zoom; the wide shots go below the game's minimum
	_hud.visible = false # The cockpit would hide the bottom of the view
	get_tree().paused = true
	_show_view(0)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey

	if key == null or not key.pressed:
		return

	if key.keycode == KEY_PAGEDOWN:
		_show_view(_view_index + 1)
	elif key.keycode == KEY_PAGEUP:
		_show_view(_view_index - 1)


func _show_view(index: int) -> void:
	_view_index = posmod(index, _views.size())
	var concept: String = _views[_view_index][0]
	var is_wide: bool = _views[_view_index][1]
	_label.text = "%s  (%s)" % [CONCEPTS[concept], "wide" if is_wide else "close"]

	for key in _drawings:
		_drawings[key].visible = key == concept

	# The mothership sits at the origin, bow to the right; the Bucket waits next to its bay.
	var drawing: Node2D = _drawings[concept]
	drawing.global_transform = Transform2D(0.0, Vector2.ZERO)
	var cradle: Transform2D = drawing.get_player_cradle()
	var start: Transform2D = drawing.global_transform * drawing.get_player_approach()
	_ship.global_transform = start
	PhysicsServer2D.body_set_state(_ship.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, start)

	# Rocks outside the hull, still in view
	var rocks := ["Asteroid", "Asteroid2", "Asteroid3"]
	var spots := [Vector2(-650, -560), Vector2(-250, -760), Vector2(250, -620)]

	for i in rocks.size():
		var rock: Node2D = _main.get_node(rocks[i])
		rock.global_position = drawing.to_global(cradle.origin + spots[i])

	var viewport_size := get_viewport().get_visible_rect().size

	if is_wide:
		var extent: Rect2 = drawing.get_extent()
		_camera.global_position = drawing.to_global(extent.get_center())
		var fit := minf(viewport_size.x / extent.size.x, viewport_size.y / extent.size.y)
		_camera.zoom = Vector2.ONE * fit
	else:
		var focus: Vector2 = drawing.get_close_focus() if drawing.has_method(&"get_close_focus") else cradle.origin + Vector2(-60, -20)
		_camera.global_position = drawing.to_global(focus)
		_camera.zoom = Vector2.ONE * (0.6 if concept == "A" or concept == "C" else 0.42)

	_camera.set(&"target_zoom", _camera.zoom) # The camera script eases zoom toward this
