extends TestCase
# 주행 씬이 조립되고 버스가 실제로 굴러가는지 본다. 1번의 자율주행 조향을
# 축 입력으로 옮겨 먹인다. 완주는 요구하지 않는다 — 최대 조향각이 줄어
# 하핀은 1번보다 더 못 돈다. 경로점 사이 도로 연속성은 1번의
# tests/bake/verify.gd 가 2 m 간격 샘플링으로 이미 훨씬 촘촘하게 본다.

const DRIVE_MIN_M := 100.0
const TARGET_SPEED := 8.0
const LOOKAHEAD := 15.0
const STUCK_LIMIT := 5.0
const MIN_Y := -5.0

var drive: Drive
var driven := 0.0
var guide_index := 0
var stuck := 0.0
var done := false

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/drive.tscn")
	drive = scene.instantiate()
	add_child(drive)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# drive.gd 는 매 프레임 입력을 읽어 버스에 먹인다. 헤드리스에서는 입력이
	# 전부 0 이라, 그대로 두면 이 테스트가 넣는 축을 매 프레임 덮어쓴다.
	drive.set_physics_process(false)

	ok(drive.data != null, "노선 데이터가 없다")
	ok(drive.city != null and drive.city.chunk_nodes.size() > 0, "도시가 비었다")
	ok(drive.bus != null, "버스가 없다")
	ok(drive.camera != null, "카메라가 없다")
	# 카메라가 버스 앞을 비추면 게임이 안 된다. SpringArm3D 가 자식을 어느
	# 축으로 밀어내는지는 눈으로 보기 전엔 헷갈리므로 여기서 단언한다.
	# 이 단언은 ChaseCamera 가 첫 프레임에 요를 스냅해야만 의미가 있다.
	# 지연 추종 중에는 피벗 요가 버스 요와 달라 거리 측정이 엉뚱해진다.
	if drive.camera != null and drive.bus != null:
		# 런타임에 만든 노드는 owner 가 없다. find_children 의 owned 를 꺼야 찾는다.
		var camera_node := drive.camera.find_children("*", "Camera3D", true, false)[0] as Camera3D
		var forward := -drive.bus.global_transform.basis.z
		var offset := camera_node.global_position - drive.bus.global_position
		var behind := -offset.dot(forward)
		ok(behind > 10.0 and behind < 30.0,
			"카메라가 버스 뒤 10-30 m 밖이다 (%.1f m)" % behind)
		ok(offset.y > 2.0, "카메라가 버스보다 높지 않다 (%.1f m)" % offset.y)

		# 시점 조작이 한계를 넘으면 카메라가 버스 안으로 들어가거나 뒤집힌다.
		var arm := drive.camera.find_children("*", "SpringArm3D", true, false)[0] as SpringArm3D
		drive.camera.apply_orbit(0.0, -900.0, -900.0)
		equal_approx(arm.spring_length, ChaseCamera.DISTANCE_MIN, 0.01, "줌 하한을 넘었다")
		equal_approx(arm.rotation_degrees.x, ChaseCamera.PITCH_MIN_DEG, 0.01, "피치 하한을 넘었다")
		drive.camera.apply_orbit(0.0, 900.0, 900.0)
		equal_approx(arm.spring_length, ChaseCamera.DISTANCE_MAX, 0.01, "줌 상한을 넘었다")
		equal_approx(arm.rotation_degrees.x, ChaseCamera.PITCH_MAX_DEG, 0.01, "피치 상한을 넘었다")
		drive.camera.reset_view()
		equal_approx(arm.spring_length, ChaseCamera.ARM_LENGTH, 0.01, "시점 복귀가 안 됐다")

	if drive.data == null or drive.bus == null:
		done = true
		finish()

func _physics_process(delta: float) -> void:
	if done or drive == null or drive.bus == null or drive.data == null:
		return
	var bus := drive.bus
	if bus.global_position.y < MIN_Y:
		ok(false, "버스가 지면 아래로 떨어졌다")
		_report()
		return

	_advance_guide()
	var target := _lookahead_point(LOOKAHEAD)
	var local := bus.to_local(target)
	# 목표가 뒤쪽일 때도 방향을 잃지 않도록 부호 있는 헤딩 오차를 쓴다.
	var heading_error := atan2(local.x, -local.z)
	var steer := clampf(heading_error / Bus.MAX_STEERING, -1.0, 1.0)
	var speed := bus.linear_velocity.length()
	var throttle := 1.0 if speed < TARGET_SPEED else 0.0
	bus.apply_axes(steer, throttle, 0.0, false, delta)

	stuck = stuck + delta if speed < 0.5 else 0.0
	if driven >= DRIVE_MIN_M or stuck > STUCK_LIMIT:
		_report()

func _advance_guide() -> void:
	var route := drive.data.route
	while guide_index < route.size() - 2 and _segment_t() > 1.0:
		driven += route[guide_index].distance_to(route[guide_index + 1])
		guide_index += 1

func _segment_t() -> float:
	var route := drive.data.route
	var start: Vector3 = route[guide_index]
	var segment: Vector3 = route[guide_index + 1] - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return 2.0
	return (drive.bus.global_position - start).dot(segment) / length_squared

func _lookahead_point(distance: float) -> Vector3:
	var route := drive.data.route
	var start: Vector3 = route[guide_index]
	var segment: Vector3 = route[mini(guide_index + 1, route.size() - 1)] - start
	var current: Vector3 = start + segment * clampf(_segment_t(), 0.0, 1.0)
	var remaining := distance
	var index := guide_index
	while index < route.size() - 1:
		var next_point: Vector3 = route[index + 1]
		var length := current.distance_to(next_point)
		if length >= remaining:
			return current.lerp(next_point, remaining / maxf(length, 0.001))
		remaining -= length
		current = next_point
		index += 1
	return route[route.size() - 1]

func _report() -> void:
	done = true
	print("주행 %.0fm, 경로점 %d/%d" % [driven, guide_index, drive.data.route.size() - 1])
	ok(driven >= DRIVE_MIN_M, "주행 거리 %.0fm < %.0fm" % [driven, DRIVE_MIN_M])

	# 신호등이 섰는지, 근거리 컬링이 실제로 도는지 본다.
	ok(drive.signal_field != null, "SignalField 가 없다")
	ok(drive.watch != null, "ViolationWatch 가 없다")
	ok(drive.patrol != null, "PatrolCars 가 없다")
	ok(drive.signal_field.head_count == drive.data.signals.size() * 4,
		"기둥이 %d 개인데 신호는 %d 개다"
		% [drive.signal_field.head_count, drive.data.signals.size()])
	ok(drive.signal_field.min_pole_clearance > 0.0,
		"신호등 기둥이 차도 위에 서 있다 (여유 %.2f m)"
		% drive.signal_field.min_pole_clearance)
	ok(drive.signal_field.updated_count > 0, "기둥을 하나도 갱신하지 않았다")
	ok(drive.signal_field.updated_count < drive.signal_field.head_count,
		"근거리 컬링이 안 걸려 기둥 %d 개를 전부 갱신했다"
		% drive.signal_field.head_count)
	# 신호 기둥에는 충돌면이 없어야 한다. 있으면 인도 위 기둥에 버스가 걸린다.
	ok(drive.signal_field.find_children("*", "StaticBody3D", true, false).is_empty(),
		"신호 기둥에 충돌면이 붙었다")

	# 정류장이 섰는지, 컬링이 실제로 도는지 본다.
	ok(drive.stop_field != null, "StopField 가 없다")
	ok(drive.boarding != null, "BoardingWatch 가 없다")
	ok(drive.boarding_hud != null, "BoardingHud 가 없다")
	# 이 테스트는 drive 의 물리 처리를 꺼서 HUD 갱신이 안 돈다. 직접 부른다.
	drive.boarding_hud.update_status(drive.boarding)
	drive.boarding_hud.on_bell_rung(0)
	ok(drive.boarding_hud.bell_count == 1, "하차벨 차임이 안 울렸다")
	ok(drive.data.stop_targets.size() == drive.data.stops.size(),
		"정차 목표점이 %d 개인데 정류장은 %d 곳이다"
		% [drive.data.stop_targets.size(), drive.data.stops.size()])
	ok(drive.stop_field.sign_count == drive.data.stops.size(),
		"표지판이 %d 개인데 정류장은 %d 곳이다"
		% [drive.stop_field.sign_count, drive.data.stops.size()])
	ok(drive.stop_field.updated_count > 0, "정류장을 하나도 안 보였다")
	ok(drive.stop_field.updated_count < drive.data.stops.size(),
		"거리 컬링이 안 걸려 정류장 %d 곳을 전부 보였다"
		% drive.data.stops.size())
	# 승객에 충돌면이 붙으면 버스가 사람을 들이받고 주행이 막힌다.
	ok(drive.stop_field.find_children("*", "StaticBody3D", true, false).is_empty(),
		"정류장에 충돌면이 붙었다")

	# 구간·시계·결과 화면 배선.
	ok(drive.data.section == 0, "구간 0 으로 뜨지 않았다 (%d)" % drive.data.section)
	ok(drive.data.section_count > 1, "노선이 구간으로 안 잘렸다")
	ok(drive.clock != null and drive.clock.deadline_s > 0.0, "RunClock 마감이 없다")
	ok(drive.clock != null and drive.clock.elapsed_s > 0.0, "시계가 안 돈다")
	ok(drive.clock_hud != null, "ClockHud 가 없다")
	ok(drive.result != null and not drive.result.visible, "결과 화면이 처음부터 떠 있다")
	if drive.result != null:
		drive.result.show_result(ScoreCard.tally(100.0, 600.0, 3, 1, 0, 0, 0, 0),
			"테스트", true)
		ok(drive.result.visible and drive.result.line_count == 4,
			"결과 화면 줄이 %d 개다" % drive.result.line_count)
	finish()
