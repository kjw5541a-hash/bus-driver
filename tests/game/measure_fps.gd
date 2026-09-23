extends Node3D
# 창 모드 전용 성능 측정. 헤드리스는 렌더링을 안 하므로 의미가 없다.
#   godot res://tests/game/measure_fps.tscn -- --route=seoul-100
# seoul-100 을 자율주행으로 달리며 프레임을 기록한다. 판정은 사람이 본다.

const WARMUP_SECONDS := 3.0      # 셰이더 컴파일과 첫 프레임 튐을 버린다
const MEASURE_SECONDS := 30.0
const TARGET_SPEED := 12.0
const LOOKAHEAD := 15.0

var drive: Drive
var elapsed := 0.0
var samples: Array[float] = []
var guide_index := 0
var done := false

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/drive.tscn")
	drive = scene.instantiate()
	add_child(drive)
	await get_tree().physics_frame
	# 자율주행으로 몰 것이므로 drive.gd 의 입력 처리를 끈다.
	drive.set_physics_process(false)

func _physics_process(delta: float) -> void:
	if done or drive == null or drive.bus == null or drive.data == null:
		return
	elapsed += delta

	var bus := drive.bus
	_advance_guide()
	var local := bus.to_local(_lookahead_point(LOOKAHEAD))
	var steer := clampf(atan2(local.x, -local.z) / Bus.MAX_STEERING, -1.0, 1.0)
	var throttle := 1.0 if bus.linear_velocity.length() < TARGET_SPEED else 0.0
	bus.apply_axes(steer, throttle, 0.0, false, delta)

	if elapsed > WARMUP_SECONDS:
		samples.append(float(Engine.get_frames_per_second()))
	if elapsed > WARMUP_SECONDS + MEASURE_SECONDS:
		_report()

func _advance_guide() -> void:
	var route := drive.data.route
	while guide_index < route.size() - 2 and _segment_t() > 1.0:
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
	var total := 0.0
	var lowest := INF
	for sample in samples:
		total += sample
		lowest = minf(lowest, sample)
	var average := total / maxf(float(samples.size()), 1.0)
	print("fps 평균 %.1f, 최저 %.1f (표본 %d)" % [average, lowest, samples.size()])
	get_tree().quit(0)
