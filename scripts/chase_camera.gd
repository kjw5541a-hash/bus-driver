extends Node3D
class_name ChaseCamera
# 버스 뒤를 지연 추종한다. 위치는 즉시 따라가고 방향만 늦게 따라와서
# 커브에서 차체가 먼저 돌아간다.
#
# SpringArm3D 를 쓰는 이유는 건물 관통을 알아서 막아주기 때문이다.
# 직접 레이캐스트를 짤 이유가 없다.

# SpringArm3D 는 자식을 자기 로컬 +Z 로 밀어낸다. 피벗의 +Z 가 버스 후방이라
# 회전 없이 그대로 두면 카메라가 뒤에 선다. 요를 돌리면 앞으로 튀어나온다.
const ARM_LENGTH := 20.0
const ARM_PITCH_DEG := -18.0
const PIVOT_HEIGHT := 1.5
const YAW_LAG := 4.0      # 클수록 빨리 따라붙는다

# 사용자 시점 조작 한계. 거리 하한을 차체 길이(11 m)보다 밑으로 두면
# 카메라가 버스 안으로 들어간다.
const DISTANCE_MIN := 12.0
const DISTANCE_MAX := 45.0
const PITCH_MIN_DEG := -75.0
const PITCH_MAX_DEG := -3.0
const ORBIT_SENSITIVITY := 0.4   # 마우스 픽셀당 도
const ZOOM_STEP := 3.0           # 휠 한 칸당 m

var target: Node3D

var _arm: SpringArm3D
var _yaw_synced := false
var _follow_yaw := 0.0
var _yaw_offset := 0.0
var _pitch_deg := ARM_PITCH_DEG
var _distance := ARM_LENGTH

func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = _distance
	_arm.margin = 0.2
	_arm.rotation_degrees = Vector3(_pitch_deg, 0.0, 0.0)
	add_child(_arm)
	var camera := Camera3D.new()
	camera.far = 2000.0
	camera.current = true
	_arm.add_child(camera)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3.UP * PIVOT_HEIGHT

	if not _yaw_synced:
		# 첫 프레임에는 지연 없이 버스 뒤로 붙인다. 안 그러면 스폰 직후
		# 카메라가 요 0 에서 버스 요까지 크게 휘둘린다.
		_yaw_synced = true
		_follow_yaw = target.global_rotation.y
	else:
		# lerp_angle 은 -PI..PI 를 감아 도는 최단 경로로 보간한다. 단순 lerp 를
		# 쓰면 요가 PI 를 넘는 순간 카메라가 한 바퀴 돈다.
		_follow_yaw = lerp_angle(_follow_yaw, target.global_rotation.y,
			clampf(YAW_LAG * delta, 0.0, 1.0))
	rotation.y = _follow_yaw + _yaw_offset

# 시점을 돌리고 당긴다. 각도는 도, 거리는 m.
func apply_orbit(yaw_delta_deg: float, pitch_delta_deg: float, zoom_delta: float) -> void:
	_yaw_offset = wrapf(_yaw_offset + deg_to_rad(yaw_delta_deg), -PI, PI)
	_pitch_deg = clampf(_pitch_deg + pitch_delta_deg, PITCH_MIN_DEG, PITCH_MAX_DEG)
	_distance = clampf(_distance + zoom_delta, DISTANCE_MIN, DISTANCE_MAX)
	_arm.rotation_degrees.x = _pitch_deg
	_arm.spring_length = _distance

func reset_view() -> void:
	apply_orbit(-rad_to_deg(_yaw_offset), ARM_PITCH_DEG - _pitch_deg, ARM_LENGTH - _distance)

func _unhandled_input(event: InputEvent) -> void:
	# 우클릭 드래그로 시점을 돌린다. 좌클릭은 emulate_touch_from_mouse 가
	# 터치로 바꿔 조향에 쓰이므로 건드리지 않는다.
	if event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		apply_orbit(-event.relative.x * ORBIT_SENSITIVITY,
			-event.relative.y * ORBIT_SENSITIVITY, 0.0)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				apply_orbit(0.0, 0.0, -ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				apply_orbit(0.0, 0.0, ZOOM_STEP)
			MOUSE_BUTTON_MIDDLE:
				reset_view()
