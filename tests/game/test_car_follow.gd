extends TestCase
# 차 한 대의 속도 규칙. 순수 계산이라 트리가 필요 없다. 위치는 여기서 적분한다.

const DT := 1.0 / 60.0
const GREEN := TrafficSignal.Phase.GREEN
const YELLOW := TrafficSignal.Phase.YELLOW
const RED := TrafficSignal.Phase.RED

func _ready() -> void:
	# 가속은 프레임당 ACCEL x delta 를 넘지 않는다.
	equal_approx(CarFollow.next_speed(0.0, INF, INF, GREEN, DT), CarFollow.ACCEL * DT,
		0.0001, "출발 가속")

	# 빈 도로에서 순항 속도까지 오르고 넘지 않는다.
	var speed := 0.0
	for frame in 600:
		speed = CarFollow.next_speed(speed, INF, INF, GREEN, DT)
	equal_approx(speed, CarFollow.CRUISE_MPS, 0.001, "순항 속도")

	# 순항 중 30 m 앞 적색 정지선: 넘지 않고 그 앞에 선다.
	var x := 0.0
	speed = CarFollow.CRUISE_MPS
	for frame in 1200:
		speed = CarFollow.next_speed(speed, INF, 30.0 - x, RED, DT)
		x += speed * DT
	ok(x <= 30.0 + 0.01, "적색 정지선을 넘었다 (%.3f m)" % x)
	ok(x > 29.0, "정지선 한참 앞에 섰다 (%.3f m)" % x)
	ok(speed < 0.01, "적색 앞에서 안 섰다 (%.3f m/s)" % speed)

	# 설 수 없는 황색(5 m 앞, 제동거리 10 m)은 지나간다. 설 수 있으면(12 m) 선다.
	ok(CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, 5.0, YELLOW, DT)
		>= CarFollow.CRUISE_MPS - 0.0001, "설 수 없는 황색에서 제동했다")
	ok(CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, 12.0, YELLOW, DT)
		< CarFollow.CRUISE_MPS, "설 수 있는 황색에서 안 줄였다")
	# 녹색 정지선은 없는 것과 같다.
	ok(CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, 1.0, GREEN, DT)
		>= CarFollow.CRUISE_MPS - 0.0001, "녹색에서 제동했다")

	# 50 m 앞 멈춘 차 뒤에 MIN_GAP_M(정지 시 6 m)을 두고 선다.
	x = 0.0
	speed = CarFollow.CRUISE_MPS
	for frame in 1200:
		speed = CarFollow.next_speed(speed, 50.0 - x, INF, GREEN, DT)
		x += speed * DT
	var gap := 50.0 - x
	ok(gap >= CarFollow.min_gap(0.0) - 0.05, "앞차에 너무 붙었다 (%.2f m)" % gap)
	ok(gap < CarFollow.min_gap(0.0) + 1.0, "앞차 한참 뒤에 섰다 (%.2f m)" % gap)
	ok(speed < 0.01, "앞차 뒤에서 안 섰다")
	finish()
