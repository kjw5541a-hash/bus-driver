extends Node3D
class_name SignalField
# 신호등 기둥을 세우고 색을 칠한다. 위반 판정은 여기서 하지 않는다 —
# ViolationWatch 의 일이다.
#
# 한 교차로에는 진입 방향이 넷이다(축 2개 x 각 축의 양방향). 진입 방향마다
# 기둥 하나를 세우므로 seoul-100 기준 93 x 4 = 372 개다.

const UPDATE_RADIUS_M := 200.0
const POLE_HEIGHT := 5.5
const POLE_RADIUS := 0.12
const LAMP_RADIUS := 0.25
const LAMP_SPACING := 0.62
const STOP_LINE_MARGIN_M := 2.0
const DEFAULT_HALF_WIDTH := 7.5

# 적/황/녹 순. 켜진 등만 emission 을 켜고 나머지는 어둡게 둔다.
const LAMP_COLORS := [Color(0.85, 0.12, 0.10), Color(0.92, 0.72, 0.10),
	Color(0.15, 0.80, 0.30)]

var target: Node3D
var head_count := 0
var updated_count := 0

# [{"lamps": [MeshInstance3D x3], "offset": float, "axis": int, "phase": int}]
var _heads: Array = []
var _grid: Dictionary = {}     # Vector2i -> PackedInt32Array(_heads 인덱스)
var _on_materials: Array = []
var _off_materials: Array = []
var _lamp_mesh: SphereMesh
var _pole_mesh: CylinderMesh
var _board_mesh: BoxMesh
var _camera_mesh: BoxMesh
var _pole_material: StandardMaterial3D
var _camera_material: StandardMaterial3D

func build(signals: Array) -> void:
	_make_shared_resources()
	for entry in signals:
		if not entry.has("axis_deg") or entry["axis_deg"].size() < 2:
			# 구 버전 산출물. 조용히 건너뛴다 — 신호 없이도 주행은 된다.
			continue
		var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		var half := float(entry.get("half_width", DEFAULT_HALF_WIDTH))
		var offset := TrafficSignal.offset_for(center.x, center.z)
		var has_camera := bool(entry.get("camera", false))
		for axis in 2:
			var bearing := float(entry["axis_deg"][axis])
			for way in 2:
				# 진입 방향. 한 축의 양방향 모두에 기둥이 선다.
				var forward := TrafficSignal.direction_of(bearing) \
					* (1.0 if way == 0 else -1.0)
				_add_head(center, forward, half, offset, axis, has_camera)

func _make_shared_resources() -> void:
	# 등마다 새 머티리얼을 만들면 372 x 3 = 1116 개가 된다. 6개를 공유하고
	# set_surface_override_material 로 바꿔 낀다.
	for color in LAMP_COLORS:
		var on := StandardMaterial3D.new()
		on.albedo_color = color
		on.emission_enabled = true
		on.emission = color
		on.emission_energy_multiplier = 2.0
		_on_materials.append(on)
		var off := StandardMaterial3D.new()
		off.albedo_color = color.darkened(0.75)
		_off_materials.append(off)

	_lamp_mesh = SphereMesh.new()
	_lamp_mesh.radius = LAMP_RADIUS
	_lamp_mesh.height = LAMP_RADIUS * 2.0
	_lamp_mesh.radial_segments = 8
	_lamp_mesh.rings = 4

	_pole_mesh = CylinderMesh.new()
	_pole_mesh.top_radius = POLE_RADIUS
	_pole_mesh.bottom_radius = POLE_RADIUS
	_pole_mesh.height = POLE_HEIGHT
	_pole_mesh.radial_segments = 6

	_board_mesh = BoxMesh.new()
	_board_mesh.size = Vector3(2.1, 0.7, 0.2)

	_camera_mesh = BoxMesh.new()
	_camera_mesh.size = Vector3(0.5, 0.3, 0.8)

	_pole_material = StandardMaterial3D.new()
	_pole_material.albedo_color = Color(0.25, 0.28, 0.26)

	_camera_material = StandardMaterial3D.new()
	_camera_material.albedo_color = Color(0.92, 0.92, 0.90)

func _add_head(center: Vector3, forward: Vector3, half: float,
		offset: float, axis: int, has_camera: bool) -> void:
	# forward 기준 오른쪽. Y 가 위인 좌표계에서 (x, z) 를 90° 돌린 것이다.
	var right := Vector3(-forward.z, 0.0, forward.x)
	var base := center - forward * (half + STOP_LINE_MARGIN_M) \
		+ right * maxf(half - 1.0, 1.0)

	var head := Node3D.new()
	# build() 는 add_child() 전에 불리므로 global_position 과 look_at 을 쓸 수
	# 없다. SignalField 자신이 원점에 단위 변환으로 있으므로 로컬 변환을 직접
	# 짠다. 기둥의 -Z(고도트 기준 정면)가 진입하는 차를 마주보게 하려면
	# 로컬 +Z 가 forward 여야 하고, 그때 X 는 UP x forward 다.
	var basis := Basis(Vector3(forward.z, 0.0, -forward.x), Vector3.UP, forward)
	head.transform = Transform3D(basis, base)
	add_child(head)

	var pole := MeshInstance3D.new()
	pole.mesh = _pole_mesh
	pole.material_override = _pole_material
	pole.position = Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)
	head.add_child(pole)

	var board := MeshInstance3D.new()
	board.mesh = _board_mesh
	board.material_override = _pole_material
	board.position = Vector3(0.0, POLE_HEIGHT, 0.0)
	head.add_child(board)

	var lamps: Array = []
	for lamp_index in 3:
		var lamp := MeshInstance3D.new()
		lamp.mesh = _lamp_mesh
		lamp.position = Vector3((lamp_index - 1) * LAMP_SPACING,
			POLE_HEIGHT, -0.12)
		lamp.set_surface_override_material(0, _off_materials[lamp_index])
		head.add_child(lamp)
		lamps.append(lamp)

	if has_camera:
		# 실제 도로에도 "신호위반 단속중" 표지가 있어 운전자가 미리 안다.
		# 모르고 걸리는 게 아니라 알고 거는 도박이라야 저울질이 된다.
		var box := MeshInstance3D.new()
		box.mesh = _camera_mesh
		box.material_override = _camera_material
		box.position = Vector3(0.0, POLE_HEIGHT + 0.6, -0.2)
		head.add_child(box)

	var index := _heads.size()
	_heads.append({"lamps": lamps, "offset": offset, "axis": axis,
		"phase": -1})
	var cell := TrafficSignal.cell_of(base.x, base.z)
	if not _grid.has(cell):
		_grid[cell] = PackedInt32Array()
	_grid[cell].append(index)
	head_count += 1

func _physics_process(_delta: float) -> void:
	if target == null or _heads.is_empty():
		return
	var t := TrafficSignal.now()
	updated_count = 0
	for cell in TrafficSignal.cells_near(target.global_position, UPDATE_RADIUS_M):
		if not _grid.has(cell):
			continue
		for index in _grid[cell]:
			updated_count += 1
			var head: Dictionary = _heads[index]
			var phase := TrafficSignal.phase_at(head["offset"], head["axis"], t)
			if head["phase"] == int(phase):
				continue
			head["phase"] = int(phase)
			# Phase 는 GREEN=0, YELLOW=1, RED=2 이고 등은 적/황/녹 순이라
			# 인덱스를 뒤집는다.
			var lit := 2 - int(phase)
			for lamp_index in 3:
				var lamp: MeshInstance3D = head["lamps"][lamp_index]
				lamp.set_surface_override_material(0,
					_on_materials[lamp_index] if lamp_index == lit
					else _off_materials[lamp_index])
