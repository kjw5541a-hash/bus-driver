extends Node3D
class_name StopField
# 정류장 표지판과 대기 승객. 판정은 여기서 하지 않는다 — BoardingWatch 의
# 일이다.
#
# 표지판과 승객은 OSM bus_stop 노드 좌표에 세운다. 정차 목표점은 노선 위에
# 있지만 그건 판정용이고, 보이는 것은 인도 위에 있어야 한다.
#
# 정차 목표점에는 노선 방향으로 노란 바닥 구역을 칠한다. 표지판만으로는
# 운전 중에 정류장이 안 보였다. 다음 정류장 구역은 밝게 깜빡이고 그 위에
# 빛기둥이 선다. 바닥 구역만으로는 70 m 밖에서 비스듬해 거의 안 보였다.
#
# 충돌면은 붙이지 않는다. 버스가 승객을 들이받아 주행이 막히는 쪽이 더 나쁘다.

const UPDATE_RADIUS_M := 200.0
const POLE_HEIGHT := 2.6
const SIGN_SIZE := Vector3(1.6, 0.9, 0.08)
const ZONE_SIZE := Vector2(3.0, 12.0)   # 차선 폭 x 버스 길이
const ZONE_Y := 0.03                    # 차선 도색(0.02) 위
const BLINK_HZ := 1.5
const BEAM_HEIGHT := 12.0
const BEAM_RADIUS := 1.2
const RIDER_HEIGHT := 1.7
const RIDER_RADIUS := 0.22
const RIDER_SPACING := 0.6
const RIDERS_PER_ROW := 4

var target: Node3D
var boarding: BoardingWatch   # 다음 정류장을 읽기만 한다
var sign_count := 0
var rider_count := 0
var zone_count := 0
var updated_count := 0

# [{"node": Node3D, "riders": Array[MeshInstance3D], "zone": MeshInstance3D,
#   "spot": Vector3}]
var _stops: Array = []
var _grid: Dictionary = {}     # Vector2i -> PackedInt32Array(_stops 인덱스)

var _pole_mesh: CylinderMesh
var _sign_mesh: BoxMesh
var _rider_mesh: CapsuleMesh
var _zone_mesh: PlaneMesh
var _pole_material: StandardMaterial3D
var _sign_material: StandardMaterial3D
var _rider_material: StandardMaterial3D
var _zone_material: StandardMaterial3D
var _next_zone_material: StandardMaterial3D
var _beam: MeshInstance3D
var _lit_index := -1
var _clock := 0.0

func build(data: RouteData, plan: PassengerPlan) -> void:
	_make_shared_resources()
	for index in range(data.stops.size()):
		var stop: Dictionary = data.stops[index]
		var here := Vector3(float(stop.get("x", 0.0)), 0.0,
			float(stop.get("z", 0.0)))
		var waiting := 0
		if plan != null:
			waiting = plan.waiting_at(index)
		# 구역 방향은 목표점 앞뒤 1 m 의 노선 방향이다.
		var progress := float(stop.get("progress_m", 0.0))
		var forward := data.point_at_progress(progress + 1.0) \
			- data.point_at_progress(progress - 1.0)
		_add_stop(index, here, waiting, data.stop_targets[index], forward)

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
	# 그늘에서도 보이게 스스로 빛낸다.
	_sign_material.emission_enabled = true
	_sign_material.emission = Color(0.10, 0.35, 0.70)

	_zone_mesh = PlaneMesh.new()
	_zone_mesh.size = ZONE_SIZE

	_zone_material = StandardMaterial3D.new()
	_zone_material.albedo_color = Color(1.0, 0.80, 0.0, 0.35)
	_zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_next_zone_material = _zone_material.duplicate()
	_next_zone_material.albedo_color = Color(1.0, 0.85, 0.0, 0.75)

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = BEAM_RADIUS
	beam_mesh.bottom_radius = BEAM_RADIUS
	beam_mesh.height = BEAM_HEIGHT
	beam_mesh.radial_segments = 12
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.mesh = beam_mesh
	_beam.material_override = _next_zone_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)

	_rider_material = StandardMaterial3D.new()
	_rider_material.albedo_color = Color(0.85, 0.72, 0.55)

func _add_stop(index: int, here: Vector3, waiting: int, spot: Vector3,
		forward: Vector3) -> void:
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

	# 구역은 표지판 노드에 달아 멀면 같이 숨는다. 노드는 회전이 없어서
	# 목표점까지의 차이가 곧 로컬 위치다.
	var zone := MeshInstance3D.new()
	zone.mesh = _zone_mesh
	zone.material_override = _zone_material
	forward.y = 0.0
	var facing := Basis.IDENTITY
	if forward.length() > 0.01:
		facing = Basis.looking_at(forward)
	zone.transform = Transform3D(facing, spot - here + Vector3(0.0, ZONE_Y, 0.0))
	node.add_child(zone)
	zone_count += 1

	_stops.append({"node": node, "riders": riders, "zone": zone, "spot": spot})
	var cell := TrafficSignal.cell_of(here.x, here.z)
	if not _grid.has(cell):
		_grid[cell] = PackedInt32Array()
	_grid[cell].append(index)

func set_boarded(index: int, count: int) -> void:
	"""앞에서부터 count 명이 탔다. 그만큼 캡슐을 치운다.

	한꺼번에 치우면 인원에 따라 승하차 시간이 다른 것이 안 보인다. 정원이
	차서 못 탄 사람은 그대로 남는다.
	"""
	if index < 0 or index >= _stops.size():
		return
	var riders: Array = _stops[index]["riders"]
	for rider_index in range(riders.size()):
		riders[rider_index].visible = rider_index >= count

func _physics_process(delta: float) -> void:
	if target == null or _stops.is_empty():
		return
	_light_next(delta)
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

func _light_next(delta: float) -> void:
	"""다음 정류장 구역만 밝은 머티리얼로 바꾸고 투명도를 깜빡인다."""
	var next := boarding.next_index if boarding != null else -1
	if next != _lit_index:
		if _lit_index >= 0 and _lit_index < _stops.size():
			_stops[_lit_index]["zone"].material_override = _zone_material
		_beam.visible = next >= 0 and next < _stops.size()
		if _beam.visible:
			_stops[next]["zone"].material_override = _next_zone_material
			# StopField 는 원점에 있어 로컬이 곧 전역이다.
			_beam.position = _stops[next]["spot"] + Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
		_lit_index = next
	_clock += delta
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * BLINK_HZ)
	_next_zone_material.albedo_color.a = lerpf(0.35, 0.9, pulse)
