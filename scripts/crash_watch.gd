extends Node
class_name CrashWatch
# 버스가 교통 차량에 부딪혔는지 본다. 사고면 버스를 잠깐 세우고(브레이크는
# drive.gd 가 건다) 부딪힌 차도 세운다. 게임 오버는 없다 — 감점은 ScoreCard.

const CRASH_STOP_S := 5.0
const CRASH_GRACE_S := 3.0   # 정지가 끝난 뒤 이 동안의 접촉은 새 사고로 안 센다

signal crashed

var bus: RigidBody3D
var traffic: Traffic
var boarding: BoardingWatch
var crashes := 0

var is_stopping: bool:
	get:
		return _stop_left > 0.0

var _stop_left := 0.0
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
	if _stop_left > 0.0:
		_stop_left = maxf(_stop_left - delta, 0.0)
		if _stop_left == 0.0:
			_grace_left = CRASH_GRACE_S
		return
	if _grace_left > 0.0:
		_grace_left = maxf(_grace_left - delta, 0.0)
		return
	# 승하차 중에는 버스가 서 있고 뒤차가 줄을 선다. 사고가 아니다.
	if boarding != null and boarding.is_boarding:
		return
	for body in bus.get_colliding_bodies():
		if traffic.car_of(body) == null:
			continue
		crashes += 1
		_stop_left = CRASH_STOP_S
		traffic.hold(body, CRASH_STOP_S)
		crashed.emit()
		return
