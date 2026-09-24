extends RefCounted
class_name RouteData
# route_<id>.json 을 읽는 유일한 지점. 1번 서브프로젝트의 데이터 계약이
# 코드 전체에 흩어지지 않게 여기서만 키 이름을 안다.

# 메뉴가 고른 노선을 주행 씬에 넘기는 통로. 씬 전환 사이에 값을 나를
# 오토로드를 따로 만들지 않으려고 static 변수를 쓴다.
static var selected_id := "seoul-100"

var id := ""
var display_name := ""
var from_name := ""
var to_name := ""
var route: PackedVector3Array = []
var stops: Array = []
var chunks: Array = []
var signals: Array = []
# 정차 목표점. stops 와 같은 순서다. 자세한 이유는 point_at_progress 를 보라.
var stop_targets: PackedVector3Array = []

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
