extends RefCounted

# Draws a top-down map of what an AsteroidField would spawn, from its planner (no nodes, no
# blueprints): density in blue, rocks to scale, barren ones grey, ore-bearing ones in the colour
# of their ore. For tuning AsteroidFieldProfile values.
# From a running game (debugger or an MCP eval):
#   load("res://_tools/field_map.gd").render($AsteroidField, "res://_tools/field_map.png")

const ORE_COLORS := {
	CellMaterials.Id.WATER_ICE: Color(0.5, 0.8, 1.0),
	CellMaterials.Id.NICKEL_IRON: Color(0.85, 0.5, 0.35),
	CellMaterials.Id.COBALT: Color(0.3, 0.5, 1.0),
	CellMaterials.Id.GOLD: Color(1.0, 0.8, 0.2),
	CellMaterials.Id.PLATINUM: Color(0.95, 0.95, 1.0),
}
const BARREN_COLOR := Color(0.55, 0.52, 0.5)


# Sectors from first to last (included). scale: map pixels per world px.
static func render(field: AsteroidField, path: String, first := Vector2i(-6, -4), last := Vector2i(5, 3), scale := 0.04) -> Dictionary:
	var planner := field._make_planner()
	var sector_size := planner.profile.sector_size
	var origin := Vector2(first) * sector_size
	var sectors := last - first + Vector2i.ONE
	var image := Image.create_empty(int(sectors.x * sector_size * scale), int(sectors.y * sector_size * scale), false, Image.FORMAT_RGB8)

	for x in image.get_width():
		for y in image.get_height():
			var density := planner.get_density(origin + Vector2(x, y) / scale)
			image.set_pixel(x, y, Color(0.03, 0.03 + density * 0.08, 0.06 + density * 0.12))

	var rocks := 0
	var with_ore := 0

	for sx in range(first.x, last.x + 1):
		for sy in range(first.y, last.y + 1):
			for spec in planner.plan_sector(Vector2i(sx, sy)):
				rocks += 1
				var color := BARREN_COLOR

				if spec.ore_ratio > 0.0:
					color = ORE_COLORS[spec.ore_type]
					with_ore += 1

				_draw_disc(image, (spec.position - origin) * scale, maxf(spec.radius_in_cells * field._cell_size * scale, 0.6), color)

	image.save_png(path)
	return { "rocks": rocks, "with_ore": with_ore }


static func _draw_disc(image: Image, center: Vector2, radius: float, color: Color) -> void:
	var reach := ceili(radius)

	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			if Vector2(dx, dy).length() > radius:
				continue

			var pixel := Vector2i(int(center.x) + dx, int(center.y) + dy)

			if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height():
				image.set_pixelv(pixel, color)
