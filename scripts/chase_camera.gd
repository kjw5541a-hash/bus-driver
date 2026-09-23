extends Node3D
class_name ChaseCamera
# 버스 뒤를 지연 추종한다. 위치는 즉시 따라가고 방향만 늦게 따라와서
# 커브에서 차체가 먼저 돌아간다.
#
# SpringArm3D 를 쓰는 이유는 건물 관통을 알아서 막아주기 때문이다.
# 직접 레이캐스트를 짤 이유가 없다.

const ARM_LENGTH := 13.0
# SpringArm3D 는 자식을 자기 로컬 -Z 로 밀어낸다. 피벗의 -Z 는 버스 전방이라
# 그대로 두면 카메라가 버스 앞에 선다. 요를 180도 돌려 뒤로 보낸다.
const ARM_YAW_DEG := 180.0
const ARM_PITCH_DEG := -20.0
const PIVOT_HEIGHT := 1.5
const YAW_LAG := 4.0      # 클수록 빨리 따라붙는다

var target: Node3D

var _arm: SpringArm3D

func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = ARM_LENGTH
	_arm.margin = 0.2
	_arm.rotation_degrees = Vector3(ARM_PITCH_DEG, ARM_YAW_DEG, 0.0)
	add_child(_arm)
	var camera := Camera3D.new()
	camera.far = 2000.0
	camera.current = true
	_arm.add_child(camera)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3.UP * PIVOT_HEIGHT
	# lerp_angle 은 -PI..PI 를 감아 도는 최단 경로로 보간한다. 단순 lerp 를
	# 쓰면 요가 PI 를 넘는 순간 카메라가 한 바퀴 돈다.
	rotation.y = lerp_angle(rotation.y, target.global_rotation.y,
		clampf(YAW_LAG * delta, 0.0, 1.0))
