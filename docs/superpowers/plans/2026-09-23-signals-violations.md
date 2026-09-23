# 신호·위반 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서울 노선의 주요 교차로에 신호등을 세우고, 적색에 정지선을 넘으면 위반으로 판정하며, 단속 카메라와 순찰 경찰차로 위반에 결과를 붙인다.

**Architecture:** 베이크(Python)가 교차로마다 두 축의 방위각·도로 반폭·카메라 설치 여부를 `route_<id>.json` 에 굽는다. 런타임(GDScript)은 신호 위상을 노드 상태 없이 시간의 순수 함수로 계산하고, 보이는 것(`SignalField`)·판정(`ViolationWatch`)·순찰(`PatrolCars`)·표시(`ViolationHud`)를 각각 독립된 노드로 나눈다. `Drive` 가 조립하고 배선한다.

**Tech Stack:** Python 3.11 표준 라이브러리만 (`unittest`), Godot 4.7.2 GDScript, 헤드리스 테스트

**Spec:** `docs/superpowers/specs/2026-09-23-signals-violations-design.md`

## Global Constraints

- 코드 주석·문서·커밋 메시지는 **한국어**로 쓴다. 기술 용어와 식별자는 원문 그대로.
- Python 은 표준 라이브러리만 쓴다. 서드파티 의존성을 추가하지 않는다.
- Godot 테스트 프레임워크를 추가하지 않는다. `tests/game/test_case.gd` 를 상속한다.
- **Godot 은 GDScript 파싱에 실패해도 종료 코드 0 을 낸다.** 테스트 통과 판정은 반드시 표준출력의 `TEST_OK` / `VERIFY_OK` 문자열로 한다.
- **Godot 이 실행되면 `project.godot` 를 다시 쓴다.** 헤드리스 실행 뒤 `git status` 에 `project.godot` 이 변경으로 뜨면 `git checkout project.godot` 로 되돌린다. 과거에 `[physics] common/physics_ticks_per_second=60` 이 이렇게 사라진 적이 있다.
- 좌표계: x=동, z=**남**, y=위, 전부 y=0 평지. 원점은 노선 bbox 중심.
- 방위각 규칙: 북 0, 동 90, 도 단위, `[0, 360)`. 월드에서 북은 `-Z`, 동은 `+X`.
- 신호 위상 상수: `GREEN_S = 30.0`, `YELLOW_S = 3.0`, `CYCLE_S = 66.0`.
- 신호 필터: 주요도로 3갈래 이상(기존) **그리고** 전체 갈래 4개 이상(신규).
- 단속 카메라 비율: 30%. 좌표만으로 결정되어야 한다 — 같은 노선을 다시 구우면 같은 결과.
- `CAMERA_RATIO` 해시는 Python 내장 `hash()` 를 쓰면 안 된다. 문자열 해시가 프로세스마다 달라진다(`PYTHONHASHSEED`). `zlib.crc32` 를 쓴다.
- 순찰 경찰차: `PATROL_SPEED_MPS = 11.0`, `PATROL_SIGHT_M = 80.0`, 2대.
- 감시 반경: `SignalField` 200 m, `ViolationWatch` 60 m. 공간 색인은 64 m 격자.
- 정지선: 교차로 중심에서 진입 방향 반대로 `half_width + 2.0` m.
- Godot 실행 파일은 `/opt/homebrew/bin/godot`. `tests/game/run_game_tests.sh` 가 알아서 찾는다.
- 테스트는 `python3 -m unittest discover -s tests -t .` 로 전체를 돌린다. 현재 129개 통과 상태에서 시작한다.

---

## 파일 구조

**생성**

| 파일 | 책임 |
|---|---|
| `scripts/traffic_signal.gd` | 신호 위상·방위각·격자 계산. 순수 static 함수만. 노드가 아니다. |
| `scripts/signal_field.gd` | 신호등 기둥 생성과 근거리 색칠. 판정하지 않는다. |
| `scripts/patrol_cars.gd` | 순찰 경찰차 위치와 시야 판정. |
| `scripts/violation_watch.gd` | 정지선 통과 판정. 그리지 않는다. |
| `scripts/violation_hud.gd` | 위반 횟수·플래시·게임 오버 표시. 판정하지 않는다. |
| `tests/game/test_traffic_signal.gd` `.tscn` | 위상·방위·격자 단위 테스트 |
| `tests/game/test_violation.gd` `.tscn` | 판정·순찰·게임 오버 테스트 |

**수정**

| 파일 | 변경 |
|---|---|
| `tools/osmbake/corridor.py` | 신호 필터 축소, `axis_deg`·`half_width`·`camera` 추가 |
| `tools/osmbake/emit.py` | `signals` 항목 docstring 갱신 |
| `tests/osmbake/test_corridor.py` | 기존 3갈래 테스트 수정 + 신규 테스트 |
| `scripts/route_data.gd` | `signals` 파싱 |
| `scripts/drive.gd` | 신호·순찰·판정·HUD 배선, 게임 오버 시 입력 차단 |
| `tests/game/test_route_data.gd` | `signals` 계약 확인 |
| `tests/game/drive_smoke.gd` | 기둥 개수·근거리 컬링 확인 |
| `tests/game/run_game_tests.sh` | 새 씬 2개를 기본 목록에 추가 |
| `assets/routes/route_*.json` | 재베이크 산출물 |
| `README.md` | 신호·단속 설명 |

---

## Task 1: 베이크에 축·반폭·카메라 굽기

**Files:**
- Modify: `tools/osmbake/corridor.py`
- Modify: `tools/osmbake/emit.py:20`
- Test: `tests/osmbake/test_corridor.py`

**Interfaces:**
- Consumes: `tools.osmbake.mesh.road_width(tags: dict) -> float`, `tools.osmbake.graph.Edge` (필드 `start, end, node_ids, length_m, highway, way_id, bus_only`), `tools.osmbake.geo.Projector.to_xz(lat, lon) -> tuple[float, float]`
- Produces: `signal_candidates(graph, osm_signal_nodes, projector, path_xz, radius_m) -> list[dict]` — 각 항목이 `{"x", "z", "source", "roads", "axis_deg": [float, float], "half_width": float, "camera": bool}`. 시그니처는 바뀌지 않는다.

- [ ] **Step 1: 기존 3갈래 테스트를 4갈래로 고치고 새 테스트를 쓴다**

`tests/osmbake/test_corridor.py` 에는 4갈래 필터로 깨지는 테스트가 **둘** 있다. 둘 다 먼저 고친다.

**(a) `test_주요도로_3갈래_교차점은_합성된다`** — 이름과 내용을 아래 `test_갈래_3개는_합성되지_않는다` 로 통째로 바꾼다.

**(b) `test_일방통행으로_들어오기만_해도_갈래로_센다`** — 갈래가 3개라 그대로면 탈락한다. 검사하려는 것(나가는 엣지만 보면 1갈래로 보인다)은 그대로 두고, `elements` 리스트의 `way(3, ...)` 줄 뒤에 네 번째 갈래를 더한다. 단언은 `self.assertEqual(len(signals), 1)` 하나뿐이라 그대로 둔다.

```python
            way(4, [50, 13], [(37.500, 127.0010), (37.499, 127.0010)]),
```

아래를 `class TestSignalCandidates` 안의 (a) 자리에 넣고, 나머지는 클래스 끝에 추가한다.

```python
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
        from tools.osmbake.corridor import _has_camera
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
```

- [ ] **Step 2: 실패를 확인한다**

Run: `python3 -m unittest tests.osmbake.test_corridor -v`
Expected: FAIL. `test_갈래_3개는_합성되지_않는다` 는 1개가 합성되어 실패하고, 나머지는 `KeyError: 'axis_deg'` / `ImportError: cannot import name '_has_camera'` 로 실패한다.

- [ ] **Step 3: `corridor.py` 를 고친다**

임포트와 상수를 파일 상단에 추가한다.

```python
import math
import zlib

from .geo import METERS_PER_DEG_LAT, Projector
from .graph import RoadGraph
from .mesh import road_width
from .routing import _nearest_on_path

MAJOR_HIGHWAYS = frozenset({"motorway", "trunk", "primary", "secondary",
                            "tertiary", "busway"})

# 주요도로 3갈래(기존)만으로는 T자 골목까지 신호가 되어 24 km 노선에 172 m 마다
# 멈춘다. 전체 갈래 4개 이상을 함께 요구하면 259 m 가 되어 실제 서울 간선도로의
# 300~500 m 에 가까워진다.
MIN_BRANCHES = 4
MIN_MAJOR_BRANCHES = 3

# 서울 신호교차로 수 대비 무인단속장비 수에서 잡은 어림값이다.
CAMERA_RATIO = 0.30

# 그래프 노드를 못 찾은 OSM 신호등이 쓰는 값. secondary 폭 15 m 의 절반.
DEFAULT_AXIS_DEG = (0.0, 90.0)
DEFAULT_HALF_WIDTH = 7.5

# OSM 신호등 노드를 그래프 노드에 붙이는 한계 거리.
SNAP_LIMIT_M = 30.0

# 두 방위각을 같은 축으로 볼지 가르는 각거리.
AXIS_TOLERANCE_DEG = 20.0
```

`signal_candidates` 앞에 헬퍼를 넣는다.

```python
def _bearing_deg(ax: float, az: float, bx: float, bz: float) -> float:
    """(ax, az) 에서 (bx, bz) 로 가는 방위각. 북 0, 동 90, 도, [0, 360).

    월드에서 북은 -z, 동은 +x 다.
    """
    return math.degrees(math.atan2(bx - ax, -(bz - az))) % 360.0


def _axis_delta(a: float, b: float) -> float:
    """180° 로 접은 두 방위각 사이의 각거리. 0~90.

    한 축의 양방향은 180° 차이라 같은 축이므로 접어서 비교한다.
    """
    delta = abs(a - b) % 180.0
    return min(delta, 180.0 - delta)


def _axis_pair(bearings: list[float]) -> tuple[float, float]:
    """갈래 방위각들을 교차로의 두 축으로 묶는다.

    축 0 은 같은 축으로 볼 이웃이 가장 많은 방위(십자 교차로면 마주보는 두
    갈래가 접혀 이웃이 하나 더 생긴다), 축 1 은 축 0 에서 가장 먼 갈래다.
    둘이 거의 같은 축이면 축 1 을 수직으로 채운다.
    """
    if not bearings:
        return DEFAULT_AXIS_DEG
    folded = [b % 180.0 for b in bearings]
    # 두 번째 정렬 키는 동점일 때 결과를 고정하기 위한 것이다. 같은 입력에
    # 항상 같은 축이 나와야 재베이크가 안정적이다.
    first = max(folded, key=lambda b: (
        sum(1 for other in folded if _axis_delta(b, other) <= AXIS_TOLERANCE_DEG),
        -b))
    second = max(folded, key=lambda b: _axis_delta(first, b))
    if _axis_delta(first, second) < AXIS_TOLERANCE_DEG:
        second = (first + 90.0) % 180.0
    return (round(first, 1), round(second, 1))


def _has_camera(x: float, z: float) -> bool:
    """좌표만으로 정해지는 단속 카메라 설치 여부.

    내장 hash() 는 문자열에 대해 프로세스마다 값이 달라서(PYTHONHASHSEED)
    재베이크마다 카메라 위치가 바뀐다. crc32 는 고정이다.
    """
    key = f"{round(x, 1)},{round(z, 1)}".encode()
    return (zlib.crc32(key) % 100) < round(CAMERA_RATIO * 100)
```

`signal_candidates` 본문을 아래로 통째로 바꾼다.

```python
def signal_candidates(graph: RoadGraph, osm_signal_nodes: list[dict],
                      projector: Projector, path_xz: list[tuple[float, float]],
                      radius_m: float) -> list[dict]:
    """OSM 신호등 + 갈래 4개 이상인 주요도로 교차점.

    OSM 신호등 태그는 서울에서 거의 비어 있다(밀집 도심 3 km 에 6개). 태그만으로는
    신호 시스템을 세울 수 없어서 교차점을 후보로 같이 낸다.

    항목마다 두 축의 방위각(axis_deg), 가장 넓은 갈래의 반폭(half_width),
    단속 카메라 설치 여부(camera)를 함께 낸다. 런타임이 버스가 어느 축에
    있는지 판정하고 정지선을 놓는 데 쓴다.
    """
    # adj 는 나가는 엣지만 담는다. 일방통행으로 들어오기만 하는 도로도 교차로의
    # 한 갈래이므로 양쪽 끝 모두에 엣지를 달아 인접 인덱스를 만든다.
    incident: dict[int, list] = {}
    for edges in graph.adj.values():
        for edge in edges:
            incident.setdefault(edge.start, []).append(edge)
            incident.setdefault(edge.end, []).append(edge)

    node_xz = {node_id: projector.to_xz(*graph.coords[node_id])
               for node_id in incident}

    def describe(node_id) -> dict:
        if node_id is None:
            return {"axis_deg": list(DEFAULT_AXIS_DEG),
                    "half_width": DEFAULT_HALF_WIDTH}
        x, z = node_xz[node_id]
        bearings = []
        for edge in incident[node_id]:
            other = edge.end if edge.start == node_id else edge.start
            if other not in node_xz:
                continue
            other_x, other_z = node_xz[other]
            bearings.append(_bearing_deg(x, z, other_x, other_z))
        axis = _axis_pair(bearings)
        half = max(road_width({"highway": edge.highway})
                   for edge in incident[node_id]) / 2.0
        return {"axis_deg": [axis[0], axis[1]], "half_width": round(half, 2)}

    def nearest_graph_node(xz):
        # ponytail: 신호등 노드 x 그래프 노드 선형 스캔. OSM 신호등이 노선당
        # 40개 안쪽이라 충분히 싸다. 늘어나면 격자 색인으로 바꾼다.
        best, best_distance = None, SNAP_LIMIT_M
        for node_id, (node_x, node_z) in node_xz.items():
            distance = math.hypot(node_x - xz[0], node_z - xz[1])
            if distance < best_distance:
                best, best_distance = node_id, distance
        return best

    signals = []
    claimed: set[int] = set()
    for node in osm_signal_nodes:
        xz = projector.to_xz(node["lat"], node["lon"])
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        snapped = nearest_graph_node(xz)
        if snapped is not None:
            claimed.add(snapped)
        entry = {"x": round(xz[0], 2), "z": round(xz[1], 2),
                 "source": "osm", "roads": 0}
        entry.update(describe(snapped))
        entry["camera"] = _has_camera(entry["x"], entry["z"])
        signals.append(entry)

    taken = {(s["x"], s["z"]) for s in signals}
    for node_id, edges in incident.items():
        # OSM 태그가 이미 이 교차점을 집었으면 합성하지 않는다. 안 그러면 몇 m
        # 어긋난 신호 두 개가 같은 교차로에 선다.
        if node_id in claimed:
            continue
        # "주요도로 3갈래 이상"은 서로 다른 way_id 가 아니라 갈래 수로 센다.
        # 간선 둘이 십자로 만나는 전형적 신호 교차로는 way_id 가 2개뿐이다.
        major_branches = {edge.end if edge.start == node_id else edge.start
                          for edge in edges if edge.highway in MAJOR_HIGHWAYS}
        if len(major_branches) < MIN_MAJOR_BRANCHES:
            continue
        branches = {edge.end if edge.start == node_id else edge.start
                    for edge in edges}
        if len(branches) < MIN_BRANCHES:
            continue
        xz = node_xz[node_id]
        if _nearest_on_path(path_xz, xz)[0] > radius_m:
            continue
        key = (round(xz[0], 2), round(xz[1], 2))
        if key in taken:
            continue
        taken.add(key)
        entry = {"x": key[0], "z": key[1],
                 "source": "synthesized", "roads": len(branches)}
        entry.update(describe(node_id))
        entry["camera"] = _has_camera(key[0], key[1])
        signals.append(entry)
    return signals
```

- [ ] **Step 4: `emit.py` 의 docstring 을 고친다**

`tools/osmbake/emit.py` 20번째 줄을 바꾼다.

```python
        signals: [{"x", "z", "source", "roads", "axis_deg", "half_width",
                   "camera"}, ...] 신호기
```

- [ ] **Step 5: 테스트가 통과하는지 본다**

Run: `python3 -m unittest discover -s tests -t . 2>&1 | grep -E "^(OK|FAILED|Ran )"`
Expected: `Ran 137 tests` 와 `OK`. 129 에서 8개 늘어난다(기존 1개는 이름만 바뀌어 수가 그대로다).

`tail` 로 보면 안 된다 — 테스트가 베이크 진행 상황을 stdout 에 찍어서 요약이 묻힌다.

- [ ] **Step 6: 커밋**

```bash
git add tools/osmbake/corridor.py tools/osmbake/emit.py tests/osmbake/test_corridor.py
git commit -m "feat: 신호 후보에 축 방위각·반폭·단속 카메라 추가

주요도로 3갈래만으로는 T자 골목까지 신호가 되어 seoul-100 에서 172 m 마다
멈춘다. 전체 갈래 4개 이상을 함께 요구해 259 m 로 맞췄다.

축 방위각은 런타임이 버스가 어느 축에 있는지 판정하는 데 쓰고, 반폭은
정지선 위치를 잡는 데 쓴다. OSM 단속 데이터는 서울 북부 전역에 13개뿐이고
전부 과속 카메라라 좌표 해시로 합성한다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: 3개 노선 재베이크

**Files:**
- Modify: `assets/routes/route_seoul-seodaemun03.json`, `assets/routes/route_seoul-100.json`, `assets/routes/route_seoul-654.json`

**Interfaces:**
- Consumes: Task 1 의 `signal_candidates`
- Produces: `signals` 배열에 새 필드가 들어간 `route_<id>.json` 3개. 이후 모든 런타임 작업이 이 산출물을 읽는다.

- [ ] **Step 1: 재베이크**

Run: `python3 -m tools.osmbake.cli bake`
Expected: 약 2분 10초. 세 줄이 찍힌다. 신호 후보 수가 줄어야 한다 — 이전은 78 / 286 / 219, 이후는 대략 절반 이하다.

`.glb` 는 신호와 무관하므로 바이트가 그대로여야 한다. 달라지면 베이크가 다른 걸 건드린 것이니 멈추고 원인을 찾는다.

- [ ] **Step 2: 산출물을 검사한다**

Run:
```bash
python3 -c "
import json, collections
for rid in ['seoul-seodaemun03', 'seoul-100', 'seoul-654']:
    d = json.load(open('assets/routes/route_%s.json' % rid))
    s = d['signals']
    cam = sum(1 for e in s if e['camera'])
    print(rid, len(s), '카메라', cam, '%.0f%%' % (100.0 * cam / len(s)))
    assert all('axis_deg' in e and 'half_width' in e for e in s)
    assert all(len(e['axis_deg']) == 2 for e in s)
    assert all(e['half_width'] >= 2.0 for e in s)
"
```
Expected: 세 줄이 찍히고 assert 가 통과한다. 카메라 비율이 대략 20~40%.

- [ ] **Step 3: `.glb` 가 안 바뀌었는지 확인한다**

Run: `git status --porcelain assets/routes/`
Expected: `.json` 3개만 `M` 으로 뜨고 `.glb` 는 뜨지 않는다.

- [ ] **Step 4: 커밋**

```bash
git add assets/routes/route_seoul-seodaemun03.json assets/routes/route_seoul-100.json assets/routes/route_seoul-654.json
git commit -m "chore: 신호 필터·축·카메라를 반영해 3개 노선 재베이크

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: 신호 위상 순수 함수

**Files:**
- Create: `scripts/traffic_signal.gd`
- Create: `tests/game/test_traffic_signal.gd`, `tests/game/test_traffic_signal.tscn`
- Modify: `tests/game/run_game_tests.sh:31`

**Interfaces:**
- Consumes: 없음. 어떤 노드에도 의존하지 않는다.
- Produces:
  - `TrafficSignal.Phase` — `{ GREEN, YELLOW, RED }`
  - `TrafficSignal.GREEN_S := 30.0`, `YELLOW_S := 3.0`, `CYCLE_S := 66.0`, `CELL_M := 64.0`
  - `static var time_override := -1.0`
  - `static func now() -> float`
  - `static func offset_for(x: float, z: float) -> float`
  - `static func phase_at(offset_s: float, axis_index: int, t: float) -> Phase`
  - `static func axis_for(heading_deg: float, axis_deg: Array) -> int`
  - `static func bearing_of(direction: Vector3) -> float`
  - `static func direction_of(bearing_deg: float) -> Vector3`
  - `static func cell_of(x: float, z: float) -> Vector2i`
  - `static func cells_near(point: Vector3, radius_m: float) -> Array[Vector2i]`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_traffic_signal.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_traffic_signal.gd" id="1"]

[node name="TestTrafficSignal" type="Node"]
script = ExtResource("1")
```

`tests/game/test_traffic_signal.gd`:

```gdscript
extends TestCase
# 신호 위상은 노드 상태 없이 시간의 순수 함수다. 여기서 경계값을 못 잡으면
# 위반 판정 전체가 한 프레임씩 어긋난다.

func _ready() -> void:
	_test_phase_boundaries()
	_test_axes_never_both_go()
	_test_offset()
	_test_axis_for()
	_test_bearing()
	_test_grid()
	finish()

func _test_phase_boundaries() -> void:
	# offset 0, 축 0: 0~30 녹, 30~33 황, 33~66 적.
	ok(TrafficSignal.phase_at(0.0, 0, 0.0) == TrafficSignal.Phase.GREEN, "t=0 이 녹이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 29.9) == TrafficSignal.Phase.GREEN, "t=29.9 가 녹이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 30.1) == TrafficSignal.Phase.YELLOW, "t=30.1 이 황이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 32.9) == TrafficSignal.Phase.YELLOW, "t=32.9 가 황이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 33.1) == TrafficSignal.Phase.RED, "t=33.1 이 적이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 65.9) == TrafficSignal.Phase.RED, "t=65.9 가 적이 아니다")
	ok(TrafficSignal.phase_at(0.0, 0, 66.1) == TrafficSignal.Phase.GREEN, "주기가 안 돈다")
	# 음수 시각에서도 감겨야 한다.
	ok(TrafficSignal.phase_at(0.0, 0, -1.0) == TrafficSignal.Phase.RED, "t=-1 이 적이 아니다")

func _test_axes_never_both_go() -> void:
	# 한 축이 녹이나 황이면 다른 축은 반드시 적이어야 한다.
	var t := 0.0
	while t < TrafficSignal.CYCLE_S:
		var a := TrafficSignal.phase_at(7.5, 0, t)
		var b := TrafficSignal.phase_at(7.5, 1, t)
		if a != TrafficSignal.Phase.RED and b != TrafficSignal.Phase.RED:
			ok(false, "t=%.1f 에서 두 축이 동시에 간다" % t)
			return
		t += 0.5

func _test_offset() -> void:
	var offset := TrafficSignal.offset_for(123.4, -567.8)
	ok(offset >= 0.0 and offset < TrafficSignal.CYCLE_S,
		"위상 오프셋이 범위 밖이다: %f" % offset)
	ok(is_equal_approx(offset, TrafficSignal.offset_for(123.4, -567.8)),
		"같은 좌표에 다른 오프셋이 나온다")
	# 이웃한 교차로가 같은 위상이면 도시 전체가 동시에 바뀐다.
	var neighbour := TrafficSignal.offset_for(223.4, -567.8)
	ok(not is_equal_approx(offset, neighbour), "다른 좌표에 같은 오프셋이 나온다")

func _test_axis_for() -> void:
	var axes := [12.0, 102.0]
	ok(TrafficSignal.axis_for(10.0, axes) == 0, "방위 10 이 축 0 이 아니다")
	# 180° 반대로 달려도 같은 축이다.
	ok(TrafficSignal.axis_for(190.0, axes) == 0, "방위 190 이 축 0 이 아니다")
	ok(TrafficSignal.axis_for(100.0, axes) == 1, "방위 100 이 축 1 이 아니다")
	ok(TrafficSignal.axis_for(280.0, axes) == 1, "방위 280 이 축 1 이 아니다")

func _test_bearing() -> void:
	# 북은 -Z 로 0, 동은 +X 로 90.
	equal_approx(TrafficSignal.bearing_of(Vector3(0.0, 0.0, -1.0)), 0.0, 0.01, "북이 0 이 아니다")
	equal_approx(TrafficSignal.bearing_of(Vector3(1.0, 0.0, 0.0)), 90.0, 0.01, "동이 90 이 아니다")
	equal_approx(TrafficSignal.bearing_of(Vector3(0.0, 0.0, 1.0)), 180.0, 0.01, "남이 180 이 아니다")
	# direction_of 는 bearing_of 의 역이다.
	for bearing in [0.0, 37.0, 90.0, 181.0, 300.0]:
		var back := TrafficSignal.bearing_of(TrafficSignal.direction_of(bearing))
		equal_approx(back, bearing, 0.01, "방위 %.0f 의 왕복이 안 맞는다" % bearing)

func _test_grid() -> void:
	ok(TrafficSignal.cell_of(0.0, 0.0) == Vector2i(0, 0), "원점 셀이 (0,0) 이 아니다")
	ok(TrafficSignal.cell_of(-1.0, -1.0) == Vector2i(-1, -1), "음수 셀이 잘못됐다")
	var cells := TrafficSignal.cells_near(Vector3.ZERO, 64.0)
	ok(cells.size() == 9, "반경 64 m 는 3x3 셀이어야 하는데 %d 개다" % cells.size())
	ok(cells.has(Vector2i(0, 0)), "자기 셀이 빠졌다")
	ok(cells.has(Vector2i(1, 1)), "대각 셀이 빠졌다")
	ok(not cells.has(Vector2i(2, 0)), "필요 없는 셀이 들어 있다")
```

`tests/game/run_game_tests.sh` 31번째 줄의 기본 씬 목록에 새 씬을 넣는다.

```bash
	scenes=(test_route_data test_city test_input test_turn_radius test_nav_line test_traffic_signal test_violation drive_smoke)
```

`test_violation` 은 Task 7 에서 만든다. 지금은 그 씬이 없어 실패하므로, 이 태스크의 검증은 씬 이름을 인자로 주어 하나만 돌린다.

- [ ] **Step 2: 실패를 확인한다**

Run: `tests/game/run_game_tests.sh test_traffic_signal`
Expected: FAIL. `Identifier "TrafficSignal" not declared` 가 출력에 보이고 `test_traffic_signal: FAIL` 로 끝난다.

- [ ] **Step 3: `scripts/traffic_signal.gd` 를 쓴다**

```gdscript
extends RefCounted
class_name TrafficSignal
# 신호 위상 계산. 노드가 아니고 상태도 없다 — 좌표와 시각만 넣으면 색이 나온다.
#
# 신호 93개를 노드 상태로 들면 매 프레임 93번의 타이머 갱신이 되고, 리플레이나
# 테스트에서 시각을 되돌릴 수 없다. 순수 함수면 둘 다 공짜다.

enum Phase { GREEN, YELLOW, RED }

const GREEN_S := 30.0
const YELLOW_S := 3.0
# 한 주기는 (녹 + 황) x 2 다. 축 1 이 축 0 보다 정확히 반주기 뒤라서, 합이
# CYCLE_S 와 다르면 두 축이 동시에 녹이 되는 순간이 생긴다.
const CYCLE_S := (GREEN_S + YELLOW_S) * 2.0

# 신호는 움직이지 않으므로 격자 색인을 한 번 만들어 쓴다. 64 m 는 감시 반경
# 60 m 보다 조금 커서 3x3 스캔이면 반드시 덮인다.
const CELL_M := 64.0

# 테스트가 시각을 고정하는 통로. 음수면 실제 시계를 쓴다. SignalField 와
# ViolationWatch 가 같은 시계를 봐야 보이는 색과 판정이 어긋나지 않는다.
static var time_override := -1.0

static func now() -> float:
	if time_override >= 0.0:
		return time_override
	return float(Time.get_ticks_msec()) / 1000.0

static func offset_for(x: float, z: float) -> float:
	"""좌표로 정해지는 위상 오프셋. 교차로마다 흩어져 도시가 동시에 안 바뀐다."""
	# 엔진 hash() 대신 직접 섞는다. 버전이 바뀌어도 같은 노선이 같은 신호를
	# 만나야 한다.
	var mixed := (roundi(x) * 73856093) ^ (roundi(z) * 19349663)
	return float(absi(mixed) % int(CYCLE_S * 100.0)) / 100.0

static func phase_at(offset_s: float, axis_index: int, t: float) -> Phase:
	var shift := CYCLE_S * 0.5 if axis_index == 1 else 0.0
	# fposmod 는 음수 시각도 [0, CYCLE_S) 로 감는다. fmod 는 음수를 그대로 둔다.
	var local := fposmod(t + offset_s + shift, CYCLE_S)
	if local < GREEN_S:
		return Phase.GREEN
	if local < GREEN_S + YELLOW_S:
		return Phase.YELLOW
	return Phase.RED

static func axis_for(heading_deg: float, axis_deg: Array) -> int:
	"""진행 방위에 가까운 축의 인덱스. 역주행해도 같은 축이 나온다."""
	var to_first := axis_delta(heading_deg, float(axis_deg[0]))
	var to_second := axis_delta(heading_deg, float(axis_deg[1]))
	return 0 if to_first <= to_second else 1

static func axis_delta(a: float, b: float) -> float:
	"""180° 로 접은 두 방위각 사이의 각거리. 0~90."""
	var delta := fposmod(a - b, 180.0)
	return minf(delta, 180.0 - delta)

static func bearing_of(direction: Vector3) -> float:
	"""월드 방향벡터의 방위각. 북(-Z) 0, 동(+X) 90, 도, [0, 360)."""
	return fposmod(rad_to_deg(atan2(direction.x, -direction.z)), 360.0)

static func direction_of(bearing_deg: float) -> Vector3:
	"""방위각을 수평 단위벡터로. bearing_of 의 역이다."""
	var radians := deg_to_rad(bearing_deg)
	return Vector3(sin(radians), 0.0, -cos(radians))

static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL_M), floori(z / CELL_M))

static func cells_near(point: Vector3, radius_m: float) -> Array[Vector2i]:
	var span := ceili(radius_m / CELL_M)
	var base := cell_of(point.x, point.z)
	var cells: Array[Vector2i] = []
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			cells.append(base + Vector2i(dx, dz))
	return cells
```

- [ ] **Step 4: 통과를 확인한다**

Run: `tests/game/run_game_tests.sh test_traffic_signal`
Expected: `TEST_OK` 가 출력에 있고 `test_traffic_signal: OK`.

- [ ] **Step 5: `project.godot` 이 바뀌었으면 되돌린다**

Run: `git status --porcelain project.godot`
Expected: 빈 출력. 무언가 뜨면 `git checkout project.godot` 한다.

- [ ] **Step 6: 커밋**

```bash
godot --headless --import >/dev/null 2>&1 || true
git add scripts/traffic_signal.gd scripts/traffic_signal.gd.uid tests/game/test_traffic_signal.gd tests/game/test_traffic_signal.gd.uid tests/game/test_traffic_signal.tscn tests/game/run_game_tests.sh
git commit -m "feat: 신호 위상 순수 함수

좌표 해시로 교차로마다 위상을 흩고, 축 1 은 축 0 의 반주기 뒤에 둬서 두 축이
동시에 녹이 되는 순간이 없게 했다. 노드 상태가 없어 테스트에서 시각을 그냥
넣으면 된다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

`.uid` 파일이 생성되지 않았으면 `git add` 에서 빼고 커밋한다.

---

## Task 4: 노선 데이터에 signals 싣기

**Files:**
- Modify: `scripts/route_data.gd:15` (`var chunks` 아래), `scripts/route_data.gd:35`
- Test: `tests/game/test_route_data.gd`

**Interfaces:**
- Consumes: Task 2 의 `route_<id>.json` `signals` 배열
- Produces: `RouteData.signals: Array` — 각 원소가 `{"x": float, "z": float, "source": String, "roads": int, "axis_deg": Array, "half_width": float, "camera": bool}` 형태의 `Dictionary`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_route_data.gd` 의 `ok(data.chunks.size() > 0, "청크가 없다")` 줄 바로 아래에 넣는다.

```gdscript
	ok(data.signals.size() > 10, "신호가 %d 개뿐이다" % data.signals.size())

	# 신호는 4번 서브프로젝트 계약대로 축 방위각과 반폭, 카메라를 가진다.
	var signal_entry: Dictionary = data.signals[0]
	ok(signal_entry.has("x") and signal_entry.has("z"),
		"신호 좌표가 없다: %s" % str(signal_entry))
	ok(signal_entry.has("axis_deg") and signal_entry["axis_deg"].size() == 2,
		"신호 축 방위각 계약이 다르다: %s" % str(signal_entry))
	ok(signal_entry.has("half_width") and float(signal_entry["half_width"]) > 0.0,
		"신호 반폭이 없다: %s" % str(signal_entry))
	ok(signal_entry.has("camera"), "신호 카메라 필드가 없다: %s" % str(signal_entry))
```

- [ ] **Step 2: 실패를 확인한다**

Run: `tests/game/run_game_tests.sh test_route_data`
Expected: FAIL. `Invalid access to property or key 'signals'` 가 보인다.

- [ ] **Step 3: `route_data.gd` 를 고친다**

`var chunks: Array = []` 아래에 추가한다.

```gdscript
var signals: Array = []
```

`data.chunks = parsed.get("chunks", [])` 아래에 추가한다.

```gdscript
	# 구 버전 산출물에는 signals 가 없거나 axis_deg 가 빠져 있다. 비어 있으면
	# 신호 관련 노드가 조용히 아무것도 안 하도록 그대로 넘긴다.
	data.signals = parsed.get("signals", [])
```

- [ ] **Step 4: 통과를 확인한다**

Run: `tests/game/run_game_tests.sh test_route_data`
Expected: `TEST_OK`, `test_route_data: OK`.

- [ ] **Step 5: 커밋**

```bash
git add scripts/route_data.gd tests/game/test_route_data.gd
git commit -m "feat: RouteData 가 signals 를 읽는다

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: 신호등 기둥과 근거리 색칠

**Files:**
- Create: `scripts/signal_field.gd`
- Test: `tests/game/drive_smoke.gd` (Task 8 에서 추가). 이 태스크는 Task 3 의 함수만 쓰므로 자체 테스트 없이 다음 태스크의 통합 테스트로 검증한다 — 대신 아래 Step 4 의 수동 확인을 반드시 한다.

**Interfaces:**
- Consumes: `TrafficSignal.Phase`, `TrafficSignal.offset_for`, `TrafficSignal.phase_at`, `TrafficSignal.direction_of`, `TrafficSignal.cell_of`, `TrafficSignal.cells_near`, `TrafficSignal.now`
- Produces:
  - `SignalField` (`extends Node3D`)
  - `func build(signals: Array) -> void`
  - `var target: Node3D` — 근거리 판정 기준(버스)
  - `var head_count: int` — 만든 기둥 수
  - `var updated_count: int` — 직전 프레임에 색을 검사한 기둥 수

- [ ] **Step 1: `scripts/signal_field.gd` 를 쓴다**

```gdscript
extends Node3D
class_name SignalField
# 신호등 기둥을 세우고 색을 칠한다. 위반 판정은 여기서 하지 않는다 —
# ViolationWatch 의 일이다.
#
# 한 교차로에는 진입 방향이 넷이다(축 2개 x 각 축의 양방향). 진입 방향마다
# 기둥 하나를 세우므로 seoul-100 기준 93 x 4 = 372 개다.

const UPDATE_RADIUS_M := 200.0
const POLE_HEIGHT := 5.5
const POLE_RADIUS := 0.12
const LAMP_RADIUS := 0.25
const LAMP_SPACING := 0.62
const STOP_LINE_MARGIN_M := 2.0
const DEFAULT_HALF_WIDTH := 7.5

# 적/황/녹 순. 켜진 등만 emission 을 켜고 나머지는 어둡게 둔다.
const LAMP_COLORS := [Color(0.85, 0.12, 0.10), Color(0.92, 0.72, 0.10),
	Color(0.15, 0.80, 0.30)]

var target: Node3D
var head_count := 0
var updated_count := 0

# [{"lamps": [MeshInstance3D x3], "offset": float, "axis": int, "phase": int}]
var _heads: Array = []
var _grid: Dictionary = {}     # Vector2i -> PackedInt32Array(_heads 인덱스)
var _on_materials: Array = []
var _off_materials: Array = []
var _lamp_mesh: SphereMesh
var _pole_mesh: CylinderMesh
var _board_mesh: BoxMesh
var _camera_mesh: BoxMesh
var _pole_material: StandardMaterial3D
var _camera_material: StandardMaterial3D

func build(signals: Array) -> void:
	_make_shared_resources()
	for entry in signals:
		if not entry.has("axis_deg") or entry["axis_deg"].size() < 2:
			# 구 버전 산출물. 조용히 건너뛴다 — 신호 없이도 주행은 된다.
			continue
		var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		var half := float(entry.get("half_width", DEFAULT_HALF_WIDTH))
		var offset := TrafficSignal.offset_for(center.x, center.z)
		var has_camera := bool(entry.get("camera", false))
		for axis in 2:
			var bearing := float(entry["axis_deg"][axis])
			for way in [1.0, -1.0]:
				# 진입 방향. 한 축의 양방향 모두에 기둥이 선다.
				var forward := TrafficSignal.direction_of(bearing) * way
				_add_head(center, forward, half, offset, axis, has_camera)

func _make_shared_resources() -> void:
	# 등마다 새 머티리얼을 만들면 372 x 3 = 1116 개가 된다. 6개를 공유하고
	# set_surface_override_material 로 바꿔 낀다.
	for color in LAMP_COLORS:
		var on := StandardMaterial3D.new()
		on.albedo_color = color
		on.emission_enabled = true
		on.emission = color
		on.emission_energy_multiplier = 2.0
		_on_materials.append(on)
		var off := StandardMaterial3D.new()
		off.albedo_color = color.darkened(0.75)
		_off_materials.append(off)

	_lamp_mesh = SphereMesh.new()
	_lamp_mesh.radius = LAMP_RADIUS
	_lamp_mesh.height = LAMP_RADIUS * 2.0
	_lamp_mesh.radial_segments = 8
	_lamp_mesh.rings = 4

	_pole_mesh = CylinderMesh.new()
	_pole_mesh.top_radius = POLE_RADIUS
	_pole_mesh.bottom_radius = POLE_RADIUS
	_pole_mesh.height = POLE_HEIGHT
	_pole_mesh.radial_segments = 6

	_board_mesh = BoxMesh.new()
	_board_mesh.size = Vector3(2.1, 0.7, 0.2)

	_camera_mesh = BoxMesh.new()
	_camera_mesh.size = Vector3(0.5, 0.3, 0.8)

	_pole_material = StandardMaterial3D.new()
	_pole_material.albedo_color = Color(0.25, 0.28, 0.26)

	_camera_material = StandardMaterial3D.new()
	_camera_material.albedo_color = Color(0.92, 0.92, 0.90)

func _add_head(center: Vector3, forward: Vector3, half: float,
		offset: float, axis: int, has_camera: bool) -> void:
	# forward 기준 오른쪽. Y 가 위인 좌표계에서 (x, z) 를 90° 돌린 것이다.
	var right := Vector3(-forward.z, 0.0, forward.x)
	var base := center - forward * (half + STOP_LINE_MARGIN_M) \
		+ right * maxf(half - 1.0, 1.0)

	var head := Node3D.new()
	add_child(head)
	head.global_position = base
	# 기둥의 -Z(고도트 기준 정면)가 진입하는 차를 마주보게 한다.
	head.look_at(base - forward, Vector3.UP)

	var pole := MeshInstance3D.new()
	pole.mesh = _pole_mesh
	pole.material_override = _pole_material
	pole.position = Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)
	head.add_child(pole)

	var board := MeshInstance3D.new()
	board.mesh = _board_mesh
	board.material_override = _pole_material
	board.position = Vector3(0.0, POLE_HEIGHT, 0.0)
	head.add_child(board)

	var lamps: Array = []
	for lamp_index in 3:
		var lamp := MeshInstance3D.new()
		lamp.mesh = _lamp_mesh
		lamp.position = Vector3((lamp_index - 1) * LAMP_SPACING,
			POLE_HEIGHT, -0.12)
		lamp.set_surface_override_material(0, _off_materials[lamp_index])
		head.add_child(lamp)
		lamps.append(lamp)

	if has_camera:
		# 실제 도로에도 "신호위반 단속중" 표지가 있어 운전자가 미리 안다.
		# 모르고 걸리는 게 아니라 알고 거는 도박이라야 저울질이 된다.
		var box := MeshInstance3D.new()
		box.mesh = _camera_mesh
		box.material_override = _camera_material
		box.position = Vector3(0.0, POLE_HEIGHT + 0.6, -0.2)
		head.add_child(box)

	var index := _heads.size()
	_heads.append({"lamps": lamps, "offset": offset, "axis": axis,
		"phase": -1})
	var cell := TrafficSignal.cell_of(base.x, base.z)
	if not _grid.has(cell):
		_grid[cell] = PackedInt32Array()
	_grid[cell].append(index)
	head_count += 1

func _physics_process(_delta: float) -> void:
	if target == null or _heads.is_empty():
		return
	var t := TrafficSignal.now()
	updated_count = 0
	for cell in TrafficSignal.cells_near(target.global_position, UPDATE_RADIUS_M):
		if not _grid.has(cell):
			continue
		for index in _grid[cell]:
			updated_count += 1
			var head: Dictionary = _heads[index]
			var phase := TrafficSignal.phase_at(head["offset"], head["axis"], t)
			if head["phase"] == int(phase):
				continue
			head["phase"] = int(phase)
			# Phase 는 GREEN=0, YELLOW=1, RED=2 이고 등은 적/황/녹 순이라
			# 인덱스를 뒤집는다.
			var lit := 2 - int(phase)
			for lamp_index in 3:
				var lamp: MeshInstance3D = head["lamps"][lamp_index]
				lamp.set_surface_override_material(0,
					_on_materials[lamp_index] if lamp_index == lit
					else _off_materials[lamp_index])
```

- [ ] **Step 2: 파싱되는지 확인한다**

Run: `tests/game/run_game_tests.sh test_traffic_signal`
Expected: `test_traffic_signal: OK`. `signal_field.gd` 에 문법 오류가 있으면 Godot 이 전역 클래스 등록 단계에서 `Parse Error` 를 찍는다. 출력에 `Parse Error` 가 있으면 실패로 본다.

- [ ] **Step 3: 임시 확인 스크립트로 기둥이 서는지 본다**

Run:
```bash
cat > /tmp/_signal_probe.gd <<'EOF'
extends Node3D
func _ready() -> void:
	var data := RouteData.load_route("seoul-seodaemun03")
	var field := SignalField.new()
	field.build(data.signals)
	add_child(field)
	print("신호 %d 개, 기둥 %d 개" % [data.signals.size(), field.head_count])
	get_tree().quit(0)
EOF
cp /tmp/_signal_probe.gd tests/game/_signal_probe.gd
cat > tests/game/_signal_probe.tscn <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/_signal_probe.gd" id="1"]

[node name="SignalProbe" type="Node3D"]
script = ExtResource("1")
EOF
godot --headless --import >/dev/null 2>&1 || true
godot --headless --quit-after 200 res://tests/game/_signal_probe.tscn 2>&1 | grep "기둥"
```
Expected: `신호 N 개, 기둥 M 개` 가 찍히고 `M == N * 4`.

- [ ] **Step 4: 확인 스크립트를 지운다**

Run: `rm -f tests/game/_signal_probe.gd tests/game/_signal_probe.gd.uid tests/game/_signal_probe.tscn`

- [ ] **Step 5: 커밋**

```bash
godot --headless --import >/dev/null 2>&1 || true
git status --porcelain project.godot && git checkout project.godot 2>/dev/null || true
git add scripts/signal_field.gd scripts/signal_field.gd.uid
git commit -m "feat: 신호등 기둥 생성과 근거리 색칠

진입 방향마다 기둥 하나를 세워 교차로당 4개다. 머티리얼 6개를 공유하고
반경 200 m 안의 기둥만 색을 검사한다. 단속 카메라 교차로는 기둥에 카메라
박스를 얹어 미리 보이게 했다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: 순찰 경찰차

**Files:**
- Create: `scripts/patrol_cars.gd`
- Test: `tests/game/test_violation.gd`, `tests/game/test_violation.tscn` (여기서 만들고 Task 7 이 채운다)

**Interfaces:**
- Consumes: 없음 (경로점 배열만 받는다)
- Produces:
  - `PatrolCars` (`extends Node3D`)
  - `const PATROL_SPEED_MPS := 11.0`, `const PATROL_SIGHT_M := 80.0`, `const CAR_COUNT := 2`
  - `func build(route: PackedVector3Array) -> void`
  - `func sees(point: Vector3) -> bool`
  - `var cars: Array[Node3D]` — 테스트가 위치를 직접 놓을 수 있게 공개한다

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_violation.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_violation.gd" id="1"]

[node name="TestViolation" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_violation.gd`:

```gdscript
extends TestCase
# 순찰 경찰차와 위반 판정. 가짜 신호 하나를 놓고 버스 대신 빈 Node3D 를
# 움직여 판정만 본다 — 물리를 끼우면 테스트가 느리고 불안정해진다.

func _ready() -> void:
	_test_patrol_follows_route()
	_test_patrol_sight()
	finish()

func _test_patrol_follows_route() -> void:
	var route := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0),
		Vector3(200.0, 0.0, 0.0), Vector3(300.0, 0.0, 0.0)])
	var patrol := PatrolCars.new()
	patrol.build(route)
	add_child(patrol)
	ok(patrol.cars.size() == PatrolCars.CAR_COUNT,
		"경찰차가 %d 대다" % patrol.cars.size())
	# 경로 위에 있어야 한다 — z 가 0 이고 x 가 0~300 사이.
	for car in patrol.cars:
		ok(absf(car.global_position.z) < 0.01,
			"경찰차가 경로를 벗어났다: %s" % str(car.global_position))
		ok(car.global_position.x >= -0.01 and car.global_position.x <= 300.01,
			"경찰차가 경로 밖 x 에 있다: %f" % car.global_position.x)
	# 두 대가 서로 다른 지점에서 출발한다.
	ok(absf(patrol.cars[0].global_position.x - patrol.cars[1].global_position.x) > 10.0,
		"경찰차 두 대가 겹쳐 있다")
	patrol.queue_free()

func _test_patrol_sight() -> void:
	var route := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(1000.0, 0.0, 0.0)])
	var patrol := PatrolCars.new()
	patrol.build(route)
	add_child(patrol)
	# 테스트가 위치와 방향을 직접 정한다. 0번만 남기고 나머지는 멀리 치운다.
	var car: Node3D = patrol.cars[0]
	car.global_position = Vector3.ZERO
	car.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)   # 북(-Z)을 본다
	for index in range(1, patrol.cars.size()):
		patrol.cars[index].global_position = Vector3(0.0, 0.0, 100000.0)

	ok(patrol.sees(Vector3(0.0, 0.0, -50.0)), "전방 50 m 를 못 본다")
	ok(not patrol.sees(Vector3(0.0, 0.0, -200.0)), "전방 200 m 를 본다")
	ok(not patrol.sees(Vector3(0.0, 0.0, 50.0)), "후방 50 m 를 본다")
	patrol.queue_free()
```

- [ ] **Step 2: 실패를 확인한다**

Run: `tests/game/run_game_tests.sh test_violation`
Expected: FAIL. `Identifier "PatrolCars" not declared`.

- [ ] **Step 3: `scripts/patrol_cars.gd` 를 쓴다**

```gdscript
extends Node3D
class_name PatrolCars
# 노선 위를 왕복하는 순찰 경찰차. 물리가 없다 — 경로 누적거리를 따라
# 위치만 옮긴다.
#
# 충돌면을 안 붙이는 이유는 버스가 들이받아 주행이 멈추는 쪽이 더 나쁘기
# 때문이다. 실제 차량과의 충돌은 6번 서브프로젝트(교통 AI)다.

const PATROL_SPEED_MPS := 11.0    # 약 40 km/h
const PATROL_SIGHT_M := 80.0
const CAR_COUNT := 2
const BODY_SIZE := Vector3(1.8, 1.4, 4.6)

var cars: Array[Node3D] = []

var _route: PackedVector3Array = []
var _cumulative: PackedFloat32Array = []
var _distances: PackedFloat32Array = []
var _directions: PackedInt32Array = []

func build(route: PackedVector3Array) -> void:
	if route.size() < 2:
		# 경로가 없으면 순찰도 없다. 조용히 아무것도 하지 않는다.
		return
	_route = route
	_cumulative = PackedFloat32Array()
	_cumulative.append(0.0)
	for index in range(1, route.size()):
		_cumulative.append(_cumulative[index - 1]
			+ route[index].distance_to(route[index - 1]))

	var total := _cumulative[_cumulative.size() - 1]
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.10, 0.18, 0.55)
	var beacon_material := StandardMaterial3D.new()
	beacon_material.albedo_color = Color(0.90, 0.10, 0.12)
	beacon_material.emission_enabled = true
	beacon_material.emission = Color(0.90, 0.10, 0.12)

	var body_mesh := BoxMesh.new()
	body_mesh.size = BODY_SIZE
	var beacon_mesh := BoxMesh.new()
	beacon_mesh.size = Vector3(1.0, 0.2, 0.3)

	# 두 대를 노선의 1/4 과 3/4 에 서로 반대 방향으로 놓는다.
	for index in CAR_COUNT:
		var car := Node3D.new()
		add_child(car)
		var body := MeshInstance3D.new()
		body.mesh = body_mesh
		body.material_override = body_material
		body.position = Vector3(0.0, BODY_SIZE.y * 0.5, 0.0)
		car.add_child(body)
		var beacon := MeshInstance3D.new()
		beacon.mesh = beacon_mesh
		beacon.material_override = beacon_material
		beacon.position = Vector3(0.0, BODY_SIZE.y + 0.1, 0.0)
		car.add_child(beacon)
		cars.append(car)
		_distances.append(total * (0.25 + 0.5 * index))
		_directions.append(1 if index == 0 else -1)
	_move_all()

func _physics_process(delta: float) -> void:
	if _route.size() < 2:
		return
	var total := _cumulative[_cumulative.size() - 1]
	for index in cars.size():
		var distance := _distances[index] + _directions[index] * PATROL_SPEED_MPS * delta
		# 끝에 닿으면 돌아온다. 노선 밖으로 나가면 위치 보간이 깨진다.
		if distance <= 0.0:
			distance = 0.0
			_directions[index] = 1
		elif distance >= total:
			distance = total
			_directions[index] = -1
		_distances[index] = distance
	_move_all()

func _move_all() -> void:
	for index in cars.size():
		var here := _sample(_distances[index])
		var ahead := _sample(clampf(_distances[index] + _directions[index] * 5.0,
			0.0, _cumulative[_cumulative.size() - 1]))
		var car := cars[index]
		car.global_position = here
		if here.distance_to(ahead) > 0.01:
			car.look_at(ahead, Vector3.UP)

func _sample(distance: float) -> Vector3:
	"""경로 누적거리 위의 점. 이분 탐색이라 경로점이 늘어도 싸다."""
	var low := 0
	var high := _cumulative.size() - 1
	while low + 1 < high:
		var mid := (low + high) / 2
		if _cumulative[mid] <= distance:
			low = mid
		else:
			high = mid
	var span := _cumulative[high] - _cumulative[low]
	if span <= 0.0:
		return _route[low]
	var ratio := clampf((distance - _cumulative[low]) / span, 0.0, 1.0)
	return _route[low].lerp(_route[high], ratio)

func sees(point: Vector3) -> bool:
	"""어느 경찰차든 point 를 전방 시야 안에 두고 있는가."""
	for car in cars:
		var to_point := point - car.global_position
		if to_point.length() > PATROL_SIGHT_M:
			continue
		# 고도트의 정면은 -Z 다.
		if (-car.global_transform.basis.z).dot(to_point) > 0.0:
			return true
	return false
```

- [ ] **Step 4: 통과를 확인한다**

Run: `tests/game/run_game_tests.sh test_violation`
Expected: `TEST_OK`, `test_violation: OK`.

- [ ] **Step 5: 커밋**

```bash
godot --headless --import >/dev/null 2>&1 || true
git status --porcelain project.godot && git checkout project.godot 2>/dev/null || true
git add scripts/patrol_cars.gd scripts/patrol_cars.gd.uid tests/game/test_violation.gd tests/game/test_violation.gd.uid tests/game/test_violation.tscn
git commit -m "feat: 노선을 왕복하는 순찰 경찰차

물리 없이 경로 누적거리만 따라간다. 버스가 들이받아 주행이 멈추는 쪽이 더
나쁘므로 충돌면을 붙이지 않았다. 실제 차량 충돌은 6번 서브프로젝트다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: 신호위반 판정

**Files:**
- Create: `scripts/violation_watch.gd`
- Test: `tests/game/test_violation.gd` (Task 6 에서 만든 파일에 추가)

**Interfaces:**
- Consumes: `TrafficSignal.*` (Task 3), `PatrolCars.sees(point: Vector3) -> bool` (Task 6)
- Produces:
  - `ViolationWatch` (`extends Node`)
  - `const WATCH_RADIUS_M := 60.0`, `const STOP_LINE_MARGIN_M := 2.0`
  - `signal violation(index: int, by_camera: bool)`
  - `signal busted`
  - `func build(signals: Array) -> void`
  - `var bus: Node3D`, `var patrol: PatrolCars`
  - `var violations := 0`, `var camera_violations := 0`, `var is_busted := false`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_violation.gd` 의 `_ready` 를 아래로 바꾸고, 새 함수들을 파일 끝에 추가한다.

```gdscript
func _ready() -> void:
	_test_patrol_follows_route()
	_test_patrol_sight()
	await _test_red_light_is_a_violation()
	await _test_green_light_is_not()
	await _test_yellow_light_is_not()
	await _test_counted_once()
	await _test_camera_counts_separately()
	await _test_patrol_busts()
	TrafficSignal.time_override = -1.0
	finish()
```

```gdscript
# 교차로 하나를 원점에 놓는다. 축 0 은 남북(방위 0), 축 1 은 동서(방위 90).
# 반폭 10 m 라 정지선은 중심에서 12 m 다.
func _signal_entry(has_camera: bool) -> Dictionary:
	return {"x": 0.0, "z": 0.0, "source": "synthesized", "roads": 4,
		"axis_deg": [0.0, 90.0], "half_width": 10.0, "camera": has_camera}

# 축 0 이 원하는 위상이 되는 시각을 고른다. offset_for(0, 0) 을 빼면 된다.
func _time_for(phase: int) -> float:
	var offset := TrafficSignal.offset_for(0.0, 0.0)
	var base := 0.0
	if phase == TrafficSignal.Phase.YELLOW:
		base = TrafficSignal.GREEN_S + 1.0
	elif phase == TrafficSignal.Phase.RED:
		base = TrafficSignal.GREEN_S + TrafficSignal.YELLOW_S + 1.0
	else:
		base = 1.0
	return base - offset + TrafficSignal.CYCLE_S * 100.0

# 버스 대신 빈 Node3D 를 북쪽(-Z)에서 남쪽(+Z)으로 두 걸음 옮긴다.
# 축 0 진행이라 축 0 의 신호를 본다.
func _drive_through(watch: ViolationWatch, mover: Node3D) -> void:
	mover.global_position = Vector3(0.0, 0.0, -20.0)
	mover.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await get_tree().physics_frame
	mover.global_position = Vector3(0.0, 0.0, -5.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

func _make_watch(has_camera: bool, phase: int) -> Array:
	TrafficSignal.time_override = _time_for(phase)
	var mover := Node3D.new()
	add_child(mover)
	var watch := ViolationWatch.new()
	watch.build([_signal_entry(has_camera)])
	watch.bus = mover
	add_child(watch)
	return [watch, mover]

func _test_red_light_is_a_violation() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	await _drive_through(watch, made[1])
	ok(watch.violations == 1, "적색 통과가 %d 회로 세어졌다" % watch.violations)
	watch.queue_free()
	made[1].queue_free()

func _test_green_light_is_not() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.GREEN)
	var watch: ViolationWatch = made[0]
	await _drive_through(watch, made[1])
	ok(watch.violations == 0, "녹색 통과가 위반으로 세어졌다")
	watch.queue_free()
	made[1].queue_free()

func _test_yellow_light_is_not() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.YELLOW)
	var watch: ViolationWatch = made[0]
	await _drive_through(watch, made[1])
	ok(watch.violations == 0, "황색 통과가 위반으로 세어졌다")
	watch.queue_free()
	made[1].queue_free()

func _test_counted_once() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	var mover: Node3D = made[1]
	await _drive_through(watch, mover)
	# 같은 자리에 더 머물러도 두 번 세면 안 된다.
	for i in 5:
		await get_tree().physics_frame
	ok(watch.violations == 1, "한 번 통과가 %d 회로 세어졌다" % watch.violations)
	watch.queue_free()
	mover.queue_free()

func _test_camera_counts_separately() -> void:
	var made := _make_watch(true, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	await _drive_through(watch, made[1])
	ok(watch.violations == 1, "카메라 교차로 위반이 안 세어졌다")
	ok(watch.camera_violations == 1,
		"카메라 위반이 %d 회다" % watch.camera_violations)
	watch.queue_free()
	made[1].queue_free()

func _test_patrol_busts() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	var mover: Node3D = made[1]
	var patrol := PatrolCars.new()
	patrol.build(PackedVector3Array([Vector3(0.0, 0.0, -1000.0),
		Vector3(0.0, 0.0, 1000.0)]))
	add_child(patrol)
	# 경찰차를 교차로 남쪽 30 m 에 두고 북쪽(오는 버스 쪽)을 보게 한다.
	patrol.cars[0].global_position = Vector3(0.0, 0.0, 30.0)
	patrol.cars[0].look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	for index in range(1, patrol.cars.size()):
		patrol.cars[index].global_position = Vector3(0.0, 0.0, 100000.0)
	patrol.set_physics_process(false)   # 테스트가 놓은 위치를 유지한다
	watch.patrol = patrol
	await _drive_through(watch, mover)
	ok(watch.is_busted, "경찰차 앞 위반인데 적발되지 않았다")
	watch.queue_free()
	mover.queue_free()
	patrol.queue_free()
```

- [ ] **Step 2: 실패를 확인한다**

Run: `tests/game/run_game_tests.sh test_violation`
Expected: FAIL. `Identifier "ViolationWatch" not declared`.

- [ ] **Step 3: `scripts/violation_watch.gd` 를 쓴다**

```gdscript
extends Node
class_name ViolationWatch
# 적색에 정지선을 넘었는지 본다. 그리지 않는다 — 표시는 ViolationHud 의 일이다.
#
# 황색 진입은 위반이 아니다. 황색 3초에 안전하게 설 수 있는 거리가 아니면
# 억울하고, 실제 단속도 이렇게 하지 않는다.

const WATCH_RADIUS_M := 60.0
const STOP_LINE_MARGIN_M := 2.0
const DEFAULT_HALF_WIDTH := 7.5

signal violation(index: int, by_camera: bool)
signal busted

var bus: Node3D
var patrol: PatrolCars

var violations := 0
var camera_violations := 0
var is_busted := false

var _signals: Array = []
var _grid: Dictionary = {}       # Vector2i -> PackedInt32Array(_signals 인덱스)
var _previous: Dictionary = {}   # 신호 인덱스 -> 직전 프레임의 부호 거리

func build(signals: Array) -> void:
	_signals = signals
	for index in range(signals.size()):
		var entry: Dictionary = signals[index]
		if not entry.has("axis_deg") or entry["axis_deg"].size() < 2:
			continue
		var cell := TrafficSignal.cell_of(float(entry["x"]), float(entry["z"]))
		if not _grid.has(cell):
			_grid[cell] = PackedInt32Array()
		_grid[cell].append(index)

func _physics_process(_delta: float) -> void:
	if bus == null or is_busted or _grid.is_empty():
		return
	var here := bus.global_position
	# 고도트의 정면은 -Z 다.
	var forward := -bus.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var heading := TrafficSignal.bearing_of(forward)
	var t := TrafficSignal.now()

	var seen := {}
	for cell in TrafficSignal.cells_near(here, WATCH_RADIUS_M):
		if not _grid.has(cell):
			continue
		for index in _grid[cell]:
			var entry: Dictionary = _signals[index]
			var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
			if center.distance_to(Vector3(here.x, 0.0, here.z)) > WATCH_RADIUS_M:
				continue
			seen[index] = true
			var half := float(entry.get("half_width", DEFAULT_HALF_WIDTH))
			# 버스에서 교차로 중심으로 가는 방향을 양으로 잡은 부호 거리.
			# 정지선은 중심에서 진입 방향 반대로 half + 2 m 떨어져 있다.
			# ponytail: 교차로 바로 옆에서 크게 꺾으면 forward 가 확 돌아
			# 부호가 뛸 수 있다. 실제로 그러려면 정지선 위에서 제자리 선회를
			# 해야 해서 놔둔다. 오검출이 보이면 직전 속도 방향을 쓴다.
			var along := (center - here).dot(forward)
			var signed := along - (half + STOP_LINE_MARGIN_M)
			var was: float = _previous.get(index, signed)
			_previous[index] = signed
			if was > 0.0 and signed <= 0.0:
				_on_enter(index, entry, heading, t)

	# 반경을 벗어난 신호는 기억에서 지운다. 안 지우면 한 바퀴 돌아왔을 때
	# 옛 부호 거리와 비교해 헛 위반이 난다.
	for index in _previous.keys():
		if not seen.has(index):
			_previous.erase(index)

func _on_enter(index: int, entry: Dictionary, heading: float, t: float) -> void:
	var axis := TrafficSignal.axis_for(heading, entry["axis_deg"])
	var offset := TrafficSignal.offset_for(float(entry["x"]), float(entry["z"]))
	if TrafficSignal.phase_at(offset, axis, t) != TrafficSignal.Phase.RED:
		return
	violations += 1
	var by_camera := bool(entry.get("camera", false))
	if by_camera:
		camera_violations += 1
	violation.emit(index, by_camera)
	# 카메라는 과태료지 현장 제지가 아니다. 주행을 멈추는 것은 경찰뿐이다.
	if patrol != null and patrol.sees(bus.global_position):
		is_busted = true
		busted.emit()
```

- [ ] **Step 4: 통과를 확인한다**

Run: `tests/game/run_game_tests.sh test_violation`
Expected: `TEST_OK`, `test_violation: OK`.

- [ ] **Step 5: 커밋**

```bash
godot --headless --import >/dev/null 2>&1 || true
git status --porcelain project.godot && git checkout project.godot 2>/dev/null || true
git add scripts/violation_watch.gd scripts/violation_watch.gd.uid tests/game/test_violation.gd
git commit -m "feat: 적색 정지선 통과 판정

정지선까지의 부호 거리가 양에서 음으로 바뀌는 프레임에 위상을 본다. 황색
진입은 위반이 아니다. 경찰차가 보고 있으면 busted 를 낸다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 8: HUD 와 주행 씬 배선

**Files:**
- Create: `scripts/violation_hud.gd`
- Modify: `scripts/drive.gd:9-14` (변수), `scripts/drive.gd:47` (`_ready` 끝), `scripts/drive.gd:60-73` (`_physics_process`)
- Test: `tests/game/drive_smoke.gd`

**Interfaces:**
- Consumes: `SignalField.build/target/head_count/updated_count` (Task 5), `PatrolCars.build` (Task 6), `ViolationWatch.build/bus/patrol/violation/busted/violations/camera_violations/is_busted` (Task 7), `RouteData.signals` (Task 4), `Bus.apply_axes(steer, throttle, brake, reverse, delta)`
- Produces:
  - `ViolationHud` (`extends CanvasLayer`)
  - `func on_violation(index: int, by_camera: bool) -> void`
  - `func on_busted() -> void`
  - `Drive.signal_field: SignalField`, `Drive.patrol: PatrolCars`, `Drive.watch: ViolationWatch`, `Drive.hud: ViolationHud`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/drive_smoke.gd` 의 `_report()` 안, `ok(driven >= DRIVE_MIN_M, ...)` 와 `finish()` 사이에 넣는다. 들여쓰기는 탭 하나다.

```gdscript
	# 신호등이 섰는지, 근거리 컬링이 실제로 도는지 본다.
	ok(drive.signal_field != null, "SignalField 가 없다")
	ok(drive.watch != null, "ViolationWatch 가 없다")
	ok(drive.patrol != null, "PatrolCars 가 없다")
	ok(drive.signal_field.head_count == drive.data.signals.size() * 4,
		"기둥이 %d 개인데 신호는 %d 개다"
		% [drive.signal_field.head_count, drive.data.signals.size()])
	ok(drive.signal_field.updated_count > 0, "기둥을 하나도 갱신하지 않았다")
	ok(drive.signal_field.updated_count < drive.signal_field.head_count,
		"근거리 컬링이 안 걸려 기둥 %d 개를 전부 갱신했다"
		% drive.signal_field.head_count)
	# 신호 기둥에는 충돌면이 없어야 한다. 있으면 인도 위 기둥에 버스가 걸린다.
	ok(drive.signal_field.find_children("*", "StaticBody3D", true, false).is_empty(),
		"신호 기둥에 충돌면이 붙었다")
```

`drive_smoke` 는 `drive.tscn` 을 그대로 인스턴스화하므로 `Drive._ready` 가 신호 노드들을 만든다. 따로 조립하지 않는다.

- [ ] **Step 2: 실패를 확인한다**

Run: `tests/game/run_game_tests.sh drive_smoke`
Expected: FAIL. `Invalid access to property or key 'signal_field'`.

- [ ] **Step 3: `scripts/violation_hud.gd` 를 쓴다**

```gdscript
extends CanvasLayer
class_name ViolationHud
# 위반 횟수와 게임 오버를 보여준다. 판정하지 않는다 — ViolationWatch 의 일이다.
#
# 2번에서 만든 터치 컨트롤이 화면 아래와 양옆을 쓰므로 좌상단만 쓴다.

const FLASH_S := 0.4

var violations := 0
var camera_violations := 0

var _label: Label
var _flash: ColorRect
var _flash_left := 0.0
var _over: Control

func _ready() -> void:
	layer = 10

	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	_label.visible = false
	add_child(_label)

	_flash = ColorRect.new()
	_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_over = _make_game_over()
	add_child(_over)

func _make_game_over() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "단속 적발 — 주행 종료"
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "R: 다시 시작"
	hint.add_theme_font_size_override("font_size", 20)
	box.add_child(hint)
	panel.add_child(box)
	return panel

func on_violation(_index: int, by_camera: bool) -> void:
	violations += 1
	if by_camera:
		camera_violations += 1
	if camera_violations > 0:
		_label.text = "위반 %d회 (카메라 %d회)" % [violations, camera_violations]
	else:
		_label.text = "위반 %d회" % violations
	_label.visible = true
	_flash_left = FLASH_S

func on_busted() -> void:
	_over.visible = true

func _process(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	_flash.color.a = 0.45 * (_flash_left / FLASH_S)
```

- [ ] **Step 4: `scripts/drive.gd` 를 배선한다**

변수 선언부에 추가한다.

```gdscript
var signal_field: SignalField
var patrol: PatrolCars
var watch: ViolationWatch
var hud: ViolationHud
```

`_ready` 의 `add_child(touch)` 아래에 추가한다.

```gdscript
	signal_field = SignalField.new()
	signal_field.build(data.signals)
	signal_field.target = bus
	add_child(signal_field)

	patrol = PatrolCars.new()
	patrol.build(data.route)
	add_child(patrol)

	watch = ViolationWatch.new()
	watch.build(data.signals)
	watch.bus = bus
	watch.patrol = patrol
	add_child(watch)

	hud = ViolationHud.new()
	add_child(hud)
	watch.violation.connect(hud.on_violation)
	watch.busted.connect(hud.on_busted)
```

`_physics_process` 의 `if bus == null or input == null: return` 아래에 추가한다.

```gdscript
	if watch != null and watch.is_busted:
		# 적발되면 조향과 가속을 끊고 브레이크만 건다. 버스가 서서히 선다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
```

- [ ] **Step 5: 통과를 확인한다**

Run: `tests/game/run_game_tests.sh drive_smoke`
Expected: `TEST_OK`, `drive_smoke: OK`.

- [ ] **Step 6: 커밋**

```bash
godot --headless --import >/dev/null 2>&1 || true
git status --porcelain project.godot && git checkout project.godot 2>/dev/null || true
git add scripts/violation_hud.gd scripts/violation_hud.gd.uid scripts/drive.gd tests/game/drive_smoke.gd
git commit -m "feat: 위반 HUD 와 주행 씬 배선

좌상단에 위반 횟수, 위반 순간 붉은 플래시, 적발 시 게임 오버 오버레이.
적발되면 조향과 가속을 끊고 브레이크만 걸어 버스를 세운다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 9: 회귀 검증과 문서

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1~8 전부
- Produces: 없음 (검증과 문서)

- [ ] **Step 1: 파이썬 테스트 전체**

Run: `./run_tests.sh 2>&1 | grep -E "^(OK|FAILED|Ran )"`
Expected: `Ran 137 tests`, `OK`.

- [ ] **Step 2: 게임 테스트 전체**

Run: `tests/game/run_game_tests.sh`
Expected: 8개 씬 전부 `OK`.

- [ ] **Step 3: 3개 노선 주행 검증**

Run: `tests/bake/run_verify.sh`
Expected: 세 노선 모두 `VERIFY_OK`. 하나라도 `VERIFY_FAIL: 주행 거리` 가 나오면 신호 기둥이 주행을 막은 것이다. 기둥에 충돌면이 없으므로 그럴 리가 없지만, 나온다면 기둥 위치(`half - 1.0` 오른쪽)가 차도 안으로 들어간 것이니 `SignalField._add_head` 의 `right` 오프셋을 늘린다.

- [ ] **Step 4: fps 재측정**

`measure_fps.gd` 는 창 모드 전용이다 — 헤드리스는 렌더링을 안 해서 숫자가 의미 없다. `--headless` 없이 돌린다. 약 33초 걸린다.

Run: `godot res://tests/game/measure_fps.tscn -- --route=seoul-100 2>&1 | grep fps`
Expected: `fps 평균 N, 최저 M` 한 줄. 평균 60 이상, 최저 55 이상. 직전 측정은 평균 119.7 / 최저 118.0 이었다(vsync 상한). 기둥 372개 x 5 메쉬가 늘었으므로 떨어졌을 수 있다. 기준을 못 넘으면 `SignalField` 의 등판과 등을 한 메쉬로 합치거나 `UPDATE_RADIUS_M` 를 줄인다.

창을 띄울 수 없는 환경이면 이 단계를 건너뛰고 사용자에게 직접 돌려 달라고 알린다 — 조용히 통과로 처리하지 않는다.

- [ ] **Step 5: `README.md` 를 고친다**

`## 게임 실행` 절 끝(시점 조작 설명 뒤, `## 테스트` 앞)에 한 단락을 넣는다.

```markdown
교차로에는 신호등이 선다. 적색에 정지선을 넘으면 위반으로 세어져 좌상단에
표시된다. 기둥에 흰 카메라 박스가 달린 교차로는 무인 단속 구간이라 위반이
따로 집계된다. 노선에는 순찰 경찰차 두 대가 돌아다니는데, 그 앞에서 신호를
위반하면 그 자리에서 주행이 끝난다. `R` 로 다시 시작한다.
```

`## 노선 굽기` 절 끝에 산출물 설명을 더한다.

```markdown
`route_<id>.json` 의 `signals` 는 교차로마다 좌표, 두 축의 방위각(`axis_deg`),
가장 넓은 갈래의 반폭(`half_width`), 단속 카메라 설치 여부(`camera`)를 담는다.
OSM 의 `highway=traffic_signals` 태그는 서울에서 거의 비어 있고 단속 카메라는
아예 없어서, 주요도로가 4갈래 이상 만나는 교차점에서 합성한다.
```

`## 문서` 절 목록 끝에 두 줄을 더한다.

```markdown
- 설계: `docs/superpowers/specs/2026-09-23-signals-violations-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-23-signals-violations.md`
```

- [ ] **Step 6: 커밋**

```bash
git status --porcelain project.godot && git checkout project.godot 2>/dev/null || true
git add README.md
git commit -m "docs: 신호·위반·단속 설명 추가

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 7: 작업 트리가 깨끗한지 확인한다**

Run: `git status --porcelain`
Expected: 빈 출력. `project.godot` 이 남아 있으면 `git checkout project.godot`.
