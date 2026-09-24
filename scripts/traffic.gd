extends Node3D
class_name Traffic
# 노선 위 일반 차량, 신호 교차로의 교차 차량, 경찰차. 물리 차량이 아니라
# 스크립트가 차선 누적 거리를 따라 옮기는 충돌 몸체(AnimatableBody3D)다.
# 속도는 CarFollow 가, 차선과 정지선은 LanePath 가 낸다.
#
# 차는 버스 둘레 창 안에만 둔다. 창을 벗어난 차는 지우지 않고 반대쪽 끝으로
# 옮겨 다시 쓴다. 노드는 build() 에서 만든 것을 끝까지 쓴다.

const SAME_COUNT := 6
const ONCOMING_COUNT := 6
const AHEAD_M := 250.0
const BEHIND_M := 100.0
const FIRST_AHEAD_M := 30.0       # 처음 배치할 때 버스 바로 앞은 비운다
const SPAWN_GAP_M := 20.0
const CROSS_RADIUS_M := 150.0
const CROSS_MAX := 6
const CROSS_SITES := 3            # CROSS_MAX 의 절반. 교차로마다 두 방향
const BUS_LANE_REACH_M := 3.0
const BUS_HALF_LENGTH_M := 5.5    # Bus 충돌 상자 길이 11 m 의 절반
const POLICE_SIGHT_M := 80.0
const BODY_SIZE := Vector3(1.8, 1.4, 4.6)
const CAR_HALF_LENGTH_M := 2.3    # BODY_SIZE.z 의 절반
const BODY_COLORS := [Color(0.55, 0.56, 0.58), Color(0.92, 0.92, 0.90),
	Color(0.08, 0.08, 0.09)]
const POLICE_COLOR := Color(0.10, 0.18, 0.55)
const BEACON_COLOR := Color(0.90, 0.10, 0.12)
const HIDDEN_Y := -100.0          # 쉬는 교차 차량을 치워 두는 높이

class Car:
	var body: AnimatableBody3D
	var lane: LanePath             # null 이면 쉬는 교차 차량
	var distance := 0.0
	var speed := 0.0
	var hold_s := 0.0
	var is_police := false
	var crossing := -1             # 교차 차량이 맡은 신호 인덱스. 노선 차량은 -1

var cars: Array = []
var same_lane: LanePath
var oncoming_lane: LanePath

var _bus: Node3D
var _signals: Array = []
var _cross_lanes: Dictionary = {}  # 신호 인덱스 -> [LanePath, LanePath]

func build(data: RouteData, bus: Node3D) -> void:
	_bus = bus
	if data.route.size() < 2:
		# 경로가 없으면 차도 없다.
		return
	_signals = data.signals
	same_lane = LanePath.make(data.route)
	same_lane.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)
	oncoming_lane = LanePath.make(LanePath.oncoming(data.route, data.route_width))
	oncoming_lane.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)

	# 같은 방향 차는 버스 앞에만 깐다. 뒤에 깔면 첫 프레임에 버스와 겹칠 수 있다.
	var along := same_lane.project(_bus_point()).x
	for index in SAME_COUNT:
		var car := _make_car(index == 0, index)
		car.lane = same_lane
		car.distance = minf(along + FIRST_AHEAD_M
			+ (AHEAD_M - FIRST_AHEAD_M) * index / SAME_COUNT, same_lane.length_m())
	# 마주 오는 차선에서 버스 앞은 누적 거리가 작은 쪽이다.
	var facing := oncoming_lane.project(_bus_point()).x
	for index in ONCOMING_COUNT:
		var car := _make_car(index == 0, index + 1)
		car.lane = oncoming_lane
		car.distance = clampf(facing - AHEAD_M
			+ (AHEAD_M + BEHIND_M) * (index + 0.5) / ONCOMING_COUNT,
			0.0, oncoming_lane.length_m())
	for index in CROSS_MAX:
		_make_car(false, index + 2)
	_place_all()

func _make_car(is_police: bool, color_index: int) -> Car:
	var car := Car.new()
	car.is_police = is_police
	var body := AnimatableBody3D.new()
	# 스크립트가 옮긴 만큼 물리 속도를 매겨, 움직이는 차에 닿은 버스가 제대로 밀린다.
	body.sync_to_physics = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	shape.position.y = BODY_SIZE.y * 0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = BODY_SIZE
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = POLICE_COLOR if is_police \
		else BODY_COLORS[color_index % BODY_COLORS.size()]
	mesh.material_override = material
	mesh.position.y = BODY_SIZE.y * 0.5
	body.add_child(mesh)
	if is_police:
		var beacon := MeshInstance3D.new()
		var beacon_mesh := BoxMesh.new()
		beacon_mesh.size = Vector3(1.0, 0.2, 0.3)
		beacon.mesh = beacon_mesh
		var beacon_material := StandardMaterial3D.new()
		beacon_material.albedo_color = BEACON_COLOR
		beacon_material.emission_enabled = true
		beacon_material.emission = BEACON_COLOR
		beacon.material_override = beacon_material
		beacon.position.y = BODY_SIZE.y + 0.1
		body.add_child(beacon)
	add_child(body)
	car.body = body
	cars.append(car)
	return car

func _bus_point() -> Vector3:
	if _bus != null and _bus.is_inside_tree():
		return _bus.global_position
	return same_lane.sample(0.0)

func _physics_process(delta: float) -> void:
	if same_lane == null:
		return
	var bus_point := _bus_point()
	_update_crossings(bus_point)
	var t := TrafficSignal.now()
	var by_lane := {}
	for car in cars:
		if car.lane == null:
			continue
		if not by_lane.has(car.lane):
			by_lane[car.lane] = []
		by_lane[car.lane].append(car)
	# 버스를 차선마다 한 번씩만 투영한다. 재활용도 같은 값을 쓴다.
	var bus_on := {}
	for lane in by_lane:
		bus_on[lane] = lane.project(bus_point) if _bus != null else Vector2(INF, INF)
		var queue: Array = by_lane[lane]
		queue.sort_custom(func(a: Car, b: Car) -> bool: return a.distance < b.distance)
		for index in queue.size():
			var leader: Car = queue[index + 1] if index + 1 < queue.size() else null
			_drive(queue[index], leader, bus_on[lane], t, delta)
	_recycle(bus_on)
	_place_all()

func _drive(car: Car, leader: Car, bus_on: Vector2, t: float, delta: float) -> void:
	if car.hold_s > 0.0:
		car.hold_s = maxf(car.hold_s - delta, 0.0)
		car.speed = 0.0
		return
	var front := car.distance + CAR_HALF_LENGTH_M
	var gap := INF
	if leader != null:
		gap = leader.distance - CAR_HALF_LENGTH_M - front
	# 차선 옆으로 비켜 선 버스(정류장)는 장애물이 아니다. 그러면 뒤차가 영원히 선다.
	if bus_on.y <= BUS_LANE_REACH_M and bus_on.x > car.distance:
		gap = minf(gap, bus_on.x - BUS_HALF_LENGTH_M - front)
	var stop_m := INF
	var phase := TrafficSignal.Phase.GREEN
	var line := car.lane.next_stop(front)
	if not line.is_empty():
		stop_m = float(line["at_m"]) - front
		phase = TrafficSignal.phase_at(float(line["offset"]), int(line["axis"]), t)
	car.speed = CarFollow.next_speed(car.speed, gap, stop_m, phase, delta)
	car.distance = minf(car.distance + car.speed * delta, car.lane.length_m())

func _recycle(bus_on: Dictionary) -> void:
	for car in cars:
		if car.lane == null or not bus_on.has(car.lane):
			continue
		var on: Vector2 = bus_on[car.lane]
		if car.lane == same_lane:
			_recycle_one(car, on.x - BEHIND_M, on.x + AHEAD_M, on)
		elif car.lane == oncoming_lane:
			_recycle_one(car, on.x - AHEAD_M, on.x + BEHIND_M, on)
		elif car.distance >= car.lane.length_m() and _free_at(car.lane, 0.0, car, on):
			# 교차 차량은 차선 끝에 닿으면 처음으로 돌아간다.
			car.distance = 0.0
			car.speed = 0.0

func _recycle_one(car: Car, low: float, high: float, bus_on: Vector2) -> void:
	var length := car.lane.length_m()
	low = maxf(low, 0.0)
	high = minf(high, length)
	var target: float
	if car.distance > high or car.distance >= length:
		target = low
	elif car.distance < low:
		target = high
	else:
		return
	# 자리가 차 있으면 이번 프레임은 놔둔다. 다음 프레임에 다시 본다.
	if _free_at(car.lane, target, car, bus_on):
		car.distance = target
		car.speed = 0.0

func _free_at(lane: LanePath, distance: float, moving: Car, bus_on: Vector2) -> bool:
	if bus_on.y <= BUS_LANE_REACH_M and absf(bus_on.x - distance) < SPAWN_GAP_M:
		return false
	for other in cars:
		if other != moving and other.lane == lane \
				and absf(other.distance - distance) < SPAWN_GAP_M:
			return false
	return true

func _update_crossings(bus_point: Vector3) -> void:
	# 버스 반경 안 노선 신호를 가까운 순으로 CROSS_SITES 곳까지 고른다.
	var nearest := {}   # 신호 인덱스 -> [거리, 정지선]
	for line in same_lane.stops:
		var entry: Dictionary = _signals[int(line["signal"])]
		var distance := Vector2(float(entry["x"]) - bus_point.x,
			float(entry["z"]) - bus_point.z).length()
		if distance <= CROSS_RADIUS_M:
			nearest[int(line["signal"])] = [distance, line]
	var picked := nearest.keys()
	picked.sort_custom(func(a: int, b: int) -> bool: return nearest[a][0] < nearest[b][0])
	picked = picked.slice(0, CROSS_SITES)

	# 반경을 벗어난 교차로의 차는 쉬게 한다.
	var served := {}
	for car in cars:
		if car.crossing < 0:
			continue
		if picked.has(car.crossing):
			served[car.crossing] = true
		else:
			car.crossing = -1
			car.lane = null
	for index in picked:
		if served.has(index):
			continue
		for lane in _crossing_lanes(index, nearest[index][1]):
			var car := _idle_car()
			if car == null:
				return
			car.lane = lane
			car.crossing = index
			car.distance = 0.0
			car.speed = 0.0

func _crossing_lanes(index: int, line: Dictionary) -> Array:
	"""버스가 지나지 않는 축으로 교차로를 가로지르는 양방향 차선 둘."""
	if not _cross_lanes.has(index):
		var entry: Dictionary = _signals[index]
		var axis := 1 - int(line["axis"])
		var bearing := float(entry["axis_deg"][axis])
		var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		var half := float(entry.get("half_width", ViolationWatch.DEFAULT_HALF_WIDTH))
		var offset := float(line["offset"])
		_cross_lanes[index] = [
			LanePath.crossing(center, bearing, half, axis, offset),
			LanePath.crossing(center, bearing + 180.0, half, axis, offset)]
	return _cross_lanes[index]

func _idle_car() -> Car:
	for car in cars:
		if car.lane == null:
			return car
	return null

func _place_all() -> void:
	# Traffic 은 원점에 있어 transform 이 곧 전역이다. 트리 밖에서도 쓸 수 있다.
	for car in cars:
		if car.lane == null:
			car.body.transform = Transform3D(Basis(), Vector3(0.0, HIDDEN_Y, 0.0))
			continue
		var forward: Vector3 = car.lane.direction_at(car.distance)
		car.body.transform = Transform3D(Basis.looking_at(forward, Vector3.UP),
			car.lane.sample(car.distance))

func car_of(body: Object) -> Car:
	for car in cars:
		if car.body == body:
			return car
	return null

func hold(body: Object, seconds: float) -> void:
	"""그 차를 seconds 동안 세운다. 이미 더 길게 서 있으면 그대로 둔다."""
	var car := car_of(body)
	if car == null:
		return
	car.hold_s = maxf(car.hold_s, seconds)
	car.speed = 0.0

func police_sees(point: Vector3) -> bool:
	"""어느 경찰차든 point 를 전방 80 m 반구 안에 두고 있는가."""
	for car in cars:
		if not car.is_police:
			continue
		var to_point: Vector3 = point - car.body.global_position
		if to_point.length() > POLICE_SIGHT_M:
			continue
		# 고도트의 정면은 -Z 다.
		if (-car.body.global_transform.basis.z).dot(to_point) > 0.0:
			return true
	return false
