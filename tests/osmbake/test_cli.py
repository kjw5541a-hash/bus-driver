"""베이크 CLI: 캐시만으로 전 과정이 도는지."""
import json
import tempfile
import unittest
from pathlib import Path

from tools.osmbake import cli
from tools.osmbake.graph import build_graph


def way(way_id, node_ids, coords, **tags):
    tags.setdefault("highway", "primary")
    return {"type": "way", "id": way_id, "nodes": list(node_ids),
            "geometry": [{"lat": lat, "lon": lon} for lat, lon in coords],
            "tags": tags}


def stop(node_id, lat, lon, name):
    return {"type": "node", "id": node_id, "lat": lat, "lon": lon,
            "tags": {"highway": "bus_stop", "name": name}}


class TestFindTerminalNode(unittest.TestCase):
    def test_이름이_같은_정류장에서_가장_가까운_도로_노드(self):
        graph = build_graph([way(1, [10, 11],
                                 [(37.500, 127.000), (37.500, 127.002)])])
        nodes = [stop(99, 37.50002, 127.00001, "기점")]
        self.assertEqual(cli.find_terminal_node(graph, nodes, "기점"), 10)

    def test_나가는_엣지가_없는_노드는_고르지_않는다(self):
        # 정류장에 더 가깝더라도 엣지가 없는 노드를 고르면 A* 가 무조건
        # 실패한다. 일방통행 끝점 11 이 정류장에 더 가깝지만 10 을 골라야 한다.
        graph = build_graph([way(1, [10, 11],
                                 [(37.500, 127.000), (37.500, 127.002)],
                                 oneway="yes")])
        nodes = [stop(99, 37.500, 127.00199, "종점")]
        self.assertEqual(cli.find_terminal_node(graph, nodes, "종점"), 10)

    def test_노선_멤버_도로를_골목보다_먼저_고른다(self):
        # 654번은 기점 정류장 옆 골목 노드를 잡아 490 m 를 주택가로 돌았다.
        # 골목(2)이 정류장에 더 가까워도 노선 멤버 도로(1)의 노드를 골라야 한다.
        graph = build_graph([
            way(1, [10, 11], [(37.500, 127.000), (37.500, 127.002)]),
            way(2, [20, 21], [(37.5003, 127.0010), (37.5006, 127.0010)],
                highway="residential"),
        ])
        nodes = [stop(99, 37.5002, 127.0010, "기점")]
        self.assertEqual(cli.find_terminal_node(graph, nodes, "기점"), 20)
        self.assertIn(cli.find_terminal_node(graph, nodes, "기점",
                                             preferred_ways=frozenset({1})),
                      (10, 11))

    def test_같은_이름_정류장_전부를_본다(self):
        # 같은 이름 노드가 여럿이면 어느 것에든 가장 가까운 노드다.
        graph = build_graph([way(1, [10, 11],
                                 [(37.500, 127.000), (37.500, 127.002)])])
        nodes = [stop(98, 37.510, 127.000, "기점"),
                 stop(99, 37.50002, 127.00199, "기점")]
        self.assertEqual(cli.find_terminal_node(graph, nodes, "기점"), 11)

    def test_이름이_없으면_None(self):
        graph = build_graph([way(1, [10, 11],
                                 [(37.500, 127.000), (37.500, 127.002)])])
        self.assertIsNone(cli.find_terminal_node(graph, [], "없는정류장"))


class TestBake(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache_dir = Path(self.tmp.name) / "cache"
        self.out_dir = Path(self.tmp.name) / "out"
        self.cache_dir.mkdir(parents=True)

        route_ways = [
            way(1, [10, 11], [(37.5000, 126.9400), (37.5000, 126.9420)]),
            way(2, [11, 12], [(37.5000, 126.9420), (37.5000, 126.9440)]),
        ]
        (self.cache_dir / "seoul-seodaemun03_relation.json").write_text(
            json.dumps({"elements": route_ways}), encoding="utf-8")

        buildings = [{
            "type": "way", "id": 50, "nodes": [1, 2, 3, 4, 1],
            "geometry": [{"lat": 37.5004, "lon": 126.9402},
                         {"lat": 37.5004, "lon": 126.9404},
                         {"lat": 37.5006, "lon": 126.9404},
                         {"lat": 37.5006, "lon": 126.9402},
                         {"lat": 37.5004, "lon": 126.9402}],
            "tags": {"building": "yes", "building:levels": "5"}}]
        # 경로는 정동쪽으로 간다. 정류장은 진행 방향 우측, 곧 남쪽에
        # 둔다 — 북쪽 정류장은 반대 방향 노선의 것이라 걸러진다.
        stops = [stop(90, 37.49997, 126.94005, "홍은2동주민센터"),
                 stop(91, 37.49997, 126.94300, "중간 정류장"),
                 stop(92, 37.49997, 126.94398, "신촌전철역")]
        (self.cache_dir / "seoul-seodaemun03_corridor.json").write_text(
            json.dumps({"elements": route_ways + buildings + stops}),
            encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def test_산출물_두_개가_생긴다(self):
        cli.bake("seoul-seodaemun03", cache_dir=self.cache_dir,
                 out_dir=self.out_dir, baked_at="2026-09-22")
        self.assertTrue((self.out_dir / "route_seoul-seodaemun03.glb").exists())
        self.assertTrue((self.out_dir / "route_seoul-seodaemun03.json").exists())

    def test_정류장_셋이_순서대로_들어간다(self):
        payload = cli.bake("seoul-seodaemun03", cache_dir=self.cache_dir,
                           out_dir=self.out_dir, baked_at="2026-09-22")
        names = [s["name"] for s in payload["stops"]]
        self.assertEqual(names, ["홍은2동주민센터", "중간 정류장", "신촌전철역"])

    def test_경로가_기점에서_종점까지_이어진다(self):
        payload = cli.bake("seoul-seodaemun03", cache_dir=self.cache_dir,
                           out_dir=self.out_dir, baked_at="2026-09-22")
        self.assertGreaterEqual(len(payload["route"]), 2)
        self.assertLess(payload["route"][0][0], payload["route"][-1][0])

    def test_청크가_하나_이상(self):
        payload = cli.bake("seoul-seodaemun03", cache_dir=self.cache_dir,
                           out_dir=self.out_dir, baked_at="2026-09-22")
        self.assertTrue(payload["chunks"])

    def test_청크_경계상자가_name_min_max를_갖는다(self):
        payload = cli.bake("seoul-seodaemun03", cache_dir=self.cache_dir,
                           out_dir=self.out_dir, baked_at="2026-09-22")
        for chunk in payload["chunks"]:
            self.assertIn("name", chunk)
            self.assertLessEqual(chunk["min"][0], chunk["max"][0])
            self.assertLessEqual(chunk["min"][1], chunk["max"][1])

    def test_모르는_노선_id_는_에러(self):
        with self.assertRaises(KeyError):
            cli.bake("없는노선", cache_dir=self.cache_dir, out_dir=self.out_dir,
                     baked_at="2026-09-22")


if __name__ == "__main__":
    unittest.main()
