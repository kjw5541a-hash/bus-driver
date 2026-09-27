extends Node
class_name CrashWatch
# 버스가 교통 차량에 부딪혔는지 본다. 버스는 세우지 않는다 — 충격은 물리
# 엔진이 버스를 튕겨 내는 것으로 끝난다. 부딪힌 차는 잠깐 세우고, 벌은
# 남은 시간(RunClock.add_penalty)과 점수(ScoreCard)로 받는다.

const CAR_HOLD_S := 5.0      # 부딪힌 차가 서 있는 시간
const PENALTY_S := 5.0       # 사고 한 번에 깎는 남은 시간
const CRASH_GRACE_S := 3.0   # 사고 뒤 이 동안의 접촉은 새 사고로 안 센다

signal crashed

var bus: RigidBody3D
var traffic: Traffic
var boarding: BoardingWatch
var crashes := 0

var _grace_left := 0.0

func build(bus_node: RigidBody3D, traffic_node: Traffic) -> void:
	bus = bus_node
	traffic = traffic_node
	# 접촉 보고는 기본으로 꺼져 있다. 켜야 get_colliding_bodies() 가 채워진다.
	bus.contact_monitor = true
	bus.max_contacts_reported = 4

func _physics_process(delta: float) -> void:
	if bus == null or traffic == null:
		return
	if _grace_left > 0.0:
		# 튕겨 나간 뒤에도 몇 프레임은 닿아 있다. 그걸 사고로 또 세지 않는다.
		_grace_left = maxf(_grace_left - delta, 0.0)
		return
	# 승하차 중에는 버스가 서 있고 뒤차가 줄을 선다. 사고가 아니다.
	if boarding != null and boarding.is_boarding:
		return
	for body in bus.get_colliding_bodies():
		if traffic.car_of(body) == null:
			continue
		crashes += 1
		_grace_left = CRASH_GRACE_S
		traffic.hold(body, CAR_HOLD_S)
		crashed.emit()
		return
