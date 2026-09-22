# OSM 베이크 파이프라인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 노선 식별자를 주면 실제 OSM 데이터에서 주행 가능한 도시 지오메트리(`.glb`)와 노선 메타데이터(`.json`)를 굽는 오프라인 도구를 만들고, 산출물이 실제로 주행 가능한지 헤드리스 Godot로 자동 검증한다.

**Architecture:** `tools/osmbake/` 아래 순수 Python 모듈 6단계 파이프라인(fetch → graph → route → corridor → mesh → emit). 각 단계는 앞 단계 산출물만 입력으로 받고 중간 결과를 파일로 떨어뜨린다. 게임은 산출물만 읽는 순수 로더라 런타임에 Overpass도 Python도 타지 않는다. 검증은 Godot 헤드리스에서 검증 전용 버스가 경로를 자율주행으로 완주하는지 보는 방식이다.

**Tech Stack:** Python 3.14 표준 라이브러리만 (numpy/shapely/trimesh 등 서드파티 없음), Godot 4.7, glTF 2.0 바이너리(`.glb`)

**Spec:** `docs/superpowers/specs/2026-09-22-osm-bake-pipeline-design.md`

## Global Constraints

- Python은 **표준 라이브러리만** 쓴다. 서드파티 의존성을 추가하지 않는다. (이 기계의 Python 3.14에는 numpy도 없고, 빌드 전용 도구에 venv를 끌어들이지 않는다.)
- Godot 4.7. 기존 게임 저장소들과 같은 버전.
- 주석과 문서는 한국어로 쓴다.
- 좌표계: 로컬 평면 미터, x는 동쪽, z는 남쪽, y는 0 고정(평지). 원점은 노선 bbox 중심.
- 도로 필터에 `busway`를 **반드시** 포함한다. 빠뜨리면 서울 노선이 깨진다.
- 산출물 JSON에 `"attribution": "© OpenStreetMap contributors (ODbL)"`를 반드시 넣는다.
- 테스트는 네트워크를 타지 않는다. Overpass 응답은 전부 픽스처나 캐시로 주입한다.
- 검증 기준(노선 3개 전부 통과): 주행 완주 100%, 교착 3초 미만, 지면 커버리지 98% 이상, 정류장 이름 커버리지 95% 이상.
- Godot 검증 하네스는 실측으로 얻은 값 둘을 고정한다: 서스펜션 `stiffness 150` / `max_force 80000`, `engine_force` **부호 반전**.
- 대상 노선 3개: 서대문03(relation 7481016), 100번(relation 2895724), 654번(relation 2907286).

---

## File Structure

```
tools/osmbake/__init__.py      빈 패키지 마커
tools/osmbake/geo.py           좌표 투영, 거리 계산
tools/osmbake/overpass.py      Overpass 조회 + 미러 폴백 + 캐시
tools/osmbake/graph.py         도로망 그래프 구축
tools/osmbake/routing.py       A* 경로 탐색, 정류장 스냅
tools/osmbake/corridor.py      경로 주변 도로/건물 수집
tools/osmbake/mesh.py          메쉬 생성(도로 리본, 건물 extrude, 삼각분할, 청크)
tools/osmbake/glb.py           glTF 2.0 바이너리 writer
tools/osmbake/emit.py          route JSON writer
tools/osmbake/routes.py        노선 3개 정의
tools/osmbake/cli.py           `python -m tools.osmbake.cli bake <route-id>`
tests/osmbake/*.py             단위 테스트 (unittest, 네트워크 없음)
tests/bake/verify.gd           Godot 검증 하네스(자율주행)
tests/bake/verify.tscn         검증 씬
tests/bake/run_verify.sh       노선 하나를 굽고 검증까지 돌리는 러너
project.godot                  검증 테스트 구동용 최소 Godot 프로젝트
```

각 파일은 파이프라인 한 단계씩 맡는다. `mesh.py`가 가장 커질 파일이므로 glTF 직렬화는 `glb.py`로 분리해 둔다.

---

### Task 1: 저장소 뼈대와 좌표 투영

**Files:**
- Create: `tools/osmbake/__init__.py`, `tools/osmbake/geo.py`
- Create: `tests/osmbake/__init__.py`, `tests/osmbake/test_geo.py`
- Create: `run_tests.sh`, `.gitignore`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `haversine(a, b) -> float`, `Projector(lat0, lon0)` with `to_xz(lat, lon) -> tuple[float, float]`, `EARTH_RADIUS_M`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_geo.py`:

```python
"""좌표 투영과 거리 계산 테스트."""
import unittest

from tools.osmbake.geo import Projector, haversine


class TestHaversine(unittest.TestCase):
    def test_같은_점은_거리_0(self):
        p = (37.5, 127.0)
        self.assertAlmostEqual(haversine(p, p), 0.0, places=6)

    def test_위도_0_001도는_약_111m(self):
        d = haversine((37.5, 127.0), (37.501, 127.0))
        self.assertAlmostEqual(d, 111.2, delta=1.0)


class TestProjector(unittest.TestCase):
    def setUp(self):
        self.proj = Projector(37.5, 127.0)

    def test_원점은_0_0(self):
        x, z = self.proj.to_xz(37.5, 127.0)
        self.assertAlmostEqual(x, 0.0, places=6)
        self.assertAlmostEqual(z, 0.0, places=6)

    def test_동쪽은_x_양수(self):
        x, z = self.proj.to_xz(37.5, 127.001)
        self.assertGreater(x, 0.0)
        self.assertAlmostEqual(z, 0.0, places=6)

    def test_북쪽은_z_음수(self):
        # Godot 의 -Z 가 북쪽을 향하므로 북쪽은 z 가 음수여야 한다.
        x, z = self.proj.to_xz(37.501, 127.0)
        self.assertAlmostEqual(x, 0.0, places=6)
        self.assertLess(z, 0.0)
        self.assertAlmostEqual(z, -111.3, delta=1.0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_geo -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/__init__.py`: 빈 파일.
`tests/osmbake/__init__.py`: 빈 파일.

`tools/osmbake/geo.py`:

```python
"""로컬 평면 좌표 투영과 거리 계산.

게임 맵은 한 노선 범위(최대 20 km)만 다루므로 정식 투영법 대신 원점 위도에서
고정한 미터 환산을 쓴다. 이 범위에서 오차는 미터 단위 이하다.
"""
import math

EARTH_RADIUS_M = 6371000.0
METERS_PER_DEG_LAT = 111320.0


def haversine(a: tuple[float, float], b: tuple[float, float]) -> float:
    """두 (위도, 경도) 사이 대권 거리(미터)."""
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat = lat2 - lat1
    dlon = math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


class Projector:
    """위경도를 로컬 평면 미터로 옮긴다. x 는 동쪽, z 는 남쪽."""

    def __init__(self, lat0: float, lon0: float) -> None:
        self.lat0 = lat0
        self.lon0 = lon0
        self._m_per_lon = METERS_PER_DEG_LAT * math.cos(math.radians(lat0))

    def to_xz(self, lat: float, lon: float) -> tuple[float, float]:
        return ((lon - self.lon0) * self._m_per_lon,
                -(lat - self.lat0) * METERS_PER_DEG_LAT)
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_geo -v`
Expected: PASS (5 tests)

- [ ] **Step 5: 러너와 .gitignore 추가**

`run_tests.sh` (기존 게임 저장소들과 같은 이름):

```bash
#!/usr/bin/env bash
# 파이썬 단위 테스트 전체 실행. Godot 주행 검증은 tests/bake/run_verify.sh 가 따로 돈다.
set -euo pipefail
cd "$(dirname "$0")"
python3 -m unittest discover -s tests -t . -v
```

`.gitignore`:

```
__pycache__/
*.pyc
.godot/
tools/osmbake/work/
```

Run: `chmod +x run_tests.sh && ./run_tests.sh`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add tools/osmbake/__init__.py tools/osmbake/geo.py \
        tests/osmbake/__init__.py tests/osmbake/test_geo.py \
        run_tests.sh .gitignore
git commit -m "feat: 로컬 평면 좌표 투영과 거리 계산"
```

---

### Task 2: Overpass 조회와 캐시

**Files:**
- Create: `tools/osmbake/overpass.py`
- Create: `tests/osmbake/test_overpass.py`

**Interfaces:**
- Consumes: 없음
- Produces: `MIRRORS: list[str]`, `fetch(query: str, cache_path: Path, *, opener=None, attempts: int = 3, sleep=time.sleep) -> dict`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_overpass.py`:

```python
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_overpass -v`
Expected: FAIL — `ImportError: cannot import name 'overpass'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/overpass.py`:

```python
"""Overpass API 조회.

공개 인스턴스는 504 를 자주 낸다. 미러를 순회하고 재시도하며, 성공한 응답은
반드시 캐시에 남긴다. OSM 데이터는 계속 바뀌므로 캐시가 없으면 같은 명령이
다른 맵을 만든다.
"""
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
USER_AGENT = "bus-driver-osmbake/0.1"
TIMEOUT_S = 180


def fetch(query: str, cache_path: Path, *, opener=None,
          attempts: int = 3, sleep=time.sleep) -> dict:
    """쿼리 결과를 반환한다. 캐시가 있으면 그것을 쓴다."""
    cache_path = Path(cache_path)
    if cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    opener = opener or urllib.request.urlopen
    body = urllib.parse.urlencode({"data": query}).encode()
    last_error = None
    for attempt in range(attempts):
        for url in MIRRORS:
            request = urllib.request.Request(url, body, {"User-Agent": USER_AGENT})
            try:
                with opener(request, timeout=TIMEOUT_S) as response:
                    payload = json.loads(response.read())
            except Exception as error:  # 미러별 장애는 전부 다음 미러로 넘긴다
                last_error = f"{url}: {error}"
                continue
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_text(json.dumps(payload, ensure_ascii=False),
                                  encoding="utf-8")
            return payload
        sleep(5 * (attempt + 1))
    raise RuntimeError(f"Overpass 미러가 전부 실패했다: {last_error}")
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_overpass -v`
Expected: PASS (4 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/overpass.py tests/osmbake/test_overpass.py
git commit -m "feat: Overpass 조회에 미러 폴백과 캐시 추가"
```

---

### Task 3: 도로망 그래프 구축

**Files:**
- Create: `tools/osmbake/graph.py`
- Create: `tests/osmbake/test_graph.py`

**Interfaces:**
- Consumes: `geo.haversine`
- Produces:
  - `DRIVABLE_HIGHWAYS: frozenset[str]`
  - `Edge` — 필드 `start: int`, `end: int`, `node_ids: tuple[int, ...]`, `length_m: float`, `highway: str`, `way_id: int`, `bus_only: bool`
  - `RoadGraph` — 필드 `coords: dict[int, tuple[float, float]]`, `adj: dict[int, list[Edge]]`
  - `build_graph(elements: list[dict]) -> RoadGraph`

Overpass 가 `out geom` 으로 돌려주는 way 에는 `nodes`(노드 id 목록)와 `geometry`(좌표 목록)가 같은 순서로 들어있다. 이 둘을 짝지어 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_graph.py`:

```python
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


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_graph -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.osmbake.graph'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/graph.py`:

```python
"""OSM 도로 way 들을 주행 그래프로 바꾼다.

way 는 교차점(둘 이상의 way 가 공유하는 노드)에서 쪼갠다. 쪼개지 않으면 A* 가
교차로에서 방향을 바꿀 수 없다.

highway=busway 는 서울 중앙버스전용차선이다. access=no 가 붙어 있지만 버스는
다닐 수 있으므로 반드시 포함한다. 이 등급을 빠뜨리면 서울 노선의 경로가 끊긴다.
"""
from collections import Counter, defaultdict
from dataclasses import dataclass

from .geo import haversine

DRIVABLE_HIGHWAYS = frozenset({
    "motorway", "trunk", "primary", "secondary", "tertiary",
    "unclassified", "residential", "living_street", "service", "busway",
    "motorway_link", "trunk_link", "primary_link", "secondary_link",
    "tertiary_link",
})


@dataclass(frozen=True)
class Edge:
    start: int
    end: int
    node_ids: tuple[int, ...]
    length_m: float
    highway: str
    way_id: int
    bus_only: bool


class RoadGraph:
    def __init__(self) -> None:
        self.coords: dict[int, tuple[float, float]] = {}
        self.adj: dict[int, list[Edge]] = {}

    def add_edge(self, edge: Edge) -> None:
        self.adj.setdefault(edge.start, []).append(edge)


def _drivable_ways(elements: list[dict]) -> list[dict]:
    return [e for e in elements
            if e.get("type") == "way"
            and e.get("tags", {}).get("highway") in DRIVABLE_HIGHWAYS
            and "geometry" in e and "nodes" in e]


def build_graph(elements: list[dict]) -> RoadGraph:
    ways = _drivable_ways(elements)

    usage: Counter[int] = Counter()
    for w in ways:
        for node_id in set(w["nodes"]):
            usage[node_id] += 1

    graph = RoadGraph()
    for w in ways:
        tags = w["tags"]
        node_ids = w["nodes"]
        points = [(g["lat"], g["lon"]) for g in w["geometry"]]
        for node_id, point in zip(node_ids, points):
            graph.coords[node_id] = point

        oneway = tags.get("oneway", "no")
        forward = oneway != "-1"
        backward = oneway not in ("yes", "true", "1")
        bus_only = tags.get("highway") == "busway" or tags.get("access") == "no"

        # 교차점 또는 way 끝에서 끊어 조각으로 나눈다
        split_at = [0]
        for index in range(1, len(node_ids) - 1):
            if usage[node_ids[index]] > 1:
                split_at.append(index)
        split_at.append(len(node_ids) - 1)

        for a, b in zip(split_at, split_at[1:]):
            chunk_ids = tuple(node_ids[a:b + 1])
            chunk_pts = points[a:b + 1]
            if len(chunk_ids) < 2:
                continue
            length = sum(haversine(chunk_pts[i], chunk_pts[i + 1])
                         for i in range(len(chunk_pts) - 1))
            if forward:
                graph.add_edge(Edge(chunk_ids[0], chunk_ids[-1], chunk_ids,
                                    length, tags["highway"], w["id"], bus_only))
            if backward:
                graph.add_edge(Edge(chunk_ids[-1], chunk_ids[0], chunk_ids[::-1],
                                    length, tags["highway"], w["id"], bus_only))
    return graph
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_graph -v`
Expected: PASS (8 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/graph.py tests/osmbake/test_graph.py
git commit -m "feat: OSM 도로 way 를 주행 그래프로 변환"
```

---

### Task 4: A* 경로 탐색

**Files:**
- Create: `tools/osmbake/routing.py`
- Create: `tests/osmbake/test_routing.py`

**Interfaces:**
- Consumes: `graph.RoadGraph`, `graph.Edge`, `geo.haversine`
- Produces:
  - `astar(graph, start: int, goal: int, *, preferred_ways: frozenset[int] = frozenset(), detour_penalty: float = 4.0) -> list[Edge]`
  - `path_latlon(graph, edges: list[Edge]) -> list[tuple[float, float]]`

노선 멤버 도로에는 비용 1배, 그 밖의 도로에는 `detour_penalty` 배를 매긴다. 그러면 노선 멤버가 끊긴 구간만 우회하고 나머지는 실제 노선을 따른다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_routing.py`:

```python
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_routing -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.osmbake.routing'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/routing.py`:

```python
"""노선 경로 탐색.

한국 OSM 의 버스 노선 relation 은 멤버 순서를 믿을 수 없고 양방향이 섞여 있다.
그래서 멤버 순서로 경로를 잇지 않고, 멤버 도로에 낮은 비용을 준 A* 로 경로를
다시 만든다. 멤버가 끊긴 구간은 주변 도로로 우회한다.
"""
import heapq

from .geo import haversine
from .graph import Edge, RoadGraph


def astar(graph: RoadGraph, start: int, goal: int, *,
          preferred_ways: frozenset[int] = frozenset(),
          detour_penalty: float = 4.0) -> list[Edge]:
    """start 에서 goal 까지 엣지 목록. 도달 불가면 빈 리스트."""
    if start == goal or start not in graph.coords or goal not in graph.coords:
        return []

    goal_point = graph.coords[goal]

    def heuristic(node_id: int) -> float:
        return haversine(graph.coords[node_id], goal_point)

    open_heap = [(heuristic(start), 0.0, start)]
    best_cost = {start: 0.0}
    came_from: dict[int, tuple[int, Edge]] = {}
    closed: set[int] = set()

    while open_heap:
        _priority, cost, node = heapq.heappop(open_heap)
        if node == goal:
            break
        if node in closed:
            continue
        closed.add(node)
        for edge in graph.adj.get(node, []):
            weight = edge.length_m
            if preferred_ways and edge.way_id not in preferred_ways:
                weight *= detour_penalty
            new_cost = cost + weight
            if new_cost < best_cost.get(edge.end, float("inf")):
                best_cost[edge.end] = new_cost
                came_from[edge.end] = (node, edge)
                heapq.heappush(open_heap,
                               (new_cost + heuristic(edge.end), new_cost, edge.end))

    if goal not in came_from:
        return []

    edges: list[Edge] = []
    node = goal
    while node != start:
        node, edge = came_from[node]
        edges.append(edge)
    edges.reverse()
    return edges


def path_latlon(graph: RoadGraph, edges: list[Edge]) -> list[tuple[float, float]]:
    """엣지 목록을 이어붙인 (위도, 경도) 폴리라인."""
    points: list[tuple[float, float]] = []
    for edge in edges:
        node_points = [graph.coords[n] for n in edge.node_ids]
        points += node_points[1:] if points else node_points
    return points
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_routing -v`
Expected: PASS (6 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/routing.py tests/osmbake/test_routing.py
git commit -m "feat: 노선 멤버 우선 A* 경로 탐색"
```

---

### Task 5: 정류장 스냅과 순서 결정

**Files:**
- Modify: `tools/osmbake/routing.py` (함수 추가)
- Modify: `tests/osmbake/test_routing.py` (테스트 추가)

**Interfaces:**
- Consumes: `geo.Projector`
- Produces:
  - `project_path(path: list[tuple[float, float]], projector) -> list[tuple[float, float]]` — (x, z) 목록
  - `snap_stops(path_xz, stop_nodes: list[dict], projector, *, max_dist_m: float = 30.0, merge_within_m: float = 50.0) -> list[dict]` — `{"name", "x", "z", "progress_m", "osm_node"}` 를 `progress_m` 오름차순으로

정류장 순서는 relation 의 platform 순서가 아니라 **경로 진행도**가 정한다. 같은 이름이 진행도 가까이에서 두 번 잡히면(양방향 정류장) 하나로 합친다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_routing.py` 에 추가:

```python
from tools.osmbake.geo import Projector
from tools.osmbake.routing import project_path, snap_stops


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

    def test_이름이_다르면_가까워도_합치지_않는다(self):
        nodes = [
            stop_node(1, 37.50010, 127.0005, "가"),
            stop_node(2, 37.49990, 127.0005, "나"),
        ]
        stops = snap_stops(self.path, nodes, self.projector)
        self.assertEqual(len(stops), 2)

    def test_이름_없는_정류장도_잡되_이름은_빈_문자열(self):
        node = {"type": "node", "id": 7, "lat": 37.50005, "lon": 127.0005,
                "tags": {"highway": "bus_stop"}}
        stops = snap_stops(self.path, [node], self.projector)
        self.assertEqual(stops[0]["name"], "")
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_routing -v`
Expected: FAIL — `ImportError: cannot import name 'snap_stops'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/routing.py` 에 추가:

```python
import math

from .geo import Projector


def project_path(path: list[tuple[float, float]],
                 projector: Projector) -> list[tuple[float, float]]:
    """(위도, 경도) 폴리라인을 (x, z) 로 옮긴다."""
    return [projector.to_xz(lat, lon) for lat, lon in path]


def _nearest_on_path(path_xz: list[tuple[float, float]],
                     point: tuple[float, float]) -> tuple[float, float]:
    """(경로까지 거리, 경로 진행도 미터). 각 구간에 수선의 발을 내려 가장 가까운 것."""
    px, pz = point
    best = (float("inf"), 0.0)
    travelled = 0.0
    for (x1, z1), (x2, z2) in zip(path_xz, path_xz[1:]):
        dx, dz = x2 - x1, z2 - z1
        seg_len = math.hypot(dx, dz)
        if seg_len < 1e-9:
            continue
        t = ((px - x1) * dx + (pz - z1) * dz) / (seg_len * seg_len)
        t = max(0.0, min(1.0, t))
        foot_x, foot_z = x1 + t * dx, z1 + t * dz
        distance = math.hypot(px - foot_x, pz - foot_z)
        if distance < best[0]:
            best = (distance, travelled + t * seg_len)
        travelled += seg_len
    return best


def snap_stops(path_xz: list[tuple[float, float]], stop_nodes: list[dict],
               projector: Projector, *, max_dist_m: float = 30.0,
               merge_within_m: float = 50.0) -> list[dict]:
    """정류장 노드를 경로에 스냅한다. 순서는 경로 진행도가 정한다."""
    snapped = []
    for node in stop_nodes:
        point = projector.to_xz(node["lat"], node["lon"])
        distance, progress = _nearest_on_path(path_xz, point)
        if distance > max_dist_m:
            continue
        snapped.append({
            "name": node.get("tags", {}).get("name", ""),
            "x": round(point[0], 2),
            "z": round(point[1], 2),
            "progress_m": round(progress, 1),
            "osm_node": node["id"],
            "_distance": distance,
        })

    snapped.sort(key=lambda s: s["progress_m"])

    merged: list[dict] = []
    for stop in snapped:
        previous = merged[-1] if merged else None
        same_place = (previous is not None
                      and previous["name"] == stop["name"]
                      and stop["progress_m"] - previous["progress_m"] <= merge_within_m)
        if same_place:
            # 경로에 더 가까운 쪽을 남긴다
            if stop["_distance"] < previous["_distance"]:
                merged[-1] = stop
            continue
        merged.append(stop)

    for stop in merged:
        del stop["_distance"]
    return merged
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_routing -v`
Expected: PASS (12 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/routing.py tests/osmbake/test_routing.py
git commit -m "feat: 정류장을 경로에 스냅하고 진행도로 순서 결정"
```

---

### Task 6: 코리도 수집과 신호 후보 합성

**Files:**
- Create: `tools/osmbake/corridor.py`
- Create: `tests/osmbake/test_corridor.py`

**Interfaces:**
- Consumes: `geo.Projector`, `graph.RoadGraph`, `graph.DRIVABLE_HIGHWAYS`
- Produces:
  - `corridor_bbox(path_latlon: list[tuple[float, float]], radius_m: float) -> tuple[float, float, float, float]` — (min_lat, min_lon, max_lat, max_lon)
  - `near_path(elements: list[dict], path_xz, projector, radius_m: float) -> list[dict]`
  - `signal_candidates(graph: RoadGraph, osm_signal_nodes: list[dict], projector, path_xz, radius_m: float) -> list[dict]` — `{"x", "z", "source", "roads"}`

밀집 도심 3 km 에 OSM 신호등이 6개뿐이었다. 그래서 주요 도로(primary/secondary/tertiary)가 3개 이상 만나는 교차점을 합성 후보로 같이 내보낸다. 실제 신호 동작은 4번 서브프로젝트가 정한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_corridor.py`:

```python
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


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_corridor -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.osmbake.corridor'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/corridor.py`:

```python
"""경로 주변만 남기는 코리도 수집, 그리고 신호 후보 합성.

반경 250 m 는 추격 시점에서 양옆 한 블록이 보이는 정도다. 넓힐수록 삼각형 수가
선형으로 늘어난다.
"""
import math

from .geo import METERS_PER_DEG_LAT, Projector
from .graph import RoadGraph
from .routing import _nearest_on_path

MAJOR_HIGHWAYS = frozenset({"motorway", "trunk", "primary", "secondary",
                            "tertiary", "busway"})


def corridor_bbox(path_latlon: list[tuple[float, float]],
                  radius_m: float) -> tuple[float, float, float, float]:
    lats = [lat for lat, _lon in path_latlon]
    lons = [lon for _lat, lon in path_latlon]
    pad_lat = radius_m / METERS_PER_DEG_LAT
    mid_lat = (min(lats) + max(lats)) / 2
    pad_lon = radius_m / (METERS_PER_DEG_LAT * math.cos(math.radians(mid_lat)))
    return (min(lats) - pad_lat, min(lons) - pad_lon,
            max(lats) + pad_lat, max(lons) + pad_lon)


def near_path(elements: list[dict], path_xz: list[tuple[float, float]],
              projector: Projector, radius_m: float) -> list[dict]:
    """기하의 점 하나라도 경로에서 radius_m 안에 있으면 남긴다."""
    kept = []
    for element in elements:
        geometry = element.get("geometry")
        if not geometry:
            continue
        for point in geometry:
            xz = projector.to_xz(point["lat"], point["lon"])
            if _nearest_on_path(path_xz, xz)[0] <= radius_m:
                kept.append(element)
                break
    return kept


def signal_candidates(graph: RoadGraph, osm_signal_nodes: list[dict],
                      projector: Projector, path_xz: list[tuple[float, float]],
                      radius_m: float) -> list[dict]:
    """OSM 신호등 + 주요도로 3갈래 이상 교차점.

    OSM 신호등 태그는 서울에서 거의 비어 있다(밀집 도심 3 km 에 6개). 태그만으로는
    신호 시스템을 세울 수 없어서 교차점을 후보로 같이 낸다.
    """
    signals = []
    for node in osm_signal_nodes:
        xz = projector.to_xz(node["lat"], node["lon"])
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        signals.append({"x": round(xz[0], 2), "z": round(xz[1], 2),
                        "source": "osm", "roads": 0})

    taken = {(s["x"], s["z"]) for s in signals}
    for node_id, edges in graph.adj.items():
        major = {e.way_id for e in edges if e.highway in MAJOR_HIGHWAYS}
        branches = {e.end for e in edges}
        if len(major) < 2 or len(branches) < 3:
            continue
        lat, lon = graph.coords[node_id]
        xz = projector.to_xz(lat, lon)
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        key = (round(xz[0], 2), round(xz[1], 2))
        if key in taken:
            continue
        taken.add(key)
        signals.append({"x": key[0], "z": key[1],
                        "source": "synthesized", "roads": len(branches)})
    return signals
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_corridor -v`
Expected: PASS (7 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/corridor.py tests/osmbake/test_corridor.py
git commit -m "feat: 코리도 수집과 교차로 신호 후보 합성"
```

---

### Task 7: 도로 메쉬 생성

**Files:**
- Create: `tools/osmbake/mesh.py`
- Create: `tests/osmbake/test_mesh.py`

**Interfaces:**
- Consumes: `geo.Projector`
- Produces:
  - `ROAD_WIDTHS: dict[str, float]`, `road_width(tags: dict) -> float`
  - `MeshBuilder` — 필드 `positions: list[tuple[float, float, float]]`, `normals: list[tuple[float, float, float]]`, `indices: list[int]`; 메서드 `add_polygon(points, normal)`, `triangle_count() -> int`
  - `build_roads(ways: list[dict], projector) -> MeshBuilder`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_mesh.py`:

```python
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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_mesh -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.osmbake.mesh'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/mesh.py`:

```python
"""메쉬 생성.

도로 폭은 태그로 얻을 수 없다. 3 km 코리도의 도로 1001 개 중 lanes 태그는 59 개,
width 태그는 1 개뿐이었다. 그래서 등급별 추정 테이블을 쓴다.

고도는 없다. 전부 y=0 평지다.
"""
import math

from .geo import Projector

ROAD_WIDTHS = {
    "motorway": 20.0, "trunk": 20.0,
    "primary": 16.0, "secondary": 12.0, "tertiary": 10.0,
    "unclassified": 7.0, "residential": 7.0, "busway": 7.0,
    "living_street": 6.0, "service": 4.5,
}
LINK_WIDTH = 7.0
DEFAULT_WIDTH = 7.0
LANE_WIDTH = 3.2
MIN_WIDTH = 4.0
UP = (0.0, 1.0, 0.0)
# 꺾이는 지점 패치를 리본보다 1 cm 올려 같은 평면에서 깜빡이는 것을 막는다
PATCH_Y = 0.01


def road_width(tags: dict) -> float:
    highway = tags.get("highway", "")
    lanes = tags.get("lanes")
    if lanes is not None:
        try:
            return max(LANE_WIDTH * int(lanes), MIN_WIDTH)
        except (TypeError, ValueError):
            pass
    if highway.endswith("_link"):
        return LINK_WIDTH
    return ROAD_WIDTHS.get(highway, DEFAULT_WIDTH)


class MeshBuilder:
    """삼각형만 담는 단순한 버퍼. 정점은 폴리곤마다 새로 만든다(공유 없음)."""

    def __init__(self) -> None:
        self.positions: list[tuple[float, float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.indices: list[int] = []

    def add_polygon(self, points, normal) -> None:
        """볼록한(또는 거의 볼록한) 폴리곤을 팬 삼각분할로 넣는다."""
        if len(points) < 3:
            return
        base = len(self.positions)
        for point in points:
            self.positions.append(tuple(point))
            self.normals.append(tuple(normal))
        for offset in range(1, len(points) - 1):
            self.indices += [base, base + offset, base + offset + 1]

    def add_triangles(self, points, triangles, normal) -> None:
        """미리 삼각분할된 폴리곤을 넣는다."""
        base = len(self.positions)
        for point in points:
            self.positions.append(tuple(point))
            self.normals.append(tuple(normal))
        for a, b, c in triangles:
            self.indices += [base + a, base + b, base + c]

    def triangle_count(self) -> int:
        return len(self.indices) // 3


def build_roads(ways: list[dict], projector: Projector) -> MeshBuilder:
    """도로 중심선을 폭만큼 넓힌 리본 + 꺾이는 지점 패치."""
    builder = MeshBuilder()
    for w in ways:
        tags = w.get("tags", {})
        if "highway" not in tags or "geometry" not in w:
            continue
        points = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        half = road_width(tags) / 2.0

        for (x1, z1), (x2, z2) in zip(points, points[1:]):
            dx, dz = x2 - x1, z2 - z1
            length = math.hypot(dx, dz)
            if length < 0.01:
                continue
            nx, nz = -dz / length * half, dx / length * half
            builder.add_polygon([
                (x1 + nx, 0.0, z1 + nz), (x2 + nx, 0.0, z2 + nz),
                (x2 - nx, 0.0, z2 - nz), (x1 - nx, 0.0, z1 - nz),
            ], UP)

        for x, z in points[1:-1]:
            builder.add_polygon([
                (x - half, PATCH_Y, z - half), (x + half, PATCH_Y, z - half),
                (x + half, PATCH_Y, z + half), (x - half, PATCH_Y, z + half),
            ], UP)
    return builder
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_mesh -v`
Expected: PASS (13 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/mesh.py tests/osmbake/test_mesh.py
git commit -m "feat: 도로 폭 추정과 도로 리본 메쉬 생성"
```

---

### Task 8: 건물 메쉬와 ear-clipping 삼각분할

**Files:**
- Modify: `tools/osmbake/mesh.py`
- Modify: `tests/osmbake/test_mesh.py`

**Interfaces:**
- Consumes: `MeshBuilder`
- Produces:
  - `building_height(tags: dict) -> float`
  - `triangulate(polygon: list[tuple[float, float]]) -> list[tuple[int, int, int]]` — ear clipping, 인덱스 삼각형
  - `build_buildings(ways: list[dict], projector) -> MeshBuilder`

스파이크에서 쓴 팬 삼각분할은 오목한 footprint 에서 눈에 띄게 깨졌다. 지붕은 ear clipping 으로 처리한다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_mesh.py` 에 추가:

```python
from tools.osmbake.mesh import build_buildings, building_height, triangulate


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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_mesh -v`
Expected: FAIL — `ImportError: cannot import name 'triangulate'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/mesh.py` 에 추가:

```python
DEFAULT_BUILDING_HEIGHT = 9.0
METERS_PER_LEVEL = 3.2
MIN_BUILDING_HEIGHT = 2.5


def building_height(tags: dict) -> float:
    for key, factor in (("height", 1.0), ("building:levels", METERS_PER_LEVEL)):
        raw = tags.get(key)
        if not raw:
            continue
        try:
            value = float(str(raw).split()[0].replace("m", "").strip())
        except (ValueError, IndexError):
            continue
        return max(value * factor, MIN_BUILDING_HEIGHT)
    return DEFAULT_BUILDING_HEIGHT


def _signed_area(polygon) -> float:
    total = 0.0
    for (x1, z1), (x2, z2) in zip(polygon, polygon[1:] + polygon[:1]):
        total += x1 * z2 - x2 * z1
    return total / 2.0


def _is_convex(a, b, c) -> bool:
    return ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) > 0


def _point_in_triangle(p, a, b, c) -> bool:
    d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
    d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
    d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
    has_negative = (d1 < 0) or (d2 < 0) or (d3 < 0)
    has_positive = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_negative and has_positive)


def triangulate(polygon: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    """Ear clipping 삼각분할. 원래 폴리곤 인덱스로 된 삼각형 목록을 낸다.

    스파이크에서 쓴 팬 삼각분할은 오목한 건물 footprint 에서 눈에 띄게 깨졌다.
    """
    if len(polygon) < 3:
        return []
    indices = list(range(len(polygon)))
    if _signed_area(polygon) < 0:
        indices.reverse()

    triangles: list[tuple[int, int, int]] = []
    guard = 0
    while len(indices) > 3 and guard < len(polygon) * len(polygon):
        guard += 1
        for position in range(len(indices)):
            i_prev = indices[position - 1]
            i_curr = indices[position]
            i_next = indices[(position + 1) % len(indices)]
            a, b, c = polygon[i_prev], polygon[i_curr], polygon[i_next]
            if not _is_convex(a, b, c):
                continue
            others = [polygon[i] for i in indices
                      if i not in (i_prev, i_curr, i_next)]
            if any(_point_in_triangle(p, a, b, c) for p in others):
                continue
            triangles.append((i_prev, i_curr, i_next))
            indices.pop(position)
            break
        else:
            break  # 귀를 못 찾으면(자기교차 등) 남은 것은 버린다
    if len(indices) == 3:
        triangles.append(tuple(indices))
    return triangles


def build_buildings(ways: list[dict], projector: Projector) -> MeshBuilder:
    """건물 footprint 를 높이만큼 밀어올린 벽 + ear clipping 지붕."""
    builder = MeshBuilder()
    for w in ways:
        tags = w.get("tags", {})
        if "building" not in tags or "geometry" not in w:
            continue
        ring = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        if len(ring) >= 2 and ring[0] == ring[-1]:
            ring = ring[:-1]
        if len(ring) < 3:
            continue

        height = building_height(tags)
        for (x1, z1), (x2, z2) in zip(ring, ring[1:] + ring[:1]):
            dx, dz = x2 - x1, z2 - z1
            length = math.hypot(dx, dz)
            if length < 0.01:
                continue
            normal = (dz / length, 0.0, -dx / length)
            builder.add_polygon([(x1, 0.0, z1), (x2, 0.0, z2),
                                 (x2, height, z2), (x1, height, z1)], normal)

        roof_triangles = triangulate(ring)
        if roof_triangles:
            builder.add_triangles([(x, height, z) for x, z in ring],
                                  roof_triangles, UP)
    return builder
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_mesh -v`
Expected: PASS (29 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/mesh.py tests/osmbake/test_mesh.py
git commit -m "feat: 건물 extrude 와 ear-clipping 지붕"
```

---

### Task 9: 청크 분할

**Files:**
- Modify: `tools/osmbake/mesh.py`
- Modify: `tests/osmbake/test_mesh.py`

**Interfaces:**
- Consumes: `MeshBuilder`
- Produces: `CHUNK_SIZE_M: float`, `split_chunks(builder: MeshBuilder, chunk_size: float = CHUNK_SIZE_M) -> dict[str, MeshBuilder]` — 키는 `"chunk_<i>_<j>"`

20 km 노선은 삼각형 약 280k 가 예상된다. 통짜로 두면 컬링할 단위가 없다. 컬링 로직 자체는 2번 서브프로젝트가 만들고, 여기서는 나눠 두기만 한다. 삼각형은 첫 정점이 속한 칸으로 통째로 들어간다(쪼개지 않는다).

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_mesh.py` 에 추가:

```python
from tools.osmbake.mesh import split_chunks


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
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_mesh -v`
Expected: FAIL — `ImportError: cannot import name 'split_chunks'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/mesh.py` 에 추가:

```python
CHUNK_SIZE_M = 200.0


def split_chunks(builder: MeshBuilder,
                 chunk_size: float = CHUNK_SIZE_M) -> dict[str, MeshBuilder]:
    """삼각형을 격자 칸으로 나눈다. 삼각형은 첫 정점이 속한 칸으로 통째로 간다."""
    chunks: dict[str, MeshBuilder] = {}
    for offset in range(0, len(builder.indices), 3):
        tri = builder.indices[offset:offset + 3]
        x, _y, z = builder.positions[tri[0]]
        key = f"chunk_{math.floor(x / chunk_size)}_{math.floor(z / chunk_size)}"
        chunk = chunks.setdefault(key, MeshBuilder())
        base = len(chunk.positions)
        for index in tri:
            chunk.positions.append(builder.positions[index])
            chunk.normals.append(builder.normals[index])
        chunk.indices += [base, base + 1, base + 2]
    return chunks
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_mesh -v`
Expected: PASS (35 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/mesh.py tests/osmbake/test_mesh.py
git commit -m "feat: 메쉬를 200m 격자 청크로 분할"
```

---

### Task 10: glTF 바이너리 writer

**Files:**
- Create: `tools/osmbake/glb.py`
- Create: `tests/osmbake/test_glb.py`

**Interfaces:**
- Consumes: `mesh.MeshBuilder`
- Produces: `write_glb(path: Path, chunks: dict[str, dict[str, MeshBuilder]]) -> None`

`chunks` 는 `{청크이름: {"road": MeshBuilder, "building": MeshBuilder}}` 구조다. 서피스를 나눠 두면 게임이 도로와 건물에 다른 재질을 줄 수 있다.

서드파티 glTF 라이브러리를 쓰지 않는다. POSITION, NORMAL, 인덱스만 필요해서 직접 쓰는 편이 의존성을 늘리는 것보다 싸다. 형식이 틀리면 Task 13 의 Godot 임포트가 실패하므로 검증 경로가 있다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_glb.py`:

```python
"""glTF 2.0 바이너리(.glb) writer."""
import json
import struct
import tempfile
import unittest
from pathlib import Path

from tools.osmbake.glb import write_glb
from tools.osmbake.mesh import MeshBuilder


def square(y=0.0):
    builder = MeshBuilder()
    builder.add_polygon([(0, y, 0), (1, y, 0), (1, y, 1), (0, y, 1)], (0, 1, 0))
    return builder


def read_glb(path):
    data = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", data, 0)
    json_len, json_type = struct.unpack_from("<II", data, 12)
    gltf = json.loads(data[20:20 + json_len])
    return magic, version, total, len(data), json_type, gltf


class TestWriteGlb(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "out.glb"

    def tearDown(self):
        self.tmp.cleanup()

    def test_헤더가_glTF_규격(self):
        write_glb(self.path, {"chunk_0_0": {"road": square()}})
        magic, version, total, size, json_type, _gltf = read_glb(self.path)
        self.assertEqual(magic, 0x46546C67)  # 'glTF'
        self.assertEqual(version, 2)
        self.assertEqual(total, size)
        self.assertEqual(json_type, 0x4E4F534A)  # 'JSON'

    def test_청크마다_노드와_메쉬(self):
        write_glb(self.path, {
            "chunk_0_0": {"road": square()},
            "chunk_1_0": {"road": square()},
        })
        *_rest, gltf = read_glb(self.path)
        self.assertEqual(len(gltf["nodes"]), 2)
        self.assertEqual(len(gltf["meshes"]), 2)
        self.assertEqual(sorted(n["name"] for n in gltf["nodes"]),
                         ["chunk_0_0", "chunk_1_0"])

    def test_도로와_건물은_별도_프리미티브(self):
        write_glb(self.path, {"chunk_0_0": {"road": square(),
                                            "building": square(3.0)}})
        *_rest, gltf = read_glb(self.path)
        self.assertEqual(len(gltf["meshes"][0]["primitives"]), 2)

    def test_빈_서피스는_넣지_않는다(self):
        write_glb(self.path, {"chunk_0_0": {"road": square(),
                                            "building": MeshBuilder()}})
        *_rest, gltf = read_glb(self.path)
        self.assertEqual(len(gltf["meshes"][0]["primitives"]), 1)

    def test_접근자_개수가_정점수와_맞는다(self):
        write_glb(self.path, {"chunk_0_0": {"road": square()}})
        *_rest, gltf = read_glb(self.path)
        primitive = gltf["meshes"][0]["primitives"][0]
        position = gltf["accessors"][primitive["attributes"]["POSITION"]]
        indices = gltf["accessors"][primitive["indices"]]
        self.assertEqual(position["count"], 4)
        self.assertEqual(position["type"], "VEC3")
        self.assertEqual(indices["count"], 6)

    def test_바운딩박스가_들어간다(self):
        write_glb(self.path, {"chunk_0_0": {"road": square()}})
        *_rest, gltf = read_glb(self.path)
        position = gltf["accessors"][
            gltf["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
        self.assertEqual(position["min"], [0.0, 0.0, 0.0])
        self.assertEqual(position["max"], [1.0, 0.0, 1.0])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_glb -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.osmbake.glb'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/glb.py`:

```python
"""glTF 2.0 바이너리(.glb) writer.

POSITION, NORMAL, 인덱스만 필요해서 직접 쓴다. 서드파티 glTF 라이브러리를
들이는 것보다 싸고, 형식이 틀리면 Godot 임포트 검증에서 걸린다.
"""
import json
import struct
from pathlib import Path

from .mesh import MeshBuilder

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
FLOAT = 5126
UNSIGNED_INT = 5125
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


def _pad4(buffer: bytearray, filler: bytes = b"\x00") -> None:
    while len(buffer) % 4:
        buffer += filler


def write_glb(path: Path, chunks: dict[str, dict[str, MeshBuilder]]) -> None:
    binary = bytearray()
    buffer_views: list[dict] = []
    accessors: list[dict] = []
    meshes: list[dict] = []
    nodes: list[dict] = []

    def add_view(data: bytes, target: int) -> int:
        _pad4(binary)
        offset = len(binary)
        binary.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset,
                             "byteLength": len(data), "target": target})
        return len(buffer_views) - 1

    def add_vec3(values) -> int:
        data = b"".join(struct.pack("<fff", *v) for v in values)
        view = add_view(data, ARRAY_BUFFER)
        xs = [v[0] for v in values]
        ys = [v[1] for v in values]
        zs = [v[2] for v in values]
        accessors.append({
            "bufferView": view, "componentType": FLOAT, "count": len(values),
            "type": "VEC3",
            "min": [min(xs), min(ys), min(zs)],
            "max": [max(xs), max(ys), max(zs)],
        })
        return len(accessors) - 1

    def add_indices(values) -> int:
        data = struct.pack(f"<{len(values)}I", *values)
        view = add_view(data, ELEMENT_ARRAY_BUFFER)
        accessors.append({"bufferView": view, "componentType": UNSIGNED_INT,
                          "count": len(values), "type": "SCALAR"})
        return len(accessors) - 1

    for chunk_name in sorted(chunks):
        primitives = []
        for surface_name, builder in sorted(chunks[chunk_name].items()):
            if not builder.indices:
                continue
            primitives.append({
                "attributes": {
                    "POSITION": add_vec3(builder.positions),
                    "NORMAL": add_vec3(builder.normals),
                },
                "indices": add_indices(builder.indices),
                "material": 0 if surface_name == "road" else 1,
            })
        if not primitives:
            continue
        meshes.append({"name": chunk_name, "primitives": primitives})
        nodes.append({"name": chunk_name, "mesh": len(meshes) - 1})

    _pad4(binary)
    gltf = {
        "asset": {"version": "2.0", "generator": "bus-driver osmbake"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(binary)}],
        "materials": [
            {"name": "road",
             "pbrMetallicRoughness": {"baseColorFactor": [0.22, 0.22, 0.24, 1.0],
                                      "metallicFactor": 0.0,
                                      "roughnessFactor": 0.95}},
            {"name": "building",
             "pbrMetallicRoughness": {"baseColorFactor": [0.72, 0.68, 0.62, 1.0],
                                      "metallicFactor": 0.0,
                                      "roughnessFactor": 0.85}},
        ],
    }

    json_bytes = bytearray(json.dumps(gltf, ensure_ascii=False).encode("utf-8"))
    _pad4(json_bytes, b" ")

    total = 12 + 8 + len(json_bytes) + 8 + len(binary)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(struct.pack("<III", GLB_MAGIC, 2, total))
        handle.write(struct.pack("<II", len(json_bytes), JSON_CHUNK))
        handle.write(json_bytes)
        handle.write(struct.pack("<II", len(binary), BIN_CHUNK))
        handle.write(binary)
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_glb -v`
Expected: PASS (6 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/glb.py tests/osmbake/test_glb.py
git commit -m "feat: 의존성 없는 glTF 바이너리 writer"
```

---

### Task 11: 노선 정의와 route JSON

**Files:**
- Create: `tools/osmbake/routes.py`, `tools/osmbake/emit.py`
- Create: `tests/osmbake/test_emit.py`

**Interfaces:**
- Consumes: `mesh.MeshBuilder`
- Produces:
  - `RouteSpec` — 필드 `route_id: str`, `relation: int`, `name: str`, `from_stop: str`, `to_stop: str`
  - `ROUTES: dict[str, RouteSpec]` — 키 `"seoul-seodaemun03"`, `"seoul-100"`, `"seoul-654"`
  - `ATTRIBUTION: str`
  - `write_route_json(path: Path, spec: RouteSpec, *, origin, route_xz, stops, signals, chunk_names, baked_at: str) -> dict`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_emit.py`:

```python
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
                      stops=self.stops, signals=[], chunk_names=["chunk_0_0"],
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


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_emit -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.osmbake.emit'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/routes.py`:

```python
"""구울 노선 정의.

후보 6개의 OSM 품질을 실측해서 셋을 골랐다(최대 연결 컴포넌트 비율 기준).
163 번은 24% 로 조각남이 심해 탈락, 동대문01 은 0.9 km 로 너무 짧아 탈락했다.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class RouteSpec:
    route_id: str
    relation: int
    name: str
    from_stop: str
    to_stop: str


ROUTES: dict[str, RouteSpec] = {
    # 마을버스. 좁은 길 위주, 4.9 km, 데이터 97% 연결. 입문용.
    "seoul-seodaemun03": RouteSpec(
        "seoul-seodaemun03", 7481016, "서울특별시 마을버스 서대문03",
        "홍은2동주민센터", "신촌전철역"),
    # 간선. 중앙버스전용차선 3.3 km 실재. 스파이크에서 주행 검증된 노선.
    "seoul-100": RouteSpec(
        "seoul-100", 2895724, "서울 버스 100", "하계동", "용산구청"),
    # 장거리. 데이터 97% 연결.
    "seoul-654": RouteSpec(
        "seoul-654", 2907286, "서울 버스 654",
        "노들역", "방화3동주민센터.국립국어원"),
}
```

`tools/osmbake/emit.py`:

```python
"""route JSON 산출. 게임이 읽는 데이터 계약."""
import json
from pathlib import Path

from .routes import RouteSpec

ATTRIBUTION = "© OpenStreetMap contributors (ODbL)"


def write_route_json(path: Path, spec: RouteSpec, *, origin, route_xz, stops,
                     signals, chunk_names, baked_at: str) -> dict:
    payload = {
        "id": spec.route_id,
        "name": spec.name,
        "from": spec.from_stop,
        "to": spec.to_stop,
        "origin": [origin[0], origin[1]],
        "attribution": ATTRIBUTION,
        "osm_relation": spec.relation,
        "baked_at": baked_at,
        "route": [[round(x, 2), round(z, 2)] for x, z in route_xz],
        "stops": sorted(stops, key=lambda s: s["progress_m"]),
        "signals": signals,
        "chunks": sorted(chunk_names),
    }
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=1),
                    encoding="utf-8")
    return payload
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_emit -v`
Expected: PASS (7 tests)

- [ ] **Step 5: 커밋**

```bash
git add tools/osmbake/routes.py tools/osmbake/emit.py tests/osmbake/test_emit.py
git commit -m "feat: 노선 3개 정의와 route JSON 데이터 계약"
```

---

### Task 12: 베이크 CLI

**Files:**
- Create: `tools/osmbake/cli.py`
- Create: `tests/osmbake/test_cli.py`

**Interfaces:**
- Consumes: 앞선 모든 모듈
- Produces:
  - `build_queries(spec) -> tuple[str, str]` — (relation 쿼리, 코리도 쿼리 템플릿)
  - `find_terminal_node(graph, stop_nodes, name: str) -> int | None`
  - `bake(route_id: str, *, cache_dir: Path, out_dir: Path, radius_m: float = 250.0, baked_at: str) -> dict`
  - `main(argv: list[str] | None = None) -> int`

CLI 는 캐시가 있으면 네트워크를 타지 않으므로, 테스트는 미리 만든 캐시 파일로 전 과정을 돌린다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/osmbake/test_cli.py`:

```python
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
        stops = [stop(90, 37.50003, 126.94005, "홍은2동주민센터"),
                 stop(91, 37.50003, 126.94300, "중간 정류장"),
                 stop(92, 37.50003, 126.94398, "신촌전철역")]
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

    def test_모르는_노선_id_는_에러(self):
        with self.assertRaises(KeyError):
            cli.bake("없는노선", cache_dir=self.cache_dir, out_dir=self.out_dir,
                     baked_at="2026-09-22")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `python3 -m unittest tests.osmbake.test_cli -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'tools.osmbake.cli'`

- [ ] **Step 3: 최소 구현**

`tools/osmbake/cli.py`:

```python
"""베이크 진입점.

    python3 -m tools.osmbake.cli bake seoul-100

캐시가 있으면 네트워크를 타지 않는다. data/osm_cache/ 는 커밋하므로 같은 명령이
항상 같은 맵을 만든다.
"""
import argparse
import datetime
import sys
from pathlib import Path

from . import corridor as corridor_mod
from . import mesh as mesh_mod
from .emit import write_route_json
from .geo import Projector, haversine
from .glb import write_glb
from .graph import DRIVABLE_HIGHWAYS, build_graph
from .overpass import fetch
from .routes import ROUTES, RouteSpec
from .routing import astar, path_latlon, project_path, snap_stops

REPO_ROOT = Path(__file__).resolve().parents[2]
CACHE_DIR = REPO_ROOT / "data" / "osm_cache"
OUT_DIR = REPO_ROOT / "assets" / "routes"
HIGHWAY_FILTER = "|".join(sorted(DRIVABLE_HIGHWAYS))


def build_queries(spec: RouteSpec) -> tuple[str, str]:
    relation_query = (f"[out:json][timeout:180];rel({spec.relation});"
                      "way(r);out geom;")
    corridor_query = (
        "[out:json][timeout:180];\n"
        "(\n"
        f'  way["highway"~"^({HIGHWAY_FILTER})$"]({{bbox}});\n'
        f'  way["building"]({{bbox}});\n'
        f'  node["highway"="traffic_signals"]({{bbox}});\n'
        f'  node["highway"="bus_stop"]({{bbox}});\n'
        ");\nout geom;")
    return relation_query, corridor_query


def find_terminal_node(graph, stop_nodes: list[dict], name: str) -> int | None:
    """기점/종점 정류장 이름에 가장 가까운 도로 노드."""
    matches = [n for n in stop_nodes if n.get("tags", {}).get("name") == name]
    if not matches or not graph.coords:
        return None
    target = (matches[0]["lat"], matches[0]["lon"])
    return min(graph.coords,
               key=lambda node_id: haversine(graph.coords[node_id], target))


def bake(route_id: str, *, cache_dir: Path = CACHE_DIR, out_dir: Path = OUT_DIR,
         radius_m: float = 250.0, baked_at: str | None = None) -> dict:
    spec = ROUTES[route_id]
    baked_at = baked_at or datetime.date.today().isoformat()
    cache_dir, out_dir = Path(cache_dir), Path(out_dir)
    relation_query, corridor_query = build_queries(spec)

    # 1. fetch — 노선 멤버 도로
    relation = fetch(relation_query, cache_dir / f"{route_id}_relation.json")
    member_elements = relation["elements"]
    member_way_ids = frozenset(e["id"] for e in member_elements
                               if e["type"] == "way")

    # 원점은 노선 멤버 기하의 중심
    lats = [g["lat"] for e in member_elements if "geometry" in e
            for g in e["geometry"]]
    lons = [g["lon"] for e in member_elements if "geometry" in e
            for g in e["geometry"]]
    origin = ((min(lats) + max(lats)) / 2, (min(lons) + max(lons)) / 2)
    projector = Projector(*origin)

    # 1b. fetch — 코리도. 멤버 기하 범위 + 여유
    box = corridor_mod.corridor_bbox(list(zip(lats, lons)), radius_m)
    corridor = fetch(corridor_query.format(bbox=",".join(f"{v:.6f}" for v in box)),
                     cache_dir / f"{route_id}_corridor.json")
    elements = corridor["elements"]

    # 2. graph
    graph = build_graph(elements)

    # 3. route
    stop_nodes = [e for e in elements if e.get("type") == "node"
                  and e.get("tags", {}).get("highway") == "bus_stop"]
    start = find_terminal_node(graph, stop_nodes, spec.from_stop)
    goal = find_terminal_node(graph, stop_nodes, spec.to_stop)
    if start is None or goal is None:
        raise RuntimeError(
            f"{route_id}: 기점/종점 정류장을 찾지 못했다 "
            f"({spec.from_stop} → {spec.to_stop})")
    edges = astar(graph, start, goal, preferred_ways=member_way_ids)
    if not edges:
        raise RuntimeError(f"{route_id}: 기점에서 종점까지 경로가 없다")
    route_latlon = path_latlon(graph, edges)
    route_xz = project_path(route_latlon, projector)
    stops = snap_stops(route_xz, stop_nodes, projector)

    # 4. corridor
    near = corridor_mod.near_path(elements, route_xz, projector, radius_m)
    roads = [e for e in near if e.get("tags", {}).get("highway") in DRIVABLE_HIGHWAYS]
    buildings = [e for e in near if "building" in e.get("tags", {})]
    signal_nodes = [e for e in elements if e.get("type") == "node"
                    and e.get("tags", {}).get("highway") == "traffic_signals"]
    signals = corridor_mod.signal_candidates(graph, signal_nodes, projector,
                                             route_xz, radius_m)

    # 5. mesh
    road_chunks = mesh_mod.split_chunks(mesh_mod.build_roads(roads, projector))
    building_chunks = mesh_mod.split_chunks(
        mesh_mod.build_buildings(buildings, projector))
    chunks: dict[str, dict[str, mesh_mod.MeshBuilder]] = {}
    for name, builder in road_chunks.items():
        chunks.setdefault(name, {})["road"] = builder
    for name, builder in building_chunks.items():
        chunks.setdefault(name, {})["building"] = builder

    # 6. emit
    write_glb(out_dir / f"route_{route_id}.glb", chunks)
    payload = write_route_json(out_dir / f"route_{route_id}.json", spec,
                               origin=origin, route_xz=route_xz, stops=stops,
                               signals=signals, chunk_names=list(chunks),
                               baked_at=baked_at)
    triangles = sum(b.triangle_count() for c in chunks.values()
                    for b in c.values())
    print(f"{route_id}: 경로 {len(route_xz)}점, 정류장 {len(stops)}개, "
          f"신호 후보 {len(signals)}개, 청크 {len(chunks)}개, 삼각형 {triangles}개")
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="OSM 노선 베이크")
    parser.add_argument("command", choices=["bake", "list"])
    parser.add_argument("route_id", nargs="?", default=None)
    args = parser.parse_args(argv)

    if args.command == "list":
        for route_id, spec in ROUTES.items():
            print(f"{route_id}\t{spec.name}\t{spec.from_stop} → {spec.to_stop}")
        return 0

    targets = [args.route_id] if args.route_id else list(ROUTES)
    for route_id in targets:
        bake(route_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `python3 -m unittest tests.osmbake.test_cli -v`
Expected: PASS (7 tests)

- [ ] **Step 5: 전체 단위 테스트 확인**

Run: `./run_tests.sh`
Expected: PASS (약 70 tests)

- [ ] **Step 6: 커밋**

```bash
git add tools/osmbake/cli.py tests/osmbake/test_cli.py
git commit -m "feat: 베이크 CLI 로 파이프라인 6단계 연결"
```

---

### Task 13: Godot 주행 검증 하네스

**Files:**
- Create: `project.godot`, `tests/bake/verify.gd`, `tests/bake/verify.tscn`, `tests/bake/run_verify.sh`
- Create: `icon.svg` (Godot 프로젝트 아이콘 자리)

**Interfaces:**
- Consumes: `assets/routes/route_<id>.glb`, `assets/routes/route_<id>.json`
- Produces: `tests/bake/run_verify.sh <route-id>` — 기준 미달이면 종료 코드 1

검증 하네스는 스파이크에서 실측으로 얻은 값 둘을 고정한다. 서스펜션을 기본값으로 두면 12 t 버스가 차체로 도로에 주저앉고, `engine_force` 부호를 반전하지 않으면 버스가 후진한다.

- [ ] **Step 1: Godot 프로젝트와 씬 만들기**

`project.godot`:

```
config_version=5

[application]
config/name="버스 운전"
run/main_scene="res://tests/bake/verify.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[physics]
common/physics_ticks_per_second=60
```

`tests/bake/verify.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/bake/verify.gd" id="1"]

[node name="Verify" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 2: 실패하는 검증 하네스 작성**

`tests/bake/verify.gd`:

```gdscript
extends Node3D
# 베이크 산출물 검증. 검증 전용 버스가 경로를 자율주행으로 완주하는지 본다.
# 정식 버스와 조작감은 2번 서브프로젝트가 만든다. 여기 버스는 테스트 도구다.
#
# 노선 id 는 --route=<id> 로 받는다:
#   godot --headless --fixed-fps 60 -- --route=seoul-100

const TARGET_SPEED := 9.0       # m/s, 약 32 km/h
const ARRIVE_RADIUS := 25.0     # 웨이포인트 도달 판정
const STUCK_LIMIT := 3.0        # 초. 이보다 오래 멈춰 있으면 실패
const GROUND_COVERAGE_MIN := 0.98
const STOP_NAME_COVERAGE_MIN := 0.95

var route: PackedVector3Array = []
var meta: Dictionary = {}
var bus: VehicleBody3D
var waypoint := 1
var elapsed := 0.0
var stuck := 0.0
var max_stuck := 0.0
var min_y := 1e9
var finished := false
var failures: Array[String] = []

func _ready() -> void:
	var route_id := _route_id_from_args()
	meta = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/routes/route_%s.json" % route_id))
	if meta == null:
		_fail_now("route JSON 을 읽지 못했다: %s" % route_id)
		return
	for point in meta["route"]:
		route.append(Vector3(point[0], 0.0, point[1]))

	var scene: PackedScene = load("res://assets/routes/route_%s.glb" % route_id)
	if scene == null:
		_fail_now("glb 를 읽지 못했다: %s" % route_id)
		return
	var city := scene.instantiate()
	add_child(city)
	for node in city.find_children("*", "MeshInstance3D", true):
		node.create_trimesh_collision()

	await get_tree().physics_frame
	_check_ground_coverage()
	_check_stop_names()
	_check_stop_order()

	bus = _make_bus()
	bus.position = route[0] + Vector3.UP * 1.5
	bus.look_at_from_position(bus.position, route[1] + Vector3.UP * 1.5, Vector3.UP)
	add_child(bus)

func _route_id_from_args() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			return argument.trim_prefix("--route=")
	return "seoul-100"

func _make_bus() -> VehicleBody3D:
	var vehicle := VehicleBody3D.new()
	vehicle.mass = 12000.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 3.0, 11.0)
	shape.shape = box
	shape.position = Vector3(0, 2.0, 0)   # 차체 밑면이 지면에 닿으면 주행을 못 한다
	vehicle.add_child(shape)
	# [앞뒤 위치, 좌우 위치, 조향 여부]
	for spec in [[3.6, -1.1, true], [3.6, 1.1, true], [-3.0, -1.1, false], [-3.0, 1.1, false]]:
		var wheel := VehicleWheel3D.new()
		wheel.position = Vector3(spec[1], 0.2, -spec[0])
		wheel.use_as_steering = spec[2]
		wheel.use_as_traction = not spec[2]
		wheel.wheel_radius = 0.5
		wheel.suspension_travel = 0.35
		# 12 t 버스라 기본값(max_force 6000N/바퀴)으로는 차체가 주저앉는다.
		# 4륜 합계 24 kN 인데 버스 무게는 117 kN 이다.
		wheel.suspension_stiffness = 150.0
		wheel.suspension_max_force = 80000.0
		wheel.damping_compression = 3.7
		wheel.damping_relaxation = 6.1
		wheel.wheel_friction_slip = 3.5
		vehicle.add_child(wheel)
	return vehicle

func _check_ground_coverage() -> void:
	var space := get_world_3d().direct_space_state
	var hits := 0
	for point in route:
		var from := point + Vector3.UP * 30.0
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
		if not space.intersect_ray(query).is_empty():
			hits += 1
	var ratio := float(hits) / float(max(route.size(), 1))
	print("지면 커버리지 %.1f%% (%d/%d)" % [ratio * 100.0, hits, route.size()])
	if ratio < GROUND_COVERAGE_MIN:
		failures.append("지면 커버리지 %.3f < %.2f" % [ratio, GROUND_COVERAGE_MIN])

func _check_stop_names() -> void:
	var stops: Array = meta["stops"]
	if stops.is_empty():
		failures.append("정류장이 하나도 없다")
		return
	var named := 0
	for stop in stops:
		if str(stop["name"]).strip_edges() != "":
			named += 1
	var ratio := float(named) / float(stops.size())
	print("정류장 이름 커버리지 %.1f%% (%d/%d)" % [ratio * 100.0, named, stops.size()])
	if ratio < STOP_NAME_COVERAGE_MIN:
		failures.append("정류장 이름 커버리지 %.3f < %.2f" % [ratio, STOP_NAME_COVERAGE_MIN])

func _check_stop_order() -> void:
	var previous := -1.0
	for stop in meta["stops"]:
		var progress := float(stop["progress_m"])
		if progress < previous:
			failures.append("정류장 진행도가 거꾸로다: %s" % stop["name"])
			return
		previous = progress

func _physics_process(delta: float) -> void:
	if finished or bus == null:
		return
	elapsed += delta
	min_y = min(min_y, bus.position.y)

	while waypoint < route.size() - 1 and bus.position.distance_to(route[waypoint]) < ARRIVE_RADIUS:
		waypoint += 1
	var local := bus.to_local(route[waypoint])
	bus.steering = clamp(atan2(-local.x, absf(local.z)) * 0.8, -0.6, 0.6)

	var speed := bus.linear_velocity.length()
	# Godot 4.7 VehicleBody3D: 양수 engine_force 가 전방(-Z)의 반대로 민다.
	bus.engine_force = -30000.0 if speed < TARGET_SPEED else 0.0
	bus.brake = 20.0 if speed > TARGET_SPEED * 1.4 else 0.0

	if speed < 0.5:
		stuck += delta
		max_stuck = max(max_stuck, stuck)
	else:
		stuck = 0.0

	if waypoint >= route.size() - 1 and bus.position.distance_to(route[-1]) < ARRIVE_RADIUS:
		_finish("완주")
	elif bus.position.y < -5.0:
		failures.append("버스가 지면 아래로 떨어졌다")
		_finish("추락")
	elif stuck > STUCK_LIMIT:
		failures.append("교착 %.1f초 > %.1f초" % [stuck, STUCK_LIMIT])
		_finish("교착")

func _finish(reason: String) -> void:
	finished = true
	var progress := float(waypoint) / float(max(route.size() - 1, 1))
	print("주행 %s: 진행률 %.1f%%, 시간 %.1f초, 최저 y %.2f, 최대 교착 %.1f초"
		% [reason, progress * 100.0, elapsed, min_y, max_stuck])
	if progress < 1.0:
		failures.append("진행률 %.3f < 1.0" % progress)
	_report()

func _fail_now(message: String) -> void:
	failures.append(message)
	_report()

func _report() -> void:
	if failures.is_empty():
		print("VERIFY_OK")
		get_tree().quit(0)
		return
	for failure in failures:
		print("VERIFY_FAIL: %s" % failure)
	get_tree().quit(1)
```

- [ ] **Step 3: 러너 스크립트 작성**

`tests/bake/run_verify.sh`:

```bash
#!/usr/bin/env bash
# 노선 하나를 굽고 Godot 헤드리스로 주행 검증까지 돌린다.
#   tests/bake/run_verify.sh seoul-100
# 노선 id 를 생략하면 정의된 노선 전부를 돈다.
set -euo pipefail
cd "$(dirname "$0")/../.."

routes=("$@")
if [ ${#routes[@]} -eq 0 ]; then
	mapfile -t routes < <(python3 -m tools.osmbake.cli list | cut -f1)
fi

godot --headless --import >/dev/null 2>&1 || true

failed=0
for route in "${routes[@]}"; do
	echo "=== $route ==="
	python3 -m tools.osmbake.cli bake "$route"
	godot --headless --import >/dev/null 2>&1 || true
	if godot --headless --fixed-fps 60 --quit-after 200000 -- --route="$route"; then
		echo "$route: OK"
	else
		echo "$route: FAIL"
		failed=1
	fi
done
exit $failed
```

- [ ] **Step 4: 가장 짧은 노선으로 실제 실행**

Run: `chmod +x tests/bake/run_verify.sh && tests/bake/run_verify.sh seoul-seodaemun03`
Expected: 첫 실행은 Overpass 를 타므로 몇 분 걸린다. 출력에 지면 커버리지·정류장 커버리지·주행 결과가 찍히고 마지막에 `VERIFY_OK`.

실패하면 고칠 순서:
- 경로를 못 찾으면 기점/종점 정류장 이름이 OSM 과 다른 것이다. `python3 -m tools.osmbake.cli list` 로 이름을 확인하고 `routes.py` 를 고친다.
- 지면 커버리지 미달이면 `DRIVABLE_HIGHWAYS` 에 빠진 등급이 있거나 코리도 반경이 좁은 것이다.
- 교착이면 그 지점 기하를 의심한다. 스파이크에서는 차체 박스가 지면에 닿은 것과 서스펜션 기본값이 원인이었다.

- [ ] **Step 5: 나머지 두 노선 검증**

Run: `tests/bake/run_verify.sh seoul-100 seoul-654`
Expected: 둘 다 `VERIFY_OK`

- [ ] **Step 6: 커밋**

```bash
git add project.godot tests/bake/verify.gd tests/bake/verify.tscn \
        tests/bake/run_verify.sh
git commit -m "feat: 헤드리스 주행 검증 하네스"
```

---

### Task 14: 노선 3개 굽고 산출물 커밋

**Files:**
- Create: `data/osm_cache/*.json`, `assets/routes/route_*.glb`, `assets/routes/route_*.json`
- Create: `README.md`

**Interfaces:**
- Consumes: Task 12 의 `bake`, Task 13 의 검증 하네스
- Produces: 커밋된 산출물 3쌍

- [ ] **Step 1: 세 노선 전부 굽고 검증**

Run: `tests/bake/run_verify.sh`
Expected: 세 노선 모두 `VERIFY_OK`, 종료 코드 0

- [ ] **Step 2: 산출물 크기 확인**

Run: `ls -lh assets/routes/ data/osm_cache/`
Expected: 노선별 `.glb` 가 수 MB 수준. 한 노선이 50 MB 를 넘으면 `corridor.py` 의 반경(기본 250 m)을 줄이고 다시 굽는다.

- [ ] **Step 3: README 작성**

`README.md`:

```markdown
# 버스 운전 게임

실제 서울 버스 노선 위를 달리는 버스 운전 게임. 정류장마다 승객을 태우고 정해진
시간 안에 종착역까지 가야 한다. 신호와 승하차로 소요 시간이 계속 바뀌고, 신호를
어겨 시간을 벌 수도 있다.

맵은 OpenStreetMap 데이터를 빌드 타임에 구워서 만든다.

## 지도 데이터

© OpenStreetMap contributors. 지도 데이터는 ODbL 라이선스를 따른다.

## 노선 굽기

```bash
python3 -m tools.osmbake.cli list          # 정의된 노선 보기
python3 -m tools.osmbake.cli bake seoul-100
```

`data/osm_cache/` 에 캐시가 있으면 네트워크를 타지 않는다. 최신 OSM 데이터로 다시
구우려면 해당 캐시 파일을 지운다.

## 테스트

```bash
./run_tests.sh                      # 파이썬 단위 테스트
tests/bake/run_verify.sh            # 노선을 굽고 Godot 헤드리스 주행 검증
```

## 문서

- 설계: `docs/superpowers/specs/2026-09-22-osm-bake-pipeline-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-22-osm-bake-pipeline.md`
```

- [ ] **Step 4: 커밋**

```bash
git add README.md data/osm_cache assets/routes
git commit -m "feat: 노선 3개 베이크 산출물과 OSM 캐시"
```

- [ ] **Step 5: 최종 확인**

Run: `./run_tests.sh && tests/bake/run_verify.sh && git status --short`
Expected: 단위 테스트 전부 통과, 세 노선 `VERIFY_OK`, 작업 트리 깨끗함

---

## Self-Review 결과

**Spec 커버리지.** spec 의 각 절이 어느 태스크에 대응하는지 확인했다.

| spec 항목 | 태스크 |
|---|---|
| 저장소 레이아웃 | 1, 14 |
| fetch (미러 폴백, 캐시, busway 포함) | 2, 12 |
| graph (분할, oneway, access) | 3 |
| route (멤버 우선 A\*, 정류장 스냅, 진행도 순서) | 4, 5 |
| corridor (반경 250 m) | 6, 12 |
| mesh (리본, 패치, extrude, ear clipping, 법선) | 7, 8 |
| 청크 분할 | 9 |
| emit (.glb, route JSON 계약) | 10, 11 |
| 좌표계·도로 폭·건물 높이 규칙 | 1, 7, 8 |
| 신호 후보 합성 | 6 |
| ODbL 표기 | 11, 14 |
| 검증 기준 4개 | 13 |
| 노선 3개 굽기 | 14 |

**타입 일관성.** 태스크 사이를 오가는 이름을 대조했다. `Projector.to_xz`, `Edge.way_id`, `RoadGraph.adj`/`coords`, `astar(..., preferred_ways=, detour_penalty=)`, `snap_stops(...) -> [{"name","x","z","progress_m","osm_node"}]`, `MeshBuilder.positions`/`normals`/`indices`/`triangle_count`, `split_chunks -> {"chunk_i_j": MeshBuilder}`, `write_glb(path, {청크: {"road"|"building": MeshBuilder}})`, `write_route_json(...)` 의 키 집합이 계획 전체에서 같다. Task 6 의 `signal_candidates` 와 Task 12 의 호출부 인자 순서도 일치한다.

**미결로 남긴 것.** `routes.py` 의 기점/종점 정류장 이름은 relation 의 `from`/`to` 태그에서 가져왔다. 실제 `highway=bus_stop` 노드의 이름과 정확히 일치하지 않을 수 있고, 그 경우 Task 13 Step 4 에서 "기점/종점 정류장을 찾지 못했다" 로 드러난다. 고치는 방법은 해당 스텝에 적어뒀다.
