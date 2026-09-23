extends Node3D
# 베이크 산출물 검증. 굽힌 .glb/.json 이 게임이 쓸 수 있는 상태인지 본다.
#
# 노선 id 는 --route=<id> 로 받는다:
#   godot --headless --fixed-fps 60 -- --route=seoul-100
#
# 검증 항목:
#   1. route JSON 과 .glb 가 읽히고 충돌 메쉬가 만들어진다
#   2. 경로 폴리라인 위 2 m 간격 표본 아래에 도로가 있다(지면 연속성)
#   3. 정류장에 이름이 있고, 진행도가 단조 증가하며, 서로 너무 붙어 있지 않다
#   4. 실제 물리 버스가 추락 없이 경로를 따라 DRIVE_MIN_M 이상 달린다
#
# 4번은 완주를 요구하지 않는다. 실제 노선에는 12 t 버스가 한 번에 못 도는
# 회차 하핀(-130도)이 있고 사람은 3점 회전으로 돈다. 그런 코너에서 멈추는
# 것은 데이터 결함이 아니라 이 하네스 자율주행의 한계다. 경로점 사이 도로가
# 끊겼는지는 2번이 훨씬 촘촘하게 본다.

const TARGET_SPEED := 9.0       # m/s, 약 32 km/h
const ARRIVE_RADIUS := 25.0     # 웨이포인트 도달 판정
const STUCK_LIMIT := 3.0        # 초. 이보다 오래 멈춰 있으면 주행을 끝낸다
const GROUND_COVERAGE_MIN := 0.98
const STOP_NAME_COVERAGE_MIN := 0.95
const STOP_GAP_MIN := 15.0      # m. 이보다 붙어 있으면 같은 자리에 중복 스냅된 것
const SAMPLE_STEP := 2.0        # m. 지면 연속성 표본 간격
const DRIVE_MIN_M := 100.0      # m. 이만큼은 실제로 굴러가야 한다
# 조향 목표점을 실제 경로점(최대 86m 앞)에 바로 맞추면 급커브에서 코너를
# 크게 잘라 도로 폭(약 7m, DEFAULT_WIDTH) 밖으로 밀려난다. 경로선을 따라
# 이 거리만큼만 앞을 보는 lookahead 목표점을 써서 실제 도로선에 붙어 돈다.
const LOOKAHEAD := 15.0
# 감속 판단용 예측 거리. 조향용 lookahead 보다 멀리 봐서 급커브 진입 전에
# 미리 속도를 줄인다. 현재 조향각만 보고 줄이면 이미 코너 안이라 늦는다.
const PREVIEW := 30.0
const MAX_STEERING := 0.9       # rad, 약 52도. 실제 버스 수준의 최대 조향각

var route: PackedVector3Array = []
var meta: Dictionary = {}
var bus: VehicleBody3D
var waypoint := 1
var elapsed := 0.0
var stuck := 0.0
var max_stuck := 0.0
var min_y := 1e9
var driven := 0.0    # 경로를 따라 전진한 거리(m)
var finished := false
var failures: Array[String] = []
var guide_idx := 0   # 조향용 lookahead 의 경로 투영 인덱스. 앞으로만 전진한다.

func _ready() -> void:
	var route_id := _route_id_from_args()
	# JSON.parse_string 은 실패 시 null 을 돌려준다. meta 는 Dictionary 로 타입
	# 지정돼 있어 null 을 직접 대입하면 그 대입 자체가 런타임 에러다.
	# 먼저 타입 없는 변수로 받아서 검사한 뒤에 meta 에 넣는다.
	var raw := FileAccess.get_file_as_string("res://assets/routes/route_%s.json" % route_id)
	var parsed = JSON.parse_string(raw)
	if parsed == null:
		_fail_now("route JSON 을 읽지 못했다: %s" % route_id)
		return
	meta = parsed
	for point in meta["route"]:
		route.append(Vector3(point[0], 0.0, point[1]))

	var scene: PackedScene = load("res://assets/routes/route_%s.glb" % route_id)
	if scene == null:
		_fail_now("glb 를 읽지 못했다: %s" % route_id)
		return
	var city := scene.instantiate()
	add_child(city)
	for node in city.find_children("*", "MeshInstance3D", true):
		node.create_trimesh_collision()

	await get_tree().physics_frame
	_check_ground_coverage()
	_check_stop_names()
	_check_stop_order()

	bus = _make_bus()
	bus.position = route[0] + Vector3.UP * 1.5
	bus.look_at_from_position(bus.position, route[1] + Vector3.UP * 1.5, Vector3.UP)
	add_child(bus)

	# 창을 띄워 실행할 때만. 검증 자체는 헤드리스라 카메라도 조명도 필요 없다.
	if DisplayServer.get_name() != "headless":
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -30, 0)
		add_child(light)
		var camera := Camera3D.new()
		camera.position = Vector3(0, 6, 14)   # 버스 뒤 위쪽
		camera.rotation_degrees = Vector3(-15, 0, 0)
		camera.far = 2000.0
		bus.add_child(camera)

func _route_id_from_args() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			return argument.trim_prefix("--route=")
	return "seoul-100"

func _make_bus() -> VehicleBody3D:
	var vehicle := VehicleBody3D.new()
	vehicle.mass = 12000.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 3.0, 11.0)
	shape.shape = box
	shape.position = Vector3(0, 2.0, 0)   # 차체 밑면이 지면에 닿으면 주행을 못 한다
	vehicle.add_child(shape)
	# [앞뒤 위치, 좌우 위치, 조향 여부]
	for spec in [[3.6, -1.1, true], [3.6, 1.1, true], [-3.0, -1.1, false], [-3.0, 1.1, false]]:
		var wheel := VehicleWheel3D.new()
		wheel.position = Vector3(spec[1], 0.2, -spec[0])
		wheel.use_as_steering = spec[2]
		wheel.use_as_traction = not spec[2]
		wheel.wheel_radius = 0.5
		wheel.suspension_travel = 0.35
		# 12 t 버스라 기본값(max_force 6000N/바퀴)으로는 차체가 주저앉는다.
		# 4륜 합계 24 kN 인데 버스 무게는 117 kN 이다.
		wheel.suspension_stiffness = 150.0
		wheel.suspension_max_force = 80000.0
		wheel.damping_compression = 3.7
		wheel.damping_relaxation = 6.1
		wheel.wheel_friction_slip = 3.5
		vehicle.add_child(wheel)
	return vehicle

func _check_ground_coverage() -> void:
	# 경로점만 쏘면 179 점뿐이라 점 사이가 끊겨 있어도 모른다. 폴리라인을
	# SAMPLE_STEP 간격으로 나눠 쏴서 구간 내부까지 본다.
	var space := get_world_3d().direct_space_state
	var hits := 0
	var total := 0
	for i in range(route.size() - 1):
		var from_point := route[i]
		var to_point := route[i + 1]
		var steps := int(from_point.distance_to(to_point) / SAMPLE_STEP) + 1
		# t 는 [0, 1) 이다. 구간 끝점은 다음 구간의 t=0 이 맡는다.
		for step in range(steps):
			var point := from_point.lerp(to_point, float(step) / float(steps))
			total += 1
			if _has_ground(space, point):
				hits += 1
	# 마지막 구간의 끝점(노선 종점)만은 뒤를 이을 구간이 없어 빠진다. 직접 쏜다.
	total += 1
	if _has_ground(space, route[-1]):
		hits += 1
	var ratio := float(hits) / float(max(total, 1))
	print("지면 커버리지 %.1f%% (%d/%d, %.0fm 간격)" % [ratio * 100.0, hits, total, SAMPLE_STEP])
	if ratio < GROUND_COVERAGE_MIN:
		failures.append("지면 커버리지 %.3f < %.2f" % [ratio, GROUND_COVERAGE_MIN])

func _has_ground(space: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	var origin := point + Vector3.UP * 30.0
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 60.0)
	return not space.intersect_ray(query).is_empty()

func _check_stop_names() -> void:
	var stops: Array = meta["stops"]
	if stops.is_empty():
		failures.append("정류장이 하나도 없다")
		return
	var named := 0
	for stop in stops:
		if str(stop["name"]).strip_edges() != "":
			named += 1
	var ratio := float(named) / float(stops.size())
	print("정류장 이름 커버리지 %.1f%% (%d/%d)" % [ratio * 100.0, named, stops.size()])
	if ratio < STOP_NAME_COVERAGE_MIN:
		failures.append("정류장 이름 커버리지 %.3f < %.2f" % [ratio, STOP_NAME_COVERAGE_MIN])

func _check_stop_order() -> void:
	var stops: Array = meta["stops"]
	for i in range(1, stops.size()):
		if float(stops[i]["progress_m"]) < float(stops[i - 1]["progress_m"]):
			failures.append("정류장 진행도가 거꾸로다: %s" % stops[i]["name"])
			return
	# 같은 자리에 승강장·출구 번호만 다른 정류장이 여럿 스냅되면 버스가 한
	# 자리에서 두 번 선다. 중복 스냅은 간격으로 드러난다.
	var closest := INF
	var closest_pair := ""
	for i in range(1, stops.size()):
		var gap := float(stops[i]["progress_m"]) - float(stops[i - 1]["progress_m"])
		if gap < closest:
			closest = gap
			closest_pair = "%s/%s" % [stops[i - 1]["name"], stops[i]["name"]]
	if stops.size() < 2:
		return
	print("정류장 최소 간격 %.1fm (%s)" % [closest, closest_pair])
	if closest < STOP_GAP_MIN:
		failures.append("정류장 간격 %.1fm < %.0fm: %s" % [closest, STOP_GAP_MIN, closest_pair])

func _advance_guide() -> void:
	# guide_idx 를 버스의 실제 위치를 따라 앞으로만 전진시킨다(뒤로 가지 않음).
	# waypoint(ARRIVE_RADIUS=25 로만 갱신)를 그대로 쓰면 최대 86m 짜리 긴
	# 구간 위에서 lookahead 시작점이 고정돼 버려, 버스가 그 점을 지나치는
	# 순간 목표가 뒤로 처지고 만다.
	# 단순히 "다음 점까지의 거리가 더 가까운지"로 전진 여부를 판단하면,
	# 급커브에서 다음다음 구간의 점이 현재 구간의 끝점보다 더 가까워
	# 보여 구간 하나를 건너뛸 수 있다(급커브 진입 전에 도로를 벗어나 지름길로
	# 질러가다 포장 밖으로 나가버리는 원인이었다, 실측 확인). 현재 구간 위로
	# 정사영해 t>1(구간을 실제로 지나침)일 때만 전진한다.
	while guide_idx < route.size() - 2 and _segment_t() > 1.0:
		driven += route[guide_idx].distance_to(route[guide_idx + 1])
		guide_idx += 1

func _segment_t() -> float:
	var seg_start: Vector3 = route[guide_idx]
	var seg_vec: Vector3 = route[guide_idx + 1] - seg_start
	var seg_len_sq := seg_vec.length_squared()
	if seg_len_sq <= 0.0001:
		return 2.0   # 길이 0 구간은 즉시 통과시킨다
	return (bus.position - seg_start).dot(seg_vec) / seg_len_sq

func _lookahead_point(distance: float) -> Vector3:
	var seg_start: Vector3 = route[guide_idx]
	var seg_vec: Vector3 = route[min(guide_idx + 1, route.size() - 1)] - seg_start
	# 현재 구간 위 버스의 투영점에서부터 경로선을 따라 distance 만큼 나아간다
	var current_point: Vector3 = seg_start + seg_vec * clamp(_segment_t(), 0.0, 1.0)
	var remaining := distance
	var idx := guide_idx
	while idx < route.size() - 1:
		var next_point: Vector3 = route[idx + 1]
		var seg_len := current_point.distance_to(next_point)
		if seg_len >= remaining:
			return current_point.lerp(next_point, remaining / max(seg_len, 0.001))
		remaining -= seg_len
		current_point = next_point
		idx += 1
	return route[route.size() - 1]

func _physics_process(delta: float) -> void:
	if finished or bus == null:
		return
	elapsed += delta
	min_y = min(min_y, bus.position.y)

	while waypoint < route.size() - 1 and bus.position.distance_to(route[waypoint]) < ARRIVE_RADIUS:
		waypoint += 1
	_advance_guide()

	# 조향 목표는 실제 다음 경로점이 아니라 경로선을 따라 LOOKAHEAD 만큼만
	# 앞선 점을 쓴다(고전적 pure pursuit). waypoint 자체를 목표로 삼으면
	# 코너에서 경로점까지 직선으로 꺾어 들어가느라 도로 리본 폭을 벗어난다.
	var local := bus.to_local(_lookahead_point(LOOKAHEAD))
	# absf(local.z) 는 목표가 뒤쪽(local.z > 0)일 때 방향 정보를 잃어버려
	# 실제 도로의 급커브에서 조향이 0에 가깝게 죽는다. atan2 로 전/후방을
	# 구분하는 부호 있는 헤딩 오차를 쓴다.
	#
	# 부호에 주의: 이 버스는 engine_force 가 음수일 때 -Z(look_at 의 전방)로
	# 나아간다. 그 상태에서는 steering 의 부호도 뒤집혀 있어서 heading_error
	# 를 그대로 주면 반대로 꺾는다. 직선에서는 오차가 0이라 멀쩡해 보이다가
	# 커브에서 오차가 단조 증가하며 도로 밖으로 이탈한다(실측 확인).
	var heading_error := atan2(local.x, -local.z)
	var target_steering: float = clamp(-heading_error * 0.8, -MAX_STEERING, MAX_STEERING)
	# lookahead 목표점이 다음 구간으로 넘어가는 순간(급커브 직후 S자 구간)
	# 목표 조향이 한 프레임 만에 반대쪽으로 확 뒤집힐 수 있다. 실제 조향
	# 장치처럼 초당 변화량을 제한해 순간적으로 반대로 꺾이지 않게 한다.
	bus.steering = move_toward(bus.steering, target_steering, 1.5 * delta)

	var speed := bus.linear_velocity.length()
	# 급커브를 목표 속도 그대로 들어가면 최대 조향각으로도 회전 반경이 모자라
	# 바깥쪽 건물에 박는다. PREVIEW 만큼 앞선 경로점과의 각도 오차로 코너의
	# 급함을 미리 재서, 진입 전에 기어가는 속도까지 줄인다.
	var preview := bus.to_local(_lookahead_point(PREVIEW))
	var preview_error: float = absf(atan2(preview.x, -preview.z))
	var turn_speed: float = TARGET_SPEED * clamp(1.0 - preview_error / 1.2, 0.2, 1.0)
	# Godot 4.7 VehicleBody3D: 음수 engine_force 가 전방(-Z)으로 민다.
	bus.engine_force = -30000.0 if speed < turn_speed else 0.0
	bus.brake = 20.0 if speed > turn_speed * 1.4 else 0.0

	if speed < 0.5:
		stuck += delta
		max_stuck = max(max_stuck, stuck)
	else:
		stuck = 0.0

	if waypoint >= route.size() - 1 and bus.position.distance_to(route[-1]) < ARRIVE_RADIUS:
		_finish("완주")
	elif bus.position.y < -5.0:
		failures.append("버스가 지면 아래로 떨어졌다")
		_finish("추락")
	elif stuck > STUCK_LIMIT:
		_finish("교착")

func _finish(reason: String) -> void:
	finished = true
	print("주행 %s: %.0fm 전진, 경로점 %d/%d, 시간 %.1f초, 최저 y %.2f, 위치 (%.1f, %.1f, %.1f)"
		% [reason, driven, waypoint, route.size() - 1, elapsed, min_y,
			bus.position.x, bus.position.y, bus.position.z])
	if driven < DRIVE_MIN_M:
		failures.append("주행 거리 %.0fm < %.0fm" % [driven, DRIVE_MIN_M])
	_report()

func _fail_now(message: String) -> void:
	failures.append(message)
	_report()

func _report() -> void:
	if failures.is_empty():
		print("VERIFY_OK")
		get_tree().quit(0)
		return
	for failure in failures:
		print("VERIFY_FAIL: %s" % failure)
	get_tree().quit(1)
