extends RefCounted
class_name RouteData
# route_<id>.json 을 읽는 유일한 지점. 1번 서브프로젝트의 데이터 계약이
# 코드 전체에 흩어지지 않게 여기서만 키 이름을 안다.

# 메뉴가 고른 노선을 주행 씬에 넘기는 통로. 씬 전환 사이에 값을 나를
# 오토로드를 따로 만들지 않으려고 static 변수를 쓴다.
static var selected_id := "seoul-100"

# 메뉴가 고른 구간. selected_id 와 같은 이유로 static 이다.
static var selected_section := 0

# 구간. 한 판을 10 분 안팎으로 만들려고 정류장 10 곳씩 자른다. 경계 정류장은
# 양쪽 구간이 함께 쓴다 — 이어 달리면 실제 노선처럼 끊김이 없다.
const SECTION_STOPS := 10
const SECTION_MIN_STOPS := 5     # 이보다 짧은 꼬리는 앞 구간에 붙인다
const LEAD_IN_M := 60.0          # 첫 정류장 앞 여유. 출발하자마자 서지 않게
const SECTION_SIGNAL_M := 30.0   # 잘린 경로에서 이만큼 안의 신호만 남긴다
const DEFAULT_ROAD_WIDTH_M := 7.0  # route_width 가 없는 옛 산출물

var id := ""
var display_name := ""
var from_name := ""
var to_name := ""
var route: PackedVector3Array = []
var route_width: PackedFloat32Array = []   # 경로점별 도로 폭. route 와 같은 길이
var stops: Array = []
var chunks: Array = []
var signals: Array = []
# 정차 목표점. stops 와 같은 순서다. 자세한 이유는 point_at_progress 를 보라.
var stop_targets: PackedVector3Array = []
# slice() 가 채운다. 자르지 않은 원본은 0 / 1 이다.
var section := 0
var section_count := 1

static func load_route(route_id: String) -> RouteData:
	var raw := FileAccess.get_file_as_string("res://assets/routes/route_%s.json" % route_id)
	if raw == "":
		return null
	# JSON.parse_string 은 실패하면 null 을 돌려준다. 타입 지정된 변수에 바로
	# 대입하면 그 대입 자체가 런타임 에러라, 타입 없는 변수로 먼저 받는다.
	var parsed = JSON.parse_string(raw)
	if parsed == null:
		return null

	var data := RouteData.new()
	data.id = str(parsed.get("id", route_id))
	data.display_name = str(parsed.get("name", route_id))
	data.from_name = str(parsed.get("from", ""))
	data.to_name = str(parsed.get("to", ""))
	for point in parsed.get("route", []):
		# 산출물은 (x, z) 쌍이다. y 는 평지라 0 이다.
		data.route.append(Vector3(point[0], 0.0, point[1]))
	for width in parsed.get("route_width", []):
		data.route_width.append(float(width))
	if data.route_width.size() != data.route.size():
		# 옛 산출물에는 폭이 없다. 기본 폭으로 채운다.
		data.route_width = PackedFloat32Array()
		data.route_width.resize(data.route.size())
		data.route_width.fill(DEFAULT_ROAD_WIDTH_M)
	data.stops = parsed.get("stops", [])
	data.chunks = parsed.get("chunks", [])
	# 구 버전 산출물에는 signals 가 없거나 axis_deg 가 빠져 있다. 비어 있으면
	# 신호 관련 노드가 조용히 아무것도 안 하도록 그대로 넘긴다.
	data.signals = parsed.get("signals", [])
	data._build_stop_targets()
	return data

static func list_route_ids() -> PackedStringArray:
	"""assets/routes 를 훑어 노선 id 를 낸다. 노선을 더 구우면 알아서 늘어난다."""
	var ids := PackedStringArray()
	var dir := DirAccess.open("res://assets/routes")
	if dir == null:
		return ids
	for file in dir.get_files():
		if file.begins_with("route_") and file.ends_with(".json"):
			ids.append(file.trim_prefix("route_").trim_suffix(".json"))
	ids.sort()
	return ids

func nearest_index(point: Vector3) -> int:
	"""point 에 가장 가까운 경로점의 인덱스. 리스폰 위치를 정할 때 쓴다."""
	var best := 0
	var best_distance := INF
	for i in range(route.size()):
		var distance := route[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best

func point_at_progress(distance_m: float) -> Vector3:
	"""노선 시작점에서 distance_m 만큼 간 지점.

	정류장 좌표(x, z)는 OSM bus_stop 노드, 곧 도로 옆 인도다. 버스가 차선에
	제대로 서도 중앙값 6.9 m, 최대 28.6 m 떨어져 있어 그대로 쓰면 피할 수
	없는 페널티가 된다. 정차 목표점은 이 함수가 내는 노선 위의 점이다.
	"""
	if route.size() == 0:
		return Vector3.ZERO
	if route.size() == 1 or distance_m <= 0.0:
		return route[0]
	var remaining := distance_m
	for index in range(1, route.size()):
		var span := route[index - 1].distance_to(route[index])
		if remaining <= span:
			var ratio := remaining / maxf(span, 0.001)
			return route[index - 1].lerp(route[index], ratio)
		remaining -= span
	# progress_m 이 노선 길이를 넘었다. 종점으로 자른다.
	return route[route.size() - 1]

func _build_stop_targets() -> void:
	stop_targets = PackedVector3Array()
	for stop in stops:
		stop_targets.append(point_at_progress(float(stop.get("progress_m", 0.0))))

func sections() -> Array:
	"""구간마다 Vector2i(첫 정류장, 끝 정류장). 정류장이 2 곳 미만이면 빈 배열."""
	var last := stops.size() - 1
	var bounds: Array = []
	if last < 1:
		return bounds
	var start := 0
	while start < last:
		var end := mini(start + SECTION_STOPS, last)
		bounds.append(Vector2i(start, end))
		start = end
	var tail: Vector2i = bounds[bounds.size() - 1]
	if bounds.size() > 1 and tail.y - tail.x + 1 < SECTION_MIN_STOPS:
		bounds.pop_back()
		bounds[bounds.size() - 1] = Vector2i(bounds[bounds.size() - 1].x, tail.y)
	return bounds

func slice(index: int) -> RouteData:
	"""index 번 구간만 담은 새 RouteData. 범위 밖이면 0 번. 구간이 없으면 자신."""
	var bounds := sections()
	if bounds.is_empty():
		return self
	if index < 0 or index >= bounds.size():
		index = 0
	var range_of: Vector2i = bounds[index]
	var start_m := maxf(0.0, float(stops[range_of.x].get("progress_m", 0.0)) - LEAD_IN_M)
	var end_m := float(stops[range_of.y].get("progress_m", 0.0))

	var part := RouteData.new()
	part.id = id
	part.display_name = display_name
	part.from_name = from_name
	part.to_name = to_name
	part.chunks = chunks
	part.section = index
	part.section_count = bounds.size()
	part.route = _route_between(start_m, end_m)
	# 손수 만든 RouteData(테스트)는 폭이 없다. 있을 때만 자른다.
	if route_width.size() == route.size():
		part.route_width = _widths_between(start_m, end_m)
	for stop_index in range(range_of.x, range_of.y + 1):
		var stop: Dictionary = stops[stop_index].duplicate()
		stop["progress_m"] = float(stop.get("progress_m", 0.0)) - start_m
		part.stops.append(stop)
	for entry in signals:
		var point := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		if part.distance_to_route(point) <= SECTION_SIGNAL_M:
			part.signals.append(entry)
	part._build_stop_targets()
	return part

func length_m() -> float:
	var total := 0.0
	for index in range(1, route.size()):
		total += route[index - 1].distance_to(route[index])
	return total

func distance_to_route(point: Vector3) -> float:
	var best := INF
	for index in range(1, route.size()):
		var foot := Geometry3D.get_closest_point_to_segment(point, route[index - 1], route[index])
		best = minf(best, foot.distance_to(point))
	return best

func _route_between(start_m: float, end_m: float) -> PackedVector3Array:
	var part := PackedVector3Array([point_at_progress(start_m)])
	var travelled := 0.0
	for index in range(1, route.size()):
		travelled += route[index - 1].distance_to(route[index])
		if travelled > start_m and travelled < end_m:
			part.append(route[index])
	part.append(point_at_progress(end_m))
	return part

func _widths_between(start_m: float, end_m: float) -> PackedFloat32Array:
	"""_route_between 과 같은 점들의 폭. 보간점은 가까운 원래 점의 폭."""
	var part := PackedFloat32Array([_width_at_progress(start_m)])
	var travelled := 0.0
	for index in range(1, route.size()):
		travelled += route[index - 1].distance_to(route[index])
		if travelled > start_m and travelled < end_m:
			part.append(route_width[index])
	part.append(_width_at_progress(end_m))
	return part

func _width_at_progress(distance_m: float) -> float:
	var travelled := 0.0
	for index in range(1, route.size()):
		var span := route[index - 1].distance_to(route[index])
		if travelled + span >= distance_m:
			return route_width[index - 1] if distance_m - travelled < span * 0.5 else route_width[index]
		travelled += span
	return route_width[route_width.size() - 1]
