extends TestCase
# 경찰 시야와 위반 판정. 가짜 신호 하나를 놓고 버스 대신 빈 Node3D 를
# 움직여 판정만 본다 — 물리를 끼우면 테스트가 느리고 불안정해진다.

func _ready() -> void:
	_test_police_sight()
	await _test_red_light_is_a_violation()
	await _test_green_light_is_not()
	await _test_yellow_light_is_not()
	await _test_counted_once()
	await _test_camera_counts_separately()
	await _test_police_busts()
	TrafficSignal.time_override = -1.0
	finish()

# 곧은 남북 노선 위 Traffic. 물리 처리를 끄고 테스트가 경찰차를 직접 놓는다.
func _make_traffic() -> Traffic:
	var data := RouteData.new()
	data.route = PackedVector3Array([Vector3(0.0, 0.0, 1000.0), Vector3(0.0, 0.0, -1000.0)])
	data.route_width = PackedFloat32Array([7.0, 7.0])
	var traffic := Traffic.new()
	traffic.build(data, null)
	add_child(traffic)
	traffic.set_physics_process(false)
	# 경찰차 한 대만 남기고 나머지는 멀리 치운다. sync_to_physics 가 켜진 몸체는
	# 옮긴 위치가 다음 물리 프레임에야 반영된다. 테스트는 바로 읽으려고 끈다.
	var first := true
	for car in traffic.cars:
		car.body.sync_to_physics = false
		if car.is_police and first:
			first = false
			continue
		car.body.global_position = Vector3(0.0, 0.0, 100000.0)
	return traffic

func _police_body(traffic: Traffic) -> Node3D:
	for car in traffic.cars:
		if car.is_police:
			return car.body
	return null

func _test_police_sight() -> void:
	var traffic := _make_traffic()
	var body := _police_body(traffic)
	body.global_position = Vector3.ZERO
	body.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)   # 북(-Z)을 본다
	ok(traffic.police_sees(Vector3(0.0, 0.0, -50.0)), "전방 50 m 를 못 본다")
	ok(not traffic.police_sees(Vector3(0.0, 0.0, -200.0)), "전방 200 m 를 본다")
	ok(not traffic.police_sees(Vector3(0.0, 0.0, 50.0)), "후방 50 m 를 본다")
	traffic.queue_free()

# 교차로 하나를 원점에 놓는다. 축 0 은 남북(방위 0), 축 1 은 동서(방위 90).
# 반폭 10 m 라 정지선은 중심에서 12 m 다.
func _signal_entry(has_camera: bool) -> Dictionary:
	return {"x": 0.0, "z": 0.0, "source": "synthesized", "roads": 4,
		"axis_deg": [0.0, 90.0], "half_width": 10.0, "camera": has_camera}

# 축 0 이 원하는 위상이 되는 시각을 고른다. offset_for(0, 0) 을 빼면 된다.
func _time_for(phase: int) -> float:
	var offset := TrafficSignal.offset_for(0.0, 0.0)
	var base := 0.0
	if phase == TrafficSignal.Phase.YELLOW:
		base = TrafficSignal.GREEN_S + 1.0
	elif phase == TrafficSignal.Phase.RED:
		base = TrafficSignal.GREEN_S + TrafficSignal.YELLOW_S + 1.0
	else:
		base = 1.0
	return base - offset + TrafficSignal.CYCLE_S * 100.0

# 버스 대신 빈 Node3D 를 북쪽(-Z)에서 남쪽(+Z)으로 두 걸음 옮긴다.
# 축 0 진행이라 축 0 의 신호를 본다.
func _drive_through(mover: Node3D) -> void:
	mover.global_position = Vector3(0.0, 0.0, -20.0)
	mover.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	# 두 번 기다린다. 갓 add_child 한 노드는 이번 physics_frame 신호가 뜬 뒤에야
	# 첫 _physics_process 를 받으므로, 한 번만 기다리면 정지선까지의 기준 부호
	# 거리가 기록되지 않아 접근 자체를 놓친다.
	await get_tree().physics_frame
	await get_tree().physics_frame
	mover.global_position = Vector3(0.0, 0.0, -5.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

func _make_watch(has_camera: bool, phase: int) -> Array:
	TrafficSignal.time_override = _time_for(phase)
	var mover := Node3D.new()
	add_child(mover)
	var watch := ViolationWatch.new()
	watch.build([_signal_entry(has_camera)])
	watch.bus = mover
	add_child(watch)
	return [watch, mover]

func _test_red_light_is_a_violation() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	await _drive_through(made[1])
	ok(watch.violations == 1, "적색 통과가 %d 회로 세어졌다" % watch.violations)
	watch.queue_free()
	made[1].queue_free()

func _test_green_light_is_not() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.GREEN)
	var watch: ViolationWatch = made[0]
	await _drive_through(made[1])
	ok(watch.violations == 0, "녹색 통과가 위반으로 세어졌다")
	watch.queue_free()
	made[1].queue_free()

func _test_yellow_light_is_not() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.YELLOW)
	var watch: ViolationWatch = made[0]
	await _drive_through(made[1])
	ok(watch.violations == 0, "황색 통과가 위반으로 세어졌다")
	watch.queue_free()
	made[1].queue_free()

func _test_counted_once() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	var mover: Node3D = made[1]
	await _drive_through(mover)
	# 같은 자리에 더 머물러도 두 번 세면 안 된다.
	for i in 5:
		await get_tree().physics_frame
	ok(watch.violations == 1, "한 번 통과가 %d 회로 세어졌다" % watch.violations)
	watch.queue_free()
	mover.queue_free()

func _test_camera_counts_separately() -> void:
	var made := _make_watch(true, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	await _drive_through(made[1])
	ok(watch.violations == 1, "카메라 교차로 위반이 안 세어졌다")
	ok(watch.camera_violations == 1,
		"카메라 위반이 %d 회다" % watch.camera_violations)
	watch.queue_free()
	made[1].queue_free()

func _test_police_busts() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	var mover: Node3D = made[1]
	var traffic := _make_traffic()
	# 경찰차를 교차로 남쪽 30 m 에 두고 북쪽(오는 버스 쪽)을 보게 한다.
	var body := _police_body(traffic)
	body.global_position = Vector3(0.0, 0.0, 30.0)
	body.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	watch.traffic = traffic
	await _drive_through(mover)
	ok(watch.is_busted, "경찰차 앞 위반인데 적발되지 않았다")
	watch.queue_free()
	mover.queue_free()
	traffic.queue_free()
