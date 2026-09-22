"""도로 폭 추정과 도로 리본 메쉬."""
import math
import unittest

from tools.osmbake.geo import METERS_PER_DEG_LAT, Projector
from tools.osmbake.mesh import (MeshBuilder, build_buildings, build_roads,
                                 building_height, road_width, triangulate,
                                 split_chunks)


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

    def test_lanes_0과_음수는_등급_기본값으로_떨어진다(self):
        self.assertEqual(road_width({"highway": "primary", "lanes": "0"}), 16.0)
        self.assertEqual(road_width({"highway": "primary", "lanes": "-1"}), 16.0)


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


def facing_y(builder):
    """삼각형마다 (v2-v1) × (v3-v1) 의 y 성분을 낸다.

    양수면 위에서 봤을 때 반시계 방향 = glTF 의 앞면이 위를 향한다는 뜻이다.
    저장된 normals 배열은 add_polygon 이 받은 값을 그대로 돌려줄 뿐이라
    정점 순서가 뒤집혀도 안 바뀐다. 향면은 정점 순서에서 직접 유도해야 한다.
    """
    for i in range(0, len(builder.indices), 3):
        p1, p2, p3 = (builder.positions[builder.indices[i + k]] for k in range(3))
        v1 = (p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2])
        v2 = (p3[0] - p1[0], p3[1] - p1[1], p3[2] - p1[2])
        yield v1[2] * v2[0] - v1[0] * v2[2]


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

    def test_리본_삼각형이_위를_향한다(self):
        """리본의 모든 삼각형이 위를 향하는지 확인 (cross product y > 0)."""
        builder = build_roads(
            [self._way([(37.500, 127.000), (37.500, 127.001)])], self.projector)

        for index, y in enumerate(facing_y(builder)):
            self.assertGreater(y, 0, f"삼각형 {index} 가 아래를 향한다 (y={y})")

    def test_꺾이는_경로의_패치_삼각형도_위를_향한다(self):
        """꺾이는 점의 패치가 위를 향하는지 확인."""
        builder = build_roads(
            [self._way([(37.500, 127.000), (37.500, 127.001), (37.501, 127.001)])],
            self.projector)

        for index, y in enumerate(facing_y(builder)):
            self.assertGreater(y, 0, f"삼각형 {index} 가 아래를 향한다 (y={y})")

    def test_리본_양쪽_가장자리_간격이_도로_폭과_같다(self):
        """동서 방향 직선에서 리본 너비(z_max - z_min)가 road_width 와 같은지 확인."""
        way = self._way([(37.500, 127.000), (37.500, 127.001)], highway="primary")
        builder = build_roads([way], self.projector)

        z_coords = [pos[2] for pos in builder.positions]
        z_width = max(z_coords) - min(z_coords)
        road_wid = road_width(way["tags"])

        self.assertAlmostEqual(z_width, road_wid, places=5)


class TestBuildingHeight(unittest.TestCase):
    def test_height_태그_우선(self):
        self.assertEqual(building_height({"height": "20"}), 20.0)

    def test_height_에_단위가_붙어도_읽는다(self):
        self.assertEqual(building_height({"height": "20 m"}), 20.0)

    def test_levels_는_층당_3_2m(self):
        self.assertAlmostEqual(building_height({"building:levels": "5"}), 16.0)

    def test_아무것도_없으면_9m(self):
        self.assertEqual(building_height({}), 9.0)

    def test_이상한_값이면_9m(self):
        self.assertEqual(building_height({"height": "높음"}), 9.0)

    def test_너무_낮으면_2_5m_로_올린다(self):
        self.assertEqual(building_height({"height": "0.5"}), 2.5)


class TestTriangulate(unittest.TestCase):
    def test_삼각형은_그대로(self):
        self.assertEqual(len(triangulate([(0, 0), (1, 0), (0, 1)])), 1)

    def test_사각형은_삼각형_둘(self):
        self.assertEqual(len(triangulate([(0, 0), (2, 0), (2, 2), (0, 2)])), 2)

    def test_오목한_L자는_삼각형_넷(self):
        l_shape = [(0, 0), (3, 0), (3, 1), (1, 1), (1, 3), (0, 3)]
        self.assertEqual(len(triangulate(l_shape)), 4)

    def test_시계방향_입력도_처리한다(self):
        clockwise = [(0, 0), (0, 2), (2, 2), (2, 0)]
        self.assertEqual(len(triangulate(clockwise)), 2)

    def test_모든_인덱스가_범위_안(self):
        l_shape = [(0, 0), (3, 0), (3, 1), (1, 1), (1, 3), (0, 3)]
        for triangle in triangulate(l_shape):
            for index in triangle:
                self.assertIn(index, range(len(l_shape)))

    def test_점이_셋_미만이면_빈_결과(self):
        self.assertEqual(triangulate([(0, 0), (1, 1)]), [])


class TestBuildBuildings(unittest.TestCase):
    def setUp(self):
        self.projector = Projector(37.500, 127.000)

    def _building(self, coords, **tags):
        tags.setdefault("building", "yes")
        ring = coords + [coords[0]]
        return {"type": "way", "id": 1, "nodes": list(range(len(ring))),
                "geometry": [{"lat": lat, "lon": lon} for lat, lon in ring],
                "tags": tags}

    def test_사각_건물은_벽_넷과_지붕(self):
        # 벽 4개(삼각형 8개) + 지붕(삼각형 2개)
        builder = build_buildings([self._building([
            (37.5000, 127.0000), (37.5000, 127.0002),
            (37.5002, 127.0002), (37.5002, 127.0000)])], self.projector)
        self.assertEqual(builder.triangle_count(), 10)

    def test_지붕_높이가_건물_높이와_같다(self):
        builder = build_buildings([self._building(
            [(37.5000, 127.0000), (37.5000, 127.0002),
             (37.5002, 127.0002), (37.5002, 127.0000)],
            height="15")], self.projector)
        self.assertAlmostEqual(max(y for _x, y, _z in builder.positions), 15.0)

    def test_바닥은_y_0(self):
        builder = build_buildings([self._building([
            (37.5000, 127.0000), (37.5000, 127.0002),
            (37.5002, 127.0002), (37.5002, 127.0000)])], self.projector)
        self.assertAlmostEqual(min(y for _x, y, _z in builder.positions), 0.0)

    def test_점이_너무_적은_건물은_건너뛴다(self):
        degenerate = {"type": "way", "id": 2, "nodes": [1, 2],
                      "geometry": [{"lat": 37.5, "lon": 127.0},
                                   {"lat": 37.5, "lon": 127.0001}],
                      "tags": {"building": "yes"}}
        builder = build_buildings([degenerate], self.projector)
        self.assertEqual(builder.triangle_count(), 0)

    def test_지붕_삼각형이_위를_향한다(self):
        """ear-clipping 지붕도 도로 리본과 같은 규칙으로 위를 향해야 한다."""
        builder = build_buildings([self._building([
            (37.5000, 127.0000), (37.5000, 127.0002),
            (37.5002, 127.0002), (37.5002, 127.0000)])], self.projector)
        # 마지막 2개 삼각형(지붕)만 확인 - 벽 4개(8삼각형) 다음에 온다
        roof_ys = list(facing_y(builder))[8:]
        self.assertEqual(len(roof_ys), 2)
        for index, y in enumerate(roof_ys):
            self.assertGreater(y, 0, f"지붕 삼각형 {index} 가 아래를 향한다 (y={y})")

    def _wall_facings(self, builder):
        """벽 삼각형마다 (법선 · 중심에서 바깥으로 가는 방향) 내적을 낸다.

        양수면 바깥을 향한다는 뜻이다. 이 중심 기준 판정은 볼록 footprint
        에서만 유효하다 — 오목한 링에서는 오목한 쪽 벽이 거짓 음성을 낸다.
        """
        positions = builder.positions
        cx = sum(p[0] for p in positions) / len(positions)
        cz = sum(p[2] for p in positions) / len(positions)
        for i in range(0, len(builder.indices), 3):
            p1, p2, p3 = (positions[builder.indices[i + k]] for k in range(3))
            if p1[1] == p2[1] == p3[1]:
                continue  # 수평면은 벽이 아니다
            v1 = tuple(p2[k] - p1[k] for k in range(3))
            v2 = tuple(p3[k] - p1[k] for k in range(3))
            nx = v1[1] * v2[2] - v1[2] * v2[1]
            nz = v1[0] * v2[1] - v1[1] * v2[0]
            mx = (p1[0] + p2[0] + p3[0]) / 3 - cx
            mz = (p1[2] + p2[2] + p3[2]) / 3 - cz
            yield nx * mx + nz * mz

    def test_뒤집힌_링으로도_벽이_바깥을_향한다(self):
        """OSM 은 건물 링 방향을 보장하지 않는다. 양쪽 다 바깥을 향해야 한다."""
        square = [(37.5000, 127.0000), (37.5000, 127.0002),
                  (37.5002, 127.0002), (37.5002, 127.0000)]
        for name, coords in (("원래", square), ("뒤집은", list(reversed(square)))):
            builder = build_buildings([self._building(coords)], self.projector)
            facings = list(self._wall_facings(builder))
            self.assertEqual(len(facings), 8)
            for index, dot in enumerate(facings):
                self.assertGreater(dot, 0,
                                   f"{name} 방향 벽 삼각형 {index} 가 안쪽을 향한다")

    def test_오목한_건물도_지붕이_온전하고_위를_향한다(self):
        """오목 footprint 를 build_buildings 끝까지 통과시킨다."""
        l_shape = [(37.5000, 127.0000), (37.5000, 127.0006),
                   (37.50015, 127.0006), (37.50015, 127.0003),
                   (37.5003, 127.0003), (37.5003, 127.0000)]
        builder = build_buildings([self._building(l_shape)], self.projector)
        # 벽 6개(삼각형 12개) + 지붕(정점 6개면 삼각형 4개)
        roof_ys = list(facing_y(builder))[12:]
        self.assertEqual(len(roof_ys), len(l_shape) - 2)
        for index, y in enumerate(roof_ys):
            self.assertGreater(y, 0, f"지붕 삼각형 {index} 가 아래를 향한다 (y={y})")

    def test_연속_중복_정점이_있어도_지붕이_온전하다(self):
        """OSM 편집 아티팩트로 생긴 중복 정점이 지붕에 구멍을 내면 안 된다."""
        square = [(37.5000, 127.0000), (37.5000, 127.0002),
                  (37.5002, 127.0002), (37.5002, 127.0000)]
        dupe = [square[0], square[1], square[1], square[2], square[3]]
        builder = build_buildings([self._building(dupe)], self.projector)
        # 중복을 턴 뒤 정점 4개: 벽 4개(삼각형 8개) + 지붕 삼각형 2개
        self.assertEqual(builder.triangle_count(), 10)
        roof_ys = list(facing_y(builder))[8:]
        self.assertEqual(len(roof_ys), 2)
        for y in roof_ys:
            self.assertGreater(y, 0)


class TestSplitChunks(unittest.TestCase):
    def _builder_with(self, squares):
        builder = MeshBuilder()
        for cx, cz in squares:
            builder.add_polygon([(cx, 0, cz), (cx + 1, 0, cz),
                                 (cx + 1, 0, cz + 1), (cx, 0, cz + 1)], (0, 1, 0))
        return builder

    def test_한_칸에_다_들어가면_청크_하나(self):
        chunks = split_chunks(self._builder_with([(0, 0), (10, 10)]), 200.0)
        self.assertEqual(len(chunks), 1)

    def test_멀리_떨어지면_청크가_나뉜다(self):
        chunks = split_chunks(self._builder_with([(0, 0), (500, 500)]), 200.0)
        self.assertEqual(len(chunks), 2)

    def test_삼각형_총수는_보존된다(self):
        builder = self._builder_with([(0, 0), (500, 500), (1000, 0)])
        chunks = split_chunks(builder, 200.0)
        self.assertEqual(sum(c.triangle_count() for c in chunks.values()),
                         builder.triangle_count())

    def test_청크_이름은_격자_좌표(self):
        chunks = split_chunks(self._builder_with([(0, 0)]), 200.0)
        self.assertEqual(list(chunks), ["chunk_0_0"])

    def test_음수_좌표도_처리한다(self):
        chunks = split_chunks(self._builder_with([(-500, -500)]), 200.0)
        self.assertEqual(list(chunks), ["chunk_-3_-3"])

    def test_빈_메쉬는_빈_결과(self):
        self.assertEqual(split_chunks(MeshBuilder(), 200.0), {})

if __name__ == "__main__":
    unittest.main()
