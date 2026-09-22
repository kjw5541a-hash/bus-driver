"""노선 경로 탐색.

한국 OSM 의 버스 노선 relation 은 멤버 순서를 믿을 수 없고 양방향이 섞여 있다.
그래서 멤버 순서로 경로를 잇지 않고, 멤버 도로에 낮은 비용을 준 A* 로 경로를
다시 만든다. 멤버가 끊긴 구간은 주변 도로로 우회한다.
"""
import heapq

from .geo import haversine
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
