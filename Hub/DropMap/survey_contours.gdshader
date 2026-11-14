shader_type canvas_item;

// Draws the survey's value texture (red channel, 0-1) as filled contour bands with lines on their
// edges, like a chart. Values under the first band stay transparent.

uniform float bands = 5.0;
uniform vec4 fill_color : source_color = vec4(0.83, 0.64, 0.16, 1.0);
uniform vec4 line_color : source_color = vec4(0.96, 0.8, 0.36, 1.0);
uniform float max_fill = 0.45; // Opacity of the top band

void fragment() {
	float scaled = texture(TEXTURE, UV).r * bands;
	float band = floor(scaled);
	float fill = band / bands * max_fill;

	// Distance to the nearest band edge, in band units, against how much that is on screen.
	float edge = abs(fract(scaled + 0.5) - 0.5);
	float width = max(fwidth(scaled), 0.0001);
	float line = 1.0 - smoothstep(width * 0.6, width * 1.6, edge);
	line *= step(0.5, scaled);
	float line_alpha = line * mix(0.35, 0.95, clamp(scaled / bands, 0.0, 1.0));

	COLOR = mix(vec4(fill_color.rgb, fill), vec4(line_color.rgb, 1.0), line_alpha);
}
