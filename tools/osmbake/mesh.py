"""메쉬 생성.

도로 폭은 태그로 얻을 수 없다. 3 km 코리도의 도로 1001 개 중 lanes 태그는 59 개,
width 태그는 1 개뿐이었다. 그래서 등급별 추정 테이블을 쓴다.

고도는 없다. 전부 y=0 평지다.
"""
import math

from .geo import Projector

ROAD_WIDTHS = {
    "motorway": 20.0, "trunk": 20.0,
    "primary": 16.0, "secondary": 12.0, "tertiary": 10.0,
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
            normal = (dz / length, 0.0, -dx / length)
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
