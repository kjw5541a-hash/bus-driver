extends TestCase
# 비 세기 전환과 그 효과.

func _ready() -> void:
	var weather := Weather.new()
	add_child(weather)
	weather.start(1)
	weather.rain = 0.0
	weather.step(Weather.RAMP_S / 2.0)
	equal_approx(weather.rain, 0.5, 0.01, "30초 전환의 중간")
	weather.step(Weather.RAMP_S)
	equal_approx(weather.rain, 1.0, 0.001, "비가 다 안 찼다")
	weather.step(600.0)
	equal_approx(weather.rain, 1.0, 0.001, "고정인데 비가 그쳤다")
	weather.start(-1)
	var changed := false
	var first := weather.rain
	for i in 1200:
		weather.step(1.0)
		ok(weather.rain >= 0.0 and weather.rain <= 1.0, "세기가 범위 밖")
		if absf(weather.rain - first) > 0.5:
			changed = true
	ok(changed, "20분 동안 날씨가 한 번도 안 바뀌었다")
	ok(Weather.rain_from_args(PackedStringArray(["--rain=1"])) == 1, "--rain=1")
	ok(Weather.rain_from_args(PackedStringArray(["--rain=0"])) == 0, "--rain=0")
	ok(Weather.rain_from_args(PackedStringArray(["--rain=x"])) == -1, "--rain=x")
	ok(Weather.rain_from_args(PackedStringArray()) == -1, "인자 없음")

	var bus := Bus.new()
	add_child(bus)
	bus.set_wet(1.0)
	for wheel in bus.find_children("*", "VehicleWheel3D", false, false):
		equal_approx(wheel.wheel_friction_slip, Bus.WET_GRIP, 0.001, "젖은 바퀴 마찰")
	bus.set_wet(0.0)
	for wheel in bus.find_children("*", "VehicleWheel3D", false, false):
		equal_approx(wheel.wheel_friction_slip, Bus.DRY_GRIP, 0.001, "마른 바퀴 마찰")

	var dry := CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, INF, TrafficSignal.Phase.GREEN, 1.0)
	var wet := CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, INF, TrafficSignal.Phase.GREEN, 1.0,
		CarFollow.CRUISE_MPS * 0.75)
	ok(wet < dry, "비 오는데 순항 속도가 그대로")

	var city := City.new()
	add_child(city)
	city.load_city("seoul-seodaemun03")
	ok(not city.road_materials().is_empty(), "도로 재질을 못 찾았다")
	city.set_wet(1.0)
	for material in city.road_materials():
		equal_approx(material.roughness, City.WET_ROUGHNESS, 0.001, "젖은 도로 반사")
	city.set_wet(0.0)
	for material in city.road_materials():
		equal_approx(material.roughness, City.DRY_ROUGHNESS, 0.001, "마른 도로")
	finish()
