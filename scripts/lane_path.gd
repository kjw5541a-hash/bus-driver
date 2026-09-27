extends RefCounted
class_name LanePath
# 차선 하나. 경로점과 누적 거리를 들고, 누적 거리로 위치와 진행 방향을 낸다.
# 자기 위의 정지선(신호 교차로)도 안다. 그리지 않는다.

const STOP_LINE_MARGIN_M := 2.0   # ViolationWatch 와 같은 정지선 여유
const STOP_PASSED_M := 0.1        # 앞 범퍼가 이만큼 넘은 정지선은 지난 것이다
const CROSS_MIN_M := 30.0
const CROSS_MAX_M := 60.0
const ARM_MIN_M := 5.0            # 갈래 차선은 정지선 뒤로 이만큼은 있어야 차가 선다

var points: PackedVector3Array = []
var cumulative: PackedFloat32Array = []
var stops: Array = []   # {"at_m", "offset", "axis", "signal"}, at_m 오름차순

static func make(route: PackedVector3Array) -> LanePath:
	var lane := LanePath.new()
	var sums := PackedFloat32Array([0.0])
	for index in range(1, route.size()):
		sums.append(sums[index - 1] + route[index].distance_to(route[index - 1]))
	lane.points = route
	lane.cumulative = sums
	return lane

static func crossing(center: Vector3, bearing_deg: float, half_width: float,
		axis: int, offset_s: float) -> LanePath:
	"""교차로 중심을 지나는 직선 차선. 진행 방향 오른쪽으로 반폭의 절반 비킨다."""
	var forward := TrafficSignal.direction_of(bearing_deg)
	var side := Vector3(-forward.z, 0.0, forward.x) * half_width * 0.5
	var reach := clampf(half_width * 4.0, CROSS_MIN_M, CROSS_MAX_M)
	var lane := make(PackedVector3Array([center - forward * reach + side,
		center + forward * reach + side]))
	lane.stops.append({"at_m": reach - half_width - STOP_LINE_MARGIN_M,
		"offset": offset_s, "axis": axis, "signal": -1})
	return lane

static func arm_points(arm: Dictionary) -> PackedVector3Array:
	"""bake 가 낸 갈래 점 [[x, z], ...]. 첫 점이 교차로다."""
	var line := PackedVector3Array()
	for point in arm.get("points", []):
		line.append(Vector3(float(point[0]), 0.0, float(point[1])))
	return line

static func from_arms(in_arm: Dictionary, out_arm: Dictionary, half_width: float,
		axis: int, offset_s: float) -> LanePath:
	"""in_arm 으로 들어와 교차로를 지나 out_arm 으로 나가는 차선. 진행 방향
	오른쪽으로 들어오는 갈래의 가장 바깥 차선 중앙만큼 비킨다. 들어오는 갈래가
	정지선 뒤로 ARM_MIN_M 도 안 되면 null."""
	var inbound := arm_points(in_arm)
	inbound.reverse()
	var outbound := arm_points(out_arm)
	var stop_m := make(inbound).length_m() - half_width - STOP_LINE_MARGIN_M
	if stop_m < ARM_MIN_M or outbound.size() < 2:
		return null
	var line := inbound + outbound.slice(1)
	var width := float(in_arm.get("width", half_width * 2.0))
	var shift := Lanes.outer_offset(width, Lanes.even_count(width))
	var shifted := PackedVector3Array()
	for index in line.size():
		var forward := line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
		shifted.append(line[index] + Vector3(-forward.z, 0.0, forward.x) * shift)
	var lane := make(shifted)
	lane.stops.append({"at_m": stop_m, "offset": offset_s, "axis": axis, "signal": -1})
	return lane

func length_m() -> float:
	return cumulative[cumulative.size() - 1] if cumulative.size() > 0 else 0.0

func sample(distance: float) -> Vector3:
	"""누적 거리 위의 점. 이분 탐색이라 경로점이 늘어도 싸다."""
	var low := 0
	var high := cumulative.size() - 1
	while low + 1 < high:
		var mid := (low + high) / 2
		if cumulative[mid] <= distance:
			low = mid
		else:
			high = mid
	var span := cumulative[high] - cumulative[low]
	if span <= 0.0:
		return points[low]
	return points[low].lerp(points[high], clampf((distance - cumulative[low]) / span, 0.0, 1.0))

func direction_at(distance: float) -> Vector3:
	var ahead := sample(minf(distance + 2.0, length_m()))
	var behind := sample(maxf(distance - 2.0, 0.0))
	var forward := ahead - behind
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

func index_at(distance: float) -> int:
	"""누적 거리에 가장 가까운 경로점 인덱스."""
	var low := 0
	var high := cumulative.size() - 1
	while low + 1 < high:
		var mid := (low + high) / 2
		if cumulative[mid] <= distance:
			low = mid
		else:
			high = mid
	return low if distance - cumulative[low] < cumulative[high] - distance else high

func project(point: Vector3) -> Vector2:
	"""(누적 거리, 차선까지 부호 있는 수평 거리 — 진행 방향 오른쪽이 양수).
	높이는 무시한다."""
	# ponytail: 경로점 전체를 훑는다(100번 636 점). 프레임당 몇 번뿐이라 놔둔다.
	# 느려지면 직전 결과 둘레만 훑는다.
	var flat := Vector3(point.x, 0.0, point.z)
	var best := INF
	var along := 0.0
	var side := 1.0
	for index in range(1, points.size()):
		var start := points[index - 1]
		var foot := Geometry3D.get_closest_point_to_segment(flat, start, points[index])
		var distance := foot.distance_to(flat)
		if distance < best:
			best = distance
			along = cumulative[index - 1] + start.distance_to(foot)
			var forward := points[index] - start
			# 진행 방향 (fx, fz) 의 오른쪽은 (-fz, fx) 다.
			side = -1.0 if Vector3(-forward.z, 0.0, forward.x).dot(flat - foot) < 0.0 else 1.0
	return Vector2(along, best * side)

func add_signals(signals: Array, reach_m: float) -> void:
	"""차선에서 reach_m 안의 신호마다 진행 방향 축과 정지선 누적 거리를 구해 둔다."""
	for index in signals.size():
		var entry: Dictionary = signals[index]
		if not entry.has("axis_deg") or entry["axis_deg"].size() < 2:
			continue
		var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		var on := project(center)
		if absf(on.y) > reach_m:
			continue
		var half := float(entry.get("half_width", ViolationWatch.DEFAULT_HALF_WIDTH))
		var at_m := on.x - half - STOP_LINE_MARGIN_M
		if at_m < 0.0:
			continue
		var heading := TrafficSignal.bearing_of(direction_at(on.x))
		stops.append({"at_m": at_m,
			"offset": TrafficSignal.offset_for(center.x, center.z),
			"axis": TrafficSignal.axis_for(heading, entry["axis_deg"]),
			"signal": index})
	stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at_m"] < b["at_m"])

func next_stop(front_m: float) -> Dictionary:
	"""앞 범퍼 누적 거리에서 아직 안 지난 첫 정지선. 없으면 빈 사전."""
	for line in stops:
		if line["at_m"] > front_m - STOP_PASSED_M:
			return line
	return {}
