extends TestCase
# 신호 위상은 노드 상태 없이 시간의 순수 함수다. 여기서 경계값을 못 잡으면
# 위반 판정 전체가 한 프레임씩 어긋난다.

func _ready() -> void:
	_test_phase_boundaries()
	_test_axes_never_both_go()
	_test_offset()
	_test_axis_for()
	_test_bearing()
	_test_grid()
	finish()

func _test_phase_boundaries() -> void:
	# offset 0, 축 0: 0~30 녹, 30~33 황, 33~66 적.
	ok(TrafficSignal.phase_at(0.0, 0, 0.0) == TrafficSignal.Phase.GREEN, "t=0 이 녹이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 29.9) == TrafficSignal.Phase.GREEN, "t=29.9 가 녹이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 30.1) == TrafficSignal.Phase.YELLOW, "t=30.1 이 황이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 32.9) == TrafficSignal.Phase.YELLOW, "t=32.9 가 황이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 33.1) == TrafficSignal.Phase.RED, "t=33.1 이 적이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 65.9) == TrafficSignal.Phase.RED, "t=65.9 가 적이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 66.1) == TrafficSignal.Phase.GREEN, "주기가 안 돈다")
	# 음수 시각에서도 감겨야 한다.
	ok(TrafficSignal.phase_at(0.0, 0, -1.0) == TrafficSignal.Phase.RED, "t=-1 이 적이 아니다")

func _test_axes_never_both_go() -> void:
	# 한 축이 녹이나 황이면 다른 축은 반드시 적이어야 한다.
	var t := 0.0
	while t < TrafficSignal.CYCLE_S:
		var a := TrafficSignal.phase_at(7.5, 0, t)
		var b := TrafficSignal.phase_at(7.5, 1, t)
		if a != TrafficSignal.Phase.RED and b != TrafficSignal.Phase.RED:
			ok(false, "t=%.1f 에서 두 축이 동시에 간다" % t)
			return
		t += 0.5

func _test_offset() -> void:
	var offset := TrafficSignal.offset_for(123.4, -567.8)
	ok(offset >= 0.0 and offset < TrafficSignal.CYCLE_S,
		"위상 오프셋이 범위 밖이다: %f" % offset)
	ok(is_equal_approx(offset, TrafficSignal.offset_for(123.4, -567.8)),
		"같은 좌표에 다른 오프셋이 나온다")
	# 이웃한 교차로가 같은 위상이면 도시 전체가 동시에 바뀐다.
	var neighbour := TrafficSignal.offset_for(223.4, -567.8)
	ok(not is_equal_approx(offset, neighbour), "다른 좌표에 같은 오프셋이 나온다")

func _test_axis_for() -> void:
	var axes := [12.0, 102.0]
	ok(TrafficSignal.axis_for(10.0, axes) == 0, "방위 10 이 축 0 이 아니다")
	# 180° 반대로 달려도 같은 축이다.
	ok(TrafficSignal.axis_for(190.0, axes) == 0, "방위 190 이 축 0 이 아니다")
	ok(TrafficSignal.axis_for(100.0, axes) == 1, "방위 100 이 축 1 이 아니다")
	ok(TrafficSignal.axis_for(280.0, axes) == 1, "방위 280 이 축 1 이 아니다")

func _test_bearing() -> void:
	# 북은 -Z 로 0, 동은 +X 로 90.
	equal_approx(TrafficSignal.bearing_of(Vector3(0.0, 0.0, -1.0)), 0.0, 0.01, "북이 0 이 아니다")
	equal_approx(TrafficSignal.bearing_of(Vector3(1.0, 0.0, 0.0)), 90.0, 0.01, "동이 90 이 아니다")
	equal_approx(TrafficSignal.bearing_of(Vector3(0.0, 0.0, 1.0)), 180.0, 0.01, "남이 180 이 아니다")
	# direction_of 는 bearing_of 의 역이다.
	for bearing in [0.0, 37.0, 90.0, 181.0, 300.0]:
		var back := TrafficSignal.bearing_of(TrafficSignal.direction_of(bearing))
		equal_approx(back, bearing, 0.01, "방위 %.0f 의 왕복이 안 맞는다" % bearing)

func _test_grid() -> void:
	ok(TrafficSignal.cell_of(0.0, 0.0) == Vector2i(0, 0), "원점 셀이 (0,0) 이 아니다")
	ok(TrafficSignal.cell_of(-1.0, -1.0) == Vector2i(-1, -1), "음수 셀이 잘못됐다")
	var cells := TrafficSignal.cells_near(Vector3.ZERO, 64.0)
	ok(cells.size() == 9, "반경 64 m 는 3x3 셀이어야 하는데 %d 개다" % cells.size())
	ok(cells.has(Vector2i(0, 0)), "자기 셀이 빠졌다")
	ok(cells.has(Vector2i(1, 1)), "대각 셀이 빠졌다")
	ok(not cells.has(Vector2i(2, 0)), "필요 없는 셀이 들어 있다")
