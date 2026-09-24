extends RefCounted
class_name PassengerPlan
# 승객 규칙 전부. 노드가 아니라서 테스트가 트리 없이 바로 돌린다.
#
# 승객 객체는 만들지 않는다. _destined[i] 에 "i 번 정류장에서 내릴 사람 수"만
# 센다. 60 명이 각자 객체일 이유가 없다.

const CAPACITY := 60              # 서울 저상버스 입석 포함
const DOOR_S := 3.0               # 문 개폐. 승객이 0 명이어도 든다
const BOARD_S := 1.2              # 1 인 탑승. 교통카드 찍는 시간
const ALIGHT_S := 0.8             # 1 인 하차
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

func dwell_for(board_n: int, alight_n: int, walk_distance_m: float,
		waiting_n: int) -> float:
	"""정차 시간. 탑승과 하차는 앞문·뒷문으로 동시에 이뤄진다."""
	var walk_s := 0.0
	if waiting_n > 0:
		walk_s = walk_distance_m / WALK_SPEED_MPS
	return DOOR_S + walk_s + maxf(board_n * BOARD_S, alight_n * ALIGHT_S)

func serve(index: int, walk_distance_m: float) -> Dictionary:
	"""index 번 정류장의 승하차를 확정한다. 상태가 여기서 바뀐다."""
	if index < 0 or index >= _stop_count:
		return {"boarded": 0, "alighted": 0, "dwell": DOOR_S}

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
		"dwell": dwell_for(boarded, alighted, walk_distance_m, waiting)}

func _pick_destination(from_index: int) -> int:
	"""뒤쪽에 남은 정류장 중 균등 랜덤. 뒤가 없으면 종점이다."""
	if from_index >= _stop_count - 1:
		return _stop_count - 1
	return randi_range(from_index + 1, _stop_count - 1)
