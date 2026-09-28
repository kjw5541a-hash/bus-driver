extends Node3D
class_name StreetLights
# 가로등. 기둥과 전등 머리는 MultiMesh 두 개로 한 번에 그린다(노선당 약
# 1,000 개). 실제 빛(OmniLight3D)은 POOL 개만 두고 target 에서 가까운 자리로
# 옮겨 다닌다 — 수천 개를 다 켜면 모바일이 버티지 못한다.

const POOL := 8                 # 모바일 렌더러의 메쉬당 옴니 라이트 한도
const RANGE_M := 18.0
const POLE_HEIGHT_M := 8.0
const ARM_M := 0.8              # 기둥에서 도로 쪽으로 전등 머리가 나온 거리
const CURB_Y := 0.15            # 인도 윗면
const UPDATE_S := 0.5
const LIGHT_COLOR := Color(1.0, 0.85, 0.6)
const LIGHT_ENERGY := 2.0

var target: Node3D

var _heads: PackedVector3Array = []
var _pool: Array[OmniLight3D] = []
var _head_material: StandardMaterial3D
var _night := 0.0
var _since_update := UPDATE_S

static func night_amount(elevation_deg: float) -> float:
	"""고도 +2° 에서 켜지기 시작해 -4° 에서 다 켜진다."""
	return clampf((2.0 - elevation_deg) / 6.0, 0.0, 1.0)

func build(entries: Array) -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = POLE_HEIGHT_M
	# 기본 64 각이면 기둥 하나가 삼각형 768 개라 노선 전체가 도시의 8배가 된다.
	pole_mesh.radial_segments = 6
	pole_mesh.rings = 0
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.35, 0.36, 0.38)
	pole_mesh.material = pole_material
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.35, 0.15, 1.0)
	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = Color(0.3, 0.3, 0.3)
	_head_material.emission_enabled = true
	_head_material.emission = LIGHT_COLOR
	_head_material.emission_energy_multiplier = 0.0
	head_mesh.material = _head_material

	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = pole_mesh
	poles.instance_count = entries.size()
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	heads.mesh = head_mesh
	heads.instance_count = entries.size()
	for index in entries.size():
		var entry: Array = entries[index]
		var basis := Basis(Vector3.UP, float(entry[2]))
		var base := Vector3(float(entry[0]), CURB_Y, float(entry[1]))
		poles.set_instance_transform(index,
			Transform3D(basis, base + Vector3.UP * POLE_HEIGHT_M / 2.0))
		# 머리는 기둥 꼭대기에서 도로 쪽(-Z)으로 ARM_M 나온다.
		var head := base + Vector3.UP * POLE_HEIGHT_M + basis * Vector3(0.0, 0.0, -ARM_M)
		heads.set_instance_transform(index, Transform3D(basis, head))
		_heads.append(head)
	for multimesh in [poles, heads]:
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		add_child(instance)
	# 머리는 작고 기둥 그림자에 묻혀 그림자 패스에서 뺀다.
	get_child(get_child_count() - 1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for i in POOL:
		var light := OmniLight3D.new()
		light.omni_range = RANGE_M
		light.light_color = LIGHT_COLOR
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_pool.append(light)

func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	if _head_material != null:
		_head_material.emission_energy_multiplier = 4.0 * _night
	if _night <= 0.0:
		for light in _pool:
			light.visible = false

func _process(delta: float) -> void:
	_since_update += delta
	if target == null or _since_update < UPDATE_S:
		return
	_since_update = 0.0
	update_pool(target.global_position)

func update_pool(from: Vector3) -> void:
	if _night <= 0.0 or _heads.is_empty():
		for light in _pool:
			light.visible = false
		return
	# ponytail: 매번 전체 정렬. 1,400 개를 0.5초마다라 무시할 만하다. 느려지면 격자 칸.
	var order := range(_heads.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _heads[a].distance_squared_to(from) < _heads[b].distance_squared_to(from))
	for i in _pool.size():
		var light := _pool[i]
		light.visible = i < order.size()
		if light.visible:
			light.position = _heads[order[i]] + Vector3.DOWN * 0.3
			light.light_energy = LIGHT_ENERGY * _night

func lit_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for light in _pool:
		if light.visible:
			out.append(light.position)
	return out
