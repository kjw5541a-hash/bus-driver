extends RefCounted
class_name TrafficSignal
# 신호 위상 계산. 노드가 아니고 상태도 없다 — 좌표와 시각만 넣으면 색이 나온다.
#
# 신호 93개를 노드 상태로 들면 매 프레임 93번의 타이머 갱신이 되고, 리플레이나
# 테스트에서 시각을 되돌릴 수 없다. 순수 함수면 둘 다 공짜다.

enum Phase { GREEN, YELLOW, RED }

const GREEN_S := 30.0
const YELLOW_S := 3.0
# 한 주기는 (녹 + 황) x 2 다. 축 1 이 축 0 보다 정확히 반주기 뒤라서, 합이
# CYCLE_S 와 다르면 두 축이 동시에 녹이 되는 순간이 생긴다.
const CYCLE_S := (GREEN_S + YELLOW_S) * 2.0

# 신호는 움직이지 않으므로 격자 색인을 한 번 만들어 쓴다. 64 m 는 감시 반경
# 60 m 보다 조금 커서 3x3 스캔이면 반드시 덮인다.
const CELL_M := 64.0

# 테스트가 시각을 고정하는 통로. 음수면 실제 시계를 쓴다. SignalField 와
# ViolationWatch 가 같은 시계를 봐야 보이는 색과 판정이 어긋나지 않는다.
static var time_override := -1.0

static func now() -> float:
	if time_override >= 0.0:
		return time_override
	return float(Time.get_ticks_msec()) / 1000.0

static func offset_for(x: float, z: float) -> float:
	"""좌표로 정해지는 위상 오프셋. 교차로마다 흩어져 도시가 동시에 안 바뀐다."""
	# 엔진 hash() 대신 직접 섞는다. 버전이 바뀌어도 같은 노선이 같은 신호를
	# 만나야 한다.
	var mixed := (roundi(x) * 73856093) ^ (roundi(z) * 19349663)
	return float(absi(mixed) % int(CYCLE_S * 100.0)) / 100.0

static func phase_at(offset_s: float, axis_index: int, t: float) -> Phase:
	var shift := CYCLE_S * 0.5 if axis_index == 1 else 0.0
	# fposmod 는 음수 시각도 [0, CYCLE_S) 로 감는다. fmod 는 음수를 그대로 둔다.
	var local := fposmod(t + offset_s + shift, CYCLE_S)
	if local < GREEN_S:
		return Phase.GREEN
	if local < GREEN_S + YELLOW_S:
		return Phase.YELLOW
	return Phase.RED

static func axis_delta(a: float, b: float) -> float:
	"""180° 로 접은 두 방위각 사이의 각거리. 0~90."""
	var delta := fposmod(a - b, 180.0)
	return minf(delta, 180.0 - delta)

static func axis_for(heading_deg: float, axis_deg: Array) -> int:
	"""진행 방위에 가까운 축의 인덱스. 역주행해도 같은 축이 나온다."""
	var to_first := axis_delta(heading_deg, float(axis_deg[0]))
	var to_second := axis_delta(heading_deg, float(axis_deg[1]))
	return 0 if to_first <= to_second else 1

static func bearing_of(direction: Vector3) -> float:
	"""월드 방향벡터의 방위각. 북(-Z) 0, 동(+X) 90, 도, [0, 360)."""
	return fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)

static func direction_of(bearing_deg: float) -> Vector3:
	"""방위각을 수평 단위벡터로. bearing_of 의 역이다."""
	var radians := deg_to_rad(bearing_deg)
	return Vector3(sin(radians), 0.0, -cos(radians))

static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL_M), floori(z / CELL_M))

static func cells_near(point: Vector3, radius_m: float) -> Array[Vector2i]:
	var span := ceili(radius_m / CELL_M)
	var base := cell_of(point.x, point.z)
	var cells: Array[Vector2i] = []
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			cells.append(base + Vector2i(dx, dz))
	return cells
