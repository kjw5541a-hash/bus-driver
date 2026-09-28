extends Node3D
class_name Atmosphere
# 해(DirectionalLight3D)와 하늘(ProceduralSky). 태양 고도에 따라 색을 섞고,
# 고도 -6°~+10° 에서 노을을 낸다. 해가 지면 같은 조명을 약한 달빛으로 쓴다
# — 빛 하나로 그림자를 계속 낸다.

const MOON_ELEVATION_DEG := 50.0
const MOON_AZIMUTH_DEG := 200.0
const RAIN_GREY := Color(0.36, 0.38, 0.41)
const RAIN_SUN_CUT := 0.6       # 비 1 에서 햇빛을 이만큼 줄인다
const RAIN_FOG_DENSITY := 0.006
const SHADOW_DISTANCE_M := 200.0

# [고도°, 하늘 위, 지평선, 햇빛 색, 햇빛 에너지, 주변광 에너지]
const KEYS := [
	[-12.0, Color(0.01, 0.015, 0.04), Color(0.03, 0.04, 0.08), Color(0.6, 0.7, 1.0), 0.08, 0.12],
	[-6.0, Color(0.05, 0.07, 0.18), Color(0.35, 0.2, 0.25), Color(0.7, 0.7, 1.0), 0.1, 0.2],
	[0.0, Color(0.2, 0.25, 0.5), Color(1.0, 0.45, 0.2), Color(1.0, 0.45, 0.2), 0.6, 0.35],
	[5.0, Color(0.3, 0.4, 0.7), Color(1.0, 0.6, 0.35), Color(1.0, 0.65, 0.4), 0.9, 0.5],
	[10.0, Color(0.35, 0.5, 0.8), Color(0.9, 0.75, 0.6), Color(1.0, 0.85, 0.7), 1.1, 0.6],
	[20.0, Color(0.3, 0.5, 0.85), Color(0.7, 0.8, 0.9), Color(1.0, 0.98, 0.95), 1.3, 0.7],
]

var sun: DirectionalLight3D
var environment: Environment
var _sky: ProceduralSkyMaterial

func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = SHADOW_DISTANCE_M
	add_child(sun)
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

static func palette(elevation_deg: float, rain: float) -> Dictionary:
	var low: Array = KEYS[0]
	var high: Array = KEYS[-1]
	for index in KEYS.size() - 1:
		if elevation_deg >= KEYS[index][0] and elevation_deg <= KEYS[index + 1][0]:
			low = KEYS[index]
			high = KEYS[index + 1]
			break
	var t := 0.0
	if high[0] > low[0]:
		t = clampf((elevation_deg - low[0]) / (high[0] - low[0]), 0.0, 1.0)
	var out := {
		"sky_top": (low[1] as Color).lerp(high[1], t),
		"horizon": (low[2] as Color).lerp(high[2], t),
		"sun_color": (low[3] as Color).lerp(high[3], t),
		"sun_energy": lerpf(low[4], high[4], t),
		"ambient": lerpf(low[5], high[5], t),
	}
	# 비는 하늘을 회색으로 덮고 해를 가린다. 밤하늘은 원래 어두워 덜 섞는다.
	var grey := RAIN_GREY * clampf(out["ambient"] / 0.7, 0.1, 1.0)
	out["sky_top"] = (out["sky_top"] as Color).lerp(grey, rain * 0.8)
	out["horizon"] = (out["horizon"] as Color).lerp(grey, rain * 0.8)
	out["sun_energy"] = out["sun_energy"] * (1.0 - RAIN_SUN_CUT * rain)
	return out

func apply(elevation_deg: float, azimuth_deg: float, rain: float) -> void:
	var colors := palette(elevation_deg, rain)
	var toward := SunPath.direction(elevation_deg, azimuth_deg)
	if elevation_deg < 0.0:
		toward = SunPath.direction(MOON_ELEVATION_DEG, MOON_AZIMUTH_DEG)
	# 빛은 해에서 땅으로 가므로 조명의 -Z 가 해 반대쪽을 보게 한다. 서울의 최대
	# 고도는 76° 라 UP 과 평행해질 일이 없다.
	sun.global_transform = Transform3D(Basis.looking_at(-toward, Vector3.UP), Vector3.ZERO)
	sun.light_color = colors["sun_color"]
	sun.light_energy = colors["sun_energy"]
	_sky.sky_top_color = colors["sky_top"]
	_sky.sky_horizon_color = colors["horizon"]
	_sky.ground_horizon_color = colors["horizon"]
	_sky.ground_bottom_color = (colors["sky_top"] as Color).darkened(0.5)
	environment.ambient_light_energy = colors["ambient"]
	environment.fog_enabled = rain > 0.01
	environment.fog_light_color = colors["horizon"]
	environment.fog_density = RAIN_FOG_DENSITY * rain
