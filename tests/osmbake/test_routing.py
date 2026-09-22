"""A* 경로 탐색: 최단 경로, 노선 멤버 우선, 우회."""
import unittest

from tools.osmbake.geo import Projector
from tools.osmbake.graph import build_graph
from tools.osmbake.routing import astar, path_latlon, project_path, snap_stops


def way(way_id, node_ids, coords, **tags):
    tags.setdefault("highway", "residential")
    return {
        "type": "way",
        "id": way_id,
        "nodes": list(node_ids),
        "geometry": [{"lat": lat, "lon": lon} for lat, lon in coords],
        "tags": tags,
    }


class TestAstar(unittest.TestCase):
    def setUp(self):
        # 10 --1-- 11 --2-- 12   (직선, 짧음)
        #  \-------3-------/     (멀리 돌아가는 길)
        self.elements = [
            way(1, [10, 11], [(37.500, 127.000), (37.500, 127.001)]),
            way(2, [11, 12], [(37.500, 127.001), (37.500, 127.002)]),
            way(3, [10, 90, 12],
                [(37.500, 127.000), (37.510, 127.001), (37.500, 127.002)]),
        ]
        self.graph = build_graph(self.elements)

    def test_최단_경로를_찾는다(self):
        edges = astar(self.graph, 10, 12)
        self.assertEqual([e.way_id for e in edges], [1, 2])

    def test_도달_불가면_빈_리스트(self):
        self.assertEqual(astar(self.graph, 10, 99999), [])

    def test_출발과_도착이_같으면_빈_리스트(self):
        self.assertEqual(astar(self.graph, 10, 10), [])

    def test_노선_멤버_도로를_우선한다(self):
        # 먼 길(way 3)만 노선 멤버면, 벌점 때문에 그쪽을 택해야 한다.
        edges = astar(self.graph, 10, 12, preferred_ways=frozenset({3}),
                      detour_penalty=50.0)
        self.assertEqual([e.way_id for e in edges], [3])

    def test_멤버가_끊긴_구간은_우회를_허용한다(self):
        # way 1 만 멤버고 11->12 구간은 멤버가 없다. 그래도 12 까지 도달해야 한다.
        edges = astar(self.graph, 10, 12, preferred_ways=frozenset({1}))
        self.assertTrue(edges)
        self.assertEqual(edges[0].way_id, 1)
        self.assertEqual(edges[-1].end, 12)


class TestPathLatLon(unittest.TestCase):
    def test_엣지들을_이어_좌표_목록으로(self):
        graph = build_graph([
            way(1, [10, 11], [(37.500, 127.000), (37.500, 127.001)]),
            way(2, [11, 12], [(37.500, 127.001), (37.500, 127.002)]),
        ])
        edges = astar(graph, 10, 12)
        points = path_latlon(graph, edges)
        self.assertEqual(points[0], (37.500, 127.000))
        self.assertEqual(points[-1], (37.500, 127.002))
        self.assertEqual(len(points), 3)  # 이어지는 점은 중복되지 않는다


def stop_node(node_id, lat, lon, name):
    return {"type": "node", "id": node_id, "lat": lat, "lon": lon,
            "tags": {"highway": "bus_stop", "name": name}}


class TestSnapStops(unittest.TestCase):
    def setUp(self):
        self.projector = Projector(37.500, 127.000)
        # 정동쪽으로 뻗은 직선 경로
        self.path = project_path(
            [(37.500, 127.000), (37.500, 127.001), (37.500, 127.002)],
            self.projector)

    def test_경로_근처_정류장을_잡는다(self):
        stops = snap_stops(self.path,
                           [stop_node(1, 37.50005, 127.0005, "가나 정류장")],
                           self.projector)
        self.assertEqual(len(stops), 1)
        self.assertEqual(stops[0]["name"], "가나 정류장")
        self.assertEqual(stops[0]["osm_node"], 1)

    def test_먼_정류장은_버린다(self):
        stops = snap_stops(self.path,
                           [stop_node(1, 37.510, 127.0005, "먼 정류장")],
                           self.projector)
        self.assertEqual(stops, [])

    def test_진행도_순으로_정렬한다(self):
        nodes = [
            stop_node(2, 37.50005, 127.0015, "두번째"),
            stop_node(1, 37.50005, 127.0005, "첫번째"),
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual([s["name"] for s in stops], ["첫번째", "두번째"])
        self.assertLess(stops[0]["progress_m"], stops[1]["progress_m"])

    def test_양방향_같은_이름은_합친다(self):
        # 경로 양옆에 같은 이름 정류장이 있으면 한 정류장으로 본다.
        nodes = [
            stop_node(1, 37.50010, 127.0005, "양방향 정류장"),
            stop_node(2, 37.49990, 127.0005, "양방향 정류장"),
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual(len(stops), 1)

    def test_이름이_달라도_같은_자리면_합친다(self):
        # 실데이터의 "방화역3번출구"/"방화역2번출구" 처럼 승강장·출구 번호만
        # 다른 정류장이 0.4 m 간격으로 들어 있다. 한 자리에서 두 번 서면 안 된다.
        nodes = [
            stop_node(1, 37.50010, 127.0005, "가"),
            stop_node(2, 37.49990, 127.0005, "나"),
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual(len(stops), 1)

    def test_이름이_다르고_same_place_m_보다_멀면_합치지_않는다(self):
        nodes = [
            stop_node(1, 37.50005, 127.0000, "가"),
            stop_node(2, 37.50005, 127.0005, "나"),   # 진행도 약 44m
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual([s["name"] for s in stops], ["가", "나"])

    def test_이름_없는_정류장도_잡되_이름은_빈_문자열(self):
        node = {"type": "node", "id": 7, "lat": 37.50005, "lon": 127.0005,
                "tags": {"highway": "bus_stop"}}
        stops = snap_stops(self.path, [node], self.projector)
        self.assertEqual(stops[0]["name"], "")

    def test_빈_이름_정류장둘은_합치지_않는다(self):
        # 빈 이름은 "같은 정류장"이 아니라 "이름을 모른다"는 뜻
        nodes = [
            {"type": "node", "id": 1, "lat": 37.50005, "lon": 127.0005,
             "tags": {"highway": "bus_stop"}},
            {"type": "node", "id": 2, "lat": 37.50010, "lon": 127.0010,
             "tags": {"highway": "bus_stop"}},
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual(len(stops), 2)
        self.assertEqual(stops[0]["osm_node"], 1)
        self.assertEqual(stops[1]["osm_node"], 2)

    def test_같은_이름_셋이상_연달아_있으면_하나로_합친다(self):
        # 진행도 0/35/70, 경로까지 거리는 가까움/멂/가까움.
        # 중간 항목이 버려져도 기준점을 전진시켜야 체인이 끊기지 않는다.
        nodes = [
            stop_node(1, 37.50005, 127.0000, "반복 정류장"),  # 진행도 0m, 거리 5.6m
            stop_node(2, 37.50022, 127.0004, "반복 정류장"),  # 진행도 35m, 거리 24m
            stop_node(3, 37.50005, 127.0008, "반복 정류장"),  # 진행도 70m, 거리 5.6m
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual(len(stops), 1)
        # 가장 가까운 첫 항목이 승자로 남는다
        self.assertEqual(stops[0]["osm_node"], 1)

    def test_같은_이름_둘이_merge_within_m보다_멀면_합치지_않는다(self):
        # 노선을 두 번 지나는 정류장 — 같은 이름이지만 진행도가 50m 이상 멀면 별개
        nodes = [
            stop_node(1, 37.50005, 127.0000, "반복 정류장"),
            stop_node(2, 37.50005, 127.0020, "반복 정류장"),  # 진행도 > 50m
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual(len(stops), 2)
        self.assertEqual([s["name"] for s in stops], ["반복 정류장", "반복 정류장"])


if __name__ == "__main__":
    unittest.main()
