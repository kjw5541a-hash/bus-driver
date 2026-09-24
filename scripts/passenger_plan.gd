extends RefCounted
class_name PassengerPlan
# 승객 규칙 전부. 노드가 아니라서 테스트가 트리 없이 바로 돌린다.
#
# 승객 객체는 만들지 않는다. _destined[i] 에 "i 번 정류장에서 내릴 사람 수"만
# 센다. 60 명이 각자 객체일 이유가 없다.

const CAPACITY := 60              # 서울 저상버스 입석 포함
const DOOR_S := 3.0               # 문 개폐. 승객이 0 명이어도 든다
# 1 인당 시간. 처음 1.2/0.8 초는 문 개폐 3 초와 걸어오는 시간에 묻혀 1 명과
# 8 명이 체감상 차이가 없었다. 서울 시내버스 실측(카드 태그 포함 약 2 초)에
# 맞춘다. 이제 1 명은 5 초, 8 명은 19 초다.
const BOARD_S := 2.0              # 1 인 탑승. 교통카드 찍는 시간
const ALIGHT_S := 1.0             # 1 인 하차
const WALK_SPEED_MPS := 1.2

var onboard := 0
var left_behind := 0

var _waiting: PackedInt32Array = []
var _destined: PackedInt32Array = []
var _stop_count := 0

func build(stop_count: int) -> void:
	"""정류장마다 대기 인원을 뽑는다. 매 플레이 새로 뽑는다."""
	_stop_count = stop_count
	_waiting = PackedInt32Array()
	_destined = PackedInt32Array()
	for _index in stop_count:
		# 균등 분포로 뽑으면 정류장 114 곳 중 101 곳에 사람이 있어 계속 선다.
		# 이 식은 0 명이 1/3, 평균 2.9 명이다.
		_waiting.append(maxi(0, randi_range(-3, 8)))
		_destined.append(0)

func waiting_at(index: int) -> int:
	if index < 0 or index >= _waiting.size():
		return 0
	return _waiting[index]

func alighting_at(index: int) -> int:
	"""index 번 정류장에서 내릴 사람 수. 종점은 남은 전원이다."""
	if index < 0 or index >= _stop_count:
		return 0
	if index == _stop_count - 1:
		return onboard
	return _destined[index]

func force_waiting(index: int, count: int) -> void:
	"""대기 인원을 정한다. 난수를 고정해야 하는 테스트 전용이다."""
	if index < 0 or index >= _waiting.size():
		return
	_waiting[index] = count

func needs_stop(index: int) -> bool:
	"""서야 하는 정류장인가. 탈 사람도 내릴 사람도 없으면 지나가는 게 맞다."""
	if index < 0 or index >= _stop_count:
		return false
	if index == _stop_count - 1:
		# 종점에서는 남은 전원이 내린다. 빈 버스여도 도착은 해야 한다.
		return true
	return _waiting[index] > 0 or _destined[index] > 0

func walk_for(walk_distance_m: float, waiting_n: int) -> float:
	"""기다리던 사람이 버스까지 걸어오는 시간. 기다린 사람이 없으면 0."""
	return walk_distance_m / WALK_SPEED_MPS if waiting_n > 0 else 0.0

func dwell_for(board_n: int, alight_n: int, walk_distance_m: float,
		waiting_n: int) -> float:
	"""정차 시간. 탑승과 하차는 앞문·뒷문으로 동시에 이뤄진다."""
	return DOOR_S + walk_for(walk_distance_m, waiting_n) \
		+ maxf(board_n * BOARD_S, alight_n * ALIGHT_S)

static func progress(elapsed_s: float, board_n: int, alight_n: int,
		walk_s: float) -> Vector2i:
	"""정차 elapsed_s 초째까지 (탄 사람, 내린 사람).

	문이 열리면 뒷문으로 바로 내리기 시작한다. 타는 사람은 걸어온 뒤에
	한 명씩 카드를 찍는다. dwell_for 와 같은 시간표라 정차가 끝날 때 둘 다
	다 채워진다.
	"""
	var board_t := elapsed_s - DOOR_S - walk_s
	var alight_t := elapsed_s - DOOR_S
	var boarded := clampi(floori(board_t / BOARD_S), 0, board_n)
	var alighted := clampi(floori(alight_t / ALIGHT_S), 0, alight_n)
	return Vector2i(boarded, alighted)

func serve(index: int, walk_distance_m: float) -> Dictionary:
	"""index 번 정류장의 승하차를 확정한다. 상태가 여기서 바뀐다."""
	if index < 0 or index >= _stop_count:
		return {"boarded": 0, "alighted": 0, "walk": 0.0, "dwell": DOOR_S}

	var is_terminus := index == _stop_count - 1
	var alighted := onboard if is_terminus else _destined[index]
	onboard -= alighted
	_destined[index] = 0

	var waiting := _waiting[index]
	# 종점에서는 아무도 타지 않는다.
	var boarded := 0 if is_terminus else mini(waiting, CAPACITY - onboard)
	left_behind += waiting - boarded
	_waiting[index] = 0
	onboard += boarded
	for _rider in boarded:
		_destined[_pick_destination(index)] += 1

	return {"boarded": boarded, "alighted": alighted,
		"walk": walk_for(walk_distance_m, waiting),
		"dwell": dwell_for(boarded, alighted, walk_distance_m, waiting)}

func _pick_destination(from_index: int) -> int:
	"""뒤쪽에 남은 정류장 중 균등 랜덤. 뒤가 없으면 종점이다."""
	if from_index >= _stop_count - 1:
		return _stop_count - 1
	return randi_range(from_index + 1, _stop_count - 1)
