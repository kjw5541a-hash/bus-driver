"""Overpass 조회: 캐시 우선, 미러 폴백, 재시도."""
import json
import tempfile
import unittest
from pathlib import Path

from tools.osmbake import overpass


class FakeResponse:
    def __init__(self, payload):
        self._data = json.dumps(payload).encode()

    def read(self):
        return self._data

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class TestFetch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name) / "resp.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_캐시가_있으면_네트워크를_타지_않는다(self):
        self.cache.write_text(json.dumps({"elements": [1]}), encoding="utf-8")

        def boom(*args, **kwargs):
            raise AssertionError("캐시가 있는데 네트워크를 탔다")

        result = overpass.fetch("q", self.cache, opener=boom)
        self.assertEqual(result, {"elements": [1]})

    def test_응답을_캐시에_저장한다(self):
        calls = []

        def opener(request, timeout=None):
            calls.append(request.full_url)
            return FakeResponse({"elements": ["ok"]})

        result = overpass.fetch("q", self.cache, opener=opener)
        self.assertEqual(result, {"elements": ["ok"]})
        self.assertEqual(json.loads(self.cache.read_text(encoding="utf-8")),
                         {"elements": ["ok"]})
        self.assertEqual(len(calls), 1)

    def test_첫_미러가_죽으면_다음_미러로_넘어간다(self):
        calls = []

        def opener(request, timeout=None):
            calls.append(request.full_url)
            if len(calls) == 1:
                raise OSError("504")
            return FakeResponse({"elements": []})

        overpass.fetch("q", self.cache, opener=opener)
        self.assertEqual(len(calls), 2)
        self.assertNotEqual(calls[0], calls[1])

    def test_모든_미러가_죽으면_예외(self):
        def opener(request, timeout=None):
            raise OSError("504")

        with self.assertRaises(RuntimeError):
            overpass.fetch("q", self.cache, opener=opener, attempts=2,
                           sleep=lambda _s: None)


if __name__ == "__main__":
    unittest.main()
