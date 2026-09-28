extends TestCase
# 하늘 색 보간과 조명 방향.

func _ready() -> void:
	var sunset := Atmosphere.palette(0.0, 0.0)
	ok(sunset["horizon"].r > sunset["horizon"].b + 0.3, "고도 0 에 노을이 없다 %s" % sunset["horizon"])
	var noon := Atmosphere.palette(60.0, 0.0)
	var night := Atmosphere.palette(-15.0, 0.0)
	ok(night["sun_energy"] < noon["sun_energy"] * 0.2, "밤이 충분히 어둡지 않다")
	ok(noon["horizon"].b >= noon["horizon"].r, "한낮 지평선이 붉다")
	var wet := Atmosphere.palette(60.0, 1.0)
	ok(wet["sun_energy"] < noon["sun_energy"], "비 오는데 햇빛이 그대로다")
	# 키 사이는 연속이다.
	var a := Atmosphere.palette(2.49, 0.0)
	var b := Atmosphere.palette(2.51, 0.0)
	equal_approx(a["sun_energy"], b["sun_energy"], 0.01, "보간이 끊긴다")

	var atmosphere := Atmosphere.new()
	add_child(atmosphere)
	atmosphere.apply(30.0, 180.0, 0.0)
	# DirectionalLight 는 -Z 로 비춘다. 남쪽 하늘의 해는 북쪽(-Z)·아래로 비춘다.
	var forward := -atmosphere.sun.global_basis.z
	ok(forward.y < 0.0 and forward.z < 0.0, "낮 빛 방향 %s" % forward)
	atmosphere.apply(-20.0, 330.0, 0.0)
	forward = -atmosphere.sun.global_basis.z
	ok(forward.y < 0.0, "밤에 빛이 땅 밑에서 올라온다 %s" % forward)
	ok(atmosphere.sun.shadow_enabled, "그림자가 꺼졌다")
	# 해가 지평선을 넘는 순간 땅 조도가 튀면 안 된다.
	var lux := func(elevation: float) -> float:
		atmosphere.apply(elevation, 270.0, 0.0)
		return atmosphere.sun.light_energy * maxf(0.0, -(-atmosphere.sun.global_basis.z).y)
	var above: float = lux.call(0.1)
	var below: float = lux.call(-0.1)
	ok(absf(above - below) < 0.1, "일몰 순간 조도가 튄다 %.3f → %.3f" % [above, below])
	equal_approx(atmosphere.sun.light_energy, Atmosphere.MOON_ENERGY, 0.001, "달빛 세기")
	atmosphere.apply(30.0, 180.0, 1.0)
	ok(atmosphere.environment.fog_enabled, "비 오는데 안개가 없다")
	atmosphere.apply(30.0, 180.0, 0.0)
	ok(not atmosphere.environment.fog_enabled, "맑은데 안개가 있다")
	finish()
