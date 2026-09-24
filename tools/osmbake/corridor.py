"""경로 주변만 남기는 코리도 수집, 그리고 신호 후보 합성.

반경 250 m 는 추격 시점에서 양옆 한 블록이 보이는 정도다. 넓힐수록 삼각형 수가
선형으로 늘어난다.
"""
import math
import zlib

from .geo import METERS_PER_DEG_LAT, Projector
from .graph import RoadGraph
from .mesh import (CURB_SLOPE_M, SIDEWALK_WIDTH, _on_roadway, _road_index,
                   road_width)
from .routing import _nearest_on_path

MAJOR_HIGHWAYS = frozenset({"motorway", "trunk", "primary", "secondary",
                            "tertiary", "busway"})

# 주요도로 3갈래(기존)만으로는 T자 골목까지 신호가 되어 24 km 노선에 172 m 마다
# 멈춘다. 전체 갈래 4개 이상을 함께 요구하면 259 m 가 되어 실제 서울 간선도로의
# 300~500 m 에 가까워진다.
MIN_BRANCHES = 4
MIN_MAJOR_BRANCHES = 3

# 서울 신호교차로 수 대비 무인단속장비 수에서 잡은 어림값이다.
CAMERA_RATIO = 0.30

# 그래프 노드를 못 찾은 OSM 신호등이 쓰는 값. secondary 폭 15 m 의 절반.
DEFAULT_AXIS_DEG = (0.0, 90.0)
DEFAULT_HALF_WIDTH = 7.5

# OSM 신호등 노드를 그래프 노드에 붙이는 한계 거리.
SNAP_LIMIT_M = 30.0

# 한 교차로로 묶는 거리. OSM 은 진입 방향마다 traffic_signals 노드를 따로
# 찍어서 큰 교차로 하나가 노드 12개로 나온다. 합치지 않으면 seoul-100 이
# 150개(161 m 간격)가 되어 버스가 계속 선다. 합치면 75개(322 m)다.
MERGE_RADIUS_M = 40.0

# 두 방위각을 같은 축으로 볼지 가르는 각거리.
AXIS_TOLERANCE_DEG = 20.0


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
    # ponytail: 요소 정점 x 경로 구간 선형 스캔. seoul-100 실측 73.6초로
    # 파이프라인 전체 75.1초의 98% 다. 빌드 타임 전용이고 노선당 한 번이라
    # 둔다. 반경을 반복해 튜닝하게 되면 250 m 격자 색인으로 약 3초가 된다.
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


def _bearing_deg(ax: float, az: float, bx: float, bz: float) -> float:
    """(ax, az) 에서 (bx, bz) 로 가는 방위각. 북 0, 동 90, 도, [0, 360).

    월드에서 북은 -z, 동은 +x 다.
    """
    return math.degrees(math.atan2(bx - ax, -(bz - az))) % 360.0


def _axis_delta(a: float, b: float) -> float:
    """180° 로 접은 두 방위각 사이의 각거리. 0~90.

    한 축의 양방향은 180° 차이라 같은 축이므로 접어서 비교한다.
    """
    delta = abs(a - b) % 180.0
    return min(delta, 180.0 - delta)


def _axis_pair(bearings: list[float]) -> tuple[float, float]:
    """갈래 방위각들을 교차로의 두 축으로 묶는다.

    축 0 은 같은 축으로 볼 이웃이 가장 많은 방위(십자 교차로면 마주보는 두
    갈래가 접혀 이웃이 하나 더 생긴다), 축 1 은 축 0 에서 가장 먼 갈래다.
    둘이 거의 같은 축이면 축 1 을 수직으로 채운다.
    """
    if not bearings:
        return DEFAULT_AXIS_DEG
    folded = [b % 180.0 for b in bearings]
    # 두 번째 정렬 키는 동점일 때 결과를 고정하기 위한 것이다. 같은 입력에
    # 항상 같은 축이 나와야 재베이크가 안정적이다.
    first = max(folded, key=lambda b: (
        sum(1 for other in folded if _axis_delta(b, other) <= AXIS_TOLERANCE_DEG),
        -b))
    second = max(folded, key=lambda b: _axis_delta(first, b))
    if _axis_delta(first, second) < AXIS_TOLERANCE_DEG:
        second = (first + 90.0) % 180.0
    return (round(first, 1), round(second, 1))


def _has_camera(x: float, z: float) -> bool:
    """좌표만으로 정해지는 단속 카메라 설치 여부.

    내장 hash() 는 문자열에 대해 프로세스마다 값이 달라서(PYTHONHASHSEED)
    재베이크마다 카메라 위치가 바뀐다. crc32 는 고정이다.
    """
    key = f"{round(x, 1)},{round(z, 1)}".encode()
    return (zlib.crc32(key) % 100) < round(CAMERA_RATIO * 100)


def signal_candidates(graph: RoadGraph, osm_signal_nodes: list[dict],
                      projector: Projector, path_xz: list[tuple[float, float]],
                      radius_m: float) -> list[dict]:
    """OSM 신호등 + 갈래 4개 이상인 주요도로 교차점.

    OSM 신호등 태그는 서울에서 거의 비어 있다(밀집 도심 3 km 에 6개). 태그만으로는
    신호 시스템을 세울 수 없어서 교차점을 후보로 같이 낸다.

    항목마다 두 축의 방위각(axis_deg), 가장 넓은 갈래의 반폭(half_width),
    단속 카메라 설치 여부(camera)를 함께 낸다. 런타임이 버스가 어느 축에
    있는지 판정하고 정지선을 놓는 데 쓴다.
    """
    # adj 는 나가는 엣지만 담는다. 일방통행으로 들어오기만 하는 도로도 교차로의
    # 한 갈래이므로 양쪽 끝 모두에 엣지를 달아 인접 인덱스를 만든다.
    incident: dict[int, list] = {}
    for edges in graph.adj.values():
        for edge in edges:
            incident.setdefault(edge.start, []).append(edge)
            incident.setdefault(edge.end, []).append(edge)

    node_xz = {node_id: projector.to_xz(*graph.coords[node_id])
               for node_id in incident}

    def describe(node_id) -> dict:
        if node_id is None:
            return {"axis_deg": list(DEFAULT_AXIS_DEG),
                    "half_width": DEFAULT_HALF_WIDTH}
        x, z = node_xz[node_id]
        bearings = []
        for edge in incident[node_id]:
            other = edge.end if edge.start == node_id else edge.start
            if other not in node_xz:
                continue
            other_x, other_z = node_xz[other]
            bearings.append(_bearing_deg(x, z, other_x, other_z))
        axis = _axis_pair(bearings)
        half = max(road_width({"highway": edge.highway})
                   for edge in incident[node_id]) / 2.0
        return {"axis_deg": [axis[0], axis[1]], "half_width": round(half, 2)}

    def nearest_graph_node(xz):
        # ponytail: 신호등 노드 x 그래프 노드 선형 스캔. OSM 신호등이 노선당
        # 40개 안쪽이라 충분히 싸다. 늘어나면 격자 색인으로 바꾼다.
        best, best_distance = None, SNAP_LIMIT_M
        for node_id, (node_x, node_z) in node_xz.items():
            distance = math.hypot(node_x - xz[0], node_z - xz[1])
            if distance < best_distance:
                best, best_distance = node_id, distance
        return best

    signals = []
    for node in osm_signal_nodes:
        xz = projector.to_xz(node["lat"], node["lon"])
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        snapped = nearest_graph_node(xz)
        entry = {"x": round(xz[0], 2), "z": round(xz[1], 2),
                 "source": "osm", "roads": 0}
        entry.update(describe(snapped))
        entry["camera"] = _has_camera(entry["x"], entry["z"])
        signals.append(entry)

    taken = {(s["x"], s["z"]) for s in signals}
    for node_id, edges in incident.items():
        # "주요도로 3갈래 이상"은 서로 다른 way_id 가 아니라 갈래 수로 센다.
        # 간선 둘이 십자로 만나는 전형적 신호 교차로는 way_id 가 2개뿐이다.
        major_branches = {edge.end if edge.start == node_id else edge.start
                          for edge in edges if edge.highway in MAJOR_HIGHWAYS}
        if len(major_branches) < MIN_MAJOR_BRANCHES:
            continue
        branches = {edge.end if edge.start == node_id else edge.start
                    for edge in edges}
        if len(branches) < MIN_BRANCHES:
            continue
        xz = node_xz[node_id]
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        key = (round(xz[0], 2), round(xz[1], 2))
        if key in taken:
            continue
        taken.add(key)
        entry = {"x": key[0], "z": key[1],
                 "source": "synthesized", "roads": len(branches)}
        entry.update(describe(node_id))
        entry["camera"] = _has_camera(key[0], key[1])
        signals.append(entry)
    return _merge_nearby(signals)


def _merge_nearby(signals: list[dict]) -> list[dict]:
    """MERGE_RADIUS_M 안의 후보를 하나로 합친다.

    큰 교차로 하나가 OSM 노드 여럿 + 합성 교차점 여럿으로 나오는 것을 막는다.
    대표는 갈래 수가 가장 많은 항목 — 합성 항목만 축 방위각과 반폭을 도로
    기하에서 제대로 얻기 때문이다. 동점이면 좌표 순으로 고정한다.
    """
    # ponytail: 대표 후보 x 남은 후보 선형 스캔. 노선당 150개 안쪽이라 싸다.
    order = sorted(signals, key=lambda e: (-e["roads"], e["x"], e["z"]))
    kept: list[dict] = []
    for entry in order:
        if any(math.hypot(entry["x"] - k["x"], entry["z"] - k["z"])
               <= MERGE_RADIUS_M for k in kept):
            continue
        kept.append(entry)
    return kept


# 기둥이 정지선 뒤로 물러나는 거리. scripts/signal_field.gd 의
# STOP_LINE_MARGIN_M 과 같아야 한다.
POLE_BACK_M = 2.0
POLE_STEP_M = 1.0
POLE_REACH_M = 25.0
# (바깥으로, 뒤로) 더 미는 거리 후보. 가까운 것부터 본다.
_POLE_SHIFTS = sorted(
    ((out * POLE_STEP_M, back * POLE_STEP_M)
     for out in range(int(POLE_REACH_M / POLE_STEP_M) + 1)
     for back in range(int(POLE_REACH_M / POLE_STEP_M) + 1)),
    key=lambda shift: (math.hypot(*shift), shift))


def place_poles(signals: list[dict], roads: list[dict],
                projector: Projector) -> None:
    """신호마다 진입 방향 4개의 기둥 자리(pole_lateral, pole_back)를 채운다.

    기둥은 교차로 중심에서 반폭 + 인도 절반만큼 우측, 정지선 뒤에 선다.
    그런데 중심은 복선 도로의 한쪽 차도 위 노드라, 반대 차도나 버스전용차로가
    그 자리를 덮으면 기둥이 도로 한가운데 선다. 교차 도로도 복선이면 뒤쪽이
    막힌다. 차도를 벗어나는 가장 가까운 자리를 바깥·뒤쪽에서 찾는다.
    순서는 signal_field.gd 의 build 와 같다 — 축 0 정·역, 축 1 정·역.
    """
    index = _road_index(roads, projector)
    for entry in signals:
        half = entry["half_width"]
        lateral0 = half + CURB_SLOPE_M + SIDEWALK_WIDTH / 2.0
        back0 = half + POLE_BACK_M
        laterals, backs = [], []
        for bearing in entry["axis_deg"]:
            for sign in (1.0, -1.0):
                radians = math.radians(bearing)
                fx, fz = math.sin(radians) * sign, -math.cos(radians) * sign
                # 끝까지 차도면(고가 밑, 광장 등) 원래 자리로 둔다.
                lateral, back = lateral0, back0
                for out, behind in _POLE_SHIFTS:
                    x = entry["x"] - fx * (back0 + behind) - fz * (lateral0 + out)
                    z = entry["z"] - fz * (back0 + behind) + fx * (lateral0 + out)
                    if not _on_roadway(index, x, z):
                        lateral, back = lateral0 + out, back0 + behind
                        break
                laterals.append(round(lateral, 2))
                backs.append(round(back, 2))
        entry["pole_lateral"] = laterals
        entry["pole_back"] = backs
