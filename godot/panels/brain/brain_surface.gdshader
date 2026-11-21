shader_type spatial;
// Brain surface coloured per vertex (sRGB colour; alpha = activity strength).
// Active areas glow, and the glow of the brain viewport blurs them into halos.
render_mode cull_disabled;

uniform float glow = 3.0;

void fragment() {
	vec3 colour = pow(COLOR.rgb, vec3(2.2));  // sRGB to linear
	ALBEDO = colour;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	EMISSION = colour * COLOR.a * glow;
}
