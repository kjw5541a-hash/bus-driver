"""면 연산으로 만든 도로와 인도."""
import math
import unittest

from shapely.geometry import LineString, Point

from tools.osmbake.geo import METERS_PER_DEG_LAT, Projector
from tools.osmbake.mesh import CURB_HEIGHT, road_width
from tools.osmbake.surface import build_surfaces

PROJECTOR = Projector(37.500, 127.000)
M_PER_LON = METERS_PER_DEG_LAT * math.cos(math.radians(37.500))


def way(way_id, nodes, points, highway="primary"):
    """xz 좌표(m)로 way 를 만든다. x 동쪽, z 남쪽."""
    return {"type": "way", "id": way_id, "nodes": nodes,
            "geometry": [{"lat": 37.500 - z / METERS_PER_DEG_LAT,
                          "lon": 127.000 + x / M_PER_LON} for x, z in points],
            "tags": {"highway": highway}}


def triangles(builder):
    """[(정점 셋)] 목록."""
    return [[builder.positions[i] for i in builder.indices[k:k + 3]]
            for k in range(0, len(builder.indices), 3)]


def covers(builder, x, z):
    """(x, z) 가 어떤 삼각형 안(경계 포함)에 드는가."""
    for a, b, c in triangles(builder):
        d1 = (b[0] - a[0]) * (z - a[2]) - (b[2] - a[2]) * (x - a[0])
        d2 = (c[0] - b[0]) * (z - b[2]) - (c[2] - b[2]) * (x - b[0])
        d3 = (a[0] - c[0]) * (z - c[2]) - (a[2] - c[2]) * (x - c[0])
        if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
            return True
    return False


def cross():
    """(0, 0) 에서 만나는 primary 네 갈래(폭 20 m)."""
    return [way(1, [1, 0], [(-60.0, 0.0), (0.0, 0.0)]),
            way(2, [0, 2], [(0.0, 0.0), (60.0, 0.0)]),
            way(3, [3, 0], [(0.0, -60.0), (0.0, 0.0)]),
            way(4, [0, 4], [(0.0, 0.0), (0.0, 60.0)])]


def oblique_t():
    """남북 primary 에 30° 로 비스듬히 붙는 secondary."""
    angle = math.radians(30.0)
    return [way(1, [1, 0, 2], [(0.0, -80.0), (0.0, 0.0), (0.0, 80.0)]),
            way(2, [0, 3], [(0.0, 0.0),
                            (80.0 * math.sin(angle), 80.0 * math.cos(angle))],
                highway="secondary")]


def crossing_without_node():
    """노드를 공유하지 않고 겹치는 두 도로(고가 아래 같은 경우)."""
    return [way(1, [1, 2], [(-60.0, 0.0), (60.0, 0.0)]),
            way(2, [3, 4], [(0.0, -60.0), (0.0, 60.0)])]


SCENES = {"교차": cross, "비스듬한_T": oblique_t, "노드_없는_교차": crossing_without_node}


class TestSurfaces(unittest.TestCase):
    def test_인도는_어떤_차도에도_올라가지_않는다(self):
        for name, scene in SCENES.items():
            ways = scene()
            _, sidewalk = build_surfaces(ways, PROJECTOR)
            lanes = [LineString([PROJECTOR.to_xz(g["lat"], g["lon"])
                                 for g in w["geometry"]])
                     .buffer(road_width(w["tags"]) / 2.0 - 0.01, cap_style="flat")
                     for w in ways]
            self.assertGreater(sidewalk.triangle_count(), 0, name)
            for tri in triangles(sidewalk):
                centre = Point(sum(p[0] for p in tri) / 3, sum(p[2] for p in tri) / 3)
                for lane in lanes:
                    self.assertFalse(lane.contains(centre), f"{name}: {centre}")

    def test_높이와_위쪽_감기(self):
        for name, scene in SCENES.items():
            road, sidewalk = build_surfaces(scene(), PROJECTOR)
            self.assertEqual({p[1] for p in road.positions}, {0.0}, name)
            self.assertEqual({round(p[1], 4) for p in sidewalk.positions},
                             {0.0, CURB_HEIGHT}, name)
            for builder in (road, sidewalk):
                for a, b, c in triangles(builder):
                    # 위에서 내려다볼 때 반시계(Godot 앞면)면 y 성분이 양수다.
                    cross_y = ((b[2] - a[2]) * (c[0] - a[0])
                               - (b[0] - a[0]) * (c[2] - a[2]))
                    self.assertGreater(cross_y, 0, name)

    def test_교차로_모서리가_메워진다(self):
        road, sidewalk = build_surfaces(cross(), PROJECTOR)
        # 두 차도 모서리는 (10, 10). 메움 원호는 중심 (16, 16) 반경 6 m 라
        # 대각선 위 모서리에서 2.49 m 까지 도로다. (13, 13) 은 원호에서
        # 1.76 m 바깥이라 인도 윗면이다.
        self.assertTrue(covers(road, 9.6, 9.6))
        self.assertTrue(covers(road, 10.0 + 1.0, 10.0 + 1.0))
        self.assertFalse(covers(sidewalk, 10.0 + 1.0, 10.0 + 1.0))
        # 모서리 바깥 원호 뒤에는 인도가 곡선으로 돈다.
        self.assertTrue(covers(sidewalk, 10.0 + 3.0, 10.0 + 3.0))

    def test_일자로_이어진_way_사이_인도가_끊기지_않는다(self):
        ways = [way(1, [1, 0], [(0.0, -60.0), (0.0, 0.0)]),
                way(2, [0, 2], [(0.0, 0.0), (0.0, 60.0)])]
        _, sidewalk = build_surfaces(ways, PROJECTOR)
        self.assertTrue(covers(sidewalk, 11.5, 0.0))
        self.assertTrue(covers(sidewalk, -11.5, 0.0))

    def test_30m_떨어진_평행_도로는_합쳐지지_않는다(self):
        ways = [way(1, [1, 2], [(-60.0, 0.0), (60.0, 0.0)]),
                way(2, [3, 4], [(-60.0, 30.0), (60.0, 30.0)])]
        road, sidewalk = build_surfaces(ways, PROJECTOR)
        self.assertFalse(covers(road, 0.0, 15.0))
        self.assertTrue(covers(sidewalk, 0.0, 11.5))
        self.assertTrue(covers(sidewalk, 0.0, 18.5))

    def test_골목에는_인도가_없다(self):
        ways = [way(1, [1, 2], [(-60.0, 0.0), (60.0, 0.0)], highway="service")]
        road, sidewalk = build_surfaces(ways, PROJECTOR)
        self.assertGreater(road.triangle_count(), 0)
        self.assertEqual(sidewalk.triangle_count(), 0)

    def test_삼각형은_청크_경계를_넘지_않는다(self):
        # 경계 x = 0 을 가로지르는 도로를 50 m 칸으로 나눈다.
        road, sidewalk = build_surfaces(cross(), PROJECTOR, chunk_size=50.0)
        for builder in (road, sidewalk):
            for tri in triangles(builder):
                cells = {(math.floor(sum(p[0] for p in tri) / 3 / 50.0),
                          math.floor(sum(p[2] for p in tri) / 3 / 50.0))}
                for p in tri:
                    cx, cz = next(iter(cells))
                    self.assertTrue(cx * 50.0 - 1e-6 <= p[0] <= (cx + 1) * 50.0 + 1e-6)
                    self.assertTrue(cz * 50.0 - 1e-6 <= p[2] <= (cz + 1) * 50.0 + 1e-6)


if __name__ == "__main__":
    unittest.main()
