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

var target: Node3D

var _arm: SpringArm3D
var _yaw_synced := false

func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = ARM_LENGTH
	_arm.margin = 0.2
	_arm.rotation_degrees = Vector3(ARM_PITCH_DEG, 0.0, 0.0)
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
		rotation.y = target.global_rotation.y
		return

	# lerp_angle 은 -PI..PI 를 감아 도는 최단 경로로 보간한다. 단순 lerp 를
	# 쓰면 요가 PI 를 넘는 순간 카메라가 한 바퀴 돈다.
	rotation.y = lerp_angle(rotation.y, target.global_rotation.y,
		clampf(YAW_LAG * delta, 0.0, 1.0))
