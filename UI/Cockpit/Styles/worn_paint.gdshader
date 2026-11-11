shader_type canvas_item;

// Worn stencil paint: knocks small chips out of whatever it's drawn on (the painted titles).
// Sampled in the node's local space, so the chips stay put when the HUD scales or moves.

uniform sampler2D wear_noise : repeat_enable, filter_linear;
uniform float wear : hint_range(0.0, 1.0) = 0.25; // Higher = more paint gone
uniform float noise_scale = 0.05; // Higher = smaller chips

varying vec2 local_position;


void vertex() {
	local_position = VERTEX;
}


void fragment() {
	float noise = texture(wear_noise, local_position * noise_scale).r;
	COLOR.a *= 1.0 - step(1.0 - wear, noise);
}
