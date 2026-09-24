"""OSM 도로 way 들을 주행 그래프로 바꾼다.

way 는 교차점(둘 이상의 way 가 공유하는 노드)에서 쪼갠다. 쪼개지 않으면 A* 가
교차로에서 방향을 바꿀 수 없다.

highway=busway 는 서울 중앙버스전용차선이다. access=no 가 붙어 있지만 버스는
다닐 수 있으므로 반드시 포함한다. 이 등급을 빠뜨리면 서울 노선의 경로가 끊긴다.
"""
from collections import Counter
from dataclasses import dataclass

from .geo import haversine
from .mesh import road_width

DRIVABLE_HIGHWAYS = frozenset({
    "motorway", "trunk", "primary", "secondary", "tertiary",
    "unclassified", "residential", "living_street", "service", "busway",
    "motorway_link", "trunk_link", "primary_link", "secondary_link",
    "tertiary_link",
})


@dataclass(frozen=True)
class Edge:
    start: int
    end: int
    node_ids: tuple[int, ...]
    length_m: float
    highway: str
    way_id: int
    bus_only: bool
    # 차도 폭. 주행선을 우측 차선으로 미는 데 쓴다.
    width: float = road_width({})


class RoadGraph:
    def __init__(self) -> None:
        self.coords: dict[int, tuple[float, float]] = {}
        self.adj: dict[int, list[Edge]] = {}

    def add_edge(self, edge: Edge) -> None:
        self.adj.setdefault(edge.start, []).append(edge)


def _drivable_ways(elements: list[dict]) -> list[dict]:
    return [e for e in elements
            if e.get("type") == "way"
            and e.get("tags", {}).get("highway") in DRIVABLE_HIGHWAYS
            and "geometry" in e and "nodes" in e]


def build_graph(elements: list[dict]) -> RoadGraph:
    ways = _drivable_ways(elements)

    usage: Counter[int] = Counter()
    for w in ways:
        for node_id in set(w["nodes"]):
            usage[node_id] += 1

    graph = RoadGraph()
    for w in ways:
        tags = w["tags"]
        node_ids = w["nodes"]
        points = [(g["lat"], g["lon"]) for g in w["geometry"]]
        for node_id, point in zip(node_ids, points):
            graph.coords[node_id] = point

        oneway = tags.get("oneway", "no")
        forward = oneway != "-1"
        backward = oneway not in ("yes", "true", "1")
        width = road_width(tags)
        bus_only = (tags.get("highway") == "busway"
                    or (tags.get("access") == "no" and tags.get("bus") == "designated"))

        # 교차점 또는 way 끝에서 끊어 조각으로 나눈다
        split_at = [0]
        for index in range(1, len(node_ids) - 1):
            if usage[node_ids[index]] > 1:
                split_at.append(index)
        split_at.append(len(node_ids) - 1)

        for a, b in zip(split_at, split_at[1:]):
            chunk_ids = tuple(node_ids[a:b + 1])
            chunk_pts = points[a:b + 1]
            if len(chunk_ids) < 2:
                continue
            length = sum(haversine(chunk_pts[i], chunk_pts[i + 1])
                         for i in range(len(chunk_pts) - 1))
            if forward:
                graph.add_edge(Edge(chunk_ids[0], chunk_ids[-1], chunk_ids,
                                    length, tags["highway"], w["id"], bus_only,
                                    width))
            if backward:
                graph.add_edge(Edge(chunk_ids[-1], chunk_ids[0], chunk_ids[::-1],
                                    length, tags["highway"], w["id"], bus_only,
                                    width))
    return graph
