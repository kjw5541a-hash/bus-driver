extends TestCase
# 가속을 떼면 바로 줄고, 제동을 밟으면 바로 서야 한다. 정류장에 맞춰 서는
# 것이 이 게임의 조작 대부분이라, 버스가 미끄러지듯 굴러가면 정차가
# 운에 맡겨진다.
# 빈 평면에서 50 km/h 까지 올린 다음, 한 번은 발을 떼고 한 번은 제동을 건다.

const CRUISE_MPS := 13.9       # 50 km/h
const COAST_SECONDS := 2.0
const COAST_DECEL_MIN := 1.5   # m/s². 발을 떼면 이만큼은 줄어야 한다
const STOP_DISTANCE_MAX := 20.0  # m. 50 km/h 에서 완전 정지까지
const STOP_TIME_MAX := 3.0     # s
const STOPPED_MPS := 0.1

enum Phase { SPEED_UP, COAST, SPEED_UP_AGAIN, BRAKE, HOLD, DONE }

var bus: Bus
var phase := Phase.SPEED_UP
var timer := 0.0
var coast_start_speed := 0.0
var brake_start: Vector3
var brake_time := 0.0

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
	if bus == null or phase == Phase.DONE:
		return
	timer += delta
	var speed := bus.linear_velocity.length()
	match phase:
		Phase.SPEED_UP, Phase.SPEED_UP_AGAIN:
			bus.apply_axes(0.0, 1.0, 0.0, false, delta)
			if speed >= CRUISE_MPS:
				timer = 0.0
				if phase == Phase.SPEED_UP:
					coast_start_speed = speed
					phase = Phase.COAST
				else:
					brake_start = bus.global_position
					phase = Phase.BRAKE
			elif timer > 30.0:
				ok(false, "30초 안에 50 km/h 에 못 올랐다 (%.1f m/s)" % speed)
				_end()
		Phase.COAST:
			bus.apply_axes(0.0, 0.0, 0.0, false, delta)
			if timer >= COAST_SECONDS:
				var decel := (coast_start_speed - speed) / timer
				print("발 뗌 감속 %.2f m/s²" % decel)
				ok(decel >= COAST_DECEL_MIN,
					"발을 떼도 %.2f m/s² 밖에 안 준다 (하한 %.1f)" % [decel, COAST_DECEL_MIN])
				timer = 0.0
				phase = Phase.SPEED_UP_AGAIN
		Phase.BRAKE:
			bus.apply_axes(0.0, 0.0, 1.0, false, delta)
			if speed < STOPPED_MPS:
				var distance := brake_start.distance_to(bus.global_position)
				print("제동 거리 %.1f m, 시간 %.2f s" % [distance, timer])
				ok(distance <= STOP_DISTANCE_MAX,
					"50 km/h 제동 거리 %.1f m > %.0f m" % [distance, STOP_DISTANCE_MAX])
				ok(timer <= STOP_TIME_MAX,
					"50 km/h 제동 시간 %.2f s > %.1f s" % [timer, STOP_TIME_MAX])
				timer = 0.0
				phase = Phase.HOLD
			elif timer > 15.0:
				ok(false, "15초 제동해도 안 선다 (%.1f m/s)" % speed)
				_end()
		Phase.HOLD:
			# 선 뒤에도 제동을 잡고 있으면 그대로 서 있어야 한다.
			bus.apply_axes(0.0, 0.0, 1.0, false, delta)
			if timer >= 1.0:
				ok(speed < STOPPED_MPS, "제동 중인데 %.2f m/s 로 움직인다" % speed)
				_end()

func _end() -> void:
	phase = Phase.DONE
	finish()
