extends Node3D
class_name Weather
# 비. 맑음과 비를 무작위 길이로 번갈아 두고, 세기(rain 0~1)는 RAMP_S 에
# 걸쳐 따라간다. 효과는 drive.gd 가 세기를 받아 각 부품에 넘긴다.
#
# 빗줄기는 follow 를 따라다니는 입자 상자 하나다. 도시 전체에 뿌릴 필요가
# 없다.

const RAMP_S := 30.0
const CLEAR_S := Vector2(120.0, 360.0)
const RAIN_S := Vector2(60.0, 240.0)
const START_RAIN_CHANCE := 0.3
const DROP_COUNT := 4000
const BOX := Vector3(40.0, 25.0, 40.0)

var rain := 0.0
var follow: Node3D

var _target := 0.0
var _forced := -1
var _left := 0.0
var _drops: GPUParticles3D

func _ready() -> void:
	_drops = GPUParticles3D.new()
	_drops.amount = DROP_COUNT
	_drops.lifetime = 1.2
	_drops.visibility_aabb = AABB(-BOX / 2.0, BOX)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(BOX.x / 2.0, 0.5, BOX.z / 2.0)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 3.0
	process.initial_velocity_min = 18.0
	process.initial_velocity_max = 22.0
	process.gravity = Vector3.ZERO
	_drops.process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.02, 0.6)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = look
	_drops.draw_pass_1 = streak
	_drops.amount_ratio = 0.0
	_drops.emitting = false
	add_child(_drops)

func start(forced: int) -> void:
	"""forced: -1 무작위 일정, 0 맑음 고정, 1 비 고정."""
	_forced = forced
	if forced >= 0:
		_target = float(forced)
	else:
		_target = 1.0 if randf() < START_RAIN_CHANCE else 0.0
		_left = _span()
	rain = _target

func _process(delta: float) -> void:
	step(delta)
	if follow != null:
		global_position = follow.global_position + Vector3.UP * (BOX.y / 2.0 - 3.0)

func step(delta: float) -> void:
	if _forced < 0:
		_left -= delta
		if _left <= 0.0:
			_target = 1.0 - _target
			_left = _span()
	rain = move_toward(rain, _target, delta / RAMP_S)
	if _drops != null:
		_drops.emitting = rain > 0.01
		_drops.amount_ratio = rain

func _span() -> float:
	var span := RAIN_S if _target > 0.5 else CLEAR_S
	return randf_range(span.x, span.y)

static func rain_from_args(args: PackedStringArray) -> int:
	"""--rain=0|1. 없거나 잘못되면 -1(무작위)."""
	for argument in args:
		if argument == "--rain=0":
			return 0
		if argument == "--rain=1":
			return 1
	return -1
