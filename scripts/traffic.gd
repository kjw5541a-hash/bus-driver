extends Node3D
class_name Traffic
# 노선 위 일반 차량, 신호 교차로의 교차 차량, 경찰차. 물리 차량이 아니라
# 스크립트가 차선 누적 거리를 따라 옮기는 충돌 몸체(AnimatableBody3D)다.
# 속도는 CarFollow 가, 차선과 정지선은 LanePath 가 낸다.
#
# 노선 차량은 도로 중심선 위 두 도로(정방향·역방향)를 달리고, 차마다 중심선에서
# 오른쪽으로 떨어진 가로 위치(side_m)를 든다. 앞차는 가로로 겹치는 차 중 가장
# 가까운 차다. 막히면 옆 차선으로 옮긴다. 일방통행 구간에는 마주 오는 차가 없다.
#
# 차는 버스 둘레 창 안에만 둔다. 창을 벗어난 차는 지우지 않고 반대쪽 끝으로
# 옮겨 다시 쓴다. 노드는 build() 에서 만든 것을 끝까지 쓴다.

const SAME_COUNT := 10
const ONCOMING_COUNT := 8
const AHEAD_M := 250.0
const BEHIND_M := 100.0
const FIRST_AHEAD_M := 30.0       # 처음 배치할 때 버스 바로 앞은 비운다
const SPAWN_GAP_M := 20.0
const CROSS_RADIUS_M := 150.0
const CROSS_MAX := 6
const CROSS_SITES := 3            # CROSS_MAX 의 절반. 교차로마다 두 방향
const BUS_HALF_LENGTH_M := 5.5    # Bus 충돌 상자 길이 11 m 의 절반
const BUS_HALF_WIDTH_M := 1.25    # Bus 충돌 상자 폭 2.5 m 의 절반
const CAR_HALF_WIDTH_M := 0.9     # BODY_SIZE.x 의 절반
const LATERAL_M := 2.4            # 가로로 이보다 가까운 차는 같은 줄이다(차 폭 + 0.6)
const BUS_LATERAL_M := BUS_HALF_WIDTH_M + CAR_HALF_WIDTH_M + 0.3
const LANE_SHIFT_MPS := 1.2       # 차선 중앙으로 옆걸음하는 최대 속도
const CHANGE_COOLDOWN_S := 4.0
const BLOCKED_GAP_M := 30.0       # 앞차가 이 안에 있고
const BLOCKED_SPEED_RATIO := 0.7  # 순항 속도의 이 비율보다 느리면 막힌 것이다
const NO_CHANGE_BEFORE_M := 25.0  # 정지선 앞뒤로는 차선을 안 바꾼다
const NO_CHANGE_AFTER_M := 10.0
const CHANGE_GAIN_M := 10.0       # 옮길 차선의 앞 간격이 지금보다 이만큼은 커야 한다
const REAR_GAP_M := 8.0           # 옮길 차선 뒤차와 최소 간격
const REAR_GAP_S := 1.0           # 뒤차 속도 1 m/s 마다 더 벌릴 간격
const ARM_AXIS_DEG := 45.0        # 교차 축 방위각에서 이만큼 안의 갈래만 쓴다
const ARM_FACING_DEG := 45.0      # 두 갈래가 180° ± 이 안이면 마주 본다
const ARM_BEARING_M := 10.0       # 갈래 방위각은 첫 점에서 이만큼 간 점으로 잰다
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
	var road: LanePath             # null 이면 쉬는 교차 차량
	var distance := 0.0
	var speed := 0.0
	var hold_s := 0.0
	var is_police := false
	var crossing := -1             # 교차 차량이 맡은 신호 인덱스. 노선 차량은 -1
	var lane_index := 0            # 가려는 차선. 0 이 중앙선(일방통행이면 왼쪽 끝) 쪽
	var side_m := 0.0              # 도로 중심선에서 진행 방향 오른쪽으로 떨어진 거리
	var parked := false            # 일방통행 구간이라 치워 둔 마주 오는 차
	var change_s := 0.0            # 다음 차선 변경을 따질 수 있을 때까지

var cars: Array = []
var forward_road: LanePath
var backward_road: LanePath

var _bus: Node3D
var _signals: Array = []
var _cross_lanes: Dictionary = {}  # 신호 인덱스 -> [LanePath, ...]
var _lanes: PackedInt32Array = []   # 정방향 경로점 순서
var _oneway: PackedByteArray = []
var _widths: PackedFloat32Array = []
var _by_road: Dictionary = {}       # LanePath -> [Car], 이번 프레임에 달리는 차

func build(data: RouteData, bus: Node3D) -> void:
	_bus = bus
	if data.route.size() < 2:
		# 경로가 없으면 차도 없다.
		return
	_signals = data.signals
	data.ensure_lanes()
	_lanes = data.route_lanes
	_oneway = data.route_oneway
	_widths = data.route_width
	var center := data.center_line()
	forward_road = LanePath.make(center)
	forward_road.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)
	var back := center.duplicate()
	back.reverse()
	backward_road = LanePath.make(back)
	backward_road.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)

	# 같은 방향 차는 버스 앞에만 깐다. 뒤에 깔면 첫 프레임에 버스와 겹칠 수 있다.
	var along := forward_road.project(_bus_point()).x
	for index in SAME_COUNT:
		_put(_make_car(index == 0, index), forward_road, minf(along + FIRST_AHEAD_M
			+ (AHEAD_M - FIRST_AHEAD_M) * index / SAME_COUNT, forward_road.length_m()),
			index)
	# 역방향 도로에서 버스 앞은 누적 거리가 작은 쪽이다.
	var facing := backward_road.project(_bus_point()).x
	for index in ONCOMING_COUNT:
		_put(_make_car(index == 0, index + 1), backward_road, clampf(facing - AHEAD_M
			+ (AHEAD_M + BEHIND_M) * (index + 0.5) / ONCOMING_COUNT,
			0.0, backward_road.length_m()), index)
	for index in CROSS_MAX:
		_make_car(false, index + 2)
	_place_all()

func _put(car: Car, road: LanePath, distance: float, lane_index: int) -> void:
	car.road = road
	car.distance = distance
	car.speed = 0.0
	var count := lane_count_at(road, distance)
	car.parked = count == 0
	car.lane_index = lane_index % maxi(count, 1)
	car.side_m = lane_side(road, distance, car.lane_index)

func _is_route(road: LanePath) -> bool:
	return road != null and (road == forward_road or road == backward_road)

func _point_index(road: LanePath, distance: float) -> int:
	var index := road.index_at(distance)
	return index if road == forward_road else _lanes.size() - 1 - index

func lane_count_at(road: LanePath, distance: float) -> int:
	"""그 지점 그 방향의 차선 수. 교차 차선은 1."""
	if not _is_route(road):
		return 1
	var index := _point_index(road, distance)
	return Lanes.count_for(_lanes[index], _oneway[index] == 1, road == forward_road)

func lane_side(road: LanePath, distance: float, lane_index: int) -> float:
	"""차선 중앙의 가로 위치. 교차 차선은 비킴이 차선 점에 들어 있어 0."""
	if not _is_route(road):
		return 0.0
	var index := _point_index(road, distance)
	return Lanes.side_of(lane_index, _lanes[index], _widths[index], _oneway[index] == 1)

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
	return forward_road.sample(0.0)

func _physics_process(delta: float) -> void:
	if forward_road == null:
		return
	var bus_point := _bus_point()
	_update_crossings(bus_point)
	var t := TrafficSignal.now()
	_by_road = {}
	for car in cars:
		if car.road != null and not car.parked:
			if not _by_road.has(car.road):
				_by_road[car.road] = []
			_by_road[car.road].append(car)
	# 버스를 도로마다 한 번씩만 투영한다. 재활용도 같은 값을 쓴다.
	var bus_on := {}
	for road in [forward_road, backward_road] + _by_road.keys():
		if not bus_on.has(road):
			bus_on[road] = road.project(bus_point) if _bus != null else Vector2(INF, INF)
	for road in _by_road:
		for car in _by_road[road]:
			_drive(car, bus_on[road], t, delta)
	_recycle(bus_on)
	_place_all()

func _drive(car: Car, bus_on: Vector2, t: float, delta: float) -> void:
	if car.hold_s > 0.0:
		car.hold_s = maxf(car.hold_s - delta, 0.0)
		car.speed = 0.0
		return
	if _is_route(car.road):
		var count := lane_count_at(car.road, car.distance)
		if count == 0:
			# 마주 오는 차가 일방통행 구간에 들어섰다. 치우고 재활용에 맡긴다.
			car.parked = true
			return
		# 차선이 줄어드는 곳에서는 남은 가장 바깥 차선으로 합류한다.
		car.lane_index = mini(car.lane_index, count - 1)
		car.change_s = maxf(car.change_s - delta, 0.0)
		if car.change_s <= 0.0:
			_consider_change(car, count, bus_on)
		car.side_m = move_toward(car.side_m,
			lane_side(car.road, car.distance, car.lane_index), LANE_SHIFT_MPS * delta)
	var front := car.distance + CAR_HALF_LENGTH_M
	var gap := _ahead(car.road, car.distance, car.side_m, car, bus_on).x
	var stop_m := INF
	var phase := TrafficSignal.Phase.GREEN
	var line := car.road.next_stop(front)
	if not line.is_empty():
		stop_m = float(line["at_m"]) - front
		phase = TrafficSignal.phase_at(float(line["offset"]), int(line["axis"]), t)
	car.speed = CarFollow.next_speed(car.speed, gap, stop_m, phase, delta)
	car.distance = minf(car.distance + car.speed * delta, car.road.length_m())

func _ahead(road: LanePath, distance: float, side: float, me: Car, bus_on: Vector2) -> Vector2:
	"""가로로 겹치는 가장 가까운 앞 장애물의 (범퍼 간격, 속도). 없으면 (INF, 0).

	차선을 옮기는 중인 차는 가로 위치로 두 차선 모두에 걸리므로 따로 볼 게 없다."""
	# ponytail: 같은 도로 차 전부를 훑는다(10 대 안팎). 늘어나면 거리순 정렬 후 이웃만 본다.
	var front := distance + CAR_HALF_LENGTH_M
	var best := Vector2(INF, 0.0)
	for other in _by_road.get(road, []):
		if other == me or other.distance <= distance \
				or absf(other.side_m - side) >= LATERAL_M:
			continue
		var gap: float = other.distance - CAR_HALF_LENGTH_M - front
		if gap < best.x:
			best = Vector2(gap, other.speed)
	# 차로 옆으로 비켜 선 버스(정류장)는 장애물이 아니다. 그러면 뒤차가 영원히 선다.
	if bus_on.x > distance and absf(bus_on.y - side) < BUS_LATERAL_M:
		var gap := bus_on.x - BUS_HALF_LENGTH_M - front
		if gap < best.x:
			best = Vector2(gap, _bus_speed())
	return best

func _bus_speed() -> float:
	var velocity = _bus.get("linear_velocity") if _bus != null else null
	return velocity.length() if velocity is Vector3 else 0.0

func _consider_change(car: Car, count: int, bus_on: Vector2) -> void:
	"""막혔으면 옆 차선으로 옮긴다. 정지선 근처와 뒤차가 붙은 차선은 피한다."""
	var here := _ahead(car.road, car.distance, car.side_m, car, bus_on)
	if here.x >= BLOCKED_GAP_M or here.y >= BLOCKED_SPEED_RATIO * CarFollow.CRUISE_MPS:
		return
	var front := car.distance + CAR_HALF_LENGTH_M
	for line in car.road.stops:
		var to_line := float(line["at_m"]) - front
		if to_line < NO_CHANGE_BEFORE_M and to_line > -NO_CHANGE_AFTER_M:
			return
	var best := -1
	var best_gap := here.x + CHANGE_GAIN_M
	for lane in [car.lane_index - 1, car.lane_index + 1]:
		if lane < 0 or lane >= count:
			continue
		var side := lane_side(car.road, car.distance, lane)
		var gap := _ahead(car.road, car.distance, side, car, bus_on).x
		if gap > best_gap and _rear_clear(car, side):
			best = lane
			best_gap = gap
	if best >= 0:
		car.lane_index = best
		car.change_s = CHANGE_COOLDOWN_S

func _rear_clear(car: Car, side: float) -> bool:
	for other in _by_road.get(car.road, []):
		if other == car or other.distance > car.distance \
				or absf(other.side_m - side) >= LATERAL_M:
			continue
		var gap: float = car.distance - other.distance - CAR_HALF_LENGTH_M * 2.0
		if gap <= REAR_GAP_M + other.speed * REAR_GAP_S:
			return false
	return true

func _recycle(bus_on: Dictionary) -> void:
	for car in cars:
		if car.road == null:
			continue
		var on: Vector2 = bus_on.get(car.road, Vector2(INF, INF))
		if car.road == forward_road:
			_recycle_route(car, on.x - BEHIND_M, on.x + AHEAD_M, on.x + AHEAD_M, on)
		elif car.road == backward_road:
			_recycle_route(car, on.x - AHEAD_M, on.x + BEHIND_M, on.x - AHEAD_M, on)
		elif car.distance >= car.road.length_m() and _free_at(car.road, 0.0, 0.0, car, on):
			# 교차 차량은 차선 끝에 닿으면 처음으로 돌아간다.
			car.distance = 0.0
			car.speed = 0.0

func _recycle_route(car: Car, low: float, high: float, entry: float, bus_on: Vector2) -> void:
	"""창을 벗어난 차를 반대쪽 끝으로, 치워 둔 차를 버스 앞 끝(entry)으로 옮긴다."""
	var length := car.road.length_m()
	low = maxf(low, 0.0)
	high = minf(high, length)
	var target: float
	if car.parked:
		target = clampf(entry, 0.0, length)
	elif car.distance > high or car.distance >= length:
		target = low
	elif car.distance < low:
		target = high
	else:
		return
	var count := lane_count_at(car.road, target)
	if count == 0:
		# 일방통행 구간이다. 치워 두고 다음 프레임에 다시 본다.
		car.parked = true
		return
	# 무작위 차선부터 본다. 자리가 차 있으면 옆 차선, 다 차 있으면 다음 프레임.
	var first := randi() % count
	for step in count:
		var lane := (first + step) % count
		var side := lane_side(car.road, target, lane)
		if _free_at(car.road, target, side, car, bus_on):
			car.distance = target
			car.speed = 0.0
			car.lane_index = lane
			car.side_m = side
			car.parked = false
			return

func _free_at(road: LanePath, distance: float, side: float, moving: Car,
		bus_on: Vector2) -> bool:
	if absf(bus_on.y - side) < BUS_LATERAL_M and absf(bus_on.x - distance) < SPAWN_GAP_M:
		return false
	for other in cars:
		if other != moving and other.road == road and not other.parked \
				and absf(other.distance - distance) < SPAWN_GAP_M \
				and absf(other.side_m - side) < LATERAL_M:
			return false
	return true

func _update_crossings(bus_point: Vector3) -> void:
	# 버스 반경 안 노선 신호를 가까운 순으로 CROSS_SITES 곳까지 고른다.
	var nearest := {}   # 신호 인덱스 -> [거리, 정지선]
	for line in forward_road.stops:
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
			car.road = null
	for index in picked:
		if served.has(index):
			continue
		for lane in _crossing_lanes(index, nearest[index][1]):
			var car := _idle_car()
			if car == null:
				return
			car.road = lane
			car.crossing = index
			car.distance = 0.0
			car.speed = 0.0
			car.lane_index = 0
			car.side_m = 0.0
			car.parked = false

func _crossing_lanes(index: int, line: Dictionary) -> Array:
	"""버스가 지나지 않는 축으로 교차로를 가로지르는 차선들. 갈래가 있으면
	마주 보는 갈래 한 쌍 위로, 옛 산출물이면 축 방위각 직선으로 낸다."""
	if not _cross_lanes.has(index):
		var entry: Dictionary = _signals[index]
		var axis := 1 - int(line["axis"])
		var bearing := float(entry["axis_deg"][axis])
		var half := float(entry.get("half_width", ViolationWatch.DEFAULT_HALF_WIDTH))
		var offset := float(line["offset"])
		if entry.has("arms"):
			_cross_lanes[index] = _arm_lanes(entry["arms"], bearing, half, axis, offset)
		else:
			var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
			_cross_lanes[index] = [
				LanePath.crossing(center, bearing, half, axis, offset),
				LanePath.crossing(center, bearing + 180.0, half, axis, offset)]
	return _cross_lanes[index]

func _arm_lanes(arms: Array, bearing: float, half: float, axis: int, offset: float) -> Array:
	"""교차 축 방위각 가까이 마주 보는 갈래 한 쌍 위 차선. 없으면 빈 배열이고,
	그 교차로에는 교차 차량이 없다. T자 교차로에서 도로 없는 쪽으로 달리는 것보다
	낫다."""
	var near: Array = []   # [갈래, 방위각]
	for arm in arms:
		var points := LanePath.arm_points(arm)
		if points.size() < 2:
			continue
		var heading := TrafficSignal.bearing_of(
			LanePath.make(points).sample(ARM_BEARING_M) - points[0])
		if _axis_delta(heading, bearing) <= ARM_AXIS_DEG:
			near.append([arm, heading])
	var pair: Array = []
	var best := ARM_FACING_DEG
	for i in near.size():
		for j in range(i + 1, near.size()):
			var facing := absf(180.0 - _angle_delta(near[i][1], near[j][1]))
			if facing <= best:
				best = facing
				pair = [near[i][0], near[j][0]]
	var lanes: Array = []
	if pair.is_empty():
		return lanes
	for way in [[pair[0], pair[1]], [pair[1], pair[0]]]:
		if way[0]["inbound"] and way[1]["outbound"]:
			var lane := LanePath.from_arms(way[0], way[1], half, axis, offset)
			if lane != null:
				lanes.append(lane)
	return lanes

static func _angle_delta(a: float, b: float) -> float:
	"""두 방위각 사이 각(0~180)."""
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)

static func _axis_delta(a: float, b: float) -> float:
	"""축(방향 무시) 사이 각(0~90)."""
	var delta := _angle_delta(a, b)
	return minf(delta, 180.0 - delta)

func _idle_car() -> Car:
	for car in cars:
		if car.road == null:
			return car
	return null

func _place_all() -> void:
	# Traffic 은 원점에 있어 transform 이 곧 전역이다. 트리 밖에서도 쓸 수 있다.
	for car in cars:
		if car.road == null or car.parked:
			car.body.transform = Transform3D(Basis(), Vector3(0.0, HIDDEN_Y, 0.0))
			continue
		var forward: Vector3 = car.road.direction_at(car.distance)
		var right := Vector3(-forward.z, 0.0, forward.x)
		car.body.transform = Transform3D(Basis.looking_at(forward, Vector3.UP),
			car.road.sample(car.distance) + right * car.side_m)

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
