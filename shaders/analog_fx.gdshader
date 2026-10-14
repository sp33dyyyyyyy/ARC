shader_type canvas_item;
// Analog FPV video degradation: horizontal tearing, noise, chroma bleed, scanlines.
// `degrade` rises with distance from the pilot (0 = clean, 1 = lost).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float degrade : hint_range(0.0, 1.0) = 0.0;
uniform float static_only : hint_range(0.0, 1.0) = 0.0;
uniform float tcount = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p.yx + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = clamp(degrade, 0.0, 1.0) * intensity;
	float t = tcount;

	// idle analog softness even when the link is good
	float base = 0.035 * intensity;
	float amt = max(d, base * 0.0);

	// horizontal tearing: bands of rows displaced sideways, more and wider as d rises
	float bands = mix(36.0, 150.0, d);
	float band = floor(uv.y * bands);
	float torn = step(1.0 - (0.04 + 0.6 * d * d), hash21(vec2(band, floor(t * 14.0))));
	float shift = (hash21(vec2(band + 11.0, floor(t * 30.0))) - 0.5) * (0.04 + 0.34 * d) * torn;
	// occasional full-frame sync slip
	float slip = step(0.97 - 0.12 * d, hash21(vec2(floor(t * 4.0), 3.7)));
	shift += slip * (hash21(vec2(floor(t * 4.0), 8.1)) - 0.5) * 0.18 * d;
	// rolling horizontal bar
	float bar_y = fract(t * (0.12 + 0.35 * d));
	float bar = smoothstep(0.06, 0.0, abs(uv.y - bar_y)) * d;
	shift += bar * 0.03 * sin(uv.y * 400.0 + t * 20.0);
	uv.x += shift;

	// chroma bleed
	float ca = (0.0012 + 0.011 * d) * intensity;
	vec3 col;
	col.r = texture(screen_tex, vec2(uv.x + ca, uv.y)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, vec2(uv.x - ca, uv.y)).b;

	// noise grain
	vec2 np = floor(uv * vec2(560.0, 300.0));
	float n = hash21(np + vec2(floor(t * 60.0) * 17.0, floor(t * 60.0) * 31.0));
	float grain = (0.015 + 0.9 * d * d) * intensity;
	col = mix(col, vec3(n), clamp(grain, 0.0, 0.97));
	col += (n - 0.5) * 0.05 * intensity;

	// scanlines
	col *= 1.0 - 0.05 * intensity * (0.5 + 0.5 * sin(uv.y * 1500.0));

	// desaturate and wash out as the signal dies
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g), 0.55 * d);
	col = mix(col, vec3(g * 1.2 + 0.1), 0.25 * d);

	// VTX not configured -> only static
	if (static_only > 0.5) {
		float sn = hash21(floor(SCREEN_UV * vec2(480.0, 270.0)) + vec2(floor(t * 60.0) * 13.0, 7.0));
		float tear = hash21(vec2(floor(SCREEN_UV.y * 40.0), floor(t * 20.0)));
		col = vec3(sn * 0.8 + 0.1 * tear);
	}
	COLOR = vec4(col, 1.0);
}
