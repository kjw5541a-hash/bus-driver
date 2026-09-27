extends RefCounted
class_name Lanes
# 차선 기하의 순수 함수. bake(tools/osmbake/mesh.py)의 lane_count 와 같은 규칙이다.
# side 는 도로 중심선에서 진행 방향 오른쪽으로 떨어진 거리다.

const LANE_WIDTH_M := 3.2

static func side_of(i: int, n: int, w: float, oneway: bool) -> float:
	"""차선 i 의 중앙. i = 0 이 중앙선(일방통행이면 왼쪽 끝) 쪽이다."""
	if oneway:
		return -w * 0.5 + (i + 0.5) * w / n
	return (i + 0.5) * w / n

static func count_for(n: int, oneway: bool, forward: bool) -> int:
	"""한 방향의 차선 수. 일방통행 도로의 마주 오는 방향은 0 이다."""
	if oneway:
		return n if forward else 0
	return maxi(1, n / 2)

static func even_count(width: float) -> int:
	"""폭에서 되짚은 왕복 차선 수. 가장 가까운 짝수, 최소 2, 딱 중간이면 적은 쪽."""
	return maxi(2, 2 * ceili(width / LANE_WIDTH_M / 2.0 - 0.5))

static func outer_offset(w: float, n: int) -> float:
	"""도로 중심에서 가장 바깥 차선 한가운데까지."""
	return w * 0.5 - w / (2.0 * n)
