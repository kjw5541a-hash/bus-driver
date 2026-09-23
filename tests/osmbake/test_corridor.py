"""코리도 수집과 신호 후보 합성."""
import unittest

from tools.osmbake.corridor import (_has_camera, corridor_bbox, near_path,
                                   signal_candidates)
from tools.osmbake.geo import Projector
from tools.osmbake.graph import build_graph
from tools.osmbake.routing import project_path


def way(way_id, node_ids, coords, **tags):
    tags.setdefault("highway", "primary")
    return {
        "type": "way",
        "id": way_id,
        "nodes": list(node_ids),
        "geometry": [{"lat": lat, "lon": lon} for lat, lon in coords],
        "tags": tags,
    }


class TestCorridorBbox(unittest.TestCase):
    def test_경로를_감싸고_여유를_둔다(self):
        box = corridor_bbox([(37.500, 127.000), (37.510, 127.010)], 250.0)
        min_lat, min_lon, max_lat, max_lon = box
        self.assertLess(min_lat, 37.500)
        self.assertLess(min_lon, 127.000)
        self.assertGreater(max_lat, 37.510)
        self.assertGreater(max_lon, 127.010)


class TestNearPath(unittest.TestCase):
    def setUp(self):
        self.projector = Projector(37.500, 127.000)
        self.path = project_path([(37.500, 127.000), (37.500, 127.002)],
                                 self.projector)

    def test_가까운_것만_남긴다(self):
        near = way(1, [1, 2], [(37.5001, 127.0005), (37.5001, 127.0010)])
        far = way(2, [3, 4], [(37.5200, 127.0005), (37.5200, 127.0010)])
        kept = near_path([near, far], self.path, self.projector, 250.0)
        self.assertEqual([e["id"] for e in kept], [1])

    def test_일부라도_걸치면_남긴다(self):
        crossing = way(1, [1, 2], [(37.5001, 127.0005), (37.5200, 127.0005)])
        kept = near_path([crossing], self.path, self.projector, 250.0)
        self.assertEqual(len(kept), 1)


class TestSignalCandidates(unittest.TestCase):
    def setUp(self):
        self.projector = Projector(37.500, 127.000)
        self.path = project_path([(37.500, 127.000), (37.500, 127.002)],
                                 self.projector)

    def test_osm_신호등은_source_osm(self):
        node = {"type": "node", "id": 9, "lat": 37.5000, "lon": 127.0010,
                "tags": {"highway": "traffic_signals"}}
        signals = signal_candidates(build_graph([]), [node], self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["source"], "osm")

    def test_갈래_3개는_합성되지_않는다(self):
        # T자 교차점. 실제 서울에서도 신호가 없는 경우가 많다.
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
            way(3, [50, 12], [(37.500, 127.0010), (37.501, 127.0010)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(signals, [])

    def test_두_갈래_길은_교차로가_아니다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(signals, [])

    def test_작은_길만_만나는_곳은_합성하지_않는다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)],
                highway="residential"),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)],
                highway="residential"),
            way(3, [50, 12], [(37.500, 127.0010), (37.501, 127.0010)],
                highway="service"),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(signals, [])

    def test_일방통행으로_들어오기만_해도_갈래로_센다(self):
        # 두 갈래는 일방통행으로 교차점을 향하기만 하고(진출 불가), 한 갈래만
        # 양방향이다. adj 는 나가는 엣지만 담으므로, 나가는 엣지만 보면 이
        # 교차점은 1갈래로 보여 탈락한다.
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)],
                oneway="yes"),
            way(2, [11, 50], [(37.500, 127.0020), (37.500, 127.0010)],
                oneway="yes"),
            way(3, [50, 12], [(37.500, 127.0010), (37.501, 127.0010)]),
            way(4, [50, 13], [(37.500, 127.0010), (37.499, 127.0010)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 1)

    def test_십자_교차점은_way_id가_2개뿐이어도_합성된다(self):
        elements = [
            way(1, [10, 50, 11], [(37.500, 127.0000), (37.500, 127.0010),
                                  (37.500, 127.0020)]),
            way(2, [12, 50, 13], [(37.4990, 127.0010), (37.500, 127.0010),
                                  (37.501, 127.0010)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["source"], "synthesized")
        self.assertEqual(signals[0]["roads"], 4)

    def test_주요도로_2갈래에_이면도로_하나는_합성하지_않는다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
            way(3, [50, 12], [(37.500, 127.0010), (37.501, 127.0010)],
                highway="residential"),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(signals, [])


    def test_갈래_4개는_합성된다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
            way(3, [12, 50], [(37.499, 127.0010), (37.500, 127.0010)]),
            way(4, [50, 13], [(37.500, 127.0010), (37.501, 127.0010)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["source"], "synthesized")
        self.assertEqual(signals[0]["roads"], 4)

    def test_십자교차로의_두_축은_거의_수직이다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
            way(3, [12, 50], [(37.499, 127.0010), (37.500, 127.0010)]),
            way(4, [50, 13], [(37.500, 127.0010), (37.501, 127.0010)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        first, second = signals[0]["axis_deg"]
        delta = abs(first - second) % 180.0
        delta = min(delta, 180.0 - delta)
        self.assertGreater(delta, 75.0)
        self.assertLessEqual(delta, 90.0)

    def test_비스듬한_교차로도_두_축으로_갈린다(self):
        # 남북/동서가 아니라 북동-남서 와 북서-남동 으로 만나는 교차로.
        elements = [
            way(1, [10, 50], [(37.4993, 127.0003), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.5007, 127.0017)]),
            way(3, [12, 50], [(37.4993, 127.0017), (37.500, 127.0010)]),
            way(4, [50, 13], [(37.500, 127.0010), (37.5007, 127.0003)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        first, second = signals[0]["axis_deg"]
        delta = abs(first - second) % 180.0
        delta = min(delta, 180.0 - delta)
        self.assertGreater(delta, 60.0)

    def test_반폭은_가장_넓은_갈래의_절반이다(self):
        # secondary 15 m, primary 20 m 가 만나면 반폭은 10 m.
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)],
                highway="secondary"),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)],
                highway="secondary"),
            way(3, [12, 50], [(37.499, 127.0010), (37.500, 127.0010)],
                highway="primary"),
            way(4, [50, 13], [(37.500, 127.0010), (37.501, 127.0010)],
                highway="primary"),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertAlmostEqual(signals[0]["half_width"], 10.0, places=2)

    def test_카메라는_좌표만으로_정해진다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
            way(3, [12, 50], [(37.499, 127.0010), (37.500, 127.0010)]),
            way(4, [50, 13], [(37.500, 127.0010), (37.501, 127.0010)]),
        ]
        graph = build_graph(elements)
        first = signal_candidates(graph, [], self.projector, self.path, 250.0)
        second = signal_candidates(graph, [], self.projector, self.path, 250.0)
        self.assertEqual(first[0]["camera"], second[0]["camera"])
        self.assertIsInstance(first[0]["camera"], bool)

    def test_카메라_비율이_20에서_40퍼센트_사이다(self):
        hits = sum(_has_camera(x * 7.3, x * -3.1) for x in range(500))
        self.assertGreater(hits, 100)   # 20%
        self.assertLess(hits, 200)      # 40%

    def test_osm_신호등도_축과_반폭을_가진다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
        ]
        node = {"type": "node", "id": 9, "lat": 37.5000, "lon": 127.00101,
                "tags": {"highway": "traffic_signals"}}
        signals = signal_candidates(build_graph(elements), [node],
                                    self.projector, self.path, 250.0)
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["source"], "osm")
        self.assertEqual(len(signals[0]["axis_deg"]), 2)
        self.assertGreater(signals[0]["half_width"], 0.0)

    def test_한_교차로의_osm_노드_여럿은_하나로_합쳐진다(self):
        # OSM 은 진입 방향마다 traffic_signals 노드를 따로 찍는다. seoul-100
        # 에서 큰 교차로 하나가 노드 12개로 나와 신호 간격이 161 m 가 됐다.
        nodes = [
            {"type": "node", "id": 9, "lat": 37.50000, "lon": 127.00100,
             "tags": {"highway": "traffic_signals"}},
            {"type": "node", "id": 10, "lat": 37.50010, "lon": 127.00100,
             "tags": {"highway": "traffic_signals"}},
            {"type": "node", "id": 11, "lat": 37.50000, "lon": 127.00113,
             "tags": {"highway": "traffic_signals"}},
        ]
        signals = signal_candidates(build_graph([]), nodes, self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 1)

    def test_멀리_떨어진_신호는_합쳐지지_않는다(self):
        nodes = [
            {"type": "node", "id": 9, "lat": 37.50000, "lon": 127.00000,
             "tags": {"highway": "traffic_signals"}},
            {"type": "node", "id": 10, "lat": 37.50000, "lon": 127.00200,
             "tags": {"highway": "traffic_signals"}},
        ]
        signals = signal_candidates(build_graph([]), nodes, self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 2)

    def test_osm_신호등이_차지한_교차점은_중복_합성되지_않는다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
            way(3, [12, 50], [(37.499, 127.0010), (37.500, 127.0010)]),
            way(4, [50, 13], [(37.500, 127.0010), (37.501, 127.0010)]),
        ]
        node = {"type": "node", "id": 9, "lat": 37.5000, "lon": 127.00100,
                "tags": {"highway": "traffic_signals"}}
        signals = signal_candidates(build_graph(elements), [node],
                                    self.projector, self.path, 250.0)
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["source"], "osm")


if __name__ == "__main__":
    unittest.main()
