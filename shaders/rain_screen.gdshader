shader_type canvas_item;
// 화면에 맺힌 빗방울. 칸마다 방울 하나를 두고 wetness 가 클수록 더 많은 칸에
// 방울이 생긴다. 방울 자리는 뒤 화면을 굴절시키고, 전체를 흐리게 한다.
// wipe_x 보다 왼쪽은 와이퍼가 막 쓸고 간 자리라 맑다.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float wetness = 0.0;
uniform float wipe_x = 0.0;
uniform float seed = 0.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float wet = wetness * step(wipe_x, uv.x);
	vec2 grid = uv * vec2(24.0, 14.0);
	vec2 cell = floor(grid) + seed;
	vec2 d = fract(grid) - (0.2 + 0.6 * hash2(cell));
	float radius = 0.12 + 0.25 * hash2(cell + 7.0).x;
	float present = step(1.0 - wet, hash2(cell + 3.0).y);
	float drop = present * smoothstep(radius, radius * 0.6, length(d));
	vec3 color = textureLod(screen_tex, uv - d * drop * 0.04, wet * 2.5).rgb;
	COLOR = vec4(color, 1.0);
}
