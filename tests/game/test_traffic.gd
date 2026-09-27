extends TestCase
# seoul-100 실데이터 위에서 교통을 20 초 돌린다. 버스 대신 빈 Node3D 를 노선을
# 따라 옮긴다 — 교통은 버스 위치만 본다. 신호 시계는 테스트가 물리 시간으로
# 돌린다. 실제 시계를 쓰면 헤드리스 속도에 따라 황색 3 초가 늘었다 줄었다 한다.

const RUN_S := 20.0
const MOVER_MPS := 8.0
const MIN_BUMPER_GAP_M := 4.0
const TELEPORT_M := 5.0     # 한 프레임에 이보다 많이 옮겨졌으면 재활용이다

var traffic: Traffic
var mover: Node3D
var lane: LanePath
var mover_m := 0.0
var elapsed := 0.0
var previous_front := {}    # Car -> 직전 앞 범퍼 누적 거리
var red_runs := 0
var tight := 0
var stopped_at_red := false
var saw_cross := false
var oneway_oncoming := 0    # 일방통행 구간을 달린 마주 오는 차
var saw_lanes := false      # 같은 방향 차가 두 차선 이상에 퍼진 적이 있다
var multi_lane := false     # 방향당 두 차선 이상인 구간이 있다(옛 json 은 없다)
var start_distances: Array = []
var done := false

func _ready() -> void:
	TrafficSignal.time_override = 0.0
	var data := RouteData.load_route("seoul-100")
	for count in data.route_lanes:
		multi_lane = multi_lane or count >= 4
	lane = LanePath.make(data.route)
	lane.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)
	ok(not lane.stops.is_empty(), "seoul-100 에 정지선이 없다")
	if lane.stops.is_empty():
		finish()
		return
	# 첫 교차로 100 m 앞에서 출발한다. 교차 차량이 바로 생긴다.
	mover_m = maxf(float(lane.stops[0]["at_m"]) - 100.0, 0.0)
	mover = Node3D.new()
	add_child(mover)
	mover.global_position = lane.sample(mover_m)

	traffic = Traffic.new()
	traffic.build(data, mover)
	add_child(traffic)
	ok(traffic.cars.size() == Traffic.SAME_COUNT + Traffic.ONCOMING_COUNT + Traffic.CROSS_MAX,
		"차가 %d 대다" % traffic.cars.size())
	var police := 0
	for car in traffic.cars:
		if car.is_police:
			police += 1
	ok(police == 2, "경찰차가 %d 대다" % police)
	start_distances = traffic.cars.map(func(car) -> float: return car.distance)

func _physics_process(delta: float) -> void:
	if done or traffic == null:
		return
	# Traffic 은 자식이라 이 노드 다음에 돈다. 여기서 보는 위치는 직전 프레임
	# 결과고, 그때 쓴 신호 시각은 아직 올리기 전인 지금 값이다.
	_check(TrafficSignal.now())
	elapsed += delta
	TrafficSignal.time_override += delta
	mover_m = minf(mover_m + MOVER_MPS * delta, lane.length_m())
	mover.global_position = lane.sample(mover_m)
	if elapsed >= RUN_S:
		_report()

func _check(t: float) -> void:
	var by_road := {}
	var forward_lanes := {}
	for car in traffic.cars:
		if car.crossing >= 0:
			saw_cross = true
		if car.road == null or car.parked:
			continue
		if car.road == traffic.backward_road \
				and traffic.lane_count_at(car.road, car.distance) == 0:
			oneway_oncoming += 1
		if car.road == traffic.forward_road:
			forward_lanes[car.lane_index] = true
		if not by_road.has(car.road):
			by_road[car.road] = []
		by_road[car.road].append(car)
		var front: float = car.distance + Traffic.CAR_HALF_LENGTH_M
		var was: float = previous_front.get(car, front)
		previous_front[car] = front
		if front > was and front - was < TELEPORT_M:
			for line in car.road.stops:
				var at: float = line["at_m"]
				if was < at and front >= at and TrafficSignal.phase_at(
						line["offset"], line["axis"], t) == TrafficSignal.Phase.RED:
					red_runs += 1
		if car.speed < 0.1:
			var line: Dictionary = car.road.next_stop(front)
			if not line.is_empty() and float(line["at_m"]) - front < 3.0 \
					and TrafficSignal.phase_at(line["offset"], line["axis"], t) \
					== TrafficSignal.Phase.RED:
				stopped_at_red = true
	if forward_lanes.size() >= 2:
		saw_lanes = true
	# 범퍼 간격은 가로로 겹치는 차끼리만 본다. 옆 차선 차는 나란히 서도 된다.
	for queue in by_road.values():
		for car in queue:
			for other in queue:
				if other == car or other.distance < car.distance \
						or absf(other.side_m - car.side_m) >= Traffic.LATERAL_M:
					continue
				var gap: float = other.distance - car.distance - Traffic.CAR_HALF_LENGTH_M * 2.0
				if gap < MIN_BUMPER_GAP_M and other.distance > car.distance:
					tight += 1

func _report() -> void:
	done = true
	ok(red_runs == 0, "적색 정지선을 넘은 차가 %d 번" % red_runs)
	ok(stopped_at_red, "적색 정지선 앞에 선 차가 한 번도 없다")
	ok(tight == 0, "범퍼 간격 %.0f m 미만이 %d 번" % [MIN_BUMPER_GAP_M, tight])
	ok(saw_cross, "교차 차량이 안 생겼다")
	ok(oneway_oncoming == 0, "일방통행 구간을 마주 오는 차가 %d 번 달렸다" % oneway_oncoming)
	ok(saw_lanes or not multi_lane, "같은 방향 차가 한 차선만 썼다")
	var moved := false
	for index in traffic.cars.size():
		if absf(traffic.cars[index].distance - start_distances[index]) > 1.0:
			moved = true
	ok(moved, "차가 하나도 안 움직였다")
	# 버스 창 안에 같은 방향 차가 거의 다 있어야 한다. 재활용이 막힌 한 대는 봐준다.
	var along := traffic.forward_road.project(mover.global_position).x
	var inside := 0
	for car in traffic.cars:
		if car.road == traffic.forward_road and not car.parked \
				and car.distance >= along - Traffic.BEHIND_M - Traffic.SPAWN_GAP_M \
				and car.distance <= along + Traffic.AHEAD_M + Traffic.SPAWN_GAP_M:
			inside += 1
	ok(inside >= Traffic.SAME_COUNT - 1, "창 안 같은 방향 차가 %d 대다" % inside)
	TrafficSignal.time_override = -1.0
	finish()
