extends TestCase
# 차선 기하. 동쪽으로 곧은 100 m 길 하나로 본다.

func _ready() -> void:
	var route := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(50.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0)])
	var lane := LanePath.make(route)
	equal_approx(lane.length_m(), 100.0, 0.001, "차선 길이")
	equal_approx(lane.sample(25.0).x, 25.0, 0.001, "누적 거리 위치 보간")
	equal_approx(lane.sample(75.0).x, 75.0, 0.001, "둘째 구간 보간")
	equal_approx(lane.direction_at(25.0).x, 1.0, 0.001, "진행 방향")
	var on := lane.project(Vector3(30.0, 5.0, 4.0))
	equal_approx(on.x, 30.0, 0.001, "투영 누적 거리")
	equal_approx(on.y, 4.0, 0.001, "투영 옆 거리 (높이는 무시)")

	# 동쪽 진행의 왼쪽은 북(-Z). 폭 10 m 면 5 m 북쪽에서 서쪽으로 간다.
	var oncoming := LanePath.make(LanePath.oncoming(route,
		PackedFloat32Array([10.0, 10.0, 10.0])))
	equal_approx(oncoming.sample(0.0).x, 100.0, 0.001, "마주 오는 차선이 안 뒤집혔다")
	equal_approx(oncoming.sample(0.0).z, -5.0, 0.001, "마주 오는 차선 오프셋")
	equal_approx(oncoming.sample(60.0).z, -5.0, 0.001, "마주 오는 차선 중간 오프셋")
	equal_approx(oncoming.direction_at(50.0).x, -1.0, 0.001, "마주 오는 차선 방향")

	# 교차로 (60, 0), 반폭 8, 축 [0, 90]. 동쪽 진행은 축 1. 정지선 60 - 8 - 2 = 50.
	# 둘째 신호는 차선에서 100 m 떨어져 안 잡혀야 한다.
	lane.add_signals([
		{"x": 60.0, "z": 0.0, "axis_deg": [0.0, 90.0], "half_width": 8.0},
		{"x": 60.0, "z": 100.0, "axis_deg": [0.0, 90.0], "half_width": 8.0}], 30.0)
	ok(lane.stops.size() == 1, "정지선이 %d 개다" % lane.stops.size())
	if lane.stops.size() == 1:
		equal_approx(lane.stops[0]["at_m"], 50.0, 0.01, "정지선 누적 거리")
		ok(lane.stops[0]["axis"] == 1, "동쪽 진행인데 축 %d" % lane.stops[0]["axis"])
		ok(lane.stops[0]["signal"] == 0, "신호 인덱스가 틀렸다")
		ok(not lane.next_stop(49.0).is_empty(), "정지선 1 m 앞에서 못 찾았다")
		ok(lane.next_stop(51.0).is_empty(), "지난 정지선을 또 찾았다")

	# 교차 차선: 원점, 북쪽 진행, 반폭 10. 길이 앞뒤 40 m, 오른쪽(동)으로 5 m.
	var cross := LanePath.crossing(Vector3.ZERO, 0.0, 10.0, 0, 3.0)
	equal_approx(cross.length_m(), 80.0, 0.001, "교차 차선 길이")
	equal_approx(cross.sample(0.0).x, 5.0, 0.001, "교차 차선 오른쪽 오프셋")
	equal_approx(cross.sample(0.0).z, 40.0, 0.001, "교차 차선 시작점")
	equal_approx(cross.direction_at(10.0).z, -1.0, 0.001, "교차 차선 방향")
	ok(cross.stops.size() == 1, "교차 차선 정지선이 %d 개" % cross.stops.size())
	if cross.stops.size() == 1:
		equal_approx(cross.stops[0]["at_m"], 28.0, 0.01, "교차 차선 정지선 (40 - 10 - 2)")
	# 좁은 교차로도 30 m 는 확보한다.
	equal_approx(LanePath.crossing(Vector3.ZERO, 0.0, 3.0, 0, 0.0).length_m(), 60.0,
		0.001, "교차 차선 하한")
	finish()
