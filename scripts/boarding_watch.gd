extends Node
class_name BoardingWatch
# 정차를 판정하고 승하차 시간을 흘린다. 그리지 않는다 — 표시는
# BoardingHud 의 일이다. 승객 규칙도 여기 없다 — PassengerPlan 의 일이다.
#
# ViolationWatch 처럼 격자 인덱스를 쓰지 않는다. 정류장은 노선 순서대로
# 지나가므로 next_index 앞뒤의 작은 창만 보면 된다.

const STOP_RADIUS_M := 15.0
const STOP_SPEED_MPS := 0.5
const AHEAD_WINDOW := 4      # next_index 부터 앞으로 보는 개수
const BACK_WINDOW := 2       # 되돌아가 다시 서는 것을 허용하는 깊이

signal boarding_started(stop_index: int)
signal boarding_finished(boarded: int, alighted: int)
signal stop_missed(stop_index: int)

var bus: Node3D
var plan: PassengerPlan

var served := 0
var missed := 0
var is_boarding := false
var boarding_left := 0.0
var boarding_total := 0.0    # 진행 바가 비율을 내려면 전체 길이도 있어야 한다
var next_index := 0

# 5번 서브프로젝트가 한 군데서 다 읽도록 plan 의 값을 그대로 내놓는다.
var onboard: int:
	get: return plan.onboard if plan != null else 0
var left_behind: int:
	get: return plan.left_behind if plan != null else 0

var _targets: PackedVector3Array = []
var _boarding_index := -1
var _pending := {}           # 진행 중인 정차의 serve() 결과
var _done := {}              # 승하차를 마친 정류장
var _missed_once := {}       # 놓침은 정류장당 한 번만 센다
var _last_position := Vector3.ZERO
var _has_last := false

func build(targets: PackedVector3Array) -> void:
	_targets = targets
	plan = PassengerPlan.new()
	plan.build(targets.size())

func _physics_process(delta: float) -> void:
	if bus == null or _targets.is_empty():
		return
	var here := bus.global_position

	if is_boarding:
		_tick(delta)
		_last_position = here
		return

	# 속도를 위치 차이로 잰다. bus 가 VehicleBody3D 든 빈 Node3D 든 된다.
	var speed := 0.0
	if _has_last and delta > 0.0:
		speed = _last_position.distance_to(here) / delta
	_last_position = here
	_has_last = true

	# 창 안에서 가장 가까운 정류장을 찾는다. 반경이 겹쳐도 가까운 쪽을 잡는다.
	var first := maxi(0, next_index - BACK_WINDOW)
	var best := -1
	var best_distance := INF
	for offset in BACK_WINDOW + AHEAD_WINDOW:
		var index := first + offset
		if index >= _targets.size():
			break
		var distance := _targets[index].distance_to(here)
		if distance < best_distance:
			best_distance = distance
			best = index
	if best < 0:
		return

	# 가장 가까운 정류장이 next_index 보다 뒤라면 그 사이는 지나간 것이다.
	# 반경 이탈로 판정하지 않는 이유는 반경 15 m 밖으로 우회하면 애초에
	# 들어온 적이 없어 놓침이 영영 안 잡히기 때문이다.
	while next_index < best:
		_pass(next_index)
		next_index += 1

	if best_distance <= STOP_RADIUS_M and speed < STOP_SPEED_MPS \
			and not _done.has(best) and plan.needs_stop(best):
		_start(best, best_distance)

func _pass(index: int) -> void:
	"""정류장을 지나갔다. 서야 했던 곳만 놓침으로 센다."""
	if _done.has(index) or _missed_once.has(index):
		return
	if not plan.needs_stop(index):
		# 탈 사람도 내릴 사람도 없다. 지나가는 것이 정상이다.
		return
	_missed_once[index] = true
	missed += 1
	stop_missed.emit(index)

func _start(index: int, walk_distance_m: float) -> void:
	_pending = plan.serve(index, walk_distance_m)
	_boarding_index = index
	boarding_total = float(_pending["dwell"])
	boarding_left = boarding_total
	is_boarding = true
	boarding_started.emit(index)

func _tick(delta: float) -> void:
	boarding_left -= delta
	if boarding_left > 0.0:
		return
	is_boarding = false
	boarding_left = 0.0
	boarding_total = 0.0
	served += 1
	_done[_boarding_index] = true
	next_index = maxi(next_index, _boarding_index + 1)
	boarding_finished.emit(int(_pending["boarded"]), int(_pending["alighted"]))
	_boarding_index = -1
	_pending = {}

func distance_to_next() -> float:
	"""다음 정류장까지 남은 거리. 종점을 지나면 -1."""
	if bus == null or next_index >= _targets.size():
		return -1.0
	return _targets[next_index].distance_to(bus.global_position)

func stop_name_at(index: int, stops: Array) -> String:
	"""HUD 가 쓰는 편의 함수. 범위를 벗어나면 빈 문자열이다."""
	if index < 0 or index >= stops.size():
		return ""
	return str(stops[index].get("name", ""))
