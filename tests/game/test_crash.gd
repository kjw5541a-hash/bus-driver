extends TestCase
# 버스를 세워 둔 차에 밀어 넣어 사고 판정을 본다. 접촉 보고가 실제 물리에서
# 오는지가 요점이라 진짜 Bus 와 바닥을 쓴다.
# 첫 사고 -> 5 초 정지 -> 3 초 유예(계속 밀어도 안 셈) -> 둘째 사고.

const TIMEOUT_S := 40.0
const THROTTLE := 0.5

var bus: Bus
var traffic: Traffic
var crash: CrashWatch
var elapsed := 0.0
var stop_started := -1.0
var stop_ended := -1.0
var second_at := -1.0
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

	# 버스가 선 자리에서 북(-Z)으로 곧은 노선. 같은 방향 첫 차가 30 m 앞에 선다.
	var data := RouteData.new()
	data.route = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -1000.0)])
	data.route_width = PackedFloat32Array([7.0, 7.0])
	traffic = Traffic.new()
	traffic.build(data, bus)
	add_child(traffic)
	# 차를 전부 세워 둔다. 버스가 들이받을 과녁이다.
	for car in traffic.cars:
		traffic.hold(car.body, 1000.0)

	crash = CrashWatch.new()
	crash.build(bus, traffic)
	add_child(crash)

func _physics_process(delta: float) -> void:
	if done or crash == null:
		return
	elapsed += delta
	if crash.is_stopping:
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		if stop_started < 0.0:
			stop_started = elapsed
	else:
		if stop_started >= 0.0 and stop_ended < 0.0:
			stop_ended = elapsed
		bus.apply_axes(0.0, THROTTLE, 0.0, false, delta)
	if crash.crashes >= 2 and second_at < 0.0:
		second_at = elapsed
	if second_at >= 0.0 or elapsed > TIMEOUT_S:
		_report()

func _report() -> void:
	done = true
	ok(stop_started >= 0.0, "사고가 한 번도 안 났다")
	ok(stop_ended >= 0.0, "사고 정지가 안 끝났다")
	equal_approx(stop_ended - stop_started, CrashWatch.CRASH_STOP_S, 0.1, "사고 정지 시간")
	ok(second_at >= 0.0, "유예가 끝난 뒤 다시 밀어도 사고가 안 세어졌다")
	ok(second_at - stop_ended >= CrashWatch.CRASH_GRACE_S - 0.05,
		"유예 %.2f 초 만에 다시 셌다" % (second_at - stop_ended))
	finish()
