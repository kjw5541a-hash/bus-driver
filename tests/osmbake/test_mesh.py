"""도로 폭 추정과 도로 리본 메쉬."""
import unittest

from tools.osmbake.geo import Projector
from tools.osmbake.mesh import MeshBuilder, build_roads, road_width


class TestRoadWidth(unittest.TestCase):
    def test_lanes_태그가_있으면_차선수로_계산(self):
        self.assertAlmostEqual(road_width({"highway": "primary", "lanes": "4"}), 12.8)

    def test_lanes_가_이상하면_등급으로_떨어진다(self):
        self.assertEqual(road_width({"highway": "primary", "lanes": "네개"}), 16.0)

    def test_등급별_기본값(self):
        self.assertEqual(road_width({"highway": "secondary"}), 12.0)
        self.assertEqual(road_width({"highway": "busway"}), 7.0)
        self.assertEqual(road_width({"highway": "service"}), 4.5)

    def test_link_는_7m(self):
        self.assertEqual(road_width({"highway": "primary_link"}), 7.0)

    def test_모르는_등급은_7m(self):
        self.assertEqual(road_width({"highway": "뭔가이상한값"}), 7.0)

    def test_차선이_아주_적어도_최소_4m(self):
        self.assertGreaterEqual(road_width({"highway": "service", "lanes": "1"}), 4.0)


class TestMeshBuilder(unittest.TestCase):
    def test_사각형은_삼각형_둘(self):
        builder = MeshBuilder()
        builder.add_polygon([(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)], (0, 1, 0))
        self.assertEqual(builder.triangle_count(), 2)
        self.assertEqual(len(builder.positions), 4)
        self.assertEqual(len(builder.normals), 4)
        self.assertEqual(builder.normals[0], (0, 1, 0))

    def test_점이_셋_미만이면_무시(self):
        builder = MeshBuilder()
        builder.add_polygon([(0, 0, 0), (1, 0, 0)], (0, 1, 0))
        self.assertEqual(builder.triangle_count(), 0)


class TestBuildRoads(unittest.TestCase):
    def setUp(self):
        self.projector = Projector(37.500, 127.000)

    def _way(self, coords, **tags):
        tags.setdefault("highway", "primary")
        return {"type": "way", "id": 1, "nodes": list(range(len(coords))),
                "geometry": [{"lat": lat, "lon": lon} for lat, lon in coords],
                "tags": tags}

    def test_한_구간은_사각형_하나(self):
        builder = build_roads(
            [self._way([(37.500, 127.000), (37.500, 127.001)])], self.projector)
        self.assertEqual(builder.triangle_count(), 2)

    def test_꺾이는_점마다_패치를_덧댄다(self):
        # 구간 2개(사각형 2개 = 삼각형 4개) + 가운데 패치 1개(삼각형 2개)
        builder = build_roads(
            [self._way([(37.500, 127.000), (37.500, 127.001), (37.501, 127.001)])],
            self.projector)
        self.assertEqual(builder.triangle_count(), 6)

    def test_도로_메쉬는_전부_y_0_근처(self):
        builder = build_roads(
            [self._way([(37.500, 127.000), (37.500, 127.001)])], self.projector)
        for _x, y, _z in builder.positions:
            self.assertLessEqual(abs(y), 0.02)

    def test_법선은_위를_향한다(self):
        builder = build_roads(
            [self._way([(37.500, 127.000), (37.500, 127.001)])], self.projector)
        for normal in builder.normals:
            self.assertEqual(normal, (0.0, 1.0, 0.0))

    def test_길이가_0인_구간은_건너뛴다(self):
        builder = build_roads(
            [self._way([(37.500, 127.000), (37.500, 127.000)])], self.projector)
        self.assertEqual(builder.triangle_count(), 0)


if __name__ == "__main__":
    unittest.main()
