shader_type canvas_item;

// Draws an asteroid from two textures that Asteroid keeps up to date:
// - look: one pixel per texel (a cell is 2x2 texels). RGB = the texel's colour.
//   A = crater shade (1 = no crater), applied only in the core.
// - cells: one pixel per cell, with a one-cell empty margin around the rock.
//   R = the cell is filled. G = the cell is in the core (deeper than the visible layers).
// Asteroid draws a single rectangle over the whole grid; this shader decides every texel:
// rock, outline, or nothing.

uniform sampler2D look : filter_nearest;
uniform sampler2D cells : filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.06, 0.055, 0.07, 1.0);
uniform float core_shade = 0.6;
uniform float edge_shade = 0.72;

const int TEXELS_PER_CELL = 2;


bool is_filled(ivec2 cell) {
	ivec2 grid_size = textureSize(cells, 0);

	if (cell.x < 0 || cell.y < 0 || cell.x >= grid_size.x || cell.y >= grid_size.y) {
		return false;
	}

	return texelFetch(cells, cell, 0).r > 0.5;
}


void fragment() {
	ivec2 look_size = textureSize(look, 0);
	ivec2 texel = clamp(ivec2(floor(UV * vec2(look_size))), ivec2(0), look_size - 1);
	ivec2 cell = texel / TEXELS_PER_CELL;

	// Which side of its cell this texel sits on: -1 or +1 on each axis.
	ivec2 side = (texel - cell * TEXELS_PER_CELL) * 2 - 1;
	bool is_side_x_filled = is_filled(cell + ivec2(side.x, 0));
	bool is_side_y_filled = is_filled(cell + ivec2(0, side.y));

	if (!is_filled(cell)) {
		// Empty cell: outline where this texel touches rock, nothing elsewhere.
		if (!is_side_x_filled && !is_side_y_filled) {
			discard;
		}

		COLOR = outline_color;
	} else {
		vec4 texel_look = texelFetch(look, texel, 0);
		vec3 color = texel_look.rgb;

		if (texelFetch(cells, cell, 0).g > 0.5) {
			color *= core_shade * texel_look.a;
		}

		// Inner edge: texels next to open space are a little darker.
		if (!is_side_x_filled || !is_side_y_filled) {
			color *= edge_shade;
		}

		COLOR = vec4(color, 1.0);
	}
}
