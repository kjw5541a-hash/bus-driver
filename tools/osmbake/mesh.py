"""메쉬 생성.

도로 폭은 태그로 얻을 수 없다. 3 km 코리도의 도로 1001 개 중 lanes 태그는 59 개,
width 태그는 1 개뿐이었다. 그래서 등급별 추정 테이블을 쓴다.

고도는 없다. 전부 y=0 평지다.
"""
import math

from .geo import Projector

# 서울 기준 차도폭 추정. primary 는 왕복 6차선(20 m), secondary 는 왕복
# 4~5차선(15 m) 이 흔하다. 처음엔 16/12 였는데 실제보다 좁아 버스가 도로를
# 꽉 채웠다.
ROAD_WIDTHS = {
    "motorway": 20.0, "trunk": 20.0,
    "primary": 20.0, "secondary": 15.0, "tertiary": 10.0,
    "unclassified": 7.0, "residential": 7.0, "busway": 7.0,
    "living_street": 6.0, "service": 4.5,
}
LINK_WIDTH = 7.0
DEFAULT_WIDTH = 7.0
LANE_WIDTH = 3.2
MIN_WIDTH = 4.0
UP = (0.0, 1.0, 0.0)
# 꺾이는 지점 패치를 리본보다 1 cm 올려 같은 평면에서 깜빡이는 것을 막는다
PATCH_Y = 0.01


def road_width(tags: dict) -> float:
    """태그에서 도로 폭을 추정한다.

    lanes 태그가 있으면 차선 수로 계산한다(1 이상일 때만).
    lanes가 파싱할 수 없거나 1 미만이면 highway 등급으로 떨어진다.
    highway가 _link로 끝나면 7m이다.
    알 수 없는 등급은 기본값 7m이다.
    최소 폭은 4m이다.
    """
    highway = tags.get("highway", "")
    lanes = tags.get("lanes")
    if lanes is not None:
        try:
            lanes_int = int(lanes)
            if lanes_int >= 1:
                return max(LANE_WIDTH * lanes_int, MIN_WIDTH)
        except (TypeError, ValueError):
            pass
    if highway.endswith("_link"):
        return LINK_WIDTH
    return ROAD_WIDTHS.get(highway, DEFAULT_WIDTH)


class MeshBuilder:
    """삼각형만 담는 단순한 버퍼. 정점은 폴리곤마다 새로 만든다(공유 없음)."""

    def __init__(self) -> None:
        self.positions: list[tuple[float, float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.indices: list[int] = []

    def add_polygon(self, points, normal) -> None:
        """볼록한(또는 거의 볼록한) 폴리곤을 팬 삼각분할로 넣는다."""
        if len(points) < 3:
            return
        base = len(self.positions)
        for point in points:
            self.positions.append(tuple(point))
            self.normals.append(tuple(normal))
        for offset in range(1, len(points) - 1):
            self.indices += [base, base + offset, base + offset + 1]

    def add_triangles(self, points, triangles, normal) -> None:
        """미리 삼각분할된 폴리곤을 넣는다."""
        base = len(self.positions)
        for point in points:
            self.positions.append(tuple(point))
            self.normals.append(tuple(normal))
        for a, b, c in triangles:
            self.indices += [base + a, base + b, base + c]

    def triangle_count(self) -> int:
        """메쉬의 삼각형 개수를 반환한다."""
        return len(self.indices) // 3


DEFAULT_BUILDING_HEIGHT = 9.0
METERS_PER_LEVEL = 3.2
MIN_BUILDING_HEIGHT = 2.5


def building_height(tags: dict) -> float:
    for key, factor in (("height", 1.0), ("building:levels", METERS_PER_LEVEL)):
        raw = tags.get(key)
        if not raw:
            continue
        try:
            value = float(str(raw).split()[0].replace("m", "").strip())
        except (ValueError, IndexError):
            continue
        return max(value * factor, MIN_BUILDING_HEIGHT)
    return DEFAULT_BUILDING_HEIGHT


def _signed_area(polygon) -> float:
    total = 0.0
    for (x1, z1), (x2, z2) in zip(polygon, polygon[1:] + polygon[:1]):
        total += x1 * z2 - x2 * z1
    return total / 2.0


def _is_convex(a, b, c) -> bool:
    return ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) > 0


def _point_in_triangle(p, a, b, c) -> bool:
    d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
    d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
    d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
    has_negative = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_positive = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_negative and has_positive)


def triangulate(polygon: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    """Ear clipping 삼각분할. 원래 폴리곤 인덱스로 된 삼각형 목록을 낸다.

    스파이크에서 쓴 팬 삼각분할은 오목한 건물 footprint 에서 눈에 띄게 깨졌다.
    """
    if len(polygon) < 3:
        return []
    indices = list(range(len(polygon)))
    if _signed_area(polygon) < 0:
        indices.reverse()

    triangles: list[tuple[int, int, int]] = []
    guard = 0
    while len(indices) > 3 and guard < len(polygon) * len(polygon):
        guard += 1
        for position in range(len(indices)):
            i_prev = indices[position - 1]
            i_curr = indices[position]
            i_next = indices[(position + 1) % len(indices)]
            a, b, c = polygon[i_prev], polygon[i_curr], polygon[i_next]
            if not _is_convex(a, b, c):
                continue
            others = [polygon[i] for i in indices
                      if i not in (i_prev, i_curr, i_next)]
            if any(_point_in_triangle(p, a, b, c) for p in others):
                continue
            triangles.append((i_prev, i_curr, i_next))
            indices.pop(position)
            break
        else:
            break  # 귀를 못 찾으면(자기교차 등) 남은 것은 버린다
    if len(indices) == 3:
        triangles.append(tuple(indices))
    # ear clipping 은 내부적으로 표준 반시계(CCW) 폴리곤을 가정해야 귀를 올바르게
    # 찾는다. 하지만 이 게임의 지붕(위를 향하는 수평면) 앞면 규칙은 반대다:
    # cross(v2-v1, v3-v1).y > 0 이 되려면 (x, z) 평면에서는 시계 방향이어야
    # 한다(build_roads 의 리본과 동일한 규칙, tests/osmbake/test_mesh.py 의
    # facing_y 참고). 그래서 반환 직전에 각 삼각형의 둘째·셋째 인덱스를 바꿔
    # 감는 방향을 뒤집는다.
    return [(a, c, b) for a, b, c in triangles]


def build_buildings(ways: list[dict], projector: Projector) -> MeshBuilder:
    """건물 footprint 를 높이만큼 밀어올린 벽 + ear clipping 지붕."""
    builder = MeshBuilder()
    for w in ways:
        tags = w.get("tags", {})
        if "building" not in tags or "geometry" not in w:
            continue
        ring = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        # 앞 점과 같은 점을 전부 턴다. i=0 이 ring[-1] 과 비교되므로 OSM 이
        # 링을 닫느라 붙인 첫점 중복과 편집 아티팩트로 생긴 내부 중복을 한
        # 번에 처리한다. 중복이 남으면 ear clipping 이 삼각형을 다 못 내고
        # 남은 것을 조용히 버려서 지붕에 구멍이 뚫린다.
        ring = [p for i, p in enumerate(ring) if p != ring[i - 1]]
        if len(ring) < 3:
            continue
        # OSM 은 건물 링 방향을 보장하지 않는다. 벽 루프는 링 순서를 그대로
        # 쓰므로(triangulate() 처럼 내부에서 정규화하지 않는다) 여기서
        # 정규화하지 않으면 실제 데이터의 절반가량이 벽이 안쪽을 향한다.
        # 음수 signed_area 가 바깥을 향하는 방향이다.
        if _signed_area(ring) > 0:
            ring = list(reversed(ring))

        height = building_height(tags)
        for (x1, z1), (x2, z2) in zip(ring, ring[1:] + ring[:1]):
            dx, dz = x2 - x1, z2 - z1
            length = math.hypot(dx, dz)
            if length < 0.01:
                continue
            # 정점 순서가 내는 법선과 같은 쪽이어야 한다. 반대로 주면 벽이
            # 안쪽에서 조명돼 건물이 새까맣게 보인다(도로·지붕은 저장 법선과
            # 정점 순서가 일치하는데 벽만 어긋나 있었다).
            normal = (-dz / length, 0.0, dx / length)
            builder.add_polygon([(x1, 0.0, z1), (x2, 0.0, z2),
                                 (x2, height, z2), (x1, height, z1)], normal)

        roof_triangles = triangulate(ring)
        if roof_triangles:
            builder.add_triangles([(x, height, z) for x, z in ring],
                                  roof_triangles, UP)
    return builder


def build_roads(ways: list[dict], projector: Projector) -> MeshBuilder:
    """도로 중심선을 폭만큼 넓힌 리본 + 꺾이는 지점 패치."""
    builder = MeshBuilder()
    for w in ways:
        tags = w.get("tags", {})
        if "highway" not in tags or "geometry" not in w:
            continue
        points = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        half = road_width(tags) / 2.0

        # 각 구간마다 사각형 리본을 만든다
        for (x1, z1), (x2, z2) in zip(points, points[1:]):
            dx, dz = x2 - x1, z2 - z1
            length = math.hypot(dx, dz)
            if length < 0.01:
                continue
            # 중심선에 수직인 벡터를 계산해서 리본의 넓이를 만든다
            nx, nz = -dz / length * half, dx / length * half
            builder.add_polygon([
                (x1 + nx, 0.0, z1 + nz), (x2 + nx, 0.0, z2 + nz),
                (x2 - nx, 0.0, z2 - nz), (x1 - nx, 0.0, z1 - nz),
            ], UP)

        # 꺾이는 지점(중간 점)에 작은 사각형 패치를 붙여 틈을 없앤다.
        # 점 순서는 리본과 같은 방향(위에서 봤을 때 CCW = glTF front-face)이어야 한다.
        for x, z in points[1:-1]:
            builder.add_polygon([
                (x - half, PATCH_Y, z + half), (x + half, PATCH_Y, z + half),
                (x + half, PATCH_Y, z - half), (x - half, PATCH_Y, z - half),
            ], UP)
    return builder


MARKING_MIN_WIDTH = 9.0   # 이보다 좁으면 왕복 2차선 이하라 도색을 생략한다
MARKING_WIDTH = 0.15
MARKING_Y = 0.02          # 도로 리본과 패치(0.01) 위에 얹는다
DASH_ON = 3.0
DASH_OFF = 5.0
ONEWAY_VALUES = frozenset({"yes", "true", "1", "-1"})


def lane_count(tags: dict) -> int:
    """차선 수. lanes 태그가 없으면 폭에서 되짚는다(최소 2)."""
    lanes = tags.get("lanes")
    if lanes is not None:
        try:
            value = int(lanes)
            if value >= 1:
                return value
        except (TypeError, ValueError):
            pass
    return max(2, round(road_width(tags) / LANE_WIDTH))


def _marking_quad(builder: MeshBuilder, ax, az, bx, bz, nx, nz,
                  offset: float) -> None:
    """(nx, nz) 는 단위 법선. offset 만큼 옆으로 민 얇은 띠 하나."""
    half = MARKING_WIDTH / 2.0
    ox, oz = nx * offset, nz * offset
    builder.add_polygon([
        (ax + ox + nx * half, MARKING_Y, az + oz + nz * half),
        (bx + ox + nx * half, MARKING_Y, bz + oz + nz * half),
        (bx + ox - nx * half, MARKING_Y, bz + oz - nz * half),
        (ax + ox - nx * half, MARKING_Y, az + oz - nz * half),
    ], UP)


def _add_dashes(builder: MeshBuilder, x1, z1, ux, uz, nx, nz,
                length: float, offset: float, phase: float) -> float:
    """구간 위에 점선을 찍고 다음 구간에 넘길 위상을 돌려준다.

    위상을 이어받지 않으면 꺾일 때마다 점선이 처음부터 다시 시작해서 칠한
    구간이 붙어버린다.
    """
    period = DASH_ON + DASH_OFF
    traveled = 0.0
    while traveled < length:
        phase_at = (phase + traveled) % period
        if phase_at < DASH_ON:
            span = min(DASH_ON - phase_at, length - traveled)
            _marking_quad(builder,
                          x1 + ux * traveled, z1 + uz * traveled,
                          x1 + ux * (traveled + span), z1 + uz * (traveled + span),
                          nx, nz, offset)
            traveled += span
        else:
            traveled += period - phase_at
    return (phase + length) % period


def build_markings(ways: list[dict],
                   projector: Projector) -> dict[str, MeshBuilder]:
    """차선 도색. 중앙선(노랑 실선)과 차선 구분선(흰 점선)을 따로 낸다.

    좁은 길에는 칠하지 않는다. 서울 이면도로에는 실제로 도색이 거의 없다.
    """
    center = MeshBuilder()
    lane = MeshBuilder()
    for w in ways:
        tags = w.get("tags", {})
        if "highway" not in tags or "geometry" not in w:
            continue
        width = road_width(tags)
        if width < MARKING_MIN_WIDTH:
            continue
        points = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        oneway = tags.get("oneway") in ONEWAY_VALUES
        lanes = lane_count(tags)
        lane_width = width / lanes
        # 차선 경계는 안쪽 lanes-1 개다. 왕복이면 한가운데 경계는 중앙선이
        # 차지하므로 흰 점선에서 뺀다.
        offsets = [-width / 2.0 + index * lane_width
                   for index in range(1, lanes)]
        if not oneway:
            offsets = [o for o in offsets if abs(o) > 0.5]

        phases = [0.0] * len(offsets)
        for (x1, z1), (x2, z2) in zip(points, points[1:]):
            dx, dz = x2 - x1, z2 - z1
            length = math.hypot(dx, dz)
            if length < 0.01:
                continue
            ux, uz = dx / length, dz / length
            nx, nz = -uz, ux
            if not oneway:
                _marking_quad(center, x1, z1, x2, z2, nx, nz, 0.0)
            for index, offset in enumerate(offsets):
                phases[index] = _add_dashes(lane, x1, z1, ux, uz, nx, nz,
                                            length, offset, phases[index])
    return {"marking_center": center, "marking_lane": lane}


SIDEWALK_MIN_ROAD_WIDTH = 6.0   # service(4.5 m) 같은 골목에는 인도가 없다
SIDEWALK_WIDTH = 2.0
CURB_HEIGHT = 0.15
CURB_SLOPE_M = 0.25   # 연석 경사면의 수평 폭
INTERSECTION_CLEAR_M = 3.0      # 교차점에서 이만큼 더 비운다
MIN_SIDEWALK_SPAN = 0.5


def _allowed_spans(start: float, length: float, cuts: list[float],
                   clear: float) -> list[tuple[float, float]]:
    """구간 [0, length] 에서 교차점 반경을 뺀 구간들. start 는 way 누적 거리."""
    spans = [(0.0, length)]
    for cut in cuts:
        low, high = cut - clear - start, cut + clear - start
        remaining: list[tuple[float, float]] = []
        for a, b in spans:
            if high <= a or low >= b:
                remaining.append((a, b))
                continue
            if low > a:
                remaining.append((a, min(low, b)))
            if high < b:
                remaining.append((max(high, a), b))
        spans = remaining
    return [(a, b) for a, b in spans if b - a > MIN_SIDEWALK_SPAN]


def _sidewalk_side(builder: MeshBuilder, ax, az, bx, bz, nx, nz,
                   half: float, side: int) -> None:
    """한쪽 인도. side 는 +1(법선 쪽) 또는 -1.

    연석은 수직면이 아니라 폭 0.25 m 경사면이다. 수직으로 세웠더니 실측
    0.15 m 턱이 VehicleBody3D 의 레이캐스트 바퀴에 그냥 벽이 됐다 —
    자율주행 검증이 153 m 에서 67 m 로 떨어졌다. 경사면은 올라탈 수는 있고
    대신 덜컹인다.

    윗면·경사면 모두 감는 방향이 저장 법선과 맞아야 한다. 틀리면 면이
    뒤에서 조명돼 새까맣게 나온다.
    """
    edge = half * side                                   # 차도 끝, y=0
    lip = (half + CURB_SLOPE_M) * side                   # 연석 위, y=CURB_HEIGHT
    outer = (half + CURB_SLOPE_M + SIDEWALK_WIDTH) * side

    if side > 0:
        top_first, top_second = outer, lip
        slope_points_forward = False
    else:
        top_first, top_second = lip, outer
        slope_points_forward = True
    builder.add_polygon([
        (ax + nx * top_first, CURB_HEIGHT, az + nz * top_first),
        (bx + nx * top_first, CURB_HEIGHT, bz + nz * top_first),
        (bx + nx * top_second, CURB_HEIGHT, bz + nz * top_second),
        (ax + nx * top_second, CURB_HEIGHT, az + nz * top_second),
    ], UP)

    # 경사면 법선은 위와 도로 쪽을 함께 본다.
    run = math.hypot(CURB_SLOPE_M, CURB_HEIGHT)
    normal = (-nx * side * CURB_HEIGHT / run, CURB_SLOPE_M / run,
              -nz * side * CURB_HEIGHT / run)
    low_a = (ax + nx * edge, 0.0, az + nz * edge)
    low_b = (bx + nx * edge, 0.0, bz + nz * edge)
    high_a = (ax + nx * lip, CURB_HEIGHT, az + nz * lip)
    high_b = (bx + nx * lip, CURB_HEIGHT, bz + nz * lip)
    if slope_points_forward:
        builder.add_polygon([low_a, low_b, high_b, high_a], normal)
    else:
        builder.add_polygon([low_b, low_a, high_a, high_b], normal)


SIDEWALK_SAMPLE_M = 2.0
_ROAD_CELL_M = 32.0


def _road_index(ways: list[dict], projector: Projector) -> dict:
    """도로 구간을 격자에 담는다. 키는 셀 좌표, 값은 (x1, z1, x2, z2, half)."""
    index: dict[tuple[int, int], list] = {}
    for w in ways:
        tags = w.get("tags", {})
        if "highway" not in tags or "geometry" not in w:
            continue
        half = road_width(tags) / 2.0
        points = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        for (x1, z1), (x2, z2) in zip(points, points[1:]):
            if math.hypot(x2 - x1, z2 - z1) < 0.01:
                continue
            segment = (x1, z1, x2, z2, half)
            cx1, cx2 = sorted((x1, x2))
            cz1, cz2 = sorted((z1, z2))
            for cx in range(math.floor(cx1 / _ROAD_CELL_M),
                            math.floor(cx2 / _ROAD_CELL_M) + 1):
                for cz in range(math.floor(cz1 / _ROAD_CELL_M),
                                math.floor(cz2 / _ROAD_CELL_M) + 1):
                    index.setdefault((cx, cz), []).append(segment)
    return index


def _on_roadway(index: dict, x: float, z: float) -> bool:
    """이 점이 어떤 도로 리본 안에 있나.

    인도 중심선은 자기 도로 반폭보다 바깥이라 자기 자신에는 안 걸린다.
    """
    cx, cz = math.floor(x / _ROAD_CELL_M), math.floor(z / _ROAD_CELL_M)
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            for x1, z1, x2, z2, half in index.get((cx + dx, cz + dz), ()):
                sx, sz = x2 - x1, z2 - z1
                length_squared = sx * sx + sz * sz
                t = ((x - x1) * sx + (z - z1) * sz) / length_squared
                t = min(1.0, max(0.0, t))
                if math.hypot(x - (x1 + sx * t), z - (z1 + sz * t)) < half:
                    return True
    return False


def _clear_runs(index: dict, x1, z1, ux, uz, nx, nz, offset: float,
                span_start: float, span_end: float) -> list[tuple[float, float]]:
    """구간을 훑어 다른 도로 위가 아닌 토막들만 낸다.

    평행한 이면도로나 측도 옆에서는 인도가 이웃 차도를 덮는다. 덮으면 거기에
    연석 턱이 생겨 멀쩡한 도로가 막힌다 — seoul-seodaemun03 의 자율주행이
    평행한 secondary 네 개가 몰린 지점에서 실제로 걸렸다.
    """
    runs: list[tuple[float, float]] = []
    open_at: float | None = None
    distance = span_start
    while True:
        distance = min(distance, span_end)
        px = x1 + ux * distance + nx * offset
        pz = z1 + uz * distance + nz * offset
        if _on_roadway(index, px, pz):
            if open_at is not None and distance - open_at > MIN_SIDEWALK_SPAN:
                runs.append((open_at, distance))
            open_at = None
        elif open_at is None:
            open_at = distance
        if distance >= span_end:
            break
        distance += SIDEWALK_SAMPLE_M
    if open_at is not None and span_end - open_at > MIN_SIDEWALK_SPAN:
        runs.append((open_at, span_end))
    return runs


def build_sidewalks(ways: list[dict], projector: Projector) -> MeshBuilder:
    """도로 양옆 인도와 연석.

    교차점 둘레는 비운다. 안 비우면 직교하는 도로를 인도가 가로질러 교차로마다
    0.15 m 턱이 생기고 버스가 덜컹인다. 교차점은 둘 이상의 way 가 공유하는
    노드다 — graph.py 와 같은 판정이다. 공유 노드가 없는 교차(고가·지하차도)는
    실제로도 안 만나므로 자르지 않는 것이 맞다.
    """
    usage: dict[int, int] = {}
    for w in ways:
        for node_id in set(w.get("nodes", [])):
            usage[node_id] = usage.get(node_id, 0) + 1

    roadway = _road_index(ways, projector)
    builder = MeshBuilder()
    for w in ways:
        tags = w.get("tags", {})
        if "highway" not in tags or "geometry" not in w:
            continue
        width = road_width(tags)
        if width < SIDEWALK_MIN_ROAD_WIDTH:
            continue
        points = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        node_ids = w.get("nodes", [])
        half = width / 2.0
        clear = half + INTERSECTION_CLEAR_M

        # 교차점을 way 시작점부터의 누적 거리로 옮긴다
        cuts: list[float] = []
        traveled = 0.0
        for index, (x, z) in enumerate(points):
            if index > 0:
                traveled += math.hypot(x - points[index - 1][0],
                                       z - points[index - 1][1])
            if index < len(node_ids) and usage.get(node_ids[index], 0) > 1:
                cuts.append(traveled)

        start = 0.0
        for (x1, z1), (x2, z2) in zip(points, points[1:]):
            dx, dz = x2 - x1, z2 - z1
            length = math.hypot(dx, dz)
            if length < 0.01:
                continue
            ux, uz = dx / length, dz / length
            nx, nz = -uz, ux
            for span_start, span_end in _allowed_spans(start, length, cuts, clear):
                for side in (1, -1):
                    middle = (half + CURB_SLOPE_M + SIDEWALK_WIDTH / 2.0) * side
                    for run_a, run_b in _clear_runs(roadway, x1, z1, ux, uz,
                                                    nx, nz, middle,
                                                    span_start, span_end):
                        _sidewalk_side(builder,
                                       x1 + ux * run_a, z1 + uz * run_a,
                                       x1 + ux * run_b, z1 + uz * run_b,
                                       nx, nz, half, side)
            start += length
    return builder


CHUNK_SIZE_M = 200.0


def split_chunks(builder: MeshBuilder,
                 chunk_size: float = CHUNK_SIZE_M) -> dict[str, MeshBuilder]:
    """삼각형을 격자 칸으로 나눈다. 삼각형은 첫 정점이 속한 칸으로 통째로 간다."""
    chunks: dict[str, MeshBuilder] = {}
    for offset in range(0, len(builder.indices), 3):
        tri = builder.indices[offset:offset + 3]
        x, _y, z = builder.positions[tri[0]]
        key = f"chunk_{math.floor(x / chunk_size)}_{math.floor(z / chunk_size)}"
        chunk = chunks.setdefault(key, MeshBuilder())
        base = len(chunk.positions)
        for index in tri:
            chunk.positions.append(builder.positions[index])
            chunk.normals.append(builder.normals[index])
        chunk.indices += [base, base + 1, base + 2]
    return chunks
