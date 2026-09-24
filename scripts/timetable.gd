extends RefCounted
class_name Timetable
# 구간 마감. 노선 기하와 승객·신호 규칙에서 자동으로 낸다 — 노선을 다시
# 구워도, 규칙 숫자를 바꿔도 알아서 따라온다. 난이도는 BASE_SPEED_MPS 하나로
# 조절한다.

const BASE_SPEED_MPS := 32.0 / 3.6   # 정차·신호를 뺀 순수 주행 평균. 30 이면 100번 긴 구간이 16 분을 넘는다
const WALK_GUESS_M := 3.0            # 차선에 제대로 섰을 때 걸어오는 거리
const ROUND_S := 10.0

static func expected_dwell() -> float:
	"""정류장 한 곳의 기대 정차 시간. 0 명이면 서지 않으므로 0 이다."""
	var plan := PassengerPlan.new()
	var total := 0.0
	for draw in range(PassengerPlan.WAITING_MIN, PassengerPlan.WAITING_MAX + 1):
		var count := maxi(0, draw)
		if count > 0:
			total += plan.dwell_for(count, 0, WALK_GUESS_M, count)
	return total / float(PassengerPlan.WAITING_MAX - PassengerPlan.WAITING_MIN + 1)

static func signal_wait() -> float:
	"""신호 한 곳의 기대 대기. 적색일 확률 1/2 x 적색 평균 잔여."""
	return 0.5 * (TrafficSignal.GREEN_S + TrafficSignal.YELLOW_S) * 0.5

static func deadline_for(data: RouteData) -> float:
	var raw := data.length_m() / BASE_SPEED_MPS \
		+ data.stops.size() * expected_dwell() \
		+ data.signals.size() * signal_wait()
	return ceilf(raw / ROUND_S) * ROUND_S

static func format_mmss(total_s: int) -> String:
	return "%d:%02d" % [floori(total_s / 60.0), total_s % 60]
