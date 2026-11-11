shader_type canvas_item;
render_mode unshaded;

// Full-screen speed overlay, driven by SpeedFx.
// - Blur: the edges of the view smear along the ship's velocity. The middle, where the ship is,
//   stays sharp.
// - Vignette: the rim darkens as speed builds, which narrows the eye onto the ship.
// - Danger: the rim glows alarm orange and pulses.
// Sits on a CanvasLayer between the world and the HUD, so the HUD never blurs.

const int SAMPLES = 10;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 blur_vector = vec2(0.0); // UV. Direction and full length of the smear
uniform float speed_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float danger : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float clear_radius = 0.2; // Share of screen height around the middle that never blurs
uniform float vignette_strength = 0.35;
uniform float glow_strength = 0.4;
uniform vec4 danger_color : source_color = vec4(0.89, 0.33, 0.11, 1.0);


void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float edge = length((SCREEN_UV - 0.5) * aspect); // 0 in the middle, 0.5 at the top and bottom edges
	float blur_mask = smoothstep(clear_radius, clear_radius + 0.3, edge);

	vec2 smear = blur_vector * blur_mask;
	vec2 sample_step = smear / float(SAMPLES - 1);
	vec2 start = SCREEN_UV - smear * 0.5;
	vec3 color = vec3(0.0);

	for (int i = 0; i < SAMPLES; i++) {
		color += texture(screen_texture, start + sample_step * float(i)).rgb;
	}

	color /= float(SAMPLES);

	float rim = smoothstep(0.3, 0.75, edge);
	color *= 1.0 - rim * vignette_strength * speed_ratio;

	float glow = rim * danger * mix(0.55, 1.0, pulse) * glow_strength;
	color = mix(color, danger_color.rgb, glow);

	COLOR = vec4(color, 1.0);
}
