shader_type spatial;
// Brain surface in the style of a functional scan: a lit grey cortex (its folds
// stay visible) with coloured blobs on top. Vertex colour = blob colour (sRGB),
// vertex alpha = blob opacity.
render_mode cull_disabled;

uniform vec3 cortex : source_color = vec3(0.55, 0.57, 0.62);
uniform float blob_light = 0.35;

void fragment() {
	vec3 blob = pow(COLOR.rgb, vec3(2.2));  // sRGB to linear
	ALBEDO = mix(cortex, blob, COLOR.a);
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	EMISSION = blob * COLOR.a * blob_light;  // a little light of their own
}
