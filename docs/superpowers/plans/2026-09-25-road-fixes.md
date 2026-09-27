# 도로·교통 수정 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 왕복 도로 차선을 짝수로 맞추고, 노선 차량이 방향별 모든 차선을 쓰며 막히면 차선을 바꾸고, 일방통행 구간에는 마주 오는 차가 없고, 교차 차량은 실제 도로 갈래 위만 달리며, 신호 교차로에 정지선이 보이게 한다.

**Architecture:** bake(파이썬)가 경로 점별 차선 수·일방통행·주행선 오프셋과 신호별 갈래(arms)를 json 에 더 쓴다. 게임은 `RouteData` 가 그것을 읽어 도로 중심선을 되짚고, `Traffic` 은 중심선 위 두 도로(정방향·역방향)에서 차마다 가로 위치(`side_m`)를 들고 달린다. 교차 차선과 정지선은 갈래 선을 따른다.

**Tech Stack:** Python 3 (unittest), Godot 4.7.2 GDScript (헤드리스 테스트).

**Spec:** `docs/superpowers/specs/2026-09-25-road-fixes-design.md`

## Global Constraints

- 파이썬 테스트: `python3 -m unittest discover -s tests -t .` 전부 OK.
- 게임 테스트: `tests/game/run_game_tests.sh [scene...]` 가 `TEST_OK`. godot 실행 뒤마다 `git checkout -q project.godot`.
- 새 `.gd` 파일은 `/opt/homebrew/bin/godot --headless --import` 로 `.uid` 를 만든다. `.uid` 도 같이 커밋한다.
- 좌표: x 동, z 남. 진행 방향 (fx, fz) 의 오른쪽은 (-fz, fx), 왼쪽은 (fz, -fx).
- `LANE_WIDTH = 3.2`, 왕복 차선 수는 `max(2, 2*ceil(x/2 - 0.5))`(x 는 lanes 태그 또는 폭/3.2), 일방통행은 `max(1, round(x))`.
- 가장 바깥 차선 중앙 오프셋: `w/2 - w/(2n)`.
- 게임 상수: `LANE_SHIFT_MPS = 1.2`, `CHANGE_COOLDOWN_S = 4`, 막힘 간격 30 m·속도 70%, 정지선 앞 25 m·뒤 10 m 변경 금지, 앞 간격 이득 10 m, 뒤 간격 `8 + 뒤차 속도 × 1`, 가로 겹침 2.4 m, 버스 가로 겹침 `1.25 + 0.9 + 0.3`, `ARM_LENGTH_M = 60`.
- 커밋은 파일 이름을 명시해 `git add`. 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 코드 주석은 한국어 문장.

---

### Task 1: 왕복 차선 수 짝수

**Files:**
- Modify: `tools/osmbake/mesh.py` (`lane_count`, 새 `outer_lane_offset`)
- Test: `tests/osmbake/test_mesh.py` (`TestLaneCount`)

**Interfaces:**
- Produces: `lane_count(tags) -> int`, `outer_lane_offset(width: float, lanes: int) -> float`

- [ ] **Step 1: 테스트** — `TestLaneCount` 를 바꾼다.

```python
class TestLaneCount(unittest.TestCase):
    def test_lanes_태그가_짝수면_그대로(self):
        self.assertEqual(lane_count({"highway": "primary", "lanes": "6"}), 6)

    def test_왕복_홀수_lanes_는_적은_짝수로(self):
        self.assertEqual(lane_count({"highway": "primary", "lanes": "7"}), 6)
        self.assertEqual(lane_count({"highway": "primary", "lanes": "3"}), 2)

    def test_일방통행은_홀수를_그대로(self):
        self.assertEqual(lane_count({"highway": "primary", "lanes": "3",
                                     "oneway": "yes"}), 3)

    def test_폭에서_짝수로_되짚는다(self):
        self.assertEqual(lane_count({"highway": "primary"}), 6)      # 20 m
        self.assertEqual(lane_count({"highway": "secondary"}), 4)    # 15 m
        self.assertEqual(lane_count({"highway": "service"}), 2)
        self.assertEqual(lane_count({"highway": "residential",
                                     "width": "9.6"}), 2)
        self.assertEqual(lane_count({"highway": "residential",
                                     "width": "19.2"}), 6)

    def test_가장_바깥_차선_중앙(self):
        self.assertAlmostEqual(outer_lane_offset(15.0, 4), 5.625)
        self.assertAlmostEqual(outer_lane_offset(7.0, 2), 1.75)
        self.assertAlmostEqual(outer_lane_offset(4.0, 1), 0.0)
```

(`width` 태그를 `road_width` 가 읽는지 먼저 확인한다. 안 읽으면 그 두 줄은 `lanes` 없이 폭이 9.6/19.2 인 등급으로 바꾼다.)

- [ ] **Step 2: 실패 확인** — `python3 -m unittest tests.osmbake.test_mesh -v` → `lanes 7` 과 `outer_lane_offset` import 실패.

- [ ] **Step 3: 구현**

```python
def lane_count(tags: dict) -> int:
    """차선 수. lanes 태그가 없으면 폭에서 되짚는다.

    왕복 도로는 가장 가까운 짝수(최소 2, 딱 중간이면 적은 쪽)로 맞춘다. 중앙선을
    오프셋 0 에 그리므로 홀수면 중앙선이 차선 한복판을 가른다. 서울의 홀수
    lanes 는 대개 중앙 회전 차로를 센 것이다.
    """
    value = None
    lanes = tags.get("lanes")
    if lanes is not None:
        try:
            value = int(lanes)
        except (TypeError, ValueError):
            value = None
        if value is not None and value < 1:
            value = None
    if value is None:
        value = road_width(tags) / LANE_WIDTH
    if tags.get("oneway") in ONEWAY_VALUES:
        return max(1, round(value))
    return max(2, 2 * math.ceil(value / 2 - 0.5))


def outer_lane_offset(width: float, lanes: int) -> float:
    """도로 중심에서 가장 바깥(오른쪽) 차선 한가운데까지. 왕복·일방통행 같은 식이다."""
    return width / 2.0 - width / (2.0 * lanes)
```

- [ ] **Step 4: 통과 확인** — 같은 명령, 그리고 전체 파이썬 테스트.
- [ ] **Step 5: 커밋** — `git add tools/osmbake/mesh.py tests/osmbake/test_mesh.py`, `fix: 왕복 도로 차선 수를 짝수로 맞춘다`.

### Task 2: 경로 점별 차선 수·일방통행·주행선 오프셋

**Files:**
- Modify: `tools/osmbake/graph.py` (`Edge.oneway`, `Edge.lanes`)
- Modify: `tools/osmbake/routing.py` (`path_lanes`, `drive_offsets`, `offset_right`)
- Modify: `tools/osmbake/cli.py` (주행선 오프셋)
- Modify: `tools/osmbake/emit.py` (`route_lanes`, `route_oneway`, `route_offset`)
- Test: `tests/osmbake/test_graph.py`, `tests/osmbake/test_routing.py`, `tests/osmbake/test_emit.py`

**Interfaces:**
- Consumes: `lane_count`, `outer_lane_offset` (Task 1)
- Produces: `Edge(..., width, oneway: bool = False, lanes: int = 2)`, `path_lanes(edges) -> list[tuple[int, bool]]`, `drive_offsets(path_xz, offsets) -> list[float]`, `write_route_json(..., route_lanes, route_oneway, route_offset, ...)`. json 키 `route_lanes`(int), `route_oneway`(0/1), `route_offset`(m, 소수 둘째).

- [ ] **Step 1: 테스트**

`test_graph.py`:
```python
    def test_일방통행_엣지는_oneway(self):
        graph = build_graph([way(1, [1, 2], [(37.5, 127.0), (37.5, 127.001)],
                                 oneway="yes", lanes="3")])
        edge = graph.adj[1][0]
        self.assertTrue(edge.oneway)
        self.assertEqual(edge.lanes, 3)

    def test_왕복_엣지는_oneway_아님(self):
        graph = build_graph([way(1, [1, 2], [(37.5, 127.0), (37.5, 127.001)],
                                 highway="secondary")])
        self.assertFalse(graph.adj[1][0].oneway)
        self.assertEqual(graph.adj[1][0].lanes, 4)
```

`test_routing.py` (`TestPathWidths` 옆):
```python
class TestPathLanes(unittest.TestCase):
    def test_경계_점은_폭을_낸_엣지를_따른다(self):
        wide = Edge(1, 2, (1, 2), 10.0, "primary", 1, False, 20.0, False, 6)
        narrow = Edge(2, 3, (2, 3, 4), 10.0, "residential", 2, False, 7.0, True, 1)
        self.assertEqual(path_lanes([wide, narrow]),
                         [(6, False), (1, True), (1, True), (1, True)])
        self.assertEqual(len(path_lanes([wide, narrow])),
                         len(path_widths(None, [wide, narrow])))

    def test_넓어지는_경계는_앞_엣지를_따른다(self):
        narrow = Edge(1, 2, (1, 2), 10.0, "residential", 1, False, 7.0, False, 2)
        wide = Edge(2, 3, (2, 3), 10.0, "primary", 2, False, 20.0, False, 6)
        self.assertEqual(path_lanes([narrow, wide]),
                         [(2, False), (2, False), (6, False)])


class TestDriveOffsets(unittest.TestCase):
    def test_곧은_길은_그대로(self):
        path = [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0)]
        self.assertEqual(drive_offsets(path, [5.625] * 3), [5.625] * 3)

    def test_급커브_꼭짓점은_0(self):
        path = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)]
        self.assertEqual(drive_offsets(path, [1.75] * 3), [0.0] * 3)
```
(`path_widths` 가 `graph` 를 쓰지 않으면 `None` 으로 부른다. 쓰면 `build_graph([])` 를 넘긴다.)

`test_emit.py`: `_write` 기본값에 `route_lanes=[2, 2]`, `route_oneway=[False, False]`, `route_offset=[1.75, 1.75]` 를 더하고,
```python
    def test_차로_정보_길이가_다르면_거부(self):
        for key in ("route_lanes", "route_oneway", "route_offset"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self._write(**{key: [1]})

    def test_차로_정보를_쓴다(self):
        payload = self._write(route_oneway=[True, False])
        self.assertEqual(payload["route_lanes"], [2, 2])
        self.assertEqual(payload["route_oneway"], [1, 0])
        self.assertEqual(payload["route_offset"], [1.75, 1.75])
```
키 목록 테스트에 세 키를 더한다.

- [ ] **Step 2: 실패 확인** — `python3 -m unittest tests.osmbake.test_graph tests.osmbake.test_routing tests.osmbake.test_emit`.

- [ ] **Step 3: 구현**

`graph.py`: `from .mesh import lane_count, road_width`. `Edge` 끝에
```python
    # 반대 방향 엣지가 없는 도로. 마주 오는 차를 두지 않는다.
    oneway: bool = False
    lanes: int = 2
```
`build_graph` 에서 `is_oneway = not (forward and backward)`, `lanes = lane_count(tags)`, 두 `Edge(...)` 호출 끝에 `width, is_oneway, lanes`.

`routing.py`:
```python
def path_lanes(edges: list[Edge]) -> list[tuple[int, bool]]:
    """path_widths 와 같은 길이의 (차선 수, 일방통행) 목록.

    두 도로가 만나는 점은 path_widths 가 그 점의 폭을 가져온 엣지를 따른다.
    폭과 차선 수가 다른 도로에서 오면 차선 중앙이 도로 밖으로 나간다.
    """
    lanes: list[tuple[int, bool]] = []
    previous = None
    for edge in edges:
        count = len(edge.node_ids)
        if lanes:
            if edge.width < previous.width:
                lanes[-1] = (edge.lanes, edge.oneway)
            count -= 1
        lanes += [(edge.lanes, edge.oneway)] * count
        previous = edge
    return lanes


def drive_offsets(path_xz: list[tuple[float, float]],
                  offsets: list[float]) -> list[float]:
    """offset_right 가 실제로 쓰는 오프셋. 급커브 꼭짓점과 이웃은 0 이다.

    급커브 꼭짓점과 그 이웃은 중심선에 둔다. 우회전이면 우측 차선이 커브
    안쪽이라 반경이 더 줄어 버스가 연석을 넘는다. 꼭짓점만 풀면 이웃 점과
    사이에 꺾임이 생긴다. 실제 버스도 이런 데서는 크게 돈다.
    """
    return [0.0 if max(_turn_deg(path_xz, near)
                       for near in (index - 1, index, index + 1)) > SHARP_TURN_DEG
            else offsets[index]
            for index in range(len(path_xz))]
```
`offset_right` 는 본문 루프에서 `distance = drive_offsets(path_xz, offsets)[index]` 대신 루프 앞에서 한 번 `distances = drive_offsets(path_xz, offsets)` 를 구해 쓰고, 급커브 주석은 `drive_offsets` 로 옮긴다.

`cli.py`:
```python
    widths = path_widths(graph, edges)
    lanes = path_lanes(edges)
    # 주행선은 가장 바깥 차선 한가운데다. 중심선을 그대로 달리면 중앙선 위를
    # 타고, 차선 경계에 두면 점선을 밟는다. 왕복 2차선(7 m)이면 1.75 m, 왕복
    # 4차선(15 m)이면 5.625 m 다.
    offsets = drive_offsets(route_xz, [
        outer_lane_offset(width, count)
        for width, (count, _) in zip(widths, lanes)])
    drive_xz = offset_right(route_xz, offsets)
```
`write_route_json(..., route_width=widths, route_lanes=[c for c, _ in lanes], route_oneway=[o for _, o in lanes], route_offset=offsets, ...)`. import 에 `drive_offsets, path_lanes`, `from .mesh import outer_lane_offset`(이미 `mesh_mod` 가 있으면 `mesh_mod.outer_lane_offset`).

`emit.py`: 키워드 인자 `route_lanes, route_oneway, route_offset` 추가.
```python
    for key, values in (("route_width", route_width), ("route_lanes", route_lanes),
                        ("route_oneway", route_oneway),
                        ("route_offset", route_offset)):
        if len(values) != len(route_xz):
            raise ValueError(f"{key} {len(values)}개, route {len(route_xz)}개")
```
payload 에 `"route_lanes": [int(n) for n in route_lanes]`, `"route_oneway": [1 if o else 0 for o in route_oneway]`, `"route_offset": [round(o, 2) for o in route_offset]` 를 `route_width` 뒤에.

- [ ] **Step 4: 통과 확인** — 전체 파이썬 테스트.
- [ ] **Step 5: 커밋** — `feat: 경로 점별 차선 수와 일방통행, 바깥 차선 주행선을 굽는다`.

### Task 3: 신호 교차로 갈래

**Files:**
- Modify: `tools/osmbake/corridor.py` (`ARM_LENGTH_M`, `describe` 에 `arms`)
- Test: `tests/osmbake/test_corridor.py`

**Interfaces:**
- Produces: 신호 항목 `arms: [{"points": [[x, z], ...], "width": float, "inbound": bool, "outbound": bool}]`. 첫 점은 교차로 노드, 길이 ≤ 60 m. 노드를 못 찾으면 `[]`.

- [ ] **Step 1: 테스트**

```python
class TestSignalArms(unittest.TestCase):
    def setUp(self):
        self.projector = Projector(37.500, 127.000)
        self.path = project_path([(37.500, 127.000), (37.500, 127.002)],
                                 self.projector)
        # T자: 서(왕복), 동(일방통행, 교차로에서 나가기만), 북(왕복, 짧은 조각 둘)
        self.elements = [
            way(1, [10, 50], [(37.500, 127.0000), (37.500, 127.0010)]),
            way(2, [50, 11], [(37.500, 127.0010), (37.500, 127.0020)],
                oneway="yes"),
            way(3, [50, 12], [(37.500, 127.0010), (37.5002, 127.0010)]),
            way(4, [12, 13], [(37.5002, 127.0010), (37.5010, 127.0010)]),
        ]
        node = {"type": "node", "id": 99, "lat": 37.500, "lon": 127.0010,
                "tags": {"highway": "traffic_signals"}}
        self.signal = signal_candidates(build_graph(self.elements), [node],
                                        self.projector, self.path, 250.0)[0]

    def _length(self, points):
        return sum(math.dist(a, b) for a, b in zip(points, points[1:]))

    def test_갈래는_조각마다_하나(self):
        self.assertEqual(len(self.signal["arms"]), 3)

    def test_갈래는_교차로_노드에서_시작하고_60m_이내(self):
        center = self.projector.to_xz(37.500, 127.0010)
        for arm in self.signal["arms"]:
            self.assertAlmostEqual(arm["points"][0][0], center[0], places=1)
            self.assertAlmostEqual(arm["points"][0][1], center[1], places=1)
            self.assertLessEqual(self._length(arm["points"]), 60.01)

    def test_짧은_조각은_곧은_이음으로_이어_60m(self):
        north = [a for a in self.signal["arms"] if a["points"][-1][1] < -1.0][0]
        self.assertAlmostEqual(self._length(north["points"]), 60.0, places=1)

    def test_일방통행_갈래는_한_방향만(self):
        east = [a for a in self.signal["arms"] if a["points"][-1][0] > 1.0][0]
        self.assertEqual((east["inbound"], east["outbound"]), (False, True))
        west = [a for a in self.signal["arms"] if a["points"][-1][0] < -1.0][0]
        self.assertEqual((west["inbound"], west["outbound"]), (True, True))

    def test_노드를_못_찾으면_빈_갈래(self):
        node = {"type": "node", "id": 9, "lat": 37.5000, "lon": 127.0010,
                "tags": {"highway": "traffic_signals"}}
        signal = signal_candidates(build_graph([]), [node], self.projector,
                                   self.path, 250.0)[0]
        self.assertEqual(signal["arms"], [])
```
(`import math` 추가. 서 갈래는 88 m 조각이라 60 m 에서 잘리고, 동 갈래도 같다. 북 갈래는 22 m + 89 m 조각을 이어 60 m.)

- [ ] **Step 2: 실패 확인** — `python3 -m unittest tests.osmbake.test_corridor` → `KeyError: 'arms'`.

- [ ] **Step 3: 구현** — `corridor.py`:

```python
# 교차로 갈래를 따라가는 길이. 교차 차선과 정지선이 이 선을 쓴다.
ARM_LENGTH_M = 60.0
# 짧은 조각 끝에서 다음 조각으로 이어 갈 때 허용하는 꺾임.
ARM_CONTINUE_DEG = 45.0
```
`signal_candidates` 안, `node_xz` 다음:
```python
    def xz_of(node_id):
        if node_id not in node_xz:
            node_xz[node_id] = projector.to_xz(*graph.coords[node_id])
        return node_xz[node_id]

    def chunk_key(edge):
        # 같은 조각의 정방향·역방향 엣지는 한 갈래다.
        return (edge.way_id, frozenset(edge.node_ids))

    def oriented(edge, node_id):
        return edge.node_ids if edge.start == node_id else edge.node_ids[::-1]

    def arm_points(first_edge, node_id):
        ids = list(oriented(first_edge, node_id))
        seen = {chunk_key(first_edge)}
        points = [xz_of(n) for n in ids]
        length = sum(math.dist(a, b) for a, b in zip(points, points[1:]))
        while length < ARM_LENGTH_M:
            tail = ids[-1]
            heading = _bearing_deg(*points[-2], *points[-1])
            best, best_delta = None, ARM_CONTINUE_DEG
            for edge in incident.get(tail, []):
                if chunk_key(edge) in seen:
                    continue
                nxt = oriented(edge, tail)
                delta = abs((_bearing_deg(*xz_of(nxt[0]), *xz_of(nxt[1]))
                             - heading + 180.0) % 360.0 - 180.0)
                if delta <= best_delta:
                    best, best_delta = edge, delta
            if best is None:
                break
            seen.add(chunk_key(best))
            more = list(oriented(best, tail))[1:]
            ids += more
            for n in more:
                length += math.dist(points[-1], xz_of(n))
                points.append(xz_of(n))
        return _cut_at(points, ARM_LENGTH_M)

    def arms_of(node_id):
        groups: dict = {}
        for edge in incident[node_id]:
            if edge.start == edge.end:
                continue
            arm = groups.setdefault(chunk_key(edge), {
                "edge": edge, "inbound": False, "outbound": False})
            arm["inbound"] |= edge.end == node_id
            arm["outbound"] |= edge.start == node_id
        return [{"points": [[round(x, 2), round(z, 2)]
                            for x, z in arm_points(arm["edge"], node_id)],
                 "width": round(arm["edge"].width, 2),
                 "inbound": arm["inbound"], "outbound": arm["outbound"]}
                for arm in groups.values()]
```
`describe` 는 `None` 이면 `"arms": []` 를 더하고, 아니면 반환 사전에 `"arms": arms_of(node_id)`. 모듈 함수:
```python
def _cut_at(points, limit):
    """폴리라인을 limit m 에서 자른다."""
    kept = [points[0]]
    travelled = 0.0
    for a, b in zip(points, points[1:]):
        span = math.dist(a, b)
        if travelled + span >= limit:
            ratio = (limit - travelled) / span if span > 0 else 0.0
            kept.append((a[0] + (b[0] - a[0]) * ratio,
                         a[1] + (b[1] - a[1]) * ratio))
            return kept
        travelled += span
        kept.append(b)
    return kept
```

- [ ] **Step 4: 통과 확인** — 전체 파이썬 테스트.
- [ ] **Step 5: 커밋** — `feat: 신호 교차로 갈래 모양을 굽는다`.

### Task 4: RouteData 차로 정보와 중심선

**Files:**
- Modify: `scripts/route_data.gd`
- Test: `tests/game/test_route_data.gd`

**Interfaces:**
- Produces: `route_lanes: PackedInt32Array`, `route_oneway: PackedByteArray`, `route_offset: PackedFloat32Array`, `ensure_lanes() -> void`(크기가 안 맞는 배열을 폭 7 m·차선 2·왕복·오프셋 w/4 로 채운다), `center_line() -> PackedVector3Array`.

- [ ] **Step 1: 테스트** — `test_route_data.gd` 끝 `finish()` 앞에:

```gdscript
	# 경로점별 차로 정보. 교통이 이것으로 차선 중앙과 도로 중심선을 잡는다.
	for key in ["route_lanes", "route_oneway", "route_offset"]:
		ok(data.get(key).size() == data.route.size(), "%s 길이가 다르다" % key)
		ok(part.get(key).size() == part.route.size(), "잘린 뒤 %s 길이가 다르다" % key)
	# 옛 형식(키 없음)이면 차선 2, 왕복, 오프셋 w/4.
	var old := RouteData.new()
	old.route = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -100.0)])
	old.ensure_lanes()
	ok(old.route_lanes == PackedInt32Array([2, 2]), "옛 형식 차선 수")
	ok(old.route_oneway == PackedByteArray([0, 0]), "옛 형식 일방통행")
	equal_approx(old.route_offset[0], RouteData.DEFAULT_ROAD_WIDTH_M * 0.25, 0.001,
		"옛 형식 오프셋")
	# 북쪽 진행의 왼쪽은 서(-X). 중심선은 경로를 왼쪽으로 오프셋만큼 민 것이다.
	var center := old.center_line()
	equal_approx(center[0].x, -1.75, 0.001, "중심선 x")
	equal_approx(center[1].z, -100.0, 0.001, "중심선 z")
```

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_route_data`.

- [ ] **Step 3: 구현**

필드(`route_width` 아래):
```gdscript
var route_lanes: PackedInt32Array = []     # 경로점별 전체 차선 수
var route_oneway: PackedByteArray = []     # 1 이면 일방통행(마주 오는 차 없음)
var route_offset: PackedFloat32Array = []  # 도로 중심에서 주행선까지 오른쪽 거리
```
`load_route`: 폭을 읽는 곳 뒤에 세 키를 읽고 `route_width` 폴백 블록을 `data.ensure_lanes()` 로 바꾼다.
```gdscript
	for count in parsed.get("route_lanes", []):
		data.route_lanes.append(int(count))
	for flag in parsed.get("route_oneway", []):
		data.route_oneway.append(int(flag))
	for offset in parsed.get("route_offset", []):
		data.route_offset.append(float(offset))
	data.ensure_lanes()
```
```gdscript
func ensure_lanes() -> void:
	"""경로와 길이가 안 맞는 차로 배열을 채운다. 옛 산출물과 테스트가 손수 만든
	RouteData 는 이것들이 없다. 차선 2·왕복·오프셋 w/4 는 차로 정보가 생기기 전
	동작과 같다."""
	var count := route.size()
	if route_width.size() != count:
		route_width = PackedFloat32Array()
		route_width.resize(count)
		route_width.fill(DEFAULT_ROAD_WIDTH_M)
	if route_lanes.size() != count:
		route_lanes = PackedInt32Array()
		route_lanes.resize(count)
		route_lanes.fill(2)
	if route_oneway.size() != count:
		route_oneway = PackedByteArray()
		route_oneway.resize(count)
		route_oneway.fill(0)
	if route_offset.size() != count:
		route_offset = PackedFloat32Array()
		for width in route_width:
			route_offset.append(width * 0.25)

func center_line() -> PackedVector3Array:
	"""경로점마다 왼쪽으로 route_offset 만큼 민 도로 중심선."""
	ensure_lanes()
	var line := PackedVector3Array()
	for index in route.size():
		var forward := route[mini(index + 1, route.size() - 1)] - route[maxi(index - 1, 0)]
		forward.y = 0.0
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
		line.append(route[index] + Vector3(forward.z, 0.0, -forward.x) * route_offset[index])
	return line
```
`slice`: 폭 자르기를 인덱스 기반으로 바꾼다. `_widths_between`/`_width_at_progress` 를 지우고
```gdscript
func _indices_between(start_m: float, end_m: float) -> PackedInt32Array:
	"""_route_between 과 같은 점들의 원래 인덱스. 보간점은 가까운 원래 점."""
	var part := PackedInt32Array([_index_at_progress(start_m)])
	var travelled := 0.0
	for index in range(1, route.size()):
		travelled += route[index - 1].distance_to(route[index])
		if travelled > start_m and travelled < end_m:
			part.append(index)
	part.append(_index_at_progress(end_m))
	return part

func _index_at_progress(distance_m: float) -> int:
	var travelled := 0.0
	for index in range(1, route.size()):
		var span := route[index - 1].distance_to(route[index])
		if travelled + span >= distance_m:
			return index - 1 if distance_m - travelled < span * 0.5 else index
		travelled += span
	return route.size() - 1
```
`slice` 안:
```gdscript
	part.route = _route_between(start_m, end_m)
	ensure_lanes()
	for index in _indices_between(start_m, end_m):
		part.route_width.append(route_width[index])
		part.route_lanes.append(route_lanes[index])
		part.route_oneway.append(route_oneway[index])
		part.route_offset.append(route_offset[index])
```

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh test_route_data test_sections`.
- [ ] **Step 5: 커밋** — `feat: RouteData 가 경로점별 차로 정보와 도로 중심선을 낸다`.

### Task 5: Lanes 순수 함수

**Files:**
- Create: `scripts/lanes.gd`, `tests/game/test_lanes.gd`, `tests/game/test_lanes.tscn`
- Modify: `tests/game/run_game_tests.sh:26` (목록에 `test_lanes`)

**Interfaces:**
- Produces: `Lanes.LANE_WIDTH_M = 3.2`, `Lanes.side_of(i: int, n: int, w: float, oneway: bool) -> float`, `Lanes.count_for(n: int, oneway: bool, forward: bool) -> int`, `Lanes.even_count(width: float) -> int`, `Lanes.outer_offset(w: float, n: int) -> float`.

- [ ] **Step 1: 테스트** — `test_lanes.gd`:

```gdscript
extends TestCase
# 차선 중앙과 방향별 차선 수.

func _ready() -> void:
	equal_approx(Lanes.side_of(0, 4, 15.0, false), 1.875, 0.001, "왕복 4차선 안쪽")
	equal_approx(Lanes.side_of(1, 4, 15.0, false), 5.625, 0.001, "왕복 4차선 바깥")
	equal_approx(Lanes.side_of(0, 3, 9.6, true), -3.2, 0.001, "일방통행 왼쪽")
	equal_approx(Lanes.side_of(1, 3, 9.6, true), 0.0, 0.001, "일방통행 가운데")
	equal_approx(Lanes.side_of(2, 3, 9.6, true), 3.2, 0.001, "일방통행 오른쪽")
	ok(Lanes.count_for(4, false, true) == 2, "왕복 4차선 정방향")
	ok(Lanes.count_for(4, false, false) == 2, "왕복 4차선 역방향")
	ok(Lanes.count_for(3, true, true) == 3, "일방통행 정방향")
	ok(Lanes.count_for(3, true, false) == 0, "일방통행 마주 오는 방향")
	ok(Lanes.count_for(1, false, true) == 1, "왕복인데 차선 1")
	ok(Lanes.even_count(15.0) == 4, "15 m 는 4차선")
	ok(Lanes.even_count(20.0) == 6, "20 m 는 6차선")
	ok(Lanes.even_count(4.5) == 2, "좁아도 2차선")
	equal_approx(Lanes.outer_offset(15.0, 4), 5.625, 0.001, "바깥 차선 중앙")
	finish()
```
`test_lanes.tscn` 은 `test_lane_path.tscn` 과 같은 형식(노드 이름 `TestLanes`, 스크립트 경로만 바꿈).

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_lanes` → `Lanes` 식별자 없음.

- [ ] **Step 3: 구현** — `scripts/lanes.gd`:

```gdscript
extends RefCounted
class_name Lanes
# 차선 기하의 순수 함수. bake(tools/osmbake/mesh.py)의 lane_count 와 같은 규칙이다.
# side 는 도로 중심선에서 진행 방향 오른쪽으로 떨어진 거리다.

const LANE_WIDTH_M := 3.2

static func side_of(i: int, n: int, w: float, oneway: bool) -> float:
	"""차선 i 의 중앙. i = 0 이 중앙선(일방통행이면 왼쪽 끝) 쪽이다."""
	if oneway:
		return -w * 0.5 + (i + 0.5) * w / n
	return (i + 0.5) * w / n

static func count_for(n: int, oneway: bool, forward: bool) -> int:
	"""한 방향의 차선 수. 일방통행 도로의 마주 오는 방향은 0 이다."""
	if oneway:
		return n if forward else 0
	return maxi(1, n / 2)

static func even_count(width: float) -> int:
	"""폭에서 되짚은 왕복 차선 수. 가장 가까운 짝수, 최소 2, 딱 중간이면 적은 쪽."""
	return maxi(2, 2 * ceili(width / LANE_WIDTH_M / 2.0 - 0.5))

static func outer_offset(w: float, n: int) -> float:
	"""도로 중심에서 가장 바깥 차선 한가운데까지."""
	return w * 0.5 - w / (2.0 * n)
```

- [ ] **Step 4:** `/opt/homebrew/bin/godot --headless --import`, `git checkout -q project.godot`, `run_game_tests.sh:26` 목록에 `test_lanes` 추가, `tests/game/run_game_tests.sh test_lanes` 통과.
- [ ] **Step 5: 커밋** — `feat: 차선 중앙과 방향별 차선 수 함수`(`scripts/lanes.gd` `.uid` 포함).

### Task 6: LanePath 부호 있는 투영, 인덱스, 갈래 차선

**Files:**
- Modify: `scripts/lane_path.gd` (`project` 부호, `add_signals` 절댓값, `index_at`, `from_arms`, `arm_points`; `oncoming` 삭제)
- Test: `tests/game/test_lane_path.gd`

**Interfaces:**
- Produces: `project(point) -> Vector2(along, signed_right)`, `index_at(distance) -> int`(가장 가까운 경로점 인덱스), `static arm_points(arm: Dictionary) -> PackedVector3Array`, `static from_arms(in_arm: Dictionary, out_arm: Dictionary, half_width: float, axis: int, offset_s: float) -> LanePath`(들어오는 갈래가 너무 짧으면 null).

- [ ] **Step 1: 테스트** — `oncoming` 블록을 지우고, 투영 기대값 옆에:

```gdscript
	# 동쪽 진행의 오른쪽은 남(+Z). 북쪽 점은 음수다.
	equal_approx(lane.project(Vector3(30.0, 0.0, -4.0)).y, -4.0, 0.001, "왼쪽은 음수")
	ok(lane.index_at(24.0) == 0 and lane.index_at(26.0) == 1, "가까운 경로점 인덱스")
```
끝에:
```gdscript
	# 갈래 차선: 남쪽 갈래(교차로로 북진해 들어옴)에서 북쪽 갈래(나감)로.
	# 폭 15 m 면 4차선, 바깥 차선 중앙은 오른쪽(동)으로 5.625 m.
	var south := {"points": [[0.0, 0.0], [0.0, 30.0], [0.0, 60.0]], "width": 15.0,
		"inbound": true, "outbound": true}
	var north := {"points": [[0.0, 0.0], [0.0, -60.0]], "width": 15.0,
		"inbound": true, "outbound": true}
	var arm_lane := LanePath.from_arms(south, north, 7.5, 0, 3.0)
	ok(arm_lane != null, "갈래 차선을 못 만들었다")
	if arm_lane != null:
		for point in arm_lane.points:
			equal_approx(point.x, 5.625, 0.001, "갈래 차선이 바깥 차선 중앙을 벗어났다")
		equal_approx(arm_lane.sample(0.0).z, 60.0, 0.001, "갈래 차선 시작점")
		equal_approx(arm_lane.length_m(), 120.0, 0.001, "갈래 차선 길이")
		equal_approx(arm_lane.stops[0]["at_m"], 60.0 - 7.5 - 2.0, 0.01, "갈래 정지선")
	var stub := {"points": [[0.0, 0.0], [0.0, 5.0]], "width": 15.0,
		"inbound": true, "outbound": true}
	ok(LanePath.from_arms(stub, north, 7.5, 0, 3.0) == null, "짧은 갈래로 차선을 만들었다")
```

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_lane_path`.

- [ ] **Step 3: 구현**

`oncoming` 삭제. 상수 `ARM_MIN_M := 5.0`(정지선 뒤로 이만큼은 있어야 차가 선다).

`project`: 최선 구간을 찾을 때 부호도 구한다.
```gdscript
		if distance < best:
			best = distance
			along = cumulative[index - 1] + start.distance_to(foot)
			var forward := points[index] - start
			# 진행 방향 (fx, fz) 의 오른쪽은 (-fz, fx) 다.
			side = signf(Vector3(-forward.z, 0.0, forward.x).dot(flat - foot))
	return Vector2(along, best * side)
```
(`var side := 1.0` 선언, 독스트링을 "(누적 거리, 부호 있는 가로 거리 — 오른쪽 양수)"로.) `add_signals` 의 `on.y > reach_m` 를 `absf(on.y) > reach_m` 로.

```gdscript
func index_at(distance: float) -> int:
	"""누적 거리에 가장 가까운 경로점 인덱스."""
	var low := 0
	var high := cumulative.size() - 1
	while low + 1 < high:
		var mid := (low + high) / 2
		if cumulative[mid] <= distance:
			low = mid
		else:
			high = mid
	return low if distance - cumulative[low] < cumulative[high] - distance else high

static func arm_points(arm: Dictionary) -> PackedVector3Array:
	var line := PackedVector3Array()
	for point in arm.get("points", []):
		line.append(Vector3(float(point[0]), 0.0, float(point[1])))
	return line

static func from_arms(in_arm: Dictionary, out_arm: Dictionary, half_width: float,
		axis: int, offset_s: float) -> LanePath:
	"""in_arm 으로 들어와 교차로를 지나 out_arm 으로 나가는 차선. 진행 방향
	오른쪽으로 들어오는 갈래의 가장 바깥 차선 중앙만큼 비킨다. 들어오는 갈래가
	정지선 뒤로 ARM_MIN_M 도 안 되면 null."""
	var inbound := arm_points(in_arm)
	inbound.reverse()
	var outbound := arm_points(out_arm)
	var inbound_m := make(inbound).length_m()
	var stop_m := inbound_m - half_width - STOP_LINE_MARGIN_M
	if stop_m < ARM_MIN_M or outbound.size() < 2:
		return null
	var line := inbound + outbound.slice(1)
	var width := float(in_arm.get("width", half_width * 2.0))
	var shift := Lanes.outer_offset(width, Lanes.even_count(width))
	var shifted := PackedVector3Array()
	for index in line.size():
		var forward := line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
		shifted.append(line[index] + Vector3(-forward.z, 0.0, forward.x) * shift)
	var lane := make(shifted)
	lane.stops.append({"at_m": stop_m, "offset": offset_s, "axis": axis, "signal": -1})
	return lane
```

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh test_lane_path`. `traffic.gd` 가 아직 `LanePath.oncoming` 을 부르면 Task 7 과 같이 커밋한다(파싱 에러 방지). 이 경우 Step 5 는 Task 7 로 넘긴다.
- [ ] **Step 5: 커밋** — `feat: 부호 있는 차선 투영과 갈래 차선`.

### Task 7: 다차선 주행과 차선 변경

**Files:**
- Modify: `scripts/traffic.gd` (전면 개정)
- Modify: `tests/game/test_traffic.gd`, `tests/game/test_crash.gd`(필요 시), `tests/game/drive_smoke.gd`(필드 이름)
- Create: `tests/game/test_lane_change.gd`, `tests/game/test_lane_change.tscn`, 목록에 추가

**Interfaces:**
- Consumes: `RouteData.ensure_lanes/center_line/route_lanes/route_oneway/route_width`, `Lanes.*`, `LanePath.project/index_at`
- Produces: `Traffic.forward_road`, `Traffic.backward_road`, `Car.road`, `Car.lane_index`, `Car.side_m`, `Car.parked`, `Car.change_s`, `Traffic.lane_count_at(road, distance) -> int`, `Traffic.lane_side(road, distance, lane_index) -> float`. `same_lane`/`oncoming_lane`/`Car.lane`/`BUS_LANE_REACH_M` 는 없어진다.

- [ ] **Step 1: 테스트** — `test_lane_change.gd`(합성 직선 북진 왕복 4차선 15 m, 신호 없음, 버스 대신 mover):

```gdscript
extends TestCase
# 합성 곧은 왕복 4차선에서 차선 변경 규칙을 하나씩 본다. 버스 대신 빈 Node3D 를
# 둔다. 필요한 차만 남기고 나머지는 cars 에서 뺀다.

const ROUTE_M := 1000.0

func _ready() -> void:
	await _test_passes_held_car()
	await _test_blocked_by_rear()
	await _test_no_change_near_stop()
	await _test_merge_when_lanes_drop()
	await _test_passes_bus()
	finish()

func _data(lanes_at_end: int = 4, signal_at_m: float = -1.0) -> RouteData:
	var data := RouteData.new()
	# 북(-Z)으로 곧은 길. 주행선은 바깥 차선 중앙(중심에서 동으로 5.625 m).
	for index in 11:
		data.route.append(Vector3(5.625, 0.0, -index * ROUTE_M / 10.0))
		data.route_width.append(15.0)
		data.route_lanes.append(4 if index < 5 else lanes_at_end)
		data.route_oneway.append(0)
		data.route_offset.append(5.625)
	if signal_at_m >= 0.0:
		data.signals = [{"x": 0.0, "z": -signal_at_m, "axis_deg": [0.0, 90.0],
			"half_width": 7.5}]
	return data

func _make(data: RouteData, mover_z: float = 0.0) -> Traffic:
	var mover := Node3D.new()
	add_child(mover)
	mover.position = Vector3(5.625, 0.0, mover_z)
	var traffic := Traffic.new()
	traffic.build(data, mover)
	add_child(traffic)
	return traffic

# 정방향 차 두 대만 남긴다. 나머지 몸체는 치운다.
func _keep(traffic: Traffic, count: int) -> Array:
	var kept: Array = []
	for car in traffic.cars.duplicate():
		if car.road == traffic.forward_road and kept.size() < count:
			kept.append(car)
			continue
		traffic.cars.erase(car)
		car.body.queue_free()
	return kept

func _put(traffic: Traffic, car, distance: float, lane: int, speed: float) -> void:
	car.distance = distance
	car.lane_index = lane
	car.side_m = traffic.lane_side(traffic.forward_road, distance, lane)
	car.speed = speed
	car.change_s = 0.0

func _run(seconds: float) -> void:
	var frames := int(seconds * Engine.physics_ticks_per_second)
	for frame in frames:
		await get_tree().physics_frame

func _cleanup(traffic: Traffic) -> void:
	traffic.queue_free()
	await get_tree().physics_frame

func _test_passes_held_car() -> void:
	var traffic := _make(_data())
	var cars := _keep(traffic, 2)
	_put(traffic, cars[0], 120.0, 1, 0.0)
	traffic.hold(cars[0].body, 100.0)
	_put(traffic, cars[1], 60.0, 1, CarFollow.CRUISE_MPS)
	await _run(10.0)
	ok(cars[1].distance > cars[0].distance + 5.0,
		"선 차를 못 앞질렀다 (%.1f vs %.1f)" % [cars[1].distance, cars[0].distance])
	await _cleanup(traffic)

func _test_blocked_by_rear() -> void:
	# 안쪽 차선 바로 뒤에 달리는 차가 있으면 옮기지 않는다. 그 차가 지나간 뒤에야 옮긴다.
	var traffic := _make(_data())
	var cars := _keep(traffic, 3)
	_put(traffic, cars[0], 90.0, 1, 0.0)
	traffic.hold(cars[0].body, 100.0)
	_put(traffic, cars[1], 70.0, 1, 0.0)
	_put(traffic, cars[2], 66.0, 0, CarFollow.CRUISE_MPS)
	await _run(0.2)
	ok(cars[1].lane_index == 1, "뒤차가 붙어 있는데 옮겼다")
	await _cleanup(traffic)

func _test_no_change_near_stop() -> void:
	# 정지선(신호 200 m, 정지선 190.5 m) 20 m 앞에서 막혀도 옮기지 않는다.
	var traffic := _make(_data(4, 200.0))
	var cars := _keep(traffic, 2)
	_put(traffic, cars[0], 175.0, 1, 0.0)
	traffic.hold(cars[0].body, 100.0)
	_put(traffic, cars[1], 165.0, 1, 0.0)
	await _run(0.5)
	ok(cars[1].lane_index == 1, "정지선 앞에서 차선을 바꿨다")
	await _cleanup(traffic)

func _test_merge_when_lanes_drop() -> void:
	# 500 m 부터 왕복 2차선. 바깥 차선 차가 안쪽(유일한 차선)으로 들어간다.
	var traffic := _make(_data(2))
	var cars := _keep(traffic, 1)
	_put(traffic, cars[0], 420.0, 1, CarFollow.CRUISE_MPS)
	var mover: Node3D = traffic._bus
	mover.position.z = -420.0
	await _run(12.0)
	ok(cars[0].lane_index == 0, "차선이 줄었는데 합류 안 했다")
	equal_approx(cars[0].side_m, Lanes.side_of(0, 2, 15.0, false), 0.05,
		"합류 뒤 가로 위치")
	await _cleanup(traffic)

func _test_passes_bus() -> void:
	# 버스(mover)가 바깥 차선 150 m 에 서 있다. 뒤차가 옆 차선으로 비켜 지나간다.
	var traffic := _make(_data(), -150.0)
	var cars := _keep(traffic, 1)
	_put(traffic, cars[0], 100.0, 1, CarFollow.CRUISE_MPS)
	await _run(10.0)
	ok(cars[0].distance > 160.0, "선 버스 뒤에서 못 지나갔다 (%.1f)" % cars[0].distance)
	await _cleanup(traffic)
```
(`_data` 는 주행선 x 5.625 라 `center_line` 이 x 0 이 된다. mover 가 창 기준이므로 테스트 차는 창 [-100, +250] 안에 둔다. 창 밖으로 나가면 재활용되니 거리를 그 안에서 고른다.)

`test_traffic.gd` 는 `lane` 을 `traffic.forward_road` 로(빌드 뒤) 잡고, mover 는 `data.route` 위를 옮긴다(버스 주행선). `car.lane` → `car.road`, 범퍼 간격은 같은 도로에서 가로 1.8 m 안인 차끼리만 3 m 기준으로 센다(`MIN_BUMPER_GAP_M` 3). 새로 센다:
- `parked` 가 아니고 `road == backward_road` 인 차가 일방통행 지점(`traffic.lane_count_at(road, distance) == 0`)에 있으면 실패 카운트.
- 정방향 차의 `lane_index` 집합 크기가 한 번이라도 2 이상.
창 안 차 수는 `forward_road.project(mover)` 기준으로 같은 방식.

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_lane_change test_traffic`.

- [ ] **Step 3: 구현** — `traffic.gd` 를 아래처럼 바꾼다(`_make_car`, `car_of`, `hold`, `police_sees`, `_idle_car` 는 그대로, 교차 차선 생성 `_crossing_lanes` 는 Task 8 전까지 기존 직선 `crossing` 그대로).

헤더 주석 끝에 "노선 차량은 도로 중심선 위 두 도로(정방향·역방향)에서 달리고 차마다 중심선에서 오른쪽으로 떨어진 가로 위치를 든다. 앞차는 가로로 겹치는 차 중 가장 가까운 차다." 를 더한다.

상수: `SAME_COUNT := 10`, `ONCOMING_COUNT := 8`, `BUS_LANE_REACH_M` 삭제, 추가:
```gdscript
const BUS_HALF_WIDTH_M := 1.25    # Bus 충돌 상자 폭 2.5 m 의 절반
const CAR_HALF_WIDTH_M := 0.9     # BODY_SIZE.x 의 절반
const LATERAL_M := 2.4            # 가로로 이보다 가까운 차는 같은 줄이다(차 폭 + 0.6)
const BUS_LATERAL_M := BUS_HALF_WIDTH_M + CAR_HALF_WIDTH_M + 0.3
const LANE_SHIFT_MPS := 1.2       # 차선 중앙으로 옆걸음하는 최대 속도
const CHANGE_COOLDOWN_S := 4.0
const BLOCKED_GAP_M := 30.0       # 앞차가 이 안에 있고
const BLOCKED_SPEED_RATIO := 0.7  # 순항 속도의 이 비율보다 느리면 막힌 것이다
const NO_CHANGE_BEFORE_M := 25.0  # 정지선 앞뒤로는 차선을 안 바꾼다
const NO_CHANGE_AFTER_M := 10.0
const CHANGE_GAIN_M := 10.0       # 옮길 차선의 앞 간격이 지금보다 이만큼은 커야 한다
const REAR_GAP_M := 8.0           # 옮길 차선 뒤차와 최소 간격
const REAR_GAP_S := 1.0           # 뒤차 속도 1 m/s 마다 더 벌릴 간격
```
`Car`:
```gdscript
class Car:
	var body: AnimatableBody3D
	var road: LanePath             # null 이면 쉬는 교차 차량
	var distance := 0.0
	var speed := 0.0
	var hold_s := 0.0
	var is_police := false
	var crossing := -1             # 교차 차량이 맡은 신호 인덱스. 노선 차량은 -1
	var lane_index := 0            # 가려는 차선. 0 이 중앙선(일방통행이면 왼쪽 끝) 쪽
	var side_m := 0.0              # 도로 중심선에서 진행 방향 오른쪽으로 떨어진 거리
	var parked := false            # 일방통행 구간이라 치워 둔 마주 오는 차
	var change_s := 0.0            # 다음 차선 변경을 따질 수 있을 때까지
```
필드:
```gdscript
var cars: Array = []
var forward_road: LanePath
var backward_road: LanePath

var _bus: Node3D
var _signals: Array = []
var _cross_lanes: Dictionary = {}  # 신호 인덱스 -> [LanePath, ...]
var _lanes: PackedInt32Array = []   # 정방향 경로점 순서
var _oneway: PackedByteArray = []
var _widths: PackedFloat32Array = []
var _by_road: Dictionary = {}       # LanePath -> [Car], 이번 프레임에 달리는 차
```
`build`:
```gdscript
func build(data: RouteData, bus: Node3D) -> void:
	_bus = bus
	if data.route.size() < 2:
		# 경로가 없으면 차도 없다.
		return
	_signals = data.signals
	data.ensure_lanes()
	_lanes = data.route_lanes
	_oneway = data.route_oneway
	_widths = data.route_width
	var center := data.center_line()
	forward_road = LanePath.make(center)
	forward_road.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)
	var back := center.duplicate()
	back.reverse()
	backward_road = LanePath.make(back)
	backward_road.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)

	# 같은 방향 차는 버스 앞에만 깐다. 뒤에 깔면 첫 프레임에 버스와 겹칠 수 있다.
	var along := forward_road.project(_bus_point()).x
	for index in SAME_COUNT:
		_put(_make_car(index == 0, index), forward_road, minf(along + FIRST_AHEAD_M
			+ (AHEAD_M - FIRST_AHEAD_M) * index / SAME_COUNT, forward_road.length_m()), index)
	# 역방향 도로에서 버스 앞은 누적 거리가 작은 쪽이다.
	var facing := backward_road.project(_bus_point()).x
	for index in ONCOMING_COUNT:
		_put(_make_car(index == 0, index + 1), backward_road, clampf(facing - AHEAD_M
			+ (AHEAD_M + BEHIND_M) * (index + 0.5) / ONCOMING_COUNT,
			0.0, backward_road.length_m()), index)
	for index in CROSS_MAX:
		_make_car(false, index + 2)
	_place_all()

func _put(car: Car, road: LanePath, distance: float, lane_index: int) -> void:
	car.road = road
	car.distance = distance
	car.speed = 0.0
	var count := lane_count_at(road, distance)
	car.parked = count == 0
	car.lane_index = lane_index % maxi(count, 1)
	car.side_m = lane_side(road, distance, car.lane_index)
```
차로 조회:
```gdscript
func _is_route(road: LanePath) -> bool:
	return road != null and (road == forward_road or road == backward_road)

func _point_index(road: LanePath, distance: float) -> int:
	var index := road.index_at(distance)
	return index if road == forward_road else _lanes.size() - 1 - index

func lane_count_at(road: LanePath, distance: float) -> int:
	"""그 지점 그 방향의 차선 수. 교차 차선은 1."""
	if not _is_route(road):
		return 1
	var index := _point_index(road, distance)
	return Lanes.count_for(_lanes[index], _oneway[index] == 1, road == forward_road)

func lane_side(road: LanePath, distance: float, lane_index: int) -> float:
	"""차선 중앙의 가로 위치. 교차 차선은 비킴이 차선 점에 들어 있어 0."""
	if not _is_route(road):
		return 0.0
	var index := _point_index(road, distance)
	return Lanes.side_of(lane_index, _lanes[index], _widths[index], _oneway[index] == 1)
```
`_bus_point` 의 `same_lane` → `forward_road`. 물리 처리:
```gdscript
func _physics_process(delta: float) -> void:
	if forward_road == null:
		return
	var bus_point := _bus_point()
	_update_crossings(bus_point)
	var t := TrafficSignal.now()
	_by_road = {}
	for car in cars:
		if car.road != null and not car.parked:
			if not _by_road.has(car.road):
				_by_road[car.road] = []
			_by_road[car.road].append(car)
	# 버스를 도로마다 한 번씩만 투영한다. 재활용도 같은 값을 쓴다.
	var bus_on := {}
	for road in [forward_road, backward_road] + _by_road.keys():
		if not bus_on.has(road):
			bus_on[road] = road.project(bus_point) if _bus != null else Vector2(INF, INF)
	for road in _by_road:
		for car in _by_road[road]:
			_drive(car, bus_on[road], t, delta)
	_recycle(bus_on)
	_place_all()

func _drive(car: Car, bus_on: Vector2, t: float, delta: float) -> void:
	if car.hold_s > 0.0:
		car.hold_s = maxf(car.hold_s - delta, 0.0)
		car.speed = 0.0
		return
	if _is_route(car.road):
		var count := lane_count_at(car.road, car.distance)
		if count == 0:
			# 마주 오는 차가 일방통행 구간에 들어섰다. 치우고 재활용에 맡긴다.
			car.parked = true
			return
		# 차선이 줄어드는 곳에서는 남은 가장 바깥 차선으로 합류한다.
		car.lane_index = mini(car.lane_index, count - 1)
		car.change_s = maxf(car.change_s - delta, 0.0)
		if car.change_s <= 0.0:
			_consider_change(car, count, bus_on)
		car.side_m = move_toward(car.side_m,
			lane_side(car.road, car.distance, car.lane_index), LANE_SHIFT_MPS * delta)
	var front := car.distance + CAR_HALF_LENGTH_M
	var gap := _ahead(car.road, car.distance, car.side_m, car, bus_on).x
	var stop_m := INF
	var phase := TrafficSignal.Phase.GREEN
	var line := car.road.next_stop(front)
	if not line.is_empty():
		stop_m = float(line["at_m"]) - front
		phase = TrafficSignal.phase_at(float(line["offset"]), int(line["axis"]), t)
	car.speed = CarFollow.next_speed(car.speed, gap, stop_m, phase, delta)
	car.distance = minf(car.distance + car.speed * delta, car.road.length_m())

func _ahead(road: LanePath, distance: float, side: float, me: Car, bus_on: Vector2) -> Vector2:
	"""가로로 겹치는 가장 가까운 앞 장애물의 (범퍼 간격, 속도). 없으면 (INF, 0).

	차선을 옮기는 중인 차는 가로 위치로 두 차선 모두에 걸리므로 따로 볼 게 없다."""
	# ponytail: 같은 도로 차 전부를 훑는다(10 대 안팎). 늘어나면 거리순 정렬 후 이웃만 본다.
	var front := distance + CAR_HALF_LENGTH_M
	var best := Vector2(INF, 0.0)
	for other in _by_road.get(road, []):
		if other == me or other.distance <= distance \
				or absf(other.side_m - side) >= LATERAL_M:
			continue
		var gap: float = other.distance - CAR_HALF_LENGTH_M - front
		if gap < best.x:
			best = Vector2(gap, other.speed)
	# 차로 옆으로 비켜 선 버스(정류장)는 장애물이 아니다. 그러면 뒤차가 영원히 선다.
	if bus_on.x > distance and absf(bus_on.y - side) < BUS_LATERAL_M:
		var gap := bus_on.x - BUS_HALF_LENGTH_M - front
		if gap < best.x:
			best = Vector2(gap, _bus_speed())
	return best

func _bus_speed() -> float:
	var velocity = _bus.get("linear_velocity") if _bus != null else null
	return velocity.length() if velocity is Vector3 else 0.0

func _consider_change(car: Car, count: int, bus_on: Vector2) -> void:
	"""막혔으면 옆 차선으로 옮긴다. 정지선 근처와 뒤차가 붙은 차선은 피한다."""
	var here := _ahead(car.road, car.distance, car.side_m, car, bus_on)
	if here.x >= BLOCKED_GAP_M or here.y >= BLOCKED_SPEED_RATIO * CarFollow.CRUISE_MPS:
		return
	var front := car.distance + CAR_HALF_LENGTH_M
	for line in car.road.stops:
		var to_line := float(line["at_m"]) - front
		if to_line < NO_CHANGE_BEFORE_M and to_line > -NO_CHANGE_AFTER_M:
			return
	var best := -1
	var best_gap := here.x + CHANGE_GAIN_M
	for lane in [car.lane_index - 1, car.lane_index + 1]:
		if lane < 0 or lane >= count:
			continue
		var side := lane_side(car.road, car.distance, lane)
		var gap := _ahead(car.road, car.distance, side, car, bus_on).x
		if gap > best_gap and _rear_clear(car, side):
			best = lane
			best_gap = gap
	if best >= 0:
		car.lane_index = best
		car.change_s = CHANGE_COOLDOWN_S

func _rear_clear(car: Car, side: float) -> bool:
	for other in _by_road.get(car.road, []):
		if other == car or other.distance > car.distance \
				or absf(other.side_m - side) >= LATERAL_M:
			continue
		var gap: float = car.distance - other.distance - CAR_HALF_LENGTH_M * 2.0
		if gap <= REAR_GAP_M + other.speed * REAR_GAP_S:
			return false
	return true
```
재활용:
```gdscript
func _recycle(bus_on: Dictionary) -> void:
	for car in cars:
		if car.road == null:
			continue
		var on: Vector2 = bus_on.get(car.road, Vector2(INF, INF))
		if car.road == forward_road:
			_recycle_route(car, on.x - BEHIND_M, on.x + AHEAD_M, on.x + AHEAD_M, on)
		elif car.road == backward_road:
			_recycle_route(car, on.x - AHEAD_M, on.x + BEHIND_M, on.x - AHEAD_M, on)
		elif car.distance >= car.road.length_m() and _free_at(car.road, 0.0, 0.0, car, on):
			# 교차 차량은 차선 끝에 닿으면 처음으로 돌아간다.
			car.distance = 0.0
			car.speed = 0.0

func _recycle_route(car: Car, low: float, high: float, entry: float, bus_on: Vector2) -> void:
	"""창을 벗어난 차를 반대쪽 끝으로, 치워 둔 차를 버스 앞 끝(entry)으로 옮긴다."""
	var length := car.road.length_m()
	low = maxf(low, 0.0)
	high = minf(high, length)
	var target: float
	if car.parked:
		target = clampf(entry, 0.0, length)
	elif car.distance > high or car.distance >= length:
		target = low
	elif car.distance < low:
		target = high
	else:
		return
	var count := lane_count_at(car.road, target)
	if count == 0:
		# 일방통행 구간이다. 치워 두고 다음 프레임에 다시 본다.
		car.parked = true
		return
	# 무작위 차선부터 본다. 자리가 차 있으면 옆 차선, 다 차 있으면 다음 프레임.
	var first := randi() % count
	for step in count:
		var lane := (first + step) % count
		var side := lane_side(car.road, target, lane)
		if _free_at(car.road, target, side, car, bus_on):
			car.distance = target
			car.speed = 0.0
			car.lane_index = lane
			car.side_m = side
			car.parked = false
			return

func _free_at(road: LanePath, distance: float, side: float, moving: Car, bus_on: Vector2) -> bool:
	if absf(bus_on.y - side) < BUS_LATERAL_M and absf(bus_on.x - distance) < SPAWN_GAP_M:
		return false
	for other in cars:
		if other != moving and other.road == road and not other.parked \
				and absf(other.distance - distance) < SPAWN_GAP_M \
				and absf(other.side_m - side) < LATERAL_M:
			return false
	return true
```
`_update_crossings`: `same_lane.stops` → `forward_road.stops`, `car.lane = null` → `car.road = null`, 배정 시 `car.road = lane`, `car.side_m = 0.0`, `car.lane_index = 0`, `car.parked = false`. `_place_all`:
```gdscript
	for car in cars:
		if car.road == null or car.parked:
			car.body.transform = Transform3D(Basis(), Vector3(0.0, HIDDEN_Y, 0.0))
			continue
		var forward: Vector3 = car.road.direction_at(car.distance)
		var right := Vector3(-forward.z, 0.0, forward.x)
		car.body.transform = Transform3D(Basis.looking_at(forward, Vector3.UP),
			car.road.sample(car.distance) + right * car.side_m)
```
`drive_smoke.gd` 는 `car.distance`·`collision_layer` 만 써서 그대로다. `test_crash.gd` 는 왕복 2차선 7 m 라 바깥 차선 중앙이 버스 주행선과 같아 그대로다.

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh test_lane_change test_traffic test_crash test_violation test_lane_path drive_smoke`. 수치가 안 맞으면 테스트가 아니라 상수를 의심하되, 스펙 수치와 다르게 바꾸면 이유를 주석에 남긴다.
- [ ] **Step 5: 커밋** — `feat: 노선 차량이 모든 차선을 쓰고 막히면 차선을 바꾼다`.

### Task 8: 교차 차선을 갈래 위로

**Files:**
- Modify: `scripts/traffic.gd` (`_crossing_lanes`)
- Test: `tests/game/test_traffic.gd`

**Interfaces:**
- Consumes: `LanePath.from_arms`, `LanePath.arm_points` (Task 6), 신호 `arms` (Task 3)

- [ ] **Step 1: 테스트** — `test_traffic.gd` 의 `_check` 에서 `car.crossing >= 0` 인 차마다 그 신호의 `arms` 가 있으면 차 위치(`car.body.position`)에서 모든 갈래 선(`LanePath.make(LanePath.arm_points(arm))`)까지 가장 가까운 거리를 재고, 그 값이 `half_width + 1.0` 을 넘으면 `off_road += 1`. `_report` 에 `ok(off_road == 0, "교차 차량이 갈래 밖에 %d 번" % off_road)`. (`arms` 는 Task 10 재굽기 전에는 없으므로 이 단언은 재굽기 뒤에 의미가 생긴다. 옛 json 이면 건너뛴다.)

- [ ] **Step 2: 구현**

```gdscript
const ARM_AXIS_DEG := 45.0        # 교차 축 방위각에서 이만큼 안의 갈래만 쓴다
const ARM_FACING_DEG := 45.0      # 두 갈래가 180° ± 이 안이면 마주 본다
const ARM_BEARING_M := 10.0       # 갈래 방위각은 첫 점에서 이만큼 간 점으로 잰다

func _crossing_lanes(index: int, line: Dictionary) -> Array:
	"""버스가 지나지 않는 축으로 교차로를 가로지르는 차선들. 갈래가 있으면
	마주 보는 갈래 한 쌍 위로, 옛 산출물이면 축 방위각 직선으로 낸다."""
	if not _cross_lanes.has(index):
		var entry: Dictionary = _signals[index]
		var axis := 1 - int(line["axis"])
		var bearing := float(entry["axis_deg"][axis])
		var half := float(entry.get("half_width", ViolationWatch.DEFAULT_HALF_WIDTH))
		var offset := float(line["offset"])
		if entry.has("arms"):
			_cross_lanes[index] = _arm_lanes(entry["arms"], bearing, half, axis, offset)
		else:
			var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
			_cross_lanes[index] = [
				LanePath.crossing(center, bearing, half, axis, offset),
				LanePath.crossing(center, bearing + 180.0, half, axis, offset)]
	return _cross_lanes[index]

func _arm_lanes(arms: Array, bearing: float, half: float, axis: int, offset: float) -> Array:
	var near: Array = []   # [갈래, 방위각]
	for arm in arms:
		var points := LanePath.arm_points(arm)
		if points.size() < 2:
			continue
		var heading := TrafficSignal.bearing_of(
			LanePath.make(points).sample(ARM_BEARING_M) - points[0])
		if _axis_delta(heading, bearing) <= ARM_AXIS_DEG:
			near.append([arm, heading])
	# 가장 곧게 마주 보는 한 쌍. 없으면 그 교차로에는 교차 차량이 없다.
	var pair: Array = []
	var best := ARM_FACING_DEG
	for i in near.size():
		for j in range(i + 1, near.size()):
			var facing := absf(180.0 - _angle_delta(near[i][1], near[j][1]))
			if facing <= best:
				best = facing
				pair = [near[i][0], near[j][0]]
	var lanes: Array = []
	if pair.is_empty():
		return lanes
	for way in [[pair[0], pair[1]], [pair[1], pair[0]]]:
		if way[0]["inbound"] and way[1]["outbound"]:
			var lane := LanePath.from_arms(way[0], way[1], half, axis, offset)
			if lane != null:
				lanes.append(lane)
	return lanes

static func _angle_delta(a: float, b: float) -> float:
	"""두 방위각 사이 각(0~180)."""
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)

static func _axis_delta(a: float, b: float) -> float:
	"""축(방향 무시) 사이 각(0~90)."""
	var delta := _angle_delta(a, b)
	return minf(delta, 180.0 - delta)
```
`TrafficSignal.bearing_of(Vector3)` 가 방향 벡터를 받는지 확인한다(`direction_at` 결과를 넘기는 기존 사용처와 같다). `_update_crossings` 는 교차 차선이 0~2 개여도 그대로 돈다.

- [ ] **Step 3: 통과 확인** — `tests/game/run_game_tests.sh test_traffic test_lane_path`.
- [ ] **Step 4: 커밋** — `feat: 교차 차량이 교차로 갈래 위로만 달린다`.

### Task 9: 정지선

**Files:**
- Modify: `scripts/signal_field.gd` (`stop_line_count`, 정지선 메쉬)
- Modify: `tests/game/drive_smoke.gd` (정지선 수 단언)

**Interfaces:**
- Consumes: 신호 `arms`, `LanePath.make/arm_points/sample/direction_at`
- Produces: `SignalField.stop_line_count: int`. 갈래가 있으면 `inbound` 갈래마다 하나, 없으면 신호마다 4.

- [ ] **Step 1: 테스트** — `drive_smoke.gd` `_report` 의 기둥 수 단언 뒤:

```gdscript
	var expected_lines := 0
	for entry in drive.data.signals:
		if not entry.has("axis_deg") or entry["axis_deg"].size() < 2:
			continue
		if entry.has("arms"):
			for arm in entry["arms"]:
				if arm["inbound"]:
					expected_lines += 1
		else:
			expected_lines += 4
	ok(drive.signal_field.stop_line_count == expected_lines,
		"정지선이 %d 개인데 %d 개여야 한다"
		% [drive.signal_field.stop_line_count, expected_lines])
	ok(expected_lines > 0, "정지선이 하나도 없다")
```

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh drive_smoke` → `stop_line_count` 없음.

- [ ] **Step 3: 구현** — 상수 `STOP_LINE_THICKNESS := 0.4`, `STOP_LINE_Y := 0.03`(차선 도색 0.02 위). 필드 `var stop_line_count := 0`, `var _stop_mesh: BoxMesh`, `var _stop_material: StandardMaterial3D`. `_make_shared_resources` 에:
```gdscript
	# 정지선은 단위 판 하나를 공유하고 변환으로 늘린다.
	_stop_mesh = BoxMesh.new()
	_stop_mesh.size = Vector3(1.0, 0.01, 1.0)
	_stop_material = StandardMaterial3D.new()
	_stop_material.albedo_color = Color(0.95, 0.95, 0.95)
	_stop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
```
`build` 의 신호 루프에서 기둥을 세운 뒤:
```gdscript
		if entry.has("arms"):
			for arm in entry["arms"]:
				if arm["inbound"]:
					_add_arm_stop_line(arm, half)
		else:
			for axis in 2:
				for way in 2:
					var inbound := TrafficSignal.direction_of(float(entry["axis_deg"][axis])) \
						* (1.0 if way == 0 else -1.0)
					_add_stop_line(center - inbound * (half + STOP_LINE_MARGIN_M),
						inbound, half, false)
```
```gdscript
func _add_arm_stop_line(arm: Dictionary, half: float) -> void:
	"""갈래를 따라 교차로 중심에서 반폭 + 2 m. 위반 판정 위치와 같다."""
	var line := LanePath.make(LanePath.arm_points(arm))
	var at := minf(half + STOP_LINE_MARGIN_M, line.length_m())
	# 갈래 점은 교차로에서 바깥으로 간다. 들어오는 차의 진행 방향은 그 반대다.
	var inbound := -line.direction_at(at)
	var oneway := not arm["outbound"]
	_add_stop_line(line.sample(at), inbound, float(arm.get("width", half * 2.0)), oneway)

func _add_stop_line(point: Vector3, inbound: Vector3, width: float, oneway: bool) -> void:
	"""왕복이면 들어오는 쪽 절반(중앙선에서 오른쪽 가장자리까지), 일방통행이면 전체 폭."""
	var right := Vector3(-inbound.z, 0.0, inbound.x)
	var length := width if oneway else width * 0.5
	var middle := point if oneway else point + right * width * 0.25
	var stripe := MeshInstance3D.new()
	stripe.mesh = _stop_mesh
	stripe.material_override = _stop_material
	stripe.transform = Transform3D(
		Basis(right * length, Vector3.UP, inbound * STOP_LINE_THICKNESS),
		Vector3(middle.x, STOP_LINE_Y, middle.z))
	add_child(stripe)
	stop_line_count += 1
```
(옛 json 의 `_add_stop_line` 폭 인자는 `half * 2.0` 이어야 반폭짜리 선이 된다 — 위 호출의 `half` 를 `half * 2.0` 으로 쓴다.) 먼 교차로 숨기기는 하지 않는다 — 기둥도 숨기지 않고, 정지선은 노선 신호당 3~4 장이라 싸다.

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh drive_smoke test_violation`.
- [ ] **Step 5: 커밋** — `feat: 신호 교차로 진입 차로에 정지선을 그린다`.

### Task 10: 재굽기, 검증, 캡처

**Files:**
- Modify: `assets/routes/route_*.json`, `assets/routes/route_*.glb` (재굽기 산출물)
- Modify: `README.md` (차로·정지선 설명이 있는 곳)

- [ ] **Step 1:** `python3 -m tools.osmbake.cli bake seoul-100`, `seoul-654`, `seoul-seodaemun03`.
- [ ] **Step 2:** `tests/bake/run_verify.sh` 통과. 주행선-도로 검사가 바깥 차선 때문에 실패하면 스펙 위험 2 대로 오프셋에 여유(예: `min(outer, w/2 - 1.6)`)를 두고 Task 2 테스트를 같이 고친다.
- [ ] **Step 3:** 노선별 짝이 나온 신호 비율을 센다(파이썬 한 줄: 각 신호의 `arms` 에서 축 45° 안 마주 보는 쌍이 있는 비율). 절반 아래면 사용자에게 보고한다(스펙 위험 1).
- [ ] **Step 4:** 게임 테스트 전체 `tests/game/run_game_tests.sh`, 파이썬 전체.
- [ ] **Step 5:** 창 모드 캡처(샌드박스 밖)로 교차로 정지선·다차선·일방통행 구간을 눈으로 본다.
- [ ] **Step 6: 커밋** — `chore: 차로 정보와 교차로 갈래를 넣어 세 노선을 다시 굽는다`.
