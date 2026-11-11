shader_type canvas_item;

// Pixel art at any scale. Each texel is drawn as a solid square and only its edges are blended,
// over one screen pixel, so every texel comes out the same size even when the scale isn't a whole
// number. (With plain nearest filtering at 0.9× or 1.5×, some columns are a screen pixel wider than
// their neighbours, which makes lines and lettering look uneven.)
// The node using it must have texture_filter set to linear.

varying vec4 tint;


void vertex() {
	tint = COLOR;
}


void fragment() {
	vec2 texture_size = vec2(textureSize(TEXTURE, 0));
	vec2 texel = UV * texture_size;
	vec2 seam = floor(texel + 0.5);
	vec2 texels_per_pixel = max(fwidth(texel), vec2(0.0001));
	texel = seam + clamp((texel - seam) / texels_per_pixel, -0.5, 0.5);
	COLOR = texture(TEXTURE, texel / texture_size) * tint;
}
