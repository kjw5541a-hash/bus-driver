extends TestCase
# 이 서브프로젝트의 핵심 숫자를 지킨다. 회전 반경이 실제 시내버스 수준이라야
# 급한 코너에서 후진이 필요해지고, 그 긴장이 게임의 재미다.
# 빈 평면 위에서 조향을 최대로 고정하고 저속으로 돌려 궤적의 반경을 잰다.

const RADIUS_MIN := 9.0
const RADIUS_MAX := 11.0
const SETTLE_SECONDS := 3.0    # 서스펜션이 가라앉고 속도가 붙을 때까지
const MEASURE_SECONDS := 25.0  # 저속으로 한 바퀴 이상 돌 시간

var bus: Bus
var elapsed := 0.0
var samples: Array[Vector3] = []
var done := false

func _ready() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	add_child(ground)

	bus = Bus.new()
	bus.position = Vector3(0.0, 1.5, 0.0)
	add_child(bus)

func _physics_process(delta: float) -> void:
	if done or bus == null:
		return
	elapsed += delta
	# 조향 최대(오른쪽), 저속 유지. 속도가 붙으면 속도 감응 조향이 각을 좁혀
	# 반경이 커지므로 천천히 돈다.
	var throttle := 1.0 if bus.linear_velocity.length() < 3.0 else 0.0
	bus.apply_axes(1.0, throttle, 0.0, false, delta)

	if elapsed > SETTLE_SECONDS:
		samples.append(bus.global_position)
	if elapsed > SETTLE_SECONDS + MEASURE_SECONDS:
		_measure()

func _measure() -> void:
	done = true
	ok(samples.size() > 100, "표본이 %d 개뿐이다" % samples.size())
	if samples.size() <= 100:
		finish()
		return

	# 원 궤적의 반경 = (x 폭 + z 폭) / 4. 한 바퀴를 다 돌지 않아도
	# 바운딩 박스가 원의 지름에 수렴하도록 충분히 돌린다.
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in samples:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var radius := ((max_x - min_x) + (max_z - min_z)) / 4.0
	print("회전 반경 %.2f m (x 폭 %.2f, z 폭 %.2f)"
		% [radius, max_x - min_x, max_z - min_z])
	ok(radius >= RADIUS_MIN and radius <= RADIUS_MAX,
		"회전 반경 %.2f m 가 %.0f–%.0f m 밖이다" % [radius, RADIUS_MIN, RADIUS_MAX])

	# 속도 감응 조향이 실제로 각을 좁히는지도 같이 본다.
	ok(Bus.steer_limit(0.0) > Bus.steer_limit(16.7),
		"속도가 올라도 조향각이 안 좁아진다")
	equal_approx(Bus.steer_limit(0.0), Bus.MAX_STEERING, 0.001,
		"정지 상태에서 최대 조향각을 다 못 쓴다")
	equal_approx(Bus.steer_limit(16.7), Bus.MAX_STEERING * 0.3, 0.001,
		"60 km/h 에서 조향각이 30% 가 아니다")

	finish()
