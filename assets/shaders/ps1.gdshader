shader_type spatial;
render_mode cull_disabled, specular_disabled, diffuse_lambert;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float snap_resolution = 160.0;
uniform float affine_strength = 0.6;

varying vec3 affine_uv;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 grid = vec2(snap_resolution, snap_resolution * VIEWPORT_SIZE.y / VIEWPORT_SIZE.x);
	clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	POSITION = clip;
	affine_uv = vec3(UV * clip.w, clip.w);
}

void fragment() {
	vec2 uv = mix(UV, affine_uv.xy / affine_uv.z, affine_strength);
	ALBEDO = texture(albedo_texture, uv).rgb;
}
