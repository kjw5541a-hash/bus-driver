"""도로망 그래프: 교차점 분할, 단방향, 버스전용차선."""
import unittest

from tools.osmbake.graph import build_graph


def way(way_id, node_ids, coords, **tags):
    tags.setdefault("highway", "residential")
    return {
        "type": "way",
        "id": way_id,
        "nodes": list(node_ids),
        "geometry": [{"lat": lat, "lon": lon} for lat, lon in coords],
        "tags": tags,
    }


class TestBuildGraph(unittest.TestCase):
    def test_단순한_길은_엣지_하나(self):
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)])])
        self.assertEqual(len(g.adj[10]), 1)
        edge = g.adj[10][0]
        self.assertEqual(edge.start, 10)
        self.assertEqual(edge.end, 11)
        self.assertGreater(edge.length_m, 50.0)

    def test_양방향_길은_양쪽에서_갈_수_있다(self):
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)])])
        self.assertEqual(len(g.adj[11]), 1)
        self.assertEqual(g.adj[11][0].end, 10)

    def test_oneway_는_한쪽만(self):
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)],
                             oneway="yes")])
        self.assertEqual(len(g.adj[10]), 1)
        self.assertEqual(g.adj.get(11, []), [])

    def test_oneway_마이너스1_은_역방향(self):
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)],
                             oneway="-1")])
        self.assertEqual(g.adj.get(10, []), [])
        self.assertEqual(len(g.adj[11]), 1)

    def test_공유_노드에서_길을_쪼갠다(self):
        # 길 1 의 가운데 노드 11 을 길 2 가 물고 있으면 길 1 은 두 엣지로 쪼개져야 한다.
        elements = [
            way(1, [10, 11, 12],
                [(37.5, 127.0), (37.5, 127.001), (37.5, 127.002)]),
            way(2, [11, 20],
                [(37.5, 127.001), (37.501, 127.001)]),
        ]
        g = build_graph(elements)
        self.assertEqual(len(g.adj[10]), 1)
        self.assertEqual(g.adj[10][0].end, 11)
        self.assertEqual(len(g.adj[11]), 3)  # 10 으로, 12 로, 20 으로

    def test_busway_는_bus_only_로_표시된다(self):
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)],
                             highway="busway", access="no", bus="designated")])
        self.assertTrue(g.adj[10][0].bus_only)

    def test_주행_불가_등급은_버린다(self):
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)],
                             highway="footway")])
        self.assertEqual(g.adj, {})

    def test_건물은_무시한다(self):
        g = build_graph([{"type": "way", "id": 5, "nodes": [1, 2],
                          "geometry": [{"lat": 37.5, "lon": 127.0},
                                       {"lat": 37.5, "lon": 127.001}],
                          "tags": {"building": "yes"}}])
        self.assertEqual(g.adj, {})

    def test_access_no_와_bus_designated_는_bus_only(self):
        # access=no + bus=designated 인 일반 도로는 버스전용으로 표시
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)],
                             highway="residential", access="no", bus="designated")])
        self.assertEqual(len(g.adj[10]), 1)
        self.assertTrue(g.adj[10][0].bus_only)

    def test_access_no_만으로는_bus_only_아님(self):
        # access=no 만 붙고 bus 태그 없는 일반 도로는 버스전용 아님
        # (그래프에는 여전히 들어있음 — 이것은 표시일 뿐 주행 여부가 아님)
        g = build_graph([way(1, [10, 11], [(37.5, 127.0), (37.5, 127.001)],
                             highway="residential", access="no")])
        self.assertEqual(len(g.adj[10]), 1)
        self.assertFalse(g.adj[10][0].bus_only)


if __name__ == "__main__":
    unittest.main()
