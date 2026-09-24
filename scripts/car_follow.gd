extends RefCounted
class_name CarFollow
# 교통 차량 한 대의 다음 프레임 속도. 순수 계산이라 헤드리스로 확인한다.
#
# 속도는 세 한도 중 가장 낮은 것을 목표로 삼고, 한 프레임에 ACCEL x delta
# 이상 오르지도 BRAKE x delta 이상 내리지도 않는다. 제동이 유한해서 적색에
# 뛰어든 버스를 교차 차량이 다 못 피할 수 있다 — 위반의 위험이다.

const CRUISE_MPS := 40.0 / 3.6
const ACCEL := 2.0            # m/s²
const BRAKE := 6.0            # m/s²
# 목표 속도는 BRAKE 보다 약한 감속 곡선으로 잡는다. 곡선이 BRAKE 와 같으면
# 프레임 단위 제한이 곡선을 한 박자 늦게 따라가 정지선을 조금 넘는다.
const PLAN_BRAKE := BRAKE * 0.8
# 정지선 바로 앞이 아니라 조금 앞을 노린다. 감속 곡선은 목표점에 점근하면서
# 마지막 몇 mm 를 한 프레임에 넘어선다.
const STOP_SHORT_M := 0.5
const HEADWAY_S := 1.5
const STANDSTILL_GAP_M := 6.0
# 황색 앞에서 제동 곡선을 따라 줄이는 중에는 남은 거리와 제동거리가 거의 같다.
# 부동소수 오차로 "못 선다" 쪽으로 넘어가 다시 가속하지 않게 여유를 둔다.
const YELLOW_SLACK_M := 1.0

static func min_gap(speed: float) -> float:
	"""앞 장애물과 둘 안전 거리. 섰을 때 6 m, 빠를수록 길다."""
	return STANDSTILL_GAP_M + speed * HEADWAY_S

static func next_speed(speed: float, gap_m: float, stop_m: float,
		phase: TrafficSignal.Phase, delta: float) -> float:
	var target := CRUISE_MPS
	# 앞 장애물: 안전 거리까지 남은 거리 안에 PLAN_BRAKE 로 설 수 있는 속도.
	target = minf(target, sqrt(2.0 * PLAN_BRAKE * maxf(0.0, gap_m - min_gap(speed))))
	# 정지선: 적색은 정지선이 간격 0 장애물이다. 황색은 설 수 있을 때만 선다.
	var must_stop := phase == TrafficSignal.Phase.RED
	if phase == TrafficSignal.Phase.YELLOW:
		must_stop = stop_m + YELLOW_SLACK_M >= speed * speed / (2.0 * BRAKE)
	if must_stop:
		target = minf(target, sqrt(2.0 * PLAN_BRAKE * maxf(0.0, stop_m - STOP_SHORT_M)))
	return maxf(0.0, clampf(target, speed - BRAKE * delta, speed + ACCEL * delta))
