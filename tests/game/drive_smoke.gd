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
	finish()
