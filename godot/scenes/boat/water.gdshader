shader_type spatial;
// Calm lake: gentle moving waves, depth-like colour and a fresnel sheen.
render_mode cull_disabled;

uniform vec3 shallow : source_color = vec3(0.16, 0.42, 0.52);
uniform vec3 deep : source_color = vec3(0.05, 0.18, 0.30);
uniform float wave_height = 0.08;
uniform float wave_scale = 0.35;

float wave(vec2 p, float t) {
	return sin(p.x * wave_scale + t * 0.9) * 0.5
		+ sin((p.x + p.y) * wave_scale * 1.7 - t * 1.3) * 0.3
		+ sin(p.y * wave_scale * 2.3 + t * 0.7) * 0.2;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += wave(world.xz, TIME) * wave_height;
	float e = 0.1;
	float dx = wave(world.xz + vec2(e, 0.0), TIME) - wave(world.xz - vec2(e, 0.0), TIME);
	float dz = wave(world.xz + vec2(0.0, e), TIME) - wave(world.xz - vec2(0.0, e), TIME);
	NORMAL = normalize(vec3(-dx * wave_height / (2.0 * e), 1.0, -dz * wave_height / (2.0 * e)));
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep, shallow, 0.5 + 0.5 * fresnel);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
