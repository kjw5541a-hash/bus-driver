extends Node3D
class_name StopField
# 정류장 표지판과 대기 승객. 판정은 여기서 하지 않는다 — BoardingWatch 의
# 일이다.
#
# 표지판과 승객은 OSM bus_stop 노드 좌표에 세운다. 정차 목표점은 노선 위에
# 있지만 그건 판정용이고, 보이는 것은 인도 위에 있어야 한다.
#
# 충돌면은 붙이지 않는다. 버스가 승객을 들이받아 주행이 막히는 쪽이 더 나쁘다.

const UPDATE_RADIUS_M := 200.0
const POLE_HEIGHT := 2.6
const SIGN_SIZE := Vector3(0.9, 0.5, 0.08)
const RIDER_HEIGHT := 1.7
const RIDER_RADIUS := 0.22
const RIDER_SPACING := 0.6
const RIDERS_PER_ROW := 4

var target: Node3D
var sign_count := 0
var rider_count := 0
var updated_count := 0

# [{"node": Node3D, "riders": Array[MeshInstance3D]}]
var _stops: Array = []
var _grid: Dictionary = {}     # Vector2i -> PackedInt32Array(_stops 인덱스)

var _pole_mesh: CylinderMesh
var _sign_mesh: BoxMesh
var _rider_mesh: CapsuleMesh
var _pole_material: StandardMaterial3D
var _sign_material: StandardMaterial3D
var _rider_material: StandardMaterial3D

func build(stops: Array, plan: PassengerPlan) -> void:
	_make_shared_resources()
	for index in range(stops.size()):
		var stop: Dictionary = stops[index]
		var here := Vector3(float(stop.get("x", 0.0)), 0.0,
			float(stop.get("z", 0.0)))
		var waiting := 0
		if plan != null:
			waiting = plan.waiting_at(index)
		_add_stop(index, here, waiting)

func _make_shared_resources() -> void:
	# 대기 승객이 노선 전체에 300 명 넘는다. 개별 머티리얼을 만들면 안 된다.
	_pole_mesh = CylinderMesh.new()
	_pole_mesh.top_radius = 0.06
	_pole_mesh.bottom_radius = 0.06
	_pole_mesh.height = POLE_HEIGHT
	_pole_mesh.radial_segments = 6

	_sign_mesh = BoxMesh.new()
	_sign_mesh.size = SIGN_SIZE

	_rider_mesh = CapsuleMesh.new()
	_rider_mesh.radius = RIDER_RADIUS
	_rider_mesh.height = RIDER_HEIGHT
	_rider_mesh.radial_segments = 6
	_rider_mesh.rings = 2

	_pole_material = StandardMaterial3D.new()
	_pole_material.albedo_color = Color(0.30, 0.32, 0.34)

	_sign_material = StandardMaterial3D.new()
	_sign_material.albedo_color = Color(0.10, 0.35, 0.70)

	_rider_material = StandardMaterial3D.new()
	_rider_material.albedo_color = Color(0.85, 0.72, 0.55)

func _add_stop(index: int, here: Vector3, waiting: int) -> void:
	var node := Node3D.new()
	# build() 는 add_child() 전에 불리므로 global_position 을 쓸 수 없다.
	# StopField 자신이 원점에 단위 변환으로 있어 로컬이 곧 전역이다.
	node.transform = Transform3D(Basis.IDENTITY, here)
	add_child(node)

	var pole := MeshInstance3D.new()
	pole.mesh = _pole_mesh
	pole.material_override = _pole_material
	pole.position = Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)
	node.add_child(pole)

	var board := MeshInstance3D.new()
	board.mesh = _sign_mesh
	board.material_override = _sign_material
	board.position = Vector3(0.0, POLE_HEIGHT, 0.0)
	node.add_child(board)
	sign_count += 1

	var riders: Array = []
	for rider_index in waiting:
		var rider := MeshInstance3D.new()
		rider.mesh = _rider_mesh
		rider.material_override = _rider_material
		# 표지판 옆에 두 줄로 세운다.
		var column := rider_index % RIDERS_PER_ROW
		var row := rider_index / RIDERS_PER_ROW
		rider.position = Vector3((column - 1.5) * RIDER_SPACING,
			RIDER_HEIGHT * 0.5, 0.8 + row * RIDER_SPACING)
		node.add_child(rider)
		riders.append(rider)
		rider_count += 1

	_stops.append({"node": node, "riders": riders})
	var cell := TrafficSignal.cell_of(here.x, here.z)
	if not _grid.has(cell):
		_grid[cell] = PackedInt32Array()
	_grid[cell].append(index)

func clear_riders(index: int) -> void:
	"""승객이 탔다. 캡슐을 치운다."""
	if index < 0 or index >= _stops.size():
		return
	for rider in _stops[index]["riders"]:
		rider.visible = false

func _physics_process(_delta: float) -> void:
	if target == null or _stops.is_empty():
		return
	# 먼 정류장은 통째로 숨긴다. seoul-100 은 정류장 114 곳에 승객 300 명이
	# 넘어서 전부 그리면 낭비다.
	updated_count = 0
	var near := {}
	for cell in TrafficSignal.cells_near(target.global_position, UPDATE_RADIUS_M):
		if not _grid.has(cell):
			continue
		for index in _grid[cell]:
			near[index] = true
	for index in range(_stops.size()):
		var wanted: bool = near.has(index)
		var node: Node3D = _stops[index]["node"]
		if node.visible != wanted:
			node.visible = wanted
		if wanted:
			updated_count += 1
