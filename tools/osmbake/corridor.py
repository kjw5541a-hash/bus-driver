"""경로 주변만 남기는 코리도 수집, 그리고 신호 후보 합성.

반경 250 m 는 추격 시점에서 양옆 한 블록이 보이는 정도다. 넓힐수록 삼각형 수가
선형으로 늘어난다.
"""
import math

from .geo import METERS_PER_DEG_LAT, Projector
from .graph import RoadGraph
from .routing import _nearest_on_path

MAJOR_HIGHWAYS = frozenset({"motorway", "trunk", "primary", "secondary",
                            "tertiary", "busway"})


def corridor_bbox(path_latlon: list[tuple[float, float]],
                  radius_m: float) -> tuple[float, float, float, float]:
    lats = [lat for lat, _lon in path_latlon]
    lons = [lon for _lat, lon in path_latlon]
    pad_lat = radius_m / METERS_PER_DEG_LAT
    mid_lat = (min(lats) + max(lats)) / 2
    pad_lon = radius_m / (METERS_PER_DEG_LAT * math.cos(math.radians(mid_lat)))
    return (min(lats) - pad_lat, min(lons) - pad_lon,
            max(lats) + pad_lat, max(lons) + pad_lon)


def near_path(elements: list[dict], path_xz: list[tuple[float, float]],
              projector: Projector, radius_m: float) -> list[dict]:
    """기하의 점 하나라도 경로에서 radius_m 안에 있으면 남긴다."""
    kept = []
    for element in elements:
        geometry = element.get("geometry")
        if not geometry:
            continue
        for point in geometry:
            xz = projector.to_xz(point["lat"], point["lon"])
            if _nearest_on_path(path_xz, xz)[0] <= radius_m:
                kept.append(element)
                break
    return kept


def signal_candidates(graph: RoadGraph, osm_signal_nodes: list[dict],
                      projector: Projector, path_xz: list[tuple[float, float]],
                      radius_m: float) -> list[dict]:
    """OSM 신호등 + 주요도로 3갈래 이상 교차점.

    OSM 신호등 태그는 서울에서 거의 비어 있다(밀집 도심 3 km 에 6개). 태그만으로는
    신호 시스템을 세울 수 없어서 교차점을 후보로 같이 낸다.
    """
    signals = []
    for node in osm_signal_nodes:
        xz = projector.to_xz(node["lat"], node["lon"])
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        signals.append({"x": round(xz[0], 2), "z": round(xz[1], 2),
                        "source": "osm", "roads": 0})

    # adj 는 나가는 엣지만 담는다. 일방통행으로 들어오기만 하는 도로도 교차로의
    # 한 갈래이므로 양쪽 끝 모두에 엣지를 달아 인접 인덱스를 만든다.
    incident: dict[int, list] = {}
    for edges in graph.adj.values():
        for edge in edges:
            incident.setdefault(edge.start, []).append(edge)
            incident.setdefault(edge.end, []).append(edge)

    taken = {(s["x"], s["z"]) for s in signals}
    for node_id, edges in incident.items():
        # "주요도로 3개 이상"은 서로 다른 way_id 가 아니라 갈래 수로 센다.
        # 간선 둘이 십자로 만나는 전형적 신호 교차로는 way_id 가 2개뿐이다.
        major_branches = {edge.end if edge.start == node_id else edge.start
                          for edge in edges if edge.highway in MAJOR_HIGHWAYS}
        if len(major_branches) < 3:
            continue
        branches = {edge.end if edge.start == node_id else edge.start
                    for edge in edges}
        lat, lon = graph.coords[node_id]
        xz = projector.to_xz(lat, lon)
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        key = (round(xz[0], 2), round(xz[1], 2))
        if key in taken:
            continue
        taken.add(key)
        signals.append({"x": key[0], "z": key[1],
                        "source": "synthesized", "roads": len(branches)})
    return signals
