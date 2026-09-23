"""코리도 수집과 신호 후보 합성."""
import unittest

from tools.osmbake.corridor import corridor_bbox, near_path, signal_candidates
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

    def test_주요도로_3갈래_교차점은_합성된다(self):
        elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)]),
            way(3, [50, 12], [(37.500, 127.0010), (37.501, 127.0010)]),
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["source"], "synthesized")
        self.assertEqual(signals[0]["roads"], 3)

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
        ]
        signals = signal_candidates(build_graph(elements), [], self.projector,
                                    self.path, 250.0)
        self.assertEqual(len(signals), 1)
        self.assertEqual(signals[0]["source"], "synthesized")
        self.assertEqual(signals[0]["roads"], 3)

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


if __name__ == "__main__":
    unittest.main()
