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
