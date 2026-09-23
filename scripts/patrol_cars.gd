extends Node3D
class_name PatrolCars
# 노선 위를 왕복하는 순찰 경찰차. 물리가 없다 — 경로 누적거리를 따라
# 위치만 옮긴다.
#
# 충돌면을 안 붙이는 이유는 버스가 들이받아 주행이 멈추는 쪽이 더 나쁘기
# 때문이다. 실제 차량과의 충돌은 6번 서브프로젝트(교통 AI)다.

const PATROL_SPEED_MPS := 11.0    # 약 40 km/h
const PATROL_SIGHT_M := 80.0
const CAR_COUNT := 2
const BODY_SIZE := Vector3(1.8, 1.4, 4.6)

var cars: Array[Node3D] = []

var _route: PackedVector3Array = []
var _cumulative: PackedFloat32Array = []
var _distances: PackedFloat32Array = []
var _directions: PackedInt32Array = []

func build(route: PackedVector3Array) -> void:
	if route.size() < 2:
		# 경로가 없으면 순찰도 없다. 조용히 아무것도 하지 않는다.
		return
	_route = route
	_cumulative = PackedFloat32Array()
	_cumulative.append(0.0)
	for index in range(1, route.size()):
		_cumulative.append(_cumulative[index - 1]
			+ route[index].distance_to(route[index - 1]))

	var total := _cumulative[_cumulative.size() - 1]
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.10, 0.18, 0.55)
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.90, 0.10, 0.12)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(0.90, 0.10, 0.12)

	var body_mesh := BoxMesh.new()
	body_mesh.size = BODY_SIZE
	var beacon_mesh := BoxMesh.new()
	beacon_mesh.size = Vector3(1.0, 0.2, 0.3)

	# 두 대를 노선의 1/4 과 3/4 에 서로 반대 방향으로 놓는다.
	for index in CAR_COUNT:
		var car := Node3D.new()
		add_child(car)
		var body := MeshInstance3D.new()
		body.mesh = body_mesh
		body.material_override = body_material
		body.position = Vector3(0.0, BODY_SIZE.y * 0.5, 0.0)
		car.add_child(body)
		var beacon := MeshInstance3D.new()
		beacon.mesh = beacon_mesh
		beacon.material_override = beacon_material
		beacon.position = Vector3(0.0, BODY_SIZE.y + 0.1, 0.0)
		car.add_child(beacon)
		cars.append(car)
		_distances.append(total * (0.25 + 0.5 * index))
		_directions.append(1 if index == 0 else -1)
	_move_all()

func _ready() -> void:
	# build() 는 add_child() 전에 불릴 수 있고, 트리 밖에서는 global_position 을
	# 쓸 수 없다. 트리에 들어온 뒤 한 번 더 놓는다.
	_move_all()

func _physics_process(delta: float) -> void:
	if _route.size() < 2:
		return
	var total := _cumulative[_cumulative.size() - 1]
	for index in cars.size():
		var distance := _distances[index] + _directions[index] * PATROL_SPEED_MPS * delta
		# 끝에 닿으면 돌아온다. 노선 밖으로 나가면 위치 보간이 깨진다.
		if distance <= 0.0:
			distance = 0.0
			_directions[index] = 1
		elif distance >= total:
			distance = total
			_directions[index] = -1
		_distances[index] = distance
	_move_all()

func _move_all() -> void:
	if cars.is_empty() or not is_inside_tree():
		return
	var total := _cumulative[_cumulative.size() - 1]
	for index in cars.size():
		var here := _sample(_distances[index])
		var ahead := _sample(clampf(_distances[index] + _directions[index] * 5.0,
			0.0, total))
		var car := cars[index]
		car.global_position = here
		if here.distance_to(ahead) > 0.01:
			car.look_at(ahead, Vector3.UP)

func _sample(distance: float) -> Vector3:
	"""경로 누적거리 위의 점. 이분 탐색이라 경로점이 늘어도 싸다."""
	var low := 0
	var high := _cumulative.size() - 1
	while low + 1 < high:
		var mid := (low + high) / 2
		if _cumulative[mid] <= distance:
			low = mid
		else:
			high = mid
	var span := _cumulative[high] - _cumulative[low]
	if span <= 0.0:
		return _route[low]
	var ratio := clampf((distance - _cumulative[low]) / span, 0.0, 1.0)
	return _route[low].lerp(_route[high], ratio)

func sees(point: Vector3) -> bool:
	"""어느 경찰차든 point 를 전방 시야 안에 두고 있는가."""
	for car in cars:
		var to_point := point - car.global_position
		if to_point.length() > PATROL_SIGHT_M:
			continue
		# 고도트의 정면은 -Z 다.
		if (-car.global_transform.basis.z).dot(to_point) > 0.0:
			return true
	return false
