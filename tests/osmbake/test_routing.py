"""A* 경로 탐색: 최단 경로, 노선 멤버 우선, 우회."""
import unittest

from tools.osmbake.graph import build_graph
from tools.osmbake.routing import astar, path_latlon


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


if __name__ == "__main__":
    unittest.main()
