extends TestCase
# 합성 곧은 왕복 4차선(15 m)에서 차선 변경 규칙을 하나씩 본다. 버스 대신 빈
# Node3D 를 둔다. 필요한 차만 남기고 나머지는 cars 에서 뺀다.

const ROUTE_M := 1000.0

func _ready() -> void:
	await _test_passes_held_car()
	await _test_blocked_by_rear()
	await _test_no_change_near_stop()
	await _test_merge_when_lanes_drop()
	await _test_passes_bus()
	finish()

# 북(-Z)으로 곧은 길. 주행선은 바깥 차선 중앙(중심에서 동으로 5.625 m)이라
# 도로 중심선이 x = 0 이다. 500 m 부터 차선 수가 lanes_at_end 가 된다.
func _data(lanes_at_end: int = 4, signal_at_m: float = -1.0) -> RouteData:
	var data := RouteData.new()
	for index in 11:
		data.route.append(Vector3(5.625, 0.0, -index * ROUTE_M / 10.0))
		data.route_width.append(15.0)
		data.route_lanes.append(4 if index < 5 else lanes_at_end)
		data.route_oneway.append(0)
		data.route_offset.append(5.625)
	if signal_at_m >= 0.0:
		data.signals = [{"x": 0.0, "z": -signal_at_m, "axis_deg": [0.0, 90.0],
			"half_width": 7.5}]
	return data

func _make(data: RouteData, mover_z: float = 0.0) -> Traffic:
	var mover := Node3D.new()
	add_child(mover)
	mover.position = Vector3(5.625, 0.0, mover_z)
	var traffic := Traffic.new()
	traffic.build(data, mover)
	add_child(traffic)
	return traffic

# 정방향 차 count 대만 남긴다. 나머지 몸체는 치운다.
func _keep(traffic: Traffic, count: int) -> Array:
	var kept: Array = []
	for car in traffic.cars.duplicate():
		if car.road == traffic.forward_road and kept.size() < count:
			kept.append(car)
			continue
		traffic.cars.erase(car)
		car.body.queue_free()
	return kept

func _put(traffic: Traffic, car, distance: float, lane: int, speed: float) -> void:
	car.distance = distance
	car.lane_index = lane
	car.side_m = traffic.lane_side(traffic.forward_road, distance, lane)
	car.speed = speed
	car.change_s = 0.0

func _run(seconds: float) -> void:
	for frame in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame

func _cleanup(traffic: Traffic) -> void:
	traffic.queue_free()
	await get_tree().physics_frame

func _test_passes_held_car() -> void:
	var traffic := _make(_data())
	var cars := _keep(traffic, 2)
	_put(traffic, cars[0], 120.0, 1, 0.0)
	traffic.hold(cars[0].body, 100.0)
	_put(traffic, cars[1], 60.0, 1, CarFollow.CRUISE_MPS)
	await _run(10.0)
	ok(cars[1].distance > cars[0].distance + 5.0,
		"선 차를 못 앞질렀다 (%.1f vs %.1f)" % [cars[1].distance, cars[0].distance])
	await _cleanup(traffic)

func _test_blocked_by_rear() -> void:
	# 안쪽 차선 바로 뒤에 달리는 차가 있으면 옮기지 않는다.
	var traffic := _make(_data())
	var cars := _keep(traffic, 3)
	_put(traffic, cars[0], 90.0, 1, 0.0)
	traffic.hold(cars[0].body, 100.0)
	_put(traffic, cars[1], 70.0, 1, 0.0)
	_put(traffic, cars[2], 66.0, 0, CarFollow.CRUISE_MPS)
	await _run(0.2)
	ok(cars[1].lane_index == 1, "뒤차가 붙어 있는데 옮겼다")
	await _cleanup(traffic)

func _test_no_change_near_stop() -> void:
	# 정지선(신호 200 m, 정지선 190.5 m) 20 m 앞에서 막혀도 옮기지 않는다.
	var traffic := _make(_data(4, 200.0))
	var cars := _keep(traffic, 2)
	_put(traffic, cars[0], 175.0, 1, 0.0)
	traffic.hold(cars[0].body, 100.0)
	_put(traffic, cars[1], 165.0, 1, 0.0)
	await _run(0.5)
	ok(cars[1].lane_index == 1, "정지선 앞에서 차선을 바꿨다")
	await _cleanup(traffic)

func _test_merge_when_lanes_drop() -> void:
	# 500 m 부터 왕복 2차선. 바깥 차선 차가 방향당 하나 남은 차선으로 들어간다.
	var traffic := _make(_data(2), -420.0)
	var cars := _keep(traffic, 1)
	_put(traffic, cars[0], 420.0, 1, CarFollow.CRUISE_MPS)
	await _run(8.0)
	ok(cars[0].lane_index == 0, "차선이 줄었는데 합류 안 했다")
	equal_approx(cars[0].side_m, Lanes.side_of(0, 2, 15.0, false), 0.05,
		"합류 뒤 가로 위치")
	await _cleanup(traffic)

func _test_passes_bus() -> void:
	# 버스(mover)가 바깥 차선 150 m 에 서 있다. 뒤차가 옆 차선으로 비켜 지나간다.
	var traffic := _make(_data(), -150.0)
	var cars := _keep(traffic, 1)
	_put(traffic, cars[0], 100.0, 1, CarFollow.CRUISE_MPS)
	await _run(10.0)
	ok(cars[0].distance > 160.0, "선 버스 뒤에서 못 지나갔다 (%.1f)" % cars[0].distance)
	await _cleanup(traffic)
