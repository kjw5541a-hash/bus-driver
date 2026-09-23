"""route JSON 데이터 계약."""
import json
import tempfile
import unittest
from pathlib import Path

from tools.osmbake.emit import ATTRIBUTION, write_route_json
from tools.osmbake.routes import ROUTES


class TestRoutes(unittest.TestCase):
    def test_노선_세_개가_정의돼_있다(self):
        self.assertEqual(sorted(ROUTES),
                         ["seoul-100", "seoul-654", "seoul-seodaemun03"])

    def test_relation_번호가_맞다(self):
        self.assertEqual(ROUTES["seoul-100"].relation, 2895724)
        self.assertEqual(ROUTES["seoul-654"].relation, 2907286)
        self.assertEqual(ROUTES["seoul-seodaemun03"].relation, 7481016)

    def test_모든_노선에_기점과_종점이_있다(self):
        for spec in ROUTES.values():
            self.assertTrue(spec.from_stop)
            self.assertTrue(spec.to_stop)


class TestWriteRouteJson(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "route.json"
        self.spec = ROUTES["seoul-100"]
        self.stops = [
            {"name": "가", "x": 0.0, "z": 0.0, "progress_m": 0.0, "osm_node": 1},
            {"name": "나", "x": 10.0, "z": 0.0, "progress_m": 10.0, "osm_node": 2},
        ]

    def tearDown(self):
        self.tmp.cleanup()

    def _write(self, **overrides):
        kwargs = dict(origin=(37.5, 127.0), route_xz=[(0.0, 0.0), (10.0, 0.0)],
                      stops=self.stops, signals=[],
                      chunks=[{"name": "chunk_0_0", "min": [0.0, 0.0], "max": [10.0, 0.0]}],
                      baked_at="2026-09-22")
        kwargs.update(overrides)
        return write_route_json(self.path, self.spec, **kwargs)

    def test_ODbL_표기가_반드시_들어간다(self):
        self._write()
        payload = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertEqual(payload["attribution"], ATTRIBUTION)
        self.assertIn("OpenStreetMap", payload["attribution"])

    def test_계약에_정한_키가_모두_있다(self):
        self._write()
        payload = json.loads(self.path.read_text(encoding="utf-8"))
        for key in ("id", "name", "from", "to", "origin", "attribution",
                    "osm_relation", "baked_at", "route", "stops", "signals",
                    "chunks"):
            self.assertIn(key, payload)

    def test_정류장은_진행도_오름차순으로_저장된다(self):
        self._write(stops=list(reversed(self.stops)))
        payload = json.loads(self.path.read_text(encoding="utf-8"))
        progress = [s["progress_m"] for s in payload["stops"]]
        self.assertEqual(progress, sorted(progress))

    def test_한글_이름이_그대로_저장된다(self):
        self._write()
        raw = self.path.read_text(encoding="utf-8")
        self.assertIn("가", raw)
        self.assertNotIn("\\uac00", raw)

    def test_청크는_이름_오름차순으로_정렬되고_경계상자를_포함한다(self):
        """청크 계약: 각 항목은 name, min, max를 가지고 이름 순으로 정렬된다."""
        # 정렬 안 된 입력으로 확인
        self._write(chunks=[
            {"name": "chunk_2_0", "min": [20.0, 0.0], "max": [30.0, 10.0]},
            {"name": "chunk_0_0", "min": [0.0, 0.0], "max": [10.0, 10.0]},
            {"name": "chunk_1_0", "min": [10.0, 0.0], "max": [20.0, 10.0]},
        ])
        payload = json.loads(self.path.read_text(encoding="utf-8"))

        # 정렬 확인
        chunks = payload["chunks"]
        self.assertEqual([c["name"] for c in chunks],
                         ["chunk_0_0", "chunk_1_0", "chunk_2_0"])

        # 각 청크가 필수 키를 모두 가짐
        for chunk in chunks:
            self.assertIn("name", chunk)
            self.assertIn("min", chunk)
            self.assertIn("max", chunk)
            # min/max는 [x, z] 형태
            self.assertEqual(len(chunk["min"]), 2)
            self.assertEqual(len(chunk["max"]), 2)


if __name__ == "__main__":
    unittest.main()
