extends VehicleBody3D
class_name Bus
# 세미 리얼 12 t 시내버스. 축 세 개만 받아 물리로 번역한다.
#
# 아래 숫자 중 서스펜션과 engine_force 부호는 1번 서브프로젝트에서 실측으로
# 얻은 값이다. 하드웨어 특성처럼 다루고 추측으로 바꾸지 않는다.

const MASS := 12000.0
const ENGINE_FORCE := 30000.0
# 50 km/h 에서 17 m, 2.5 초에 선다(약 0.57 g). 처음 값 40 은 60 m, 10 초라
# 정류장에 맞춰 설 수가 없었다. test_brake 가 지킨다.
const BRAKE_FORCE := 250.0
# 가속을 뗐을 때 거는 엔진 브레이크. 없으면 12 t 이 관성으로 계속 굴러간다.
# 1.9 m/s² 로 준다. 서 있을 때 버스를 붙잡아 두는 몫도 한다.
const COAST_BRAKE := 40.0
const MAX_SPEED := 19.4                      # m/s, 70 km/h
const REVERSE_SPEED_LIMIT := MAX_SPEED * 0.3
# 회전 반경 9–11 m 를 내는 최대 조향각. 자전거 모델 R = L / tan(δ) 에
# 휠베이스 6.6 m 를 넣으면 δ 가 0.6–0.65 rad 이다. 반경이 기준이고 이 값은
# 그 기준을 맞추는 손잡이다 — test_turn_radius 가 지킨다.
# spec 의 시작값 0.62 는 실측 11.62 m 로 범위를 벗어났다. 바퀴 슬립 때문에
# 자전거 모델보다 실제 반경이 크다. 0.70 에서 실측 10.16 m.
const MAX_STEERING := 0.70
const STEER_RATE := 1.5                      # rad/s. 조향 변화 속도 상한
const STEER_SPEED_FULL := 16.7               # m/s, 60 km/h

var _respawn_transform := Transform3D()
var _respawn_pending := false

static func steer_limit(speed: float) -> float:
	"""속도 감응 조향. 정지에서 최대각, 60 km/h 에서 그 30%.

	안 좁히면 고속에서 조금만 밀어도 스핀한다.
	"""
	return MAX_STEERING * lerpf(1.0, 0.3, clampf(speed / STEER_SPEED_FULL, 0.0, 1.0))

func _ready() -> void:
	mass = MASS
	# 질량 중심을 바닥 근처로 내려 급회전 전복을 막는다. 충돌 상자 중심은
	# y=2.0 이지만 무게는 아래에 몰려 있어야 한다.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.5, 0.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 3.0, 11.0)
	shape.shape = box
	# 차체 밑면이 지면에 닿으면 바퀴가 일을 못 한다. 상자를 띄운다.
	shape.position = Vector3(0.0, 2.0, 0.0)
	add_child(shape)

	var body_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.5, 3.0, 11.0)
	body_mesh.mesh = mesh
	body_mesh.position = Vector3(0.0, 2.0, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.45, 0.85)
	body_mesh.material_override = material
	add_child(body_mesh)

	# [z 위치, x 위치, 조향 여부]. 앞바퀴가 조향, 뒷바퀴가 구동이다.
	for spec in [[-3.6, -1.1, true], [-3.6, 1.1, true],
				 [3.0, -1.1, false], [3.0, 1.1, false]]:
		var wheel := VehicleWheel3D.new()
		wheel.position = Vector3(spec[1], 0.2, spec[0])
		wheel.use_as_steering = spec[2]
		wheel.use_as_traction = not spec[2]
		wheel.wheel_radius = 0.5
		wheel.suspension_travel = 0.35
		# 12 t 은 기본값(바퀴당 6 kN, 4륜 합 24 kN)으로 주저앉는다. 무게가
		# 117 kN 이다. 아래 값은 1번에서 실측으로 맞춘 것이다.
		wheel.suspension_stiffness = 150.0
		wheel.suspension_max_force = 80000.0
		wheel.damping_compression = 3.7
		wheel.damping_relaxation = 6.1
		wheel.wheel_friction_slip = 3.5
		add_child(wheel)

func apply_axes(steer_axis: float, throttle_axis: float, brake_axis: float,
		reverse: bool, delta: float) -> void:
	var speed := linear_velocity.length()
	var limit := steer_limit(speed)
	# engine_force 가 음수일 때 전방(-Z)으로 가고, 그 상태에서는 steering
	# 부호도 뒤집혀 있다. 오른쪽(steer_axis > 0)으로 돌려면 steering 이
	# 음수여야 한다. 1번에서 이걸 모르고 커브마다 도로를 이탈했다.
	var target := clampf(-steer_axis, -1.0, 1.0) * limit
	steering = move_toward(steering, target, STEER_RATE * delta)

	if reverse:
		# 후진 중에는 제동 축이 뒤로 미는 구동이 된다. 가속 축은 입력 계층이
		# 이미 전진 복귀에 썼으므로 여기선 보지 않는다.
		engine_force = ENGINE_FORCE * brake_axis if speed < REVERSE_SPEED_LIMIT else 0.0
		brake = 0.0
		return

	engine_force = -ENGINE_FORCE * throttle_axis if speed < MAX_SPEED else 0.0
	brake = BRAKE_FORCE * brake_axis
	if throttle_axis <= 0.0:
		brake = maxf(brake, COAST_BRAKE)

func respawn_to(point: Vector3, look_target: Vector3) -> void:
	"""끼거나 뒤집혔을 때 경로 위로 되돌린다. 벌점은 없다 — 5번이 정한다."""
	var origin := point + Vector3.UP * 1.5
	var target := look_target + Vector3.UP * 1.5
	if origin.distance_to(target) < 0.01:
		target = origin - global_transform.basis.z
	_respawn_transform = Transform3D().looking_at(target - origin, Vector3.UP)
	_respawn_transform.origin = origin
	_respawn_pending = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# 강체의 transform 을 밖에서 직접 대입하면 물리 서버와 어긋난다.
	# 순간이동은 _integrate_forces 안에서 state 를 통해 해야 한다.
	if not _respawn_pending:
		return
	_respawn_pending = false
	state.transform = _respawn_transform
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	steering = 0.0
	engine_force = 0.0
	brake = 0.0
