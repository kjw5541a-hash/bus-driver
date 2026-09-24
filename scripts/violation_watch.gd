extends Node
class_name ViolationWatch
# 적색에 정지선을 넘었는지 본다. 그리지 않는다 — 표시는 ViolationHud 의 일이다.
#
# 황색 진입은 위반이 아니다. 황색 3초에 안전하게 설 수 있는 거리가 아니면
# 억울하고, 실제 단속도 이렇게 하지 않는다.

const WATCH_RADIUS_M := 60.0
const STOP_LINE_MARGIN_M := 2.0
const DEFAULT_HALF_WIDTH := 7.5

signal violation(index: int, by_camera: bool)
signal busted

var bus: Node3D
var traffic: Traffic

var violations := 0
var camera_violations := 0
var is_busted := false

var _signals: Array = []
var _grid: Dictionary = {}       # Vector2i -> PackedInt32Array(_signals 인덱스)
var _previous: Dictionary = {}   # 신호 인덱스 -> 직전 프레임의 부호 거리

func build(signals: Array) -> void:
	_signals = signals
	for index in range(signals.size()):
		var entry: Dictionary = signals[index]
		if not entry.has("axis_deg") or entry["axis_deg"].size() < 2:
			continue
		var cell := TrafficSignal.cell_of(float(entry["x"]), float(entry["z"]))
		if not _grid.has(cell):
			_grid[cell] = PackedInt32Array()
		_grid[cell].append(index)

func _physics_process(_delta: float) -> void:
	if bus == null or is_busted or _grid.is_empty():
		return
	var here := bus.global_position
	# 고도트의 정면은 -Z 다.
	var forward := -bus.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var heading := TrafficSignal.bearing_of(forward)
	var t := TrafficSignal.now()

	var seen := {}
	for cell in TrafficSignal.cells_near(here, WATCH_RADIUS_M):
		if not _grid.has(cell):
			continue
		for index in _grid[cell]:
			var entry: Dictionary = _signals[index]
			var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
			if center.distance_to(Vector3(here.x, 0.0, here.z)) > WATCH_RADIUS_M:
				continue
			seen[index] = true
			var half := float(entry.get("half_width", DEFAULT_HALF_WIDTH))
			# 버스에서 교차로 중심으로 가는 방향을 양으로 잡은 부호 거리.
			# 정지선은 중심에서 진입 방향 반대로 half + 2 m 떨어져 있다.
			# ponytail: 교차로 바로 옆에서 크게 꺾으면 forward 가 확 돌아
			# 부호가 뛸 수 있다. 실제로 그러려면 정지선 위에서 제자리 선회를
			# 해야 해서 놔둔다. 오검출이 보이면 직전 속도 방향을 쓴다.
			var along := (center - here).dot(forward)
			var signed := along - (half + STOP_LINE_MARGIN_M)
			var was: float = _previous.get(index, signed)
			_previous[index] = signed
			if was > 0.0 and signed <= 0.0:
				_on_enter(index, entry, heading, t)

	# 반경을 벗어난 신호는 기억에서 지운다. 안 지우면 한 바퀴 돌아왔을 때
	# 옛 부호 거리와 비교해 헛 위반이 난다.
	for index in _previous.keys():
		if not seen.has(index):
			_previous.erase(index)

func _on_enter(index: int, entry: Dictionary, heading: float, t: float) -> void:
	var axis := TrafficSignal.axis_for(heading, entry["axis_deg"])
	var offset := TrafficSignal.offset_for(float(entry["x"]), float(entry["z"]))
	if TrafficSignal.phase_at(offset, axis, t) != TrafficSignal.Phase.RED:
		return
	violations += 1
	var by_camera := bool(entry.get("camera", false))
	if by_camera:
		camera_violations += 1
	violation.emit(index, by_camera)
	# 카메라는 과태료지 현장 제지가 아니다. 주행을 멈추는 것은 경찰뿐이다.
	if traffic != null and traffic.police_sees(bus.global_position):
		is_busted = true
		busted.emit()
