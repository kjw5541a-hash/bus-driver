extends TestCase
# 구간 경계와 자르기. 합성 데이터로 규칙을, 실데이터로 구간 수를 본다.

func _ready() -> void:
	_test_bounds()
	_test_slice()
	_test_real_routes()
	_test_deadline()
	finish()

# 정류장 n 곳을 +X 축 직선 위 100 m 간격(50, 150, ...)에 놓는다.
func _synthetic(stop_count: int) -> RouteData:
	var data := RouteData.new()
	data.id = "test"
	for index in stop_count + 1:
		data.route.append(Vector3(index * 100.0, 0.0, 0.0))
	for index in stop_count:
		data.stops.append({"name": "정류장%d" % index,
			"x": index * 100.0 + 50.0, "z": 5.0,
			"progress_m": index * 100.0 + 50.0})
	data.signals = [
		{"x": 1500.0, "z": 0.0},    # 구간 1 경로 위
		{"x": 1500.0, "z": 100.0},  # 구간 1 범위지만 경로에서 100 m
		{"x": 300.0, "z": 0.0},     # 구간 0
	]
	data._build_stop_targets()
	return data

func _test_bounds() -> void:
	ok(_synthetic(25).sections() == [Vector2i(0, 10), Vector2i(10, 20), Vector2i(20, 24)],
		"25 곳 구간이 틀렸다: %s" % str(_synthetic(25).sections()))
	# 꼬리 20~22 는 3 곳이라 앞 구간에 붙는다.
	ok(_synthetic(23).sections() == [Vector2i(0, 10), Vector2i(10, 22)],
		"23 곳 구간이 틀렸다: %s" % str(_synthetic(23).sections()))
	ok(_synthetic(4).sections() == [Vector2i(0, 3)],
		"4 곳 구간이 틀렸다: %s" % str(_synthetic(4).sections()))
	ok(_synthetic(1).sections().is_empty(), "1 곳이면 구간이 없어야 한다")

func _test_slice() -> void:
	var data := _synthetic(25)
	var part := data.slice(1)
	ok(part != data, "원본을 그대로 돌려줬다")
	ok(part.section == 1 and part.section_count == 3,
		"구간 번호가 틀렸다: %d/%d" % [part.section, part.section_count])
	ok(part.stops.size() == 11, "정류장이 %d 곳이다" % part.stops.size())
	equal_approx(float(part.stops[0]["progress_m"]), RouteData.LEAD_IN_M, 0.01,
		"첫 정류장 진행도가 앞 여유와 다르다")
	equal_approx(part.route[0].x, 990.0, 0.01, "잘린 시작점")
	equal_approx(part.route[part.route.size() - 1].x, 2050.0, 0.01, "잘린 끝점")
	equal_approx(part.length_m(), 1060.0, 0.01, "잘린 길이")
	ok(part.stop_targets.size() == 11, "정차 목표점을 다시 안 만들었다")
	equal_approx(part.stop_targets[0].x, 1050.0, 0.01, "첫 정차 목표점")
	ok(part.signals.size() == 1, "신호가 %d 개다" % part.signals.size())
	# 원본은 그대로다.
	equal_approx(float(data.stops[10]["progress_m"]), 1050.0, 0.01, "원본 정류장이 바뀌었다")
	# 범위 밖 구간 번호는 0 번이다.
	ok(data.slice(9).section == 0, "범위 밖 구간이 0 번이 아니다")
	# 첫 구간은 노선 시작점을 넘어가지 않는다.
	equal_approx(data.slice(0).route[0].x, 0.0, 0.01, "첫 구간 시작점")

func _test_real_routes() -> void:
	var expected := {"seoul-100": 6, "seoul-654": 8, "seoul-seodaemun03": 2}
	for route_id in expected:
		var data := RouteData.load_route(route_id)
		ok(data != null, "%s 를 읽지 못했다" % route_id)
		if data == null:
			continue
		var bounds := data.sections()
		ok(bounds.size() == expected[route_id],
			"%s 구간이 %d 개다" % [route_id, bounds.size()])
		for index in bounds.size():
			var part := data.slice(index)
			for entry in part.signals:
				var point := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
				ok(part.distance_to_route(point) <= RouteData.SECTION_SIGNAL_M + 0.01,
					"%s 구간 %d 신호가 경로에서 멀다" % [route_id, index])

func _test_deadline() -> void:
	# 0 명이 4/12, 1~8 명이 각 1/12. n 명이면 3 + 3/1.2 + 2n 초.
	equal_approx(Timetable.expected_dwell(), 116.0 / 12.0, 0.001, "기대 정차 시간")
	equal_approx(Timetable.signal_wait(), 8.25, 0.001, "기대 신호 대기")
	# 1000 m 직선, 정류장 3, 신호 2: 112.5 + 29 + 16.5 = 158 -> 160.
	var data := RouteData.new()
	data.route = PackedVector3Array([Vector3.ZERO, Vector3(1000.0, 0.0, 0.0)])
	data.stops = [{}, {}, {}]
	data.signals = [{}, {}]
	equal_approx(Timetable.deadline_for(data), 160.0, 0.001, "마감")
	ok(Timetable.format_mmss(462) == "7:42", "포맷: %s" % Timetable.format_mmss(462))
	ok(Timetable.format_mmss(60) == "1:00", "포맷: %s" % Timetable.format_mmss(60))
	ok(Timetable.format_mmss(5) == "0:05", "포맷: %s" % Timetable.format_mmss(5))
	# 실데이터 모든 구간이 5~16 분이다.
	for route_id in ["seoul-100", "seoul-654", "seoul-seodaemun03"]:
		var route := RouteData.load_route(route_id)
		if route == null:
			continue
		for index in route.sections().size():
			var deadline := Timetable.deadline_for(route.slice(index))
			ok(deadline >= 300.0 and deadline <= 960.0,
				"%s 구간 %d 마감 %.0f 초" % [route_id, index, deadline])
