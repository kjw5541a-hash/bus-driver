extends TestCase
# route_data.gd 가 1번의 실제 산출물을 읽는지 본다. 가짜 데이터로 테스트하면
# 데이터 계약이 어긋나도 모른다.

func _ready() -> void:
	var data := RouteData.load_route("seoul-seodaemun03")
	ok(data != null, "seoul-seodaemun03 을 읽지 못했다")
	if data == null:
		finish()
		return

	ok(data.id == "seoul-seodaemun03", "id 가 틀렸다: %s" % data.id)
	ok(data.display_name != "", "표시 이름이 비었다")
	ok(data.from_name != "", "기점 이름이 비었다")
	ok(data.to_name != "", "종점 이름이 비었다")
	ok(data.route.size() > 100, "경로점이 %d 개뿐이다" % data.route.size())
	ok(data.stops.size() > 10, "정류장이 %d 개뿐이다" % data.stops.size())
	ok(data.chunks.size() > 0, "청크가 없다")
	ok(data.signals.size() > 10, "신호가 %d 개뿐이다" % data.signals.size())

	# 신호는 4번 서브프로젝트 계약대로 축 방위각과 반폭, 카메라를 가진다.
	var signal_entry: Dictionary = data.signals[0]
	ok(signal_entry.has("x") and signal_entry.has("z"),
		"신호 좌표가 없다: %s" % str(signal_entry))
	ok(signal_entry.has("axis_deg") and signal_entry["axis_deg"].size() == 2,
		"신호 축 방위각 계약이 다르다: %s" % str(signal_entry))
	ok(signal_entry.has("half_width") and float(signal_entry["half_width"]) > 0.0,
		"신호 반폭이 없다: %s" % str(signal_entry))
	ok(signal_entry.has("camera"), "신호 카메라 필드가 없다: %s" % str(signal_entry))
	ok(data.streetlights.size() > 20, "가로등이 %d 개뿐이다" % data.streetlights.size())
	if not data.streetlights.is_empty():
		ok(data.streetlights[0].size() == 3, "가로등 계약이 [x, z, yaw] 가 아니다")

	# 정차 목표점은 노선 위의 점이다. OSM 정류장 노드는 인도에 있어서
	# 그대로 쓰면 차선에 제대로 세워도 걸어오는 시간이 붙는다.
	ok(data.stop_targets.size() == data.stops.size(),
		"정차 목표점이 %d 개인데 정류장은 %d 곳이다"
		% [data.stop_targets.size(), data.stops.size()])
	var worst := 0.0
	for index in range(data.stops.size()):
		var target: Vector3 = data.stop_targets[index]
		# 목표점은 경로점이 아니라 선분 위에 있다. 직선 구간은 경로점이
		# 드물어 가장 가까운 경로점까지도 수십 m 가 나온다.
		var best := INF
		for segment in range(data.route.size() - 1):
			var closest := Geometry3D.get_closest_point_to_segment(target,
				data.route[segment], data.route[segment + 1])
			best = minf(best, target.distance_to(closest))
		worst = maxf(worst, best)
	ok(worst < 0.5, "정차 목표점이 노선 선분에서 %.2f m 떨어졌다" % worst)

	# progress_m 이 노선 길이를 넘으면 마지막 점으로 자른다.
	var last: Vector3 = data.route[data.route.size() - 1]
	ok(data.point_at_progress(1.0e9).distance_to(last) < 0.01,
		"노선 끝을 넘는 진행거리를 자르지 않았다")
	ok(data.point_at_progress(-5.0).distance_to(data.route[0]) < 0.01,
		"음수 진행거리를 0 으로 자르지 않았다")

	# 경로는 (x, z) 평면이다. y 는 전부 0 이어야 한다.
	for point in data.route:
		if point.y != 0.0:
			ok(false, "경로점의 y 가 0 이 아니다: %f" % point.y)
			break

	# 청크는 1번 계약대로 name/min/max 를 가진 사전이다.
	var chunk = data.chunks[0]
	ok(chunk.has("name") and chunk.has("min") and chunk.has("max"),
		"청크 계약이 다르다: %s" % str(chunk))

	# nearest_index 는 경로 위의 점에 대해 그 점 자신을 찾아야 한다.
	var probe: Vector3 = data.route[7]
	ok(data.nearest_index(probe) == 7, "nearest_index 가 자기 자신을 못 찾는다")
	# 경로에서 살짝 떨어진 점도 같은 인덱스로 붙어야 한다.
	ok(data.nearest_index(probe + Vector3(0.5, 0.0, 0.5)) == 7,
		"nearest_index 가 근처 점을 못 붙인다")

	ok(RouteData.list_route_ids().size() >= 3,
		"노선 목록이 %d 개다" % RouteData.list_route_ids().size())

	# 경로점별 도로 폭. 마주 오는 차선이 이것으로 반대편 차선 중앙을 잡는다.
	ok(data.route_width.size() == data.route.size(),
		"route_width %d 개, route %d 개" % [data.route_width.size(), data.route.size()])
	ok(data.route_width[0] >= 3.0, "도로 폭이 이상하다: %.2f" % data.route_width[0])
	var part := data.slice(0)
	ok(part.route_width.size() == part.route.size(),
		"잘린 뒤 route_width %d 개, route %d 개"
		% [part.route_width.size(), part.route.size()])
	# 경로점별 차로 정보. 교통이 이것으로 차선 중앙과 도로 중심선을 잡는다.
	for key in ["route_lanes", "route_oneway", "route_offset"]:
		ok(data.get(key).size() == data.route.size(), "%s 길이가 다르다" % key)
		ok(part.get(key).size() == part.route.size(), "잘린 뒤 %s 길이가 다르다" % key)
	# 옛 형식(키 없음)이면 차선 2, 왕복, 오프셋 w/4.
	var old := RouteData.new()
	old.route = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -100.0)])
	old.ensure_lanes()
	ok(old.route_lanes == PackedInt32Array([2, 2]), "옛 형식 차선 수")
	ok(old.route_oneway == PackedByteArray([0, 0]), "옛 형식 일방통행")
	equal_approx(old.route_offset[0], RouteData.DEFAULT_ROAD_WIDTH_M * 0.25, 0.001,
		"옛 형식 오프셋")
	# 북쪽 진행의 왼쪽은 서(-X). 중심선은 경로를 왼쪽으로 오프셋만큼 민 것이다.
	var center := old.center_line()
	equal_approx(center[0].x, -1.75, 0.001, "중심선 x")
	equal_approx(center[1].z, -100.0, 0.001, "중심선 z")
	finish()
