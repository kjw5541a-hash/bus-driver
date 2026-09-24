extends TestCase
# 정차 판정. 버스 대신 빈 Node3D 를 옮겨서 판정만 본다 — 물리를 끼우면
# 테스트가 느리고 불안정해진다.

var _started: Array = []
var _finished: Array = []
var _missed: Array = []
var _bells: Array = []

func _ready() -> void:
	await _test_far_away_does_not_start()
	await _test_moving_does_not_start()
	await _test_stopped_starts()
	await _test_nearest_of_overlapping()
	await _test_passing_by_is_missed()
	await _test_empty_stop_is_not_missed()
	await _test_timer_finishes_and_boards()
	await _test_riders_board_one_by_one()
	await _test_bell_rings_before_alighting_stop()
	finish()

# 정류장 네 곳을 30 m 간격으로 +X 축에 놓는다. 마지막이 종점이다.
func _targets() -> PackedVector3Array:
	return PackedVector3Array([Vector3.ZERO, Vector3(30.0, 0.0, 0.0),
		Vector3(60.0, 0.0, 0.0), Vector3(90.0, 0.0, 0.0)])

func _make(waiting: Array) -> Array:
	_started = []
	_finished = []
	_missed = []
	_bells = []
	var bus := Node3D.new()
	# 정류장에서 멀리 떨어뜨려 놓는다. 원점에 두면 0 번 정류장 자리라
	# 배선을 마치기도 전에 승하차가 시작된다.
	bus.position = Vector3(0.0, 0.0, 500.0)
	add_child(bus)
	var watch := BoardingWatch.new()
	watch.build(_targets())
	# 난수를 고정한다. 안 그러면 대기 0 명이 나와 판정 테스트가 흔들린다.
	for index in range(waiting.size()):
		watch.plan.force_waiting(index, int(waiting[index]))
	watch.bus = bus
	watch.boarding_started.connect(
		func(i: int) -> void: _started.append(i))
	watch.boarding_finished.connect(
		func(b: int, a: int) -> void: _finished.append([b, a]))
	watch.stop_missed.connect(
		func(i: int) -> void: _missed.append(i))
	watch.bell_rung.connect(
		func(i: int) -> void: _bells.append(i))
	add_child(watch)
	# 갓 add_child 한 노드는 이번 physics_frame 이 뜬 뒤에야 첫
	# _physics_process 를 받는다. 두 번 기다려야 기준 위치가 잡힌다.
	await get_tree().physics_frame
	await get_tree().physics_frame
	return [watch, bus]

# 같은 자리에 머무르게 해서 속도 0 을 만든다.
func _hold(bus: Node3D, position: Vector3, frames: int) -> void:
	for _frame in frames:
		bus.global_position = position
		await get_tree().physics_frame

func _drop(made: Array) -> void:
	# queue_free 는 프레임 끝에야 지운다. 그때까지 옛 watch 가 계속 돌며
	# 다음 테스트의 신호 목록에 끼어든다. 버스를 먼저 끊어 멈춰 세운다.
	made[0].bus = null
	made[0].queue_free()
	made[1].queue_free()

func _test_far_away_does_not_start() -> void:
	var made := await _make([4, 4, 4, 4])
	await _hold(made[1], Vector3(0.0, 0.0, 300.0), 4)
	ok(not made[0].is_boarding, "정류장에서 300 m 떨어졌는데 승하차가 시작됐다")
	_drop(made)

func _test_moving_does_not_start() -> void:
	var made := await _make([4, 4, 4, 4])
	var bus: Node3D = made[1]
	# 프레임마다 1 m 씩 옮기면 60 m/s 다. 문턱 0.5 m/s 를 한참 넘는다.
	for step in 6:
		bus.global_position = Vector3(-3.0 + step, 0.0, 0.0)
		await get_tree().physics_frame
	ok(not made[0].is_boarding, "주행 중인데 승하차가 시작됐다")
	_drop(made)

func _test_stopped_starts() -> void:
	var made := await _make([4, 4, 4, 4])
	await _hold(made[1], Vector3(2.0, 0.0, 0.0), 4)
	ok(made[0].is_boarding, "정류장 앞에 섰는데 승하차가 시작되지 않았다")
	ok(made[0].boarding_left > 0.0, "남은 승하차 시간이 0 이다")
	ok(_started == [0], "시작 신호가 %s 다" % str(_started))
	_drop(made)

func _test_nearest_of_overlapping() -> void:
	var made := await _make([4, 4, 4, 4])
	# 0 번(0 m)과 1 번(30 m) 사이 18 m 지점. 1 번이 12 m 로 더 가깝다.
	await _hold(made[1], Vector3(18.0, 0.0, 0.0), 4)
	ok(made[0].is_boarding, "겹친 구간에서 승하차가 시작되지 않았다")
	ok(_started == [1], "가까운 1 번이 아니라 %s 를 잡았다" % str(_started))
	_drop(made)

func _test_passing_by_is_missed() -> void:
	var made := await _make([4, 4, 4, 4])
	var bus: Node3D = made[1]
	# 0 번과 1 번을 속도를 유지한 채 지나쳐 2 번 근처까지 간다.
	for step in 16:
		bus.global_position = Vector3(-10.0 + step * 5.0, 0.0, 0.0)
		await get_tree().physics_frame
	ok(_missed.has(0) and _missed.has(1),
		"0·1 번을 지나쳤는데 놓침이 %s 다" % str(_missed))
	ok(made[0].missed == _missed.size(),
		"놓침 수 %d 와 신호 수 %d 가 다르다" % [made[0].missed, _missed.size()])
	_drop(made)

func _test_empty_stop_is_not_missed() -> void:
	# 1 번에만 사람이 없다. 지나쳐도 놓침이 아니다.
	var made := await _make([4, 0, 4, 4])
	var bus: Node3D = made[1]
	for step in 16:
		bus.global_position = Vector3(-10.0 + step * 5.0, 0.0, 0.0)
		await get_tree().physics_frame
	ok(not _missed.has(1),
		"탈 사람도 내릴 사람도 없는 정류장을 놓침으로 셌다: %s" % str(_missed))
	_drop(made)

func _test_timer_finishes_and_boards() -> void:
	var made := await _make([4, 4, 4, 4])
	var watch: BoardingWatch = made[0]
	var bus: Node3D = made[1]
	await _hold(bus, Vector3(1.0, 0.0, 0.0), 3)
	ok(watch.is_boarding, "승하차가 시작되지 않았다")
	# 문 3 초 + 걸어오기 1 초 미만 + 4 명 8 초 = 12 초 남짓이다.
	# 물리 프레임 60 Hz 라 900 프레임(15 초)이면 무조건 끝난다.
	for _frame in 900:
		bus.global_position = Vector3(1.0, 0.0, 0.0)
		await get_tree().physics_frame
		if not watch.is_boarding:
			break
	ok(_finished.size() == 1,
		"완료 신호가 %d 번 났다 (남은 %.2f 초)"
		% [_finished.size(), watch.boarding_left])
	ok(watch.served == 1, "처리한 정류장이 %d 곳이다" % watch.served)
	ok(watch.onboard == 4, "4 명이 기다렸는데 %d 명이 탔다" % watch.onboard)
	ok(watch.next_index == 1, "다음 정류장이 %d 번이다" % watch.next_index)
	_drop(made)

func _test_riders_board_one_by_one() -> void:
	# 한꺼번에 사라지면 인원에 따라 시간이 다른 것이 안 보인다.
	var made := await _make([4, 0, 0, 0])
	var watch: BoardingWatch = made[0]
	var bus: Node3D = made[1]
	await _hold(bus, Vector3.ZERO, 3)
	ok(watch.is_boarding, "승하차가 시작되지 않았다")
	var counts: Array = []
	for _frame in 900:
		bus.global_position = Vector3.ZERO
		if watch.is_boarding and (counts.is_empty() or counts[-1] != watch.boarded_so_far):
			counts.append(watch.boarded_so_far)
		await get_tree().physics_frame
		if not watch.is_boarding:
			break
	ok(counts == [0, 1, 2, 3], "탑승 인원이 %s 순으로 늘었다" % [counts])
	_drop(made)

func _test_bell_rings_before_alighting_stop() -> void:
	# 0 번에서 3 명이 타고 목적지는 1~3 번 중 하나다. 종점(3)은 전원이 내리니
	# 벨은 1~3 번 가운데 누군가 내릴 첫 정류장에서 반드시 울린다.
	var made := await _make([3, 0, 0, 0])
	var watch: BoardingWatch = made[0]
	var bus: Node3D = made[1]
	ok(not watch.bell_on, "아무도 안 탔는데 벨이 켜졌다")
	await _hold(bus, Vector3.ZERO, 3)
	for _frame in 900:
		bus.global_position = Vector3.ZERO
		await get_tree().physics_frame
		if not watch.is_boarding:
			break
	await _hold(bus, Vector3.ZERO, 2)
	var expected := watch.plan.alighting_at(1) > 0
	ok(watch.bell_on == expected,
		"1 번에서 내릴 사람이 %d 명인데 벨이 %s" % [watch.plan.alighting_at(1), watch.bell_on])
	ok(_bells == ([1] if expected else []), "벨 신호가 %s 다" % [_bells])
	# 벨이 켜진 정류장에서 문이 열리면 꺼진다.
	if expected:
		await _hold(bus, Vector3(30.0, 0.0, 0.0), 3)
		ok(watch.is_boarding and not watch.bell_on, "문이 열렸는데 벨이 켜져 있다")
	_drop(made)
