"""노선 경로 탐색.

한국 OSM 의 버스 노선 relation 은 멤버 순서를 믿을 수 없고 양방향이 섞여 있다.
그래서 멤버 순서로 경로를 잇지 않고, 멤버 도로에 낮은 비용을 준 A* 로 경로를
다시 만든다. 멤버가 끊긴 구간은 주변 도로로 우회한다.
"""
import heapq
import math

from .geo import haversine, Projector
from .graph import Edge, RoadGraph


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


def snap_stops(path_xz: list[tuple[float, float]], stop_nodes: list[dict],
               projector: Projector, *, max_dist_m: float = 30.0,
               merge_within_m: float = 50.0) -> list[dict]:
    """정류장 노드를 경로에 스냅한다. 순서는 경로 진행도가 정한다."""
    snapped = []
    for node in stop_nodes:
        point = projector.to_xz(node["lat"], node["lon"])
        distance, progress = _nearest_on_path(path_xz, point)
        if distance > max_dist_m:
            continue
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
        # 빈 이름은 "같은 정류장"이 아니라 "이름을 모른다"는 뜻이라 합치지 않는다.
        same_place = (previous is not None
                      and stop["name"] != ""
                      and previous["name"] == stop["name"]
                      and stop["progress_m"] - cluster_end <= merge_within_m)
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
