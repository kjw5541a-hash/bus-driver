"""노선 경로 탐색.

한국 OSM 의 버스 노선 relation 은 멤버 순서를 믿을 수 없고 양방향이 섞여 있다.
그래서 멤버 순서로 경로를 잇지 않고, 멤버 도로에 낮은 비용을 준 A* 로 경로를
다시 만든다. 멤버가 끊긴 구간은 주변 도로로 우회한다.
"""
import heapq
import math

from .geo import haversine, Projector
from .graph import Edge, RoadGraph
from .mesh import CURB_SLOPE_M, SIDEWALK_WIDTH


def astar(graph: RoadGraph, start: int, goal: int, *,
          preferred_ways: frozenset[int] = frozenset(),
          detour_penalty: float = 4.0) -> list[Edge]:
    """start 에서 goal 까지 엣지 목록. 도달 불가면 빈 리스트."""
    if start == goal or start not in graph.coords or goal not in graph.coords:
        return []

    goal_point = graph.coords[goal]

    def heuristic(node_id: int) -> float:
        return haversine(graph.coords[node_id], goal_point)

    open_heap = [(heuristic(start), 0.0, start)]
    best_cost = {start: 0.0}
    came_from: dict[int, tuple[int, Edge]] = {}
    closed: set[int] = set()

    while open_heap:
        _priority, cost, node = heapq.heappop(open_heap)
        if node == goal:
            break
        if node in closed:
            continue
        closed.add(node)
        for edge in graph.adj.get(node, []):
            weight = edge.length_m
            if preferred_ways and edge.way_id not in preferred_ways:
                weight *= detour_penalty
            new_cost = cost + weight
            if new_cost < best_cost.get(edge.end, float("inf")):
                best_cost[edge.end] = new_cost
                came_from[edge.end] = (node, edge)
                heapq.heappush(open_heap,
                               (new_cost + heuristic(edge.end), new_cost, edge.end))

    if goal not in came_from:
        return []

    edges: list[Edge] = []
    node = goal
    while node != start:
        node, edge = came_from[node]
        edges.append(edge)
    edges.reverse()
    return edges


def path_latlon(graph: RoadGraph, edges: list[Edge]) -> list[tuple[float, float]]:
    """엣지 목록을 이어붙인 (위도, 경도) 폴리라인."""
    points: list[tuple[float, float]] = []
    for edge in edges:
        node_points = [graph.coords[n] for n in edge.node_ids]
        points += node_points[1:] if points else node_points
    return points


def path_widths(graph: RoadGraph, edges: list[Edge]) -> list[float]:
    """path_latlon 과 같은 길이의 차도 폭 목록."""
    widths: list[float] = []
    for edge in edges:
        count = len(edge.node_ids)
        if widths:
            # 두 도로가 만나는 점은 좁은 쪽을 따른다. 넓은 쪽 폭으로 밀면
            # 좁은 도로로 들어서는 순간 주행선이 도로 밖으로 나간다.
            widths[-1] = min(widths[-1], edge.width)
            count -= 1
        widths += [edge.width] * count
    return widths


def _tangent(path_xz: list[tuple[float, float]], index: int) -> tuple[float, float]:
    """점에서의 진행 방향 단위벡터. 꺾이는 점에서는 앞뒤 구간의 평균이다."""
    parts = []
    for a, b in ((index - 1, index), (index, index + 1)):
        if a < 0 or b >= len(path_xz):
            continue
        dx = path_xz[b][0] - path_xz[a][0]
        dz = path_xz[b][1] - path_xz[a][1]
        length = math.hypot(dx, dz)
        if length > 1e-9:
            parts.append((dx / length, dz / length))
    if not parts:
        return (1.0, 0.0)
    tx = sum(p[0] for p in parts)
    tz = sum(p[1] for p in parts)
    length = math.hypot(tx, tz)
    if length < 1e-9:
        return parts[0]
    return (tx / length, tz / length)


# 이보다 크게 꺾이는 점은 주행선을 차선으로 밀지 않는다.
SHARP_TURN_DEG = 60.0


def offset_right(path_xz: list[tuple[float, float]],
                 offsets: list[float]) -> list[tuple[float, float]]:
    """각 점을 진행 방향 우측으로 offsets[i] 만큼 민다.

    x 가 동쪽, z 가 남쪽이라 진행 방향 (tx, tz) 의 우측은 (-tz, tx) 다.

    꺾이는 점에서 마이터 보정은 하지 않는다. 안쪽 코너에서 오프셋이 조금
    줄지만, 늘어나서 도로 밖으로 나가는 쪽보다 낫다.
    """
    moved = []
    for index, (x, z) in enumerate(path_xz):
        tx, tz = _tangent(path_xz, index)
        distance = offsets[index]
        if max(_turn_deg(path_xz, near)
               for near in (index - 1, index, index + 1)) > SHARP_TURN_DEG:
            # 급커브 꼭짓점과 그 이웃은 중심선에 둔다. 우회전이면 우측 차선이
            # 커브 안쪽이라 반경이 더 줄어 버스가 연석을 넘는다. 꼭짓점만
            # 풀면 이웃 점과 사이에 꺾임이 생긴다. 실제 버스도 이런 데서는
            # 크게 돈다.
            distance = 0.0
        moved.append((x - tz * distance, z + tx * distance))
    return moved


def _turn_deg(path_xz: list[tuple[float, float]], index: int) -> float:
    """점에서 꺾이는 각의 크기(도). 끝점은 0."""
    if index <= 0 or index >= len(path_xz) - 1:
        return 0.0
    (ax, az), (bx, bz), (cx, cz) = path_xz[index - 1:index + 2]
    first = math.atan2(bz - az, bx - ax)
    second = math.atan2(cz - bz, cx - bx)
    turn = (second - first + math.pi) % (2.0 * math.pi) - math.pi
    return abs(math.degrees(turn))


def progress_on_path(path_xz: list[tuple[float, float]],
                     point: tuple[float, float]) -> float:
    """경로 시작점에서 이 점의 수선의 발까지 간 거리."""
    return _nearest_on_path(path_xz, point)[1]


def project_path(path: list[tuple[float, float]],
                 projector: Projector) -> list[tuple[float, float]]:
    """(위도, 경도) 폴리라인을 (x, z) 로 옮긴다."""
    return [projector.to_xz(lat, lon) for lat, lon in path]


def _nearest_on_path(path_xz: list[tuple[float, float]],
                     point: tuple[float, float]) -> tuple[float, float]:
    """(경로까지 거리, 경로 진행도 미터). 각 구간에 수선의 발을 내려 가장 가까운 것."""
    px, pz = point
    best = (float("inf"), 0.0)
    travelled = 0.0
    for (x1, z1), (x2, z2) in zip(path_xz, path_xz[1:]):
        dx, dz = x2 - x1, z2 - z1
        seg_len = math.hypot(dx, dz)
        if seg_len < 1e-9:
            continue
        t = ((px - x1) * dx + (pz - z1) * dz) / (seg_len * seg_len)
        t = max(0.0, min(1.0, t))
        foot_x, foot_z = x1 + t * dx, z1 + t * dz
        distance = math.hypot(px - foot_x, pz - foot_z)
        if distance < best[0]:
            best = (distance, travelled + t * seg_len)
        travelled += seg_len
    return best


def _foot_of(path_xz: list[tuple[float, float]],
             point: tuple[float, float]) -> tuple[int, float, float, float]:
    """(구간 인덱스, 수선의 발 x, 수선의 발 z, 구간 진행도 t)."""
    px, pz = point
    best = (float("inf"), 0, 0.0, 0.0, 0.0)
    for index, ((x1, z1), (x2, z2)) in enumerate(zip(path_xz, path_xz[1:])):
        dx, dz = x2 - x1, z2 - z1
        seg_len = math.hypot(dx, dz)
        if seg_len < 1e-9:
            continue
        t = ((px - x1) * dx + (pz - z1) * dz) / (seg_len * seg_len)
        t = max(0.0, min(1.0, t))
        foot_x, foot_z = x1 + t * dx, z1 + t * dz
        distance = math.hypot(px - foot_x, pz - foot_z)
        if distance < best[0]:
            best = (distance, index, foot_x, foot_z, t)
    return best[1], best[2], best[3], best[4]


def _to_sidewalk(path_xz: list[tuple[float, float]], road_widths: list[float],
                 point: tuple[float, float]) -> tuple[float, float] | None:
    """정류장을 진행 방향 우측 인도 위로 옮긴다. 좌측 정류장은 None.

    OSM bus_stop 노드는 경로 중심선에서 중앙값 6.9 m 떨어져 있는데, 서울
    간선도로 반폭이 7.5~10 m 라 그 자리는 차도 한복판이다. 그대로 두면
    승객이 도로에서 버스를 기다린다.

    좌측 노드는 반대 방향 노선의 정류장이다. 우측통행하는 이 노선에서는
    설 수 없으므로 버린다.
    """
    index, foot_x, foot_z, _t = _foot_of(path_xz, point)
    tx, tz = _tangent(path_xz, index)
    right_x, right_z = -tz, tx
    side = (point[0] - foot_x) * right_x + (point[1] - foot_z) * right_z
    if side <= 0.0:
        return None
    # 구간 양 끝 중 넓은 쪽. 만나는 점은 좁은 쪽 폭을 갖고 있어서, 넓은
    # 도로 위 정류장이 차도 안에 떨어지는 것을 막는다.
    width = max(road_widths[index], road_widths[min(index + 1, len(road_widths) - 1)])
    out = width / 2.0 + CURB_SLOPE_M + SIDEWALK_WIDTH / 2.0
    return (foot_x + right_x * out, foot_z + right_z * out)


def snap_stops(path_xz: list[tuple[float, float]], stop_nodes: list[dict],
               projector: Projector, *, max_dist_m: float = 30.0,
               merge_within_m: float = 50.0,
               same_place_m: float = 20.0,
               road_widths: list[float] | None = None) -> list[dict]:
    """정류장 노드를 경로에 스냅한다. 순서는 경로 진행도가 정한다.

    road_widths 를 주면 진행 방향 우측 정류장만 남기고, 좌표를 차도 밖
    인도 위로 옮긴다.
    """
    snapped = []
    for node in stop_nodes:
        point = projector.to_xz(node["lat"], node["lon"])
        distance, progress = _nearest_on_path(path_xz, point)
        if distance > max_dist_m:
            continue
        if road_widths is not None:
            placed = _to_sidewalk(path_xz, road_widths, point)
            if placed is None:
                continue
            point = placed
        snapped.append({
            "name": node.get("tags", {}).get("name", ""),
            "x": round(point[0], 2),
            "z": round(point[1], 2),
            "progress_m": round(progress, 1),
            "osm_node": node["id"],
            "_distance": distance,
        })

    snapped.sort(key=lambda s: s["progress_m"])

    merged: list[dict] = []
    cluster_end = 0.0  # 현재 클러스터에서 마지막으로 본 진행도
    for stop in snapped:
        previous = merged[-1] if merged else None
        gap = stop["progress_m"] - cluster_end if previous is not None else 0.0
        # 빈 이름은 "같은 정류장"이 아니라 "이름을 모른다"는 뜻이라 합치지 않는다.
        same_name = (stop["name"] != "" and previous is not None
                     and previous["name"] == stop["name"]
                     and gap <= merge_within_m)
        # 이름이 달라도 이만큼 붙어 있으면 같은 자리다. 실데이터에는 승강장
        # 번호나 출구 번호만 다른 정류장이 0.4 m 간격으로 들어 있어서,
        # 이름만 보고 합치면 버스가 한 자리에서 두 번 선다.
        same_place = previous is not None and (same_name or gap <= same_place_m)
        if same_place:
            # 버려지는 쪽도 기준점은 전진시킨다. 같은 이름이 셋 이상 이어질 때
            # 승자 진행도만 보면 체인이 끊겨 한 정류장이 둘로 쪼개진다.
            cluster_end = stop["progress_m"]
            if stop["_distance"] < previous["_distance"]:
                merged[-1] = stop
            continue
        merged.append(stop)
        cluster_end = stop["progress_m"]

    for stop in merged:
        del stop["_distance"]
    return merged
