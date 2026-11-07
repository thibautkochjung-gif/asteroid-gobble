shader_type canvas_item;
render_mode blend_add, unshaded;

// Set per instance by ThrusterFX (the material is local to each scene instance)
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float time_offset = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0; // 0 = just ignited, 1 = has been firing long enough to be at full burn

// Colours, from the hot centre to the cool edge
uniform vec4 core_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform vec4 outer_color : source_color = vec4(0.85, 0.12, 0.04, 1.0);
uniform float brightness = 1.3;

// Burn: how the plume changes as the thruster keeps firing
uniform float cold_size : hint_range(0.1, 1.0) = 1.0; // Plume length and width at ignition, as a fraction of full burn. 1 = no growth
uniform vec4 hot_mid_color : source_color = vec4(1.0, 0.55, 0.15, 1.0); // Replaces mid_color at full burn
uniform vec4 hot_outer_color : source_color = vec4(0.85, 0.12, 0.04, 1.0); // Replaces outer_color at full burn

// Shape. UV.x is 0 at the nozzle and 1 at the far end of the sprite
uniform float nozzle_width : hint_range(0.05, 1.0) = 0.7; // Plume width at the nozzle, as a fraction of sprite height
uniform float flare : hint_range(1.0, 4.0) = 1.0; // Above 1, the plume widens after the nozzle (cold gas puff)
uniform float swell_end : hint_range(0.05, 1.0) = 1.0; // Where along the plume the widening from flare is complete
uniform float swell_round : hint_range(1.0, 4.0) = 1.0; // 1 = the plume widens in a straight line, above 1 = rounded shoulder (spindle shape)
uniform float taper : hint_range(0.1, 3.0) = 0.6; // How fast the plume closes towards its tip
uniform float min_length : hint_range(0.0, 1.0) = 0.3; // Plume length at very low strength

// Motion
uniform float flicker : hint_range(0.0, 0.5) = 0.12; // How much the plume length wobbles
uniform float flicker_speed = 20.0;
uniform float scroll_speed = 2.0; // How fast the turbulence travels away from the nozzle
uniform float distortion : hint_range(0.0, 1.0) = 0.35; // How much the noise bends the plume edges


void fragment() {
	float t = TIME + time_offset;

	// The plume grows from cold_size to full size as burn builds up
	float burn_curve = smoothstep(0.0, 1.0, burn);
	float size = mix(cold_size, 1.0, burn_curve);

	// Plume length follows strength and burn, and the tail flickers
	float wobble = 0.5 + 0.25 * sin(t * flicker_speed) + 0.25 * sin(t * flicker_speed * 2.3 + 1.7);
	float plume_length = mix(min_length, 1.0, strength) * size * (1.0 - flicker * wobble);

	// Turbulence: the sprite texture is a seamless noise, scrolled away from the nozzle
	float noise = texture(TEXTURE, vec2(UV.x - t * scroll_speed, UV.y + t * 0.3)).r - 0.5;

	// x: 0 at the nozzle, 1 at the plume tip. y: 0 on the axis, 1 at the sprite edge
	float x = UV.x / plume_length + noise * distortion * UV.x;
	float y = abs(UV.y - 0.5) * 2.0;

	// d: below 1 inside the plume
	// The plume widens from the nozzle up to swell_end, then taper closes it towards the tip
	float swell = 1.0 - pow(1.0 - clamp(x / swell_end, 0.0, 1.0), swell_round);
	float half_width = nozzle_width * size * mix(1.0, flare, swell) * pow(max(1.0 - x, 0.0), taper);
	float d = y / max(half_width, 0.001) + noise * distortion;

	float body = (1.0 - smoothstep(0.5, 1.0, d)) * (1.0 - smoothstep(0.6, 1.0, x));
	float ignition = smoothstep(0.0, 0.3, strength);

	// Heat is highest on the axis next to the nozzle
	float heat = clamp((1.0 - d) * (1.0 - x), 0.0, 1.0);
	vec3 outer = mix(outer_color.rgb, hot_outer_color.rgb, burn_curve);
	vec3 mid = mix(mid_color.rgb, hot_mid_color.rgb, burn_curve);
	vec3 color = mix(outer, mid, smoothstep(0.0, 0.35, heat));
	color = mix(color, core_color.rgb, smoothstep(0.35, 0.8, heat));

	COLOR = vec4(color * brightness, body * ignition);
}
