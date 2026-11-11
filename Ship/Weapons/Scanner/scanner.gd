class_name Scanner
extends HardpointWeapon

# Hold the fire button: a scan line sweeps back and forth across a narrow cone ahead of the muzzle.
# Wherever the line passes, it sees through every rock on it, however thick. What it picks up
# stays found, in the rock and in the chunks cut from it. Each rock also remembers which of its
# cells the line has crossed (Asteroid.mark_scanned): that is how far the scan has got.
# Two builds (precise, set in the scene):
# - basic: the ore the line crosses shows as a blurry heat map (ScanOverlay). Once it has met
#   ore, the readout lists one to three possible ores; the real one is always among them.
# - precision: the ore cells themselves show up (Asteroid.reveal_ore_cells), and a tech readout
#   gives the ore, how many ore cells have been found and what they are worth.
# Either way, "no ore detected" only shows once the line has covered the whole rock (full_coverage).
# Every rock the line crosses gets its own readout, for readout_linger seconds after the last pass.

const TEXEL: float = 2.0
const FADE_STEPS: int = 8 # Segments in a line that fades out toward the end of the range

@export var precise: bool = false
@export var max_range: float = 1200.0
@export var cone_degrees: float = 16.0 # Full width the line sweeps across
@export var sweep_speed: float = 2.0 # rad/s of the sweep's back-and-forth (sine phase)
@export var band_degrees: float = 1.2 # Full width of the scan line itself: rays are cast inside it
@export var rays_per_frame: int = 6
@export var power_per_second: float = 1.5 # Short on power or damaged: fewer rays
@export var readout_linger: float = 4.0 # s a rock's readout stays after the line last crossed it
@export_range(0.0, 1.0) var full_coverage: float = 0.95 # Share of a rock's cells crossed to call it fully scanned

@export_group("Look")
@export var beam_color: Color = CockpitPalette.YELLOW_LIT
@export var precise_color: Color = Color(0.4, 0.95, 1.0)
@export_range(0.0, 1.0) var fade_start: float = 0.6 # Share of the range where lines start fading out
@export var afterglow_lines: int = 7 # Fading copies of the scan line, trailing behind it
@export var afterglow_spacing_degrees: float = 0.7

var is_scanning: bool = false
var readout_rocks: Dictionary[Asteroid, float] = {} # Rock -> seconds its readout has left

var _phase: float = 0.0 # Sweep phase. The line's angle is sin(_phase) * half the cone
var _time: float = 0.0


func _ready() -> void:
	ScanOverlay.ensure(get_tree())

	var layer := CanvasLayer.new() # Screen space, whatever the ship's rotation
	add_child(layer)

	var readout := ScanReadout.new()
	readout.scanner = self
	layer.add_child(readout)


func _process(delta: float) -> void:
	_time += delta

	for rock in readout_rocks.keys():
		readout_rocks[rock] -= delta

		if readout_rocks[rock] <= 0.0 or not is_instance_valid(rock) or rock.is_queued_for_deletion():
			readout_rocks.erase(rock)

	queue_redraw()


func _physics_process(delta: float) -> void:
	is_scanning = Input.is_action_pressed(fire_action) and get_performance() > 0.0

	if not is_scanning:
		return

	var strength := draw_power(power_per_second * delta) * get_performance()
	_phase += sweep_speed * delta * strength
	var ray_count := ceili(rays_per_frame * strength)

	if ray_count <= 0:
		return

	var from := muzzle.global_position
	var forward := get_forward()
	var rocks := Asteroid.find_near(get_tree(), from + forward * max_range * 0.5, max_range * 0.5)

	if rocks.is_empty():
		return

	var half_band := deg_to_rad(band_degrees) * 0.5
	var sweep_angle := get_sweep_angle()

	for i in ray_count:
		var angle := sweep_angle + randf_range(-half_band, half_band)
		var to := from + forward.rotated(angle) * max_range

		for rock in rocks:
			if not is_instance_valid(rock) or not rock.may_cross(from, to):
				continue

			var hits := rock.get_cells_on_ray(from, to)

			if hits.is_empty():
				continue

			var crossed: Array[Vector2i] = []

			for hit in hits:
				crossed.append(hit["cell"])

			rock.mark_scanned(crossed)

			if precise:
				rock.reveal_ore_cells(crossed)
			else:
				rock.add_heat(crossed)

			readout_rocks[rock] = readout_linger


# Angle of the scan line from the muzzle's axis, in radians.
func get_sweep_angle() -> float:
	return sin(_phase) * deg_to_rad(cone_degrees) * 0.5


# Share of the rock the scan line has crossed, rescaled so full_coverage reads as 1.
func get_progress(rock: Asteroid) -> float:
	return clampf(rock.get_scan_coverage() / full_coverage, 0.0, 1.0)


func is_fully_scanned(rock: Asteroid) -> bool:
	return rock.get_scan_coverage() >= full_coverage


# One to three ores, the real one among them, sorted so its place gives nothing away.
# Seeded by the rock's look, which its chunks inherit: the guesses don't change as it's cut.
func get_probable_ores(rock: Asteroid) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rock.look_seed)

	var others: Array[int] = []

	for ore in CellMaterials.ORES:
		if ore != rock.ore_type:
			others.append(ore)

	var ores: Array[int] = [rock.ore_type]

	for i in rng.randi_range(0, 2):
		ores.append(others.pop_at(rng.randi_range(0, others.size() - 1)))

	ores.sort()
	return ores


# Credits for the ore cells found so far, once refined (one ore cell = one unit).
func get_found_value(rock: Asteroid) -> float:
	return rock.revealed_ore.size() * CellMaterials.get_material(rock.ore_type).value


# --- Look


func _draw() -> void:
	if is_scanning:
		_draw_beam()

	if precise:
		_draw_precise_body()
	else:
		_draw_basic_body()


# Cone edges, the scan line, and fading copies of it trailing behind, like a radar's afterglow.
# Everything fades out toward the end of the range.
func _draw_beam() -> void:
	var color := precise_color if precise else beam_color
	var half_cone := deg_to_rad(cone_degrees) * 0.5
	var sweep_angle := get_sweep_angle()
	var direction := signf(cos(_phase)) # Which way the line is moving
	var edge := color
	edge.a = 0.18
	_draw_fading_ray(-half_cone, edge, 1.0)
	_draw_fading_ray(half_cone, edge, 1.0)

	for i in range(afterglow_lines, 0, -1):
		var angle := sweep_angle - direction * deg_to_rad(afterglow_spacing_degrees) * i

		if absf(angle) > half_cone:
			continue

		var glow := color
		glow.a = 0.28 * (1.0 - float(i) / (afterglow_lines + 1))
		_draw_fading_ray(angle, glow, 2.0)

	var line := color
	line.a = 0.85
	_draw_fading_ray(sweep_angle, line, 2.0)

	if precise:
		# Range rings rolling outward along the cone: the precision build's tell.
		for i in 3:
			var ring := fmod(_time * 0.6 + i / 3.0, 1.0) * max_range
			var ring_color := color
			ring_color.a = 0.25 * _get_fade(ring)
			draw_arc(muzzle.position, ring, -half_cone, half_cone, 8, ring_color, 1.0)


# A line from the muzzle along this angle, solid up to fade_start of the range, then fading out.
func _draw_fading_ray(angle: float, color: Color, width: float) -> void:
	var direction := Vector2.from_angle(angle)
	var points := PackedVector2Array([muzzle.position])
	var colors := PackedColorArray([color])
	var solid := max_range * fade_start
	points.append(muzzle.position + direction * solid)
	colors.append(color)

	for i in range(1, FADE_STEPS + 1):
		var distance := lerpf(solid, max_range, float(i) / FADE_STEPS)
		var faded := color
		faded.a *= _get_fade(distance)
		points.append(muzzle.position + direction * distance)
		colors.append(faded)

	draw_polyline_colors(points, colors, width)


# 1 up to fade_start of the range, then down to 0 at the end, eased.
func _get_fade(distance: float) -> float:
	var fade := clampf(inverse_lerp(max_range, max_range * fade_start, distance), 0.0, 1.0)
	return fade * fade


# The cheap one: a scuffed box on the hull with a hazard stripe, and a small rusty dish on a stalk
# that swings with the scan line. A red lamp blinks while it works.
func _draw_basic_body() -> void:
	var outline := CockpitPalette.OUTLINE
	var box := Rect2(-TEXEL * 2.0, -TEXEL * 3.0, TEXEL * 5.0, TEXEL * 6.0)
	draw_rect(box.grow(TEXEL * 0.5), outline)
	draw_rect(box, CockpitPalette.STEEL)
	draw_rect(Rect2(box.position, Vector2(box.size.x, TEXEL)), CockpitPalette.STEEL.lightened(0.15))

	# Hazard stripe along the back of the box.
	for i in 3:
		var stripe := CockpitPalette.YELLOW if i % 2 == 0 else outline
		draw_rect(Rect2(box.position.x, box.position.y + TEXEL * 2.0 * i, TEXEL, TEXEL * 2.0), stripe)

	var lamp := CockpitPalette.ALARM if is_scanning and int(_time * 4.0) % 2 == 0 else CockpitPalette.LED_OFF
	draw_rect(Rect2(TEXEL, -TEXEL * 2.0, TEXEL, TEXEL), lamp)

	# Stalk, then the dish, turned toward the scan line.
	var pivot := Vector2(muzzle.position.x - TEXEL * 2.5, 0.0)
	draw_rect(Rect2(box.end.x, -TEXEL * 0.5, pivot.x - box.end.x, TEXEL), outline)
	draw_set_transform(pivot, get_sweep_angle() * 1.5 if is_scanning else 0.0)
	draw_rect(Rect2(-TEXEL * 0.5, -TEXEL * 3.5, TEXEL * 2.0, TEXEL * 7.0), outline)
	draw_rect(Rect2(0.0, -TEXEL * 3.0, TEXEL, TEXEL * 6.0), CockpitPalette.PRIMER)
	draw_rect(Rect2(TEXEL, -TEXEL * 1.5, TEXEL, TEXEL * 3.0), CockpitPalette.RUST)
	draw_rect(Rect2(TEXEL * 1.5, -TEXEL * 0.5, TEXEL * 1.5, TEXEL), outline) # Feed horn
	draw_set_transform(Vector2.ZERO)


# The expensive one: a dark sealed housing with a lit lens strip and status lights.
func _draw_precise_body() -> void:
	var housing := Rect2(-TEXEL * 2.0, -TEXEL * 2.5, muzzle.position.x + TEXEL * 2.0, TEXEL * 5.0)
	draw_rect(housing.grow(TEXEL * 0.5), CockpitPalette.OUTLINE)
	draw_rect(housing, Color(0.16, 0.18, 0.21))
	draw_rect(Rect2(housing.position, Vector2(housing.size.x, TEXEL)), Color(0.27, 0.3, 0.34))

	var lens := precise_color if is_scanning else precise_color.darkened(0.5)
	draw_rect(Rect2(housing.end.x - TEXEL, housing.position.y + TEXEL, TEXEL, housing.size.y - TEXEL * 2.0), lens)

	for i in 3:
		var is_lit := is_scanning and int(_time * 6.0) % 3 == i
		var light := precise_color if is_lit else Color(0.1, 0.25, 0.3)
		draw_rect(Rect2(TEXEL * (i * 2.0), TEXEL * 1.0, TEXEL, TEXEL), light)
