"""도로 면과 인도를 면 연산으로 만든다.

way 마다 따로 리본과 인도를 깔던 방식은 교차로에서 틈이 남고, 비스듬한
합류에서 인도가 이웃 차도로 튀어나왔다. 여기서는 모든 차도를 한 면으로
합치고, 인도는 그 면을 빼서 만든다. 그래서 인도는 어떤 차도와도 겹칠 수
없다.
"""

import math

import shapely
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union

from .geo import Projector
from .mesh import (CHUNK_SIZE_M, CURB_HEIGHT, CURB_SLOPE_M, SIDEWALK_MIN_ROAD_WIDTH,
                   SIDEWALK_WIDTH, MeshBuilder, road_width)

CORNER_RADIUS_M = 6.0
SIMPLIFY_M = 0.05   # 원호 정점을 이만큼 솎는다. 삼각형 수가 절반 가까이 준다.


def _way_polygons(ways: list[dict], projector: Projector):
    """(차도 다각형, 인도를 둘 넓은 도로 다각형, 공유 노드 둘레 원) 목록."""
    usage: dict[int, int] = {}
    for w in ways:
        for node_id in set(w.get("nodes", [])):
            usage[node_id] = usage.get(node_id, 0) + 1

    roads, wide = [], []
    node_half: dict[int, tuple[tuple[float, float], float]] = {}
    for w in ways:
        tags = w.get("tags", {})
        if "highway" not in tags or "geometry" not in w:
            continue
        points = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        if len(points) < 2:
            continue
        width = road_width(tags)
        polygon = LineString(points).buffer(width / 2.0, cap_style="flat",
                                            join_style="round")
        roads.append(polygon)
        if width >= SIDEWALK_MIN_ROAD_WIDTH:
            wide.append(polygon)
        for node_id, point in zip(w.get("nodes", []), points):
            if usage.get(node_id, 0) > 1:
                _, half = node_half.get(node_id, (point, 0.0))
                node_half[node_id] = (point, max(half, width / 2.0))
    discs = [Point(point).buffer(half + 2.0 * CORNER_RADIUS_M)
             for point, half in node_half.values()]
    return roads, wide, discs


def road_and_sidewalk(ways: list[dict], projector: Projector):
    """(도로 면, 인도 윗면, 연석 경사면) shapely 다각형."""
    roads, wide, discs = _way_polygons(ways, projector)
    carriageway = unary_union(roads)
    # 닫힘 연산은 오목한 모서리를 반경 R 원호로 메운다. 교차점 둘레만 쓴다 —
    # 전체에 쓰면 12 m 안으로 붙은 평행 도로가 한 덩어리가 된다.
    closed = carriageway.buffer(CORNER_RADIUS_M).buffer(-CORNER_RADIUS_M)
    fillets = closed.intersection(unary_union(discs))
    road = unary_union([carriageway, fillets]).simplify(SIMPLIFY_M)
    # 인도 띠도 메운 모서리를 따라 돈다. 안 그러면 모서리 원호가 띠를 먹는다.
    band = unary_union(wide + [fillets]).buffer(
        CURB_SLOPE_M + SIDEWALK_WIDTH).simplify(SIMPLIFY_M)
    curb_edge = road.buffer(CURB_SLOPE_M).simplify(SIMPLIFY_M)
    top = band.difference(curb_edge)
    slope = band.intersection(curb_edge).difference(road)
    return road, top, slope


def _triangles(geometry, chunk_size: float):
    """청크 칸마다 잘라 삼각분할한 삼각형 좌표 배열 목록."""
    if geometry.is_empty:
        return []
    min_x, min_z, max_x, max_z = geometry.bounds
    out = []
    for cx in range(math.floor(min_x / chunk_size), math.floor(max_x / chunk_size) + 1):
        for cz in range(math.floor(min_z / chunk_size),
                        math.floor(max_z / chunk_size) + 1):
            cell = box(cx * chunk_size, cz * chunk_size,
                       (cx + 1) * chunk_size, (cz + 1) * chunk_size)
            part = geometry.intersection(cell)
            if part.is_empty:
                continue
            triangles = shapely.get_parts(shapely.constrained_delaunay_triangles(part))
            # 삼각형 하나는 닫힌 고리라 좌표가 4 개다.
            out += shapely.get_coordinates(triangles).reshape(-1, 4, 2)[:, :3].tolist()
    return out


def _add(builder: MeshBuilder, corners, heights) -> None:
    """삼각형 하나를 위를 향하게 넣는다. 법선은 면 법선이다."""
    points = [(x, y, z) for (x, z), y in zip(corners, heights)]
    a, b, c = points
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if ny < 0:
        points = [a, c, b]
        nx, ny, nz = -nx, -ny, -nz
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 1e-9:
        return
    builder.add_triangles(points, [(0, 1, 2)], (nx / length, ny / length, nz / length))


def build_surfaces(ways: list[dict], projector: Projector,
                   chunk_size: float = CHUNK_SIZE_M) -> tuple[MeshBuilder, MeshBuilder]:
    """(도로, 인도) 메쉬. 삼각형은 청크 칸을 넘지 않는다."""
    return surface_meshes(*road_and_sidewalk(ways, projector), chunk_size)


def surface_meshes(road, top, slope,
                   chunk_size: float = CHUNK_SIZE_M) -> tuple[MeshBuilder, MeshBuilder]:
    """road_and_sidewalk 결과로 (도로, 인도) 메쉬를 만든다."""
    road_builder = MeshBuilder()
    for corners in _triangles(road, chunk_size):
        _add(road_builder, corners, [0.0] * 3)
    sidewalk = MeshBuilder()
    for corners in _triangles(top, chunk_size):
        _add(sidewalk, corners, [CURB_HEIGHT] * 3)
    # 경사면 정점은 모두 차도 경계(높이 0)나 인도 윗면 경계(0.15) 위에 있다.
    # 차도에 닿는지만 보면 된다. 큰 다각형과의 거리 계산보다 훨씬 빠르다.
    road_edge = road.buffer(0.01)
    shapely.prepare(road_edge)
    for corners in _triangles(slope, chunk_size):
        on_road = shapely.intersects(road_edge, shapely.points(corners))
        _add(sidewalk, corners, [0.0 if hit else CURB_HEIGHT for hit in on_road])
    return road_builder, sidewalk

