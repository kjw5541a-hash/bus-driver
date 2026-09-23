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

	finish()
