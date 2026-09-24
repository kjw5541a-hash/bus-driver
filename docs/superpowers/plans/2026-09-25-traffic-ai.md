# 교통 AI 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 버스 주변 노선에 같은 방향·마주 오는 차, 가까운 신호 교차로에 교차 차량을 두고, 모두 신호와 차간 거리를 지키게 하며, 버스가 차와 부딪히면 사고로 감점하고 잠깐 세운다. 경찰차는 이 교통 위로 옮긴다.

**Architecture:** 순수 계산 `CarFollow`(한 프레임 속도)와 `LanePath`(차선 기하·정지선)를 두고, `Traffic` 노드가 차 18대(`AnimatableBody3D`)를 차선 누적 거리로 옮긴다. `CrashWatch` 가 버스 접촉을 세고, `drive.gd` 가 사고 정지를 건다. 베이크는 경로점별 도로 폭 `route_width` 를 새로 쓴다.

**Tech Stack:** Godot 4.7.2 GDScript, 파이썬 3 베이크 도구(`tools/osmbake`), 헤드리스 테스트 러너 `tests/game/run_game_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-25-traffic-ai-design.md`

## Global Constraints

- Godot 실행 파일: `/opt/homebrew/bin/godot`. 헤드리스 테스트는 `tests/game/run_game_tests.sh [scene...]` 로 돌리고 `^TEST_OK$` 출력으로 판정한다. 스크립트에 파싱 에러가 있어도 Godot 은 0 으로 끝나므로 출력의 `TEST_OK` 를 반드시 확인한다.
- godot 을 실행하면 `project.godot` 이 바뀐다. 커밋 전에 `git checkout -q project.godot`.
- 새 `.gd` 는 `--import` 가 만드는 `.gd.uid` 도 같이 커밋한다.
- `git add -A` / `git add .` 금지. 파일 이름을 하나씩 적는다.
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- 주석·문서·테스트 메시지는 한국어.
- 좌표: x=동, z=남, 방위 북=0(−Z). 진행 방향 (fx, fz) 의 오른쪽은 (−fz, fx), 왼쪽은 (fz, −fx).
- 이 프로젝트 패턴: `build()` 를 `add_child()` 전에 부른다. 트리 밖에서는 `global_position`/`look_at` 을 못 쓴다 — `transform` 을 직접 짠다. 갓 `add_child` 한 노드는 테스트에서 `physics_frame` 을 두 번 await 한다.
- spec 수치: `SAME_COUNT=6`, `ONCOMING_COUNT=6`, 창 앞 250 m / 뒤 100 m, `SPAWN_GAP_M=20`, `CROSS_RADIUS_M=150`, `CROSS_MAX=6`, 교차 차선 길이 `clampf(half_width*4, 30, 60)`, `BUS_LANE_REACH_M=3`, `CRUISE_MPS=40 km/h`, `ACCEL=2`, `BRAKE=6`, `MIN_GAP_M=6+speed*1.5`, `STOP_LINE_MARGIN_M=2`, `DEFAULT_ROAD_WIDTH_M=7.0`, `CRASH_STOP_S=5`, `CRASH_GRACE_S=3`, `CRASH=-200`, 경찰 시야 80 m, 차 상자 `(1.8, 1.4, 4.6)`.

## 파일 구조

| 파일 | 할 일 |
|---|---|
| `tools/osmbake/emit.py` | `route_width` 인자 추가, 길이 검사 |
| `tools/osmbake/cli.py` | `widths` 를 넘긴다 |
| `tests/osmbake/test_emit.py` | `route_width` 테스트 |
| `assets/routes/route_*.json` (+ `.glb`) | 재베이크 산출물 |
| `scripts/route_data.gd` | `route_width` 읽기, `slice()` 에서 자르기 |
| `scripts/car_follow.gd` (새) | 한 프레임 속도 계산 |
| `scripts/lane_path.gd` (새) | 차선 기하, 마주 오는 차선, 교차 차선, 정지선 |
| `scripts/traffic.gd` (새) | 차 생성·주행·재활용·교차 차량·경찰 시야·hold |
| `scripts/crash_watch.gd` (새) | 사고 판정, 정지·유예 |
| `scripts/patrol_cars.gd` (+ `.uid`) | 삭제 |
| `scripts/violation_watch.gd` | `patrol` → `traffic` |
| `scripts/score_card.gd` | `crashes` 인자, `CRASH` |
| `scripts/boarding_hud.gd` | 사고 표시 |
| `scripts/drive.gd` | 배선 |
| `tests/game/test_car_follow.*`, `test_lane_path.*`, `test_traffic.*`, `test_crash.*` (새) | 테스트 |
| `tests/game/test_route_data.gd`, `test_violation.gd`, `test_score_card.gd`, `drive_smoke.gd`, `run_game_tests.sh` | 테스트 수정 |
| `README.md` | 설명 갱신 |

---

### Task 1: 베이크 `route_width` 와 `RouteData.route_width`

**Files:**
- Modify: `tools/osmbake/emit.py:10-41`
- Modify: `tools/osmbake/cli.py:167-170`
- Modify: `tests/osmbake/test_emit.py:40-60`
- Modify: `scripts/route_data.gd`
- Modify: `tests/game/test_route_data.gd` (끝 `finish()` 앞)
- Regenerate: `assets/routes/route_seoul-100.json`, `route_seoul-654.json`, `route_seoul-seodaemun03.json` (glb 가 바뀌면 같이)

**Interfaces:**
- Produces: JSON 키 `"route_width": [float...]` (`route` 와 같은 길이). `RouteData.DEFAULT_ROAD_WIDTH_M := 7.0`, `RouteData.route_width: PackedFloat32Array` (로드 후 항상 `route` 와 같은 길이, `slice()` 결과도 같음. 단 `RouteData.new()` 로 손수 만든 데이터는 비어 있을 수 있다).

- [ ] **Step 1: 파이썬 실패 테스트**

`tests/osmbake/test_emit.py` 의 `_write` 기본값에 `route_width=[7.0, 7.0]` 을 넣고, "계약에 정한 키" 목록에 `"route_width"` 를 더하고, 테스트 둘을 추가한다.

```python
    def _write(self, **overrides):
        kwargs = dict(origin=(37.5, 127.0), route_xz=[(0.0, 0.0), (10.0, 0.0)],
                      route_width=[7.0, 7.0],
                      stops=self.stops, signals=[],
                      chunks=[{"name": "chunk_0_0", "min": [0.0, 0.0], "max": [10.0, 0.0]}],
                      baked_at="2026-09-22")
        kwargs.update(overrides)
        return write_route_json(self.path, self.spec, **kwargs)
```

```python
    def test_route_width_는_route_와_길이가_같고_반올림된다(self):
        payload = self._write(route_width=[7.123, 15.0])
        self.assertEqual(payload["route_width"], [7.12, 15.0])
        self.assertEqual(len(payload["route_width"]), len(payload["route"]))

    def test_route_width_길이가_다르면_거부한다(self):
        with self.assertRaises(ValueError):
            self._write(route_width=[7.0])
```

- [ ] **Step 2: 실패 확인**

Run: `python3 -m unittest tests.osmbake.test_emit -v`
Expected: `TypeError: write_route_json() got an unexpected keyword argument 'route_width'` 로 실패.

- [ ] **Step 3: emit / cli 구현**

`tools/osmbake/emit.py`:

```python
def write_route_json(path: Path, spec: RouteSpec, *, origin, route_xz, route_width,
                     stops, signals, chunks, baked_at: str) -> dict:
```

docstring Args 에 `route_xz` 다음 줄로 추가:

```python
        route_width: [폭, ...] 경로점별 도로 폭(m). route_xz 와 같은 길이
```

payload 를 만들기 전에:

```python
    if len(route_width) != len(route_xz):
        raise ValueError(f"route_width {len(route_width)}개, route {len(route_xz)}개")
```

payload 의 `"route"` 다음 줄:

```python
        "route_width": [round(width, 2) for width in route_width],
```

`tools/osmbake/cli.py` 의 호출:

```python
    payload = write_route_json(
        out_dir / f"route_{route_id}.json", spec,
        origin=origin, route_xz=drive_xz, route_width=widths, stops=stops,
        signals=signals,
```

- [ ] **Step 4: 파이썬 통과 확인**

Run: `python3 -m unittest discover -s tests -t .`
Expected: `OK` (152 개).

- [ ] **Step 5: 재베이크**

```bash
for id in seoul-100 seoul-654 seoul-seodaemun03; do python3 -m tools.osmbake.cli bake $id; done
python3 -c "
import json
for rid in ['seoul-100', 'seoul-654', 'seoul-seodaemun03']:
    d = json.load(open(f'assets/routes/route_{rid}.json'))
    assert len(d['route_width']) == len(d['route']), rid
    print(rid, len(d['route']), min(d['route_width']), max(d['route_width']))
"
git status --short assets/routes
```

Expected: 세 노선 모두 길이가 같고 폭이 대략 3~20 m. 경로점 수는 전과 같다(100번 636, 654번 490, 서대문03 181). 달라졌으면 멈추고 보고한다.

- [ ] **Step 6: GDScript 실패 테스트**

`tests/game/test_route_data.gd` 의 마지막 `finish()` 바로 앞에:

```gdscript
	# 경로점별 도로 폭. 마주 오는 차선이 이것으로 반대편 차선 중앙을 잡는다.
	ok(data.route_width.size() == data.route.size(),
		"route_width %d 개, route %d 개" % [data.route_width.size(), data.route.size()])
	ok(data.route_width[0] >= 3.0, "도로 폭이 이상하다: %.2f" % data.route_width[0])
	var part := data.slice(0)
	ok(part.route_width.size() == part.route.size(),
		"잘린 뒤 route_width %d 개, route %d 개"
		% [part.route_width.size(), part.route.size()])
```

Run: `tests/game/run_game_tests.sh test_route_data`
Expected: FAIL (`route_width` 가 없다는 파싱 에러로 `TEST_OK` 없음).

- [ ] **Step 7: RouteData 구현**

`scripts/route_data.gd` 상수 블록(`SECTION_SIGNAL_M` 다음 줄):

```gdscript
const DEFAULT_ROAD_WIDTH_M := 7.0  # route_width 가 없는 옛 산출물
```

필드(`var route` 다음 줄):

```gdscript
var route_width: PackedFloat32Array = []   # 경로점별 도로 폭. route 와 같은 길이
```

`load_route` 의 route 루프 다음:

```gdscript
	for width in parsed.get("route_width", []):
		data.route_width.append(float(width))
	if data.route_width.size() != data.route.size():
		# 옛 산출물에는 폭이 없다. 기본 폭으로 채운다.
		data.route_width = PackedFloat32Array()
		data.route_width.resize(data.route.size())
		data.route_width.fill(DEFAULT_ROAD_WIDTH_M)
```

`slice()` 의 `part.route = _route_between(start_m, end_m)` 다음:

```gdscript
	# 손수 만든 RouteData(테스트)는 폭이 없다. 있을 때만 자른다.
	if route_width.size() == route.size():
		part.route_width = _widths_between(start_m, end_m)
```

`_route_between` 아래에 두 함수 추가. `_widths_between` 은 `_route_between` 과 같은 규칙으로 점을 고르므로 길이가 같다.

```gdscript
func _widths_between(start_m: float, end_m: float) -> PackedFloat32Array:
	"""_route_between 과 같은 점들의 폭. 보간점은 가까운 원래 점의 폭."""
	var part := PackedFloat32Array([_width_at_progress(start_m)])
	var travelled := 0.0
	for index in range(1, route.size()):
		travelled += route[index - 1].distance_to(route[index])
		if travelled > start_m and travelled < end_m:
			part.append(route_width[index])
	part.append(_width_at_progress(end_m))
	return part

func _width_at_progress(distance_m: float) -> float:
	var travelled := 0.0
	for index in range(1, route.size()):
		var span := route[index - 1].distance_to(route[index])
		if travelled + span >= distance_m:
			return route_width[index - 1] if distance_m - travelled < span * 0.5 else route_width[index]
		travelled += span
	return route_width[route_width.size() - 1]
```

- [ ] **Step 8: 통과 확인**

Run: `tests/game/run_game_tests.sh test_route_data test_sections`
Expected: 둘 다 OK.

- [ ] **Step 9: 커밋**

```bash
git checkout -q project.godot
git add tools/osmbake/emit.py tools/osmbake/cli.py tests/osmbake/test_emit.py scripts/route_data.gd tests/game/test_route_data.gd assets/routes/route_seoul-100.json assets/routes/route_seoul-654.json assets/routes/route_seoul-seodaemun03.json
# glb 가 바뀌었으면 git status 로 보고 그것도 이름을 적어 add
git commit -m "feat: 베이크에 경로점별 도로 폭 route_width 추가

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `CarFollow`

**Files:**
- Create: `scripts/car_follow.gd`
- Create: `tests/game/test_car_follow.gd`, `tests/game/test_car_follow.tscn`
- Modify: `tests/game/run_game_tests.sh` (씬 목록)

**Interfaces:**
- Produces: `CarFollow.CRUISE_MPS`, `ACCEL`, `BRAKE`, `static min_gap(speed: float) -> float`, `static next_speed(speed: float, gap_m: float, stop_m: float, phase: TrafficSignal.Phase, delta: float) -> float`. `gap_m`/`stop_m` 은 없으면 `INF`.

- [ ] **Step 1: 실패 테스트**

`tests/game/test_car_follow.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_car_follow.gd" id="1"]

[node name="TestCarFollow" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_car_follow.gd`:

```gdscript
extends TestCase
# 차 한 대의 속도 규칙. 순수 계산이라 트리가 필요 없다. 위치는 여기서 적분한다.

const DT := 1.0 / 60.0
const GREEN := TrafficSignal.Phase.GREEN
const YELLOW := TrafficSignal.Phase.YELLOW
const RED := TrafficSignal.Phase.RED

func _ready() -> void:
	# 가속은 프레임당 ACCEL x delta 를 넘지 않는다.
	equal_approx(CarFollow.next_speed(0.0, INF, INF, GREEN, DT), CarFollow.ACCEL * DT,
		0.0001, "출발 가속")

	# 빈 도로에서 순항 속도까지 오르고 넘지 않는다.
	var speed := 0.0
	for frame in 600:
		speed = CarFollow.next_speed(speed, INF, INF, GREEN, DT)
	equal_approx(speed, CarFollow.CRUISE_MPS, 0.001, "순항 속도")

	# 순항 중 30 m 앞 적색 정지선: 넘지 않고 그 앞에 선다.
	var x := 0.0
	speed = CarFollow.CRUISE_MPS
	for frame in 1200:
		speed = CarFollow.next_speed(speed, INF, 30.0 - x, RED, DT)
		x += speed * DT
	ok(x <= 30.0 + 0.01, "적색 정지선을 넘었다 (%.3f m)" % x)
	ok(x > 29.0, "정지선 한참 앞에 섰다 (%.3f m)" % x)
	ok(speed < 0.01, "적색 앞에서 안 섰다 (%.3f m/s)" % speed)

	# 설 수 없는 황색(5 m 앞, 제동거리 10 m)은 지나간다. 설 수 있으면(30 m) 선다.
	ok(CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, 5.0, YELLOW, DT)
		>= CarFollow.CRUISE_MPS - 0.0001, "설 수 없는 황색에서 제동했다")
	ok(CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, 30.0, YELLOW, DT)
		< CarFollow.CRUISE_MPS, "설 수 있는 황색에서 안 줄였다")
	# 녹색 정지선은 없는 것과 같다.
	ok(CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, 1.0, GREEN, DT)
		>= CarFollow.CRUISE_MPS - 0.0001, "녹색에서 제동했다")

	# 50 m 앞 멈춘 차 뒤에 MIN_GAP_M(정지 시 6 m)을 두고 선다.
	x = 0.0
	speed = CarFollow.CRUISE_MPS
	for frame in 1200:
		speed = CarFollow.next_speed(speed, 50.0 - x, INF, GREEN, DT)
		x += speed * DT
	var gap := 50.0 - x
	ok(gap >= CarFollow.min_gap(0.0) - 0.05, "앞차에 너무 붙었다 (%.2f m)" % gap)
	ok(gap < CarFollow.min_gap(0.0) + 1.0, "앞차 한참 뒤에 섰다 (%.2f m)" % gap)
	ok(speed < 0.01, "앞차 뒤에서 안 섰다")
	finish()
```

`tests/game/run_game_tests.sh` 의 `scenes=(...)` 에서 `drive_smoke` 앞에 `test_car_follow` 를 넣는다.

Run: `tests/game/run_game_tests.sh test_car_follow`
Expected: FAIL (`CarFollow` 없음).

- [ ] **Step 2: 구현**

`scripts/car_follow.gd`:

```gdscript
extends RefCounted
class_name CarFollow
# 교통 차량 한 대의 다음 프레임 속도. 순수 계산이라 헤드리스로 확인한다.
#
# 속도는 세 한도 중 가장 낮은 것을 목표로 삼고, 한 프레임에 ACCEL x delta
# 이상 오르지도 BRAKE x delta 이상 내리지도 않는다. 제동이 유한해서 적색에
# 뛰어든 버스를 교차 차량이 다 못 피할 수 있다 — 위반의 위험이다.

const CRUISE_MPS := 40.0 / 3.6
const ACCEL := 2.0            # m/s²
const BRAKE := 6.0            # m/s²
const HEADWAY_S := 1.5
const STANDSTILL_GAP_M := 6.0
# 황색 앞에서 제동 곡선을 따라 줄이는 중에는 남은 거리와 제동거리가 거의 같다.
# 부동소수 오차로 "못 선다" 쪽으로 넘어가 다시 가속하지 않게 여유를 둔다.
const YELLOW_SLACK_M := 1.0

static func min_gap(speed: float) -> float:
	"""앞 장애물과 둘 안전 거리. 섰을 때 6 m, 빠를수록 길다."""
	return STANDSTILL_GAP_M + speed * HEADWAY_S

static func next_speed(speed: float, gap_m: float, stop_m: float,
		phase: TrafficSignal.Phase, delta: float) -> float:
	var target := CRUISE_MPS
	# 앞 장애물: 안전 거리까지 남은 거리 안에 BRAKE 로 설 수 있는 속도.
	target = minf(target, sqrt(2.0 * BRAKE * maxf(0.0, gap_m - min_gap(speed))))
	# 정지선: 적색은 정지선이 간격 0 장애물이다. 황색은 설 수 있을 때만 선다.
	var must_stop := phase == TrafficSignal.Phase.RED
	if phase == TrafficSignal.Phase.YELLOW:
		must_stop = stop_m + YELLOW_SLACK_M >= speed * speed / (2.0 * BRAKE)
	if must_stop:
		target = minf(target, sqrt(2.0 * BRAKE * maxf(0.0, stop_m)))
	return maxf(0.0, clampf(target, speed - BRAKE * delta, speed + ACCEL * delta))
```

- [ ] **Step 3: 통과 확인**

Run: `/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1; tests/game/run_game_tests.sh test_car_follow`
Expected: `test_car_follow: OK`

- [ ] **Step 4: 커밋**

```bash
git checkout -q project.godot
git add scripts/car_follow.gd scripts/car_follow.gd.uid tests/game/test_car_follow.gd tests/game/test_car_follow.gd.uid tests/game/test_car_follow.tscn tests/game/run_game_tests.sh
git commit -m "feat: 교통 차량 속도 규칙 CarFollow

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `LanePath`

**Files:**
- Create: `scripts/lane_path.gd`
- Create: `tests/game/test_lane_path.gd`, `tests/game/test_lane_path.tscn`
- Modify: `tests/game/run_game_tests.sh`

**Interfaces:**
- Consumes: `TrafficSignal.bearing_of/direction_of/axis_for/offset_for`, `ViolationWatch.DEFAULT_HALF_WIDTH`, `RouteData.DEFAULT_ROAD_WIDTH_M`.
- Produces:
  - `LanePath.make(points: PackedVector3Array) -> LanePath`
  - `LanePath.oncoming(route: PackedVector3Array, widths: PackedFloat32Array) -> PackedVector3Array` (좌측 `width*0.5` 이동 후 뒤집음)
  - `LanePath.crossing(center: Vector3, bearing_deg: float, half_width: float, axis: int, offset_s: float) -> LanePath` (정지선 하나 포함)
  - `length_m() -> float`, `sample(distance: float) -> Vector3`, `direction_at(distance: float) -> Vector3`, `project(point: Vector3) -> Vector2` (x=누적 거리, y=차선까지 수평 거리)
  - `add_signals(signals: Array, reach_m: float)`, `next_stop(front_m: float) -> Dictionary` (없으면 `{}`)
  - `stops: Array` — `{"at_m": float, "offset": float, "axis": int, "signal": int}` `at_m` 오름차순. 교차 차선은 `signal == -1`.

- [ ] **Step 1: 실패 테스트**

`tests/game/test_lane_path.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_lane_path.gd" id="1"]

[node name="TestLanePath" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_lane_path.gd`:

```gdscript
extends TestCase
# 차선 기하. 동쪽으로 곧은 100 m 길 하나로 본다.

func _ready() -> void:
	var route := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(50.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0)])
	var lane := LanePath.make(route)
	equal_approx(lane.length_m(), 100.0, 0.001, "차선 길이")
	equal_approx(lane.sample(25.0).x, 25.0, 0.001, "누적 거리 위치 보간")
	equal_approx(lane.sample(75.0).x, 75.0, 0.001, "둘째 구간 보간")
	equal_approx(lane.direction_at(25.0).x, 1.0, 0.001, "진행 방향")
	var on := lane.project(Vector3(30.0, 5.0, 4.0))
	equal_approx(on.x, 30.0, 0.001, "투영 누적 거리")
	equal_approx(on.y, 4.0, 0.001, "투영 옆 거리 (높이는 무시)")

	# 동쪽 진행의 왼쪽은 북(-Z). 폭 10 m 면 5 m 북쪽에서 서쪽으로 간다.
	var oncoming := LanePath.make(LanePath.oncoming(route,
		PackedFloat32Array([10.0, 10.0, 10.0])))
	equal_approx(oncoming.sample(0.0).x, 100.0, 0.001, "마주 오는 차선이 안 뒤집혔다")
	equal_approx(oncoming.sample(0.0).z, -5.0, 0.001, "마주 오는 차선 오프셋")
	equal_approx(oncoming.sample(60.0).z, -5.0, 0.001, "마주 오는 차선 중간 오프셋")
	equal_approx(oncoming.direction_at(50.0).x, -1.0, 0.001, "마주 오는 차선 방향")

	# 교차로 (60, 0), 반폭 8, 축 [0, 90]. 동쪽 진행은 축 1. 정지선 60 - 8 - 2 = 50.
	# 둘째 신호는 차선에서 100 m 떨어져 안 잡혀야 한다.
	lane.add_signals([
		{"x": 60.0, "z": 0.0, "axis_deg": [0.0, 90.0], "half_width": 8.0},
		{"x": 60.0, "z": 100.0, "axis_deg": [0.0, 90.0], "half_width": 8.0}], 30.0)
	ok(lane.stops.size() == 1, "정지선이 %d 개다" % lane.stops.size())
	if lane.stops.size() == 1:
		equal_approx(lane.stops[0]["at_m"], 50.0, 0.01, "정지선 누적 거리")
		ok(lane.stops[0]["axis"] == 1, "동쪽 진행인데 축 %d" % lane.stops[0]["axis"])
		ok(lane.stops[0]["signal"] == 0, "신호 인덱스가 틀렸다")
		ok(not lane.next_stop(49.0).is_empty(), "정지선 1 m 앞에서 못 찾았다")
		ok(lane.next_stop(51.0).is_empty(), "지난 정지선을 또 찾았다")

	# 교차 차선: 원점, 북쪽 진행, 반폭 10. 길이 앞뒤 40 m, 오른쪽(동)으로 5 m.
	var cross := LanePath.crossing(Vector3.ZERO, 0.0, 10.0, 0, 3.0)
	equal_approx(cross.length_m(), 80.0, 0.001, "교차 차선 길이")
	equal_approx(cross.sample(0.0).x, 5.0, 0.001, "교차 차선 오른쪽 오프셋")
	equal_approx(cross.sample(0.0).z, 40.0, 0.001, "교차 차선 시작점")
	equal_approx(cross.direction_at(10.0).z, -1.0, 0.001, "교차 차선 방향")
	ok(cross.stops.size() == 1, "교차 차선 정지선이 %d 개" % cross.stops.size())
	if cross.stops.size() == 1:
		equal_approx(cross.stops[0]["at_m"], 28.0, 0.01, "교차 차선 정지선 (40 - 10 - 2)")
	# 좁은 교차로도 30 m 는 확보한다.
	equal_approx(LanePath.crossing(Vector3.ZERO, 0.0, 3.0, 0, 0.0).length_m(), 60.0,
		0.001, "교차 차선 하한")
	finish()
```

`run_game_tests.sh` 목록에서 `test_car_follow` 뒤에 `test_lane_path`.

Run: `tests/game/run_game_tests.sh test_lane_path`
Expected: FAIL (`LanePath` 없음).

- [ ] **Step 2: 구현**

`scripts/lane_path.gd`:

```gdscript
extends RefCounted
class_name LanePath
# 차선 하나. 경로점과 누적 거리를 들고, 누적 거리로 위치와 진행 방향을 낸다.
# 자기 위의 정지선(신호 교차로)도 안다. 그리지 않는다.

const STOP_LINE_MARGIN_M := 2.0   # ViolationWatch 와 같은 정지선 여유
const STOP_PASSED_M := 0.1        # 앞 범퍼가 이만큼 넘은 정지선은 지난 것이다
const CROSS_MIN_M := 30.0
const CROSS_MAX_M := 60.0

var points: PackedVector3Array = []
var cumulative: PackedFloat32Array = []
var stops: Array = []   # {"at_m", "offset", "axis", "signal"}, at_m 오름차순

static func make(route: PackedVector3Array) -> LanePath:
	var lane := LanePath.new()
	var sums := PackedFloat32Array([0.0])
	for index in range(1, route.size()):
		sums.append(sums[index - 1] + route[index].distance_to(route[index - 1]))
	lane.points = route
	lane.cumulative = sums
	return lane

static func oncoming(route: PackedVector3Array, widths: PackedFloat32Array) -> PackedVector3Array:
	"""버스 주행선을 왼쪽으로 폭의 절반 밀고 뒤집은 반대편 차선.

	주행선은 도로 중심에서 오른쪽으로 폭의 1/4 이다. 왼쪽으로 1/2 밀면 반대편
	차선 중앙이다."""
	var shifted := PackedVector3Array()
	for index in route.size():
		var forward := route[mini(index + 1, route.size() - 1)] - route[maxi(index - 1, 0)]
		forward.y = 0.0
		forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
		var left := Vector3(forward.z, 0.0, -forward.x)
		var width := widths[index] if index < widths.size() else RouteData.DEFAULT_ROAD_WIDTH_M
		shifted.append(route[index] + left * width * 0.5)
	shifted.reverse()
	return shifted

static func crossing(center: Vector3, bearing_deg: float, half_width: float,
		axis: int, offset_s: float) -> LanePath:
	"""교차로 중심을 지나는 직선 차선. 진행 방향 오른쪽으로 반폭의 절반 비킨다."""
	var forward := TrafficSignal.direction_of(bearing_deg)
	var side := Vector3(-forward.z, 0.0, forward.x) * half_width * 0.5
	var reach := clampf(half_width * 4.0, CROSS_MIN_M, CROSS_MAX_M)
	var lane := make(PackedVector3Array([center - forward * reach + side,
		center + forward * reach + side]))
	lane.stops.append({"at_m": reach - half_width - STOP_LINE_MARGIN_M,
		"offset": offset_s, "axis": axis, "signal": -1})
	return lane

func length_m() -> float:
	return cumulative[cumulative.size() - 1] if cumulative.size() > 0 else 0.0

func sample(distance: float) -> Vector3:
	"""누적 거리 위의 점. 이분 탐색이라 경로점이 늘어도 싸다."""
	var low := 0
	var high := cumulative.size() - 1
	while low + 1 < high:
		var mid := (low + high) / 2
		if cumulative[mid] <= distance:
			low = mid
		else:
			high = mid
	var span := cumulative[high] - cumulative[low]
	if span <= 0.0:
		return points[low]
	return points[low].lerp(points[high], clampf((distance - cumulative[low]) / span, 0.0, 1.0))

func direction_at(distance: float) -> Vector3:
	var ahead := sample(minf(distance + 2.0, length_m()))
	var behind := sample(maxf(distance - 2.0, 0.0))
	var forward := ahead - behind
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

func project(point: Vector3) -> Vector2:
	"""(누적 거리, 차선까지 수평 거리). 높이는 무시한다."""
	# ponytail: 경로점 전체를 훑는다(100번 636 점). 프레임당 몇 번뿐이라 놔둔다.
	# 느려지면 직전 결과 둘레만 훑는다.
	var flat := Vector3(point.x, 0.0, point.z)
	var best := INF
	var along := 0.0
	for index in range(1, points.size()):
		var start := points[index - 1]
		var foot := Geometry3D.get_closest_point_to_segment(flat, start, points[index])
		var distance := foot.distance_to(flat)
		if distance < best:
			best = distance
			along = cumulative[index - 1] + start.distance_to(foot)
	return Vector2(along, best)

func add_signals(signals: Array, reach_m: float) -> void:
	"""차선에서 reach_m 안의 신호마다 진행 방향 축과 정지선 누적 거리를 구해 둔다."""
	for index in signals.size():
		var entry: Dictionary = signals[index]
		if not entry.has("axis_deg") or entry["axis_deg"].size() < 2:
			continue
		var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		var on := project(center)
		if on.y > reach_m:
			continue
		var half := float(entry.get("half_width", ViolationWatch.DEFAULT_HALF_WIDTH))
		var at_m := on.x - half - STOP_LINE_MARGIN_M
		if at_m < 0.0:
			continue
		var heading := TrafficSignal.bearing_of(direction_at(on.x))
		stops.append({"at_m": at_m,
			"offset": TrafficSignal.offset_for(center.x, center.z),
			"axis": TrafficSignal.axis_for(heading, entry["axis_deg"]),
			"signal": index})
	stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at_m"] < b["at_m"])

func next_stop(front_m: float) -> Dictionary:
	"""앞 범퍼 누적 거리에서 아직 안 지난 첫 정지선. 없으면 빈 사전."""
	for line in stops:
		if line["at_m"] > front_m - STOP_PASSED_M:
			return line
	return {}
```

- [ ] **Step 3: 통과 확인**

Run: `/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1; tests/game/run_game_tests.sh test_lane_path`
Expected: `test_lane_path: OK`

- [ ] **Step 4: 커밋**

```bash
git checkout -q project.godot
git add scripts/lane_path.gd scripts/lane_path.gd.uid tests/game/test_lane_path.gd tests/game/test_lane_path.gd.uid tests/game/test_lane_path.tscn tests/game/run_game_tests.sh
git commit -m "feat: 차선 기하와 정지선 LanePath

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `Traffic` (노선 차량·교차 차량·경찰차)

**Files:**
- Create: `scripts/traffic.gd`
- Create: `tests/game/test_traffic.gd`, `tests/game/test_traffic.tscn`
- Modify: `tests/game/run_game_tests.sh`

**Interfaces:**
- Consumes: Task 1 `RouteData.route_width`, Task 2 `CarFollow.next_speed`, Task 3 `LanePath` 전부.
- Produces:
  - `Traffic.build(data: RouteData, bus: Node3D)` — `bus` 는 트리 안에 있어야 한다. `null` 이면 차선 시작점을 버스 자리로 본다.
  - `Traffic.cars: Array` — 원소는 `Traffic.Car` (`body: AnimatableBody3D`, `lane: LanePath` (쉬는 교차 차량은 `null`), `distance`, `speed`, `hold_s`, `is_police`, `crossing: int` (교차 차량의 신호 인덱스, 노선 차량 −1)).
  - `same_lane`, `oncoming_lane: LanePath`.
  - `car_of(body: Object) -> Car` (없으면 null), `hold(body: Object, seconds: float)`, `police_sees(point: Vector3) -> bool`.
  - 상수 `SAME_COUNT`, `ONCOMING_COUNT`, `CROSS_MAX`, `AHEAD_M`, `BEHIND_M`, `SPAWN_GAP_M`, `CAR_HALF_LENGTH_M`, `POLICE_SIGHT_M`.

- [ ] **Step 1: 실패 테스트**

`tests/game/test_traffic.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_traffic.gd" id="1"]

[node name="TestTraffic" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_traffic.gd`:

```gdscript
extends TestCase
# seoul-100 실데이터 위에서 교통을 20 초 돌린다. 버스 대신 빈 Node3D 를 노선을
# 따라 옮긴다 — 교통은 버스 위치만 본다. 신호 시계는 테스트가 물리 시간으로
# 돌린다. 실제 시계를 쓰면 헤드리스 속도에 따라 황색 3 초가 늘었다 줄었다 한다.

const RUN_S := 20.0
const MOVER_MPS := 8.0
const MIN_BUMPER_GAP_M := 4.0
const TELEPORT_M := 5.0     # 한 프레임에 이보다 많이 옮겨졌으면 재활용이다

var traffic: Traffic
var mover: Node3D
var lane: LanePath
var mover_m := 0.0
var elapsed := 0.0
var previous_front := {}    # Car -> 직전 앞 범퍼 누적 거리
var red_runs := 0
var tight := 0
var stopped_at_red := false
var saw_cross := false
var start_distances: Array = []
var done := false

func _ready() -> void:
	TrafficSignal.time_override = 0.0
	var data := RouteData.load_route("seoul-100")
	lane = LanePath.make(data.route)
	lane.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)
	ok(not lane.stops.is_empty(), "seoul-100 에 정지선이 없다")
	if lane.stops.is_empty():
		finish()
		return
	# 첫 교차로 100 m 앞에서 출발한다. 교차 차량이 바로 생긴다.
	mover_m = maxf(float(lane.stops[0]["at_m"]) - 100.0, 0.0)
	mover = Node3D.new()
	add_child(mover)
	mover.global_position = lane.sample(mover_m)

	traffic = Traffic.new()
	traffic.build(data, mover)
	add_child(traffic)
	ok(traffic.cars.size() == Traffic.SAME_COUNT + Traffic.ONCOMING_COUNT + Traffic.CROSS_MAX,
		"차가 %d 대다" % traffic.cars.size())
	var police := 0
	for car in traffic.cars:
		if car.is_police:
			police += 1
	ok(police == 2, "경찰차가 %d 대다" % police)
	start_distances = traffic.cars.map(func(car) -> float: return car.distance)

func _physics_process(delta: float) -> void:
	if done or traffic == null:
		return
	# Traffic 은 자식이라 이 노드 다음에 돈다. 여기서 보는 위치는 직전 프레임
	# 결과고, 그때 쓴 신호 시각은 아직 올리기 전인 지금 값이다.
	_check(TrafficSignal.now())
	elapsed += delta
	TrafficSignal.time_override += delta
	mover_m = minf(mover_m + MOVER_MPS * delta, lane.length_m())
	mover.global_position = lane.sample(mover_m)
	if elapsed >= RUN_S:
		_report()

func _check(t: float) -> void:
	var by_lane := {}
	for car in traffic.cars:
		if car.crossing >= 0:
			saw_cross = true
		if car.lane == null:
			continue
		if not by_lane.has(car.lane):
			by_lane[car.lane] = []
		by_lane[car.lane].append(car)
		var front: float = car.distance + Traffic.CAR_HALF_LENGTH_M
		var was: float = previous_front.get(car, front)
		previous_front[car] = front
		if front > was and front - was < TELEPORT_M:
			for line in car.lane.stops:
				var at: float = line["at_m"]
				if was < at and front >= at and TrafficSignal.phase_at(
						line["offset"], line["axis"], t) == TrafficSignal.Phase.RED:
					red_runs += 1
		if car.speed < 0.1:
			var line: Dictionary = car.lane.next_stop(front)
			if not line.is_empty() and float(line["at_m"]) - front < 3.0 \
					and TrafficSignal.phase_at(line["offset"], line["axis"], t) \
					== TrafficSignal.Phase.RED:
				stopped_at_red = true
	for queue in by_lane.values():
		queue.sort_custom(func(a, b) -> bool: return a.distance < b.distance)
		for index in range(1, queue.size()):
			var gap: float = queue[index].distance - queue[index - 1].distance \
				- Traffic.CAR_HALF_LENGTH_M * 2.0
			if gap < MIN_BUMPER_GAP_M:
				tight += 1

func _report() -> void:
	done = true
	ok(red_runs == 0, "적색 정지선을 넘은 차가 %d 번" % red_runs)
	ok(stopped_at_red, "적색 정지선 앞에 선 차가 한 번도 없다")
	ok(tight == 0, "범퍼 간격 %.0f m 미만이 %d 번" % [MIN_BUMPER_GAP_M, tight])
	ok(saw_cross, "교차 차량이 안 생겼다")
	var moved := false
	for index in traffic.cars.size():
		if absf(traffic.cars[index].distance - start_distances[index]) > 1.0:
			moved = true
	ok(moved, "차가 하나도 안 움직였다")
	# 버스 창 안에 같은 방향 차가 거의 다 있어야 한다. 재활용이 막힌 한 대는 봐준다.
	var along := traffic.same_lane.project(mover.global_position).x
	var inside := 0
	for car in traffic.cars:
		if car.lane == traffic.same_lane \
				and car.distance >= along - Traffic.BEHIND_M - Traffic.SPAWN_GAP_M \
				and car.distance <= along + Traffic.AHEAD_M + Traffic.SPAWN_GAP_M:
			inside += 1
	ok(inside >= Traffic.SAME_COUNT - 1, "창 안 같은 방향 차가 %d 대다" % inside)
	TrafficSignal.time_override = -1.0
	finish()
```

`run_game_tests.sh` 목록에서 `test_lane_path` 뒤에 `test_traffic`.

Run: `tests/game/run_game_tests.sh test_traffic`
Expected: FAIL (`Traffic` 없음).

- [ ] **Step 2: 구현**

`scripts/traffic.gd`:

```gdscript
extends Node3D
class_name Traffic
# 노선 위 일반 차량, 신호 교차로의 교차 차량, 경찰차. 물리 차량이 아니라
# 스크립트가 차선 누적 거리를 따라 옮기는 충돌 몸체(AnimatableBody3D)다.
# 속도는 CarFollow 가, 차선과 정지선은 LanePath 가 낸다.
#
# 차는 버스 둘레 창 안에만 둔다. 창을 벗어난 차는 지우지 않고 반대쪽 끝으로
# 옮겨 다시 쓴다. 노드는 build() 에서 만든 것을 끝까지 쓴다.

const SAME_COUNT := 6
const ONCOMING_COUNT := 6
const AHEAD_M := 250.0
const BEHIND_M := 100.0
const FIRST_AHEAD_M := 30.0       # 처음 배치할 때 버스 바로 앞은 비운다
const SPAWN_GAP_M := 20.0
const CROSS_RADIUS_M := 150.0
const CROSS_MAX := 6
const CROSS_SITES := 3            # CROSS_MAX 의 절반. 교차로마다 두 방향
const BUS_LANE_REACH_M := 3.0
const BUS_HALF_LENGTH_M := 5.5    # Bus 충돌 상자 길이 11 m 의 절반
const POLICE_SIGHT_M := 80.0
const BODY_SIZE := Vector3(1.8, 1.4, 4.6)
const CAR_HALF_LENGTH_M := 2.3    # BODY_SIZE.z 의 절반
const BODY_COLORS := [Color(0.55, 0.56, 0.58), Color(0.92, 0.92, 0.90),
	Color(0.08, 0.08, 0.09)]
const POLICE_COLOR := Color(0.10, 0.18, 0.55)
const BEACON_COLOR := Color(0.90, 0.10, 0.12)
const HIDDEN_Y := -100.0          # 쉬는 교차 차량을 치워 두는 높이

class Car:
	var body: AnimatableBody3D
	var lane: LanePath             # null 이면 쉬는 교차 차량
	var distance := 0.0
	var speed := 0.0
	var hold_s := 0.0
	var is_police := false
	var crossing := -1             # 교차 차량이 맡은 신호 인덱스. 노선 차량은 -1

var cars: Array = []
var same_lane: LanePath
var oncoming_lane: LanePath

var _bus: Node3D
var _signals: Array = []
var _cross_lanes: Dictionary = {}  # 신호 인덱스 -> [LanePath, LanePath]

func build(data: RouteData, bus: Node3D) -> void:
	_bus = bus
	if data.route.size() < 2:
		# 경로가 없으면 차도 없다.
		return
	_signals = data.signals
	same_lane = LanePath.make(data.route)
	same_lane.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)
	oncoming_lane = LanePath.make(LanePath.oncoming(data.route, data.route_width))
	oncoming_lane.add_signals(data.signals, RouteData.SECTION_SIGNAL_M)

	# 같은 방향 차는 버스 앞에만 깐다. 뒤에 깔면 첫 프레임에 버스와 겹칠 수 있다.
	var along := same_lane.project(_bus_point()).x
	for index in SAME_COUNT:
		var car := _make_car(index == 0, index)
		car.lane = same_lane
		car.distance = minf(along + FIRST_AHEAD_M
			+ (AHEAD_M - FIRST_AHEAD_M) * index / SAME_COUNT, same_lane.length_m())
	# 마주 오는 차선에서 버스 앞은 누적 거리가 작은 쪽이다.
	var facing := oncoming_lane.project(_bus_point()).x
	for index in ONCOMING_COUNT:
		var car := _make_car(index == 0, index + 1)
		car.lane = oncoming_lane
		car.distance = clampf(facing - AHEAD_M
			+ (AHEAD_M + BEHIND_M) * (index + 0.5) / ONCOMING_COUNT,
			0.0, oncoming_lane.length_m())
	for index in CROSS_MAX:
		_make_car(false, index + 2)
	_place_all()

func _make_car(is_police: bool, color_index: int) -> Car:
	var car := Car.new()
	car.is_police = is_police
	var body := AnimatableBody3D.new()
	# 스크립트가 옮긴 만큼 물리 속도를 매겨, 움직이는 차에 닿은 버스가 제대로 밀린다.
	body.sync_to_physics = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = BODY_SIZE
	shape.shape = box
	shape.position.y = BODY_SIZE.y * 0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = BODY_SIZE
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = POLICE_COLOR if is_police \
		else BODY_COLORS[color_index % BODY_COLORS.size()]
	mesh.material_override = material
	mesh.position.y = BODY_SIZE.y * 0.5
	body.add_child(mesh)
	if is_police:
		var beacon := MeshInstance3D.new()
		var beacon_mesh := BoxMesh.new()
		beacon_mesh.size = Vector3(1.0, 0.2, 0.3)
		beacon.mesh = beacon_mesh
		var beacon_material := StandardMaterial3D.new()
		beacon_material.albedo_color = BEACON_COLOR
		beacon_material.emission_enabled = true
		beacon_material.emission = BEACON_COLOR
		beacon.material_override = beacon_material
		beacon.position.y = BODY_SIZE.y + 0.1
		body.add_child(beacon)
	add_child(body)
	car.body = body
	cars.append(car)
	return car

func _bus_point() -> Vector3:
	if _bus != null and _bus.is_inside_tree():
		return _bus.global_position
	return same_lane.sample(0.0)

func _physics_process(delta: float) -> void:
	if same_lane == null:
		return
	var bus_point := _bus_point()
	_update_crossings(bus_point)
	var t := TrafficSignal.now()
	var by_lane := {}
	for car in cars:
		if car.lane == null:
			continue
		if not by_lane.has(car.lane):
			by_lane[car.lane] = []
		by_lane[car.lane].append(car)
	# 버스를 차선마다 한 번씩만 투영한다. 재활용도 같은 값을 쓴다.
	var bus_on := {}
	for lane in by_lane:
		bus_on[lane] = lane.project(bus_point) if _bus != null else Vector2(INF, INF)
		var queue: Array = by_lane[lane]
		queue.sort_custom(func(a: Car, b: Car) -> bool: return a.distance < b.distance)
		for index in queue.size():
			var leader: Car = queue[index + 1] if index + 1 < queue.size() else null
			_drive(queue[index], leader, bus_on[lane], t, delta)
	_recycle(bus_on)
	_place_all()

func _drive(car: Car, leader: Car, bus_on: Vector2, t: float, delta: float) -> void:
	if car.hold_s > 0.0:
		car.hold_s = maxf(car.hold_s - delta, 0.0)
		car.speed = 0.0
		return
	var front := car.distance + CAR_HALF_LENGTH_M
	var gap := INF
	if leader != null:
		gap = leader.distance - CAR_HALF_LENGTH_M - front
	# 차선 옆으로 비켜 선 버스(정류장)는 장애물이 아니다. 그러면 뒤차가 영원히 선다.
	if bus_on.y <= BUS_LANE_REACH_M and bus_on.x > car.distance:
		gap = minf(gap, bus_on.x - BUS_HALF_LENGTH_M - front)
	var stop_m := INF
	var phase := TrafficSignal.Phase.GREEN
	var line := car.lane.next_stop(front)
	if not line.is_empty():
		stop_m = float(line["at_m"]) - front
		phase = TrafficSignal.phase_at(float(line["offset"]), int(line["axis"]), t)
	car.speed = CarFollow.next_speed(car.speed, gap, stop_m, phase, delta)
	car.distance = minf(car.distance + car.speed * delta, car.lane.length_m())

func _recycle(bus_on: Dictionary) -> void:
	for car in cars:
		if car.lane == null or not bus_on.has(car.lane):
			continue
		var on: Vector2 = bus_on[car.lane]
		if car.lane == same_lane:
			_recycle_one(car, on.x - BEHIND_M, on.x + AHEAD_M, on)
		elif car.lane == oncoming_lane:
			_recycle_one(car, on.x - AHEAD_M, on.x + BEHIND_M, on)
		elif car.distance >= car.lane.length_m() and _free_at(car.lane, 0.0, car, on):
			# 교차 차량은 차선 끝에 닿으면 처음으로 돌아간다.
			car.distance = 0.0
			car.speed = 0.0

func _recycle_one(car: Car, low: float, high: float, bus_on: Vector2) -> void:
	var length := car.lane.length_m()
	low = maxf(low, 0.0)
	high = minf(high, length)
	var target: float
	if car.distance > high or car.distance >= length:
		target = low
	elif car.distance < low:
		target = high
	else:
		return
	# 자리가 차 있으면 이번 프레임은 놔둔다. 다음 프레임에 다시 본다.
	if _free_at(car.lane, target, car, bus_on):
		car.distance = target
		car.speed = 0.0

func _free_at(lane: LanePath, distance: float, moving: Car, bus_on: Vector2) -> bool:
	if bus_on.y <= BUS_LANE_REACH_M and absf(bus_on.x - distance) < SPAWN_GAP_M:
		return false
	for other in cars:
		if other != moving and other.lane == lane \
				and absf(other.distance - distance) < SPAWN_GAP_M:
			return false
	return true

func _update_crossings(bus_point: Vector3) -> void:
	# 버스 반경 안 노선 신호를 가까운 순으로 CROSS_SITES 곳까지 고른다.
	var nearest := {}   # 신호 인덱스 -> [거리, 정지선]
	for line in same_lane.stops:
		var entry: Dictionary = _signals[int(line["signal"])]
		var distance := Vector2(float(entry["x"]) - bus_point.x,
			float(entry["z"]) - bus_point.z).length()
		if distance <= CROSS_RADIUS_M:
			nearest[int(line["signal"])] = [distance, line]
	var picked := nearest.keys()
	picked.sort_custom(func(a: int, b: int) -> bool: return nearest[a][0] < nearest[b][0])
	picked = picked.slice(0, CROSS_SITES)

	# 반경을 벗어난 교차로의 차는 쉬게 한다.
	var served := {}
	for car in cars:
		if car.crossing < 0:
			continue
		if picked.has(car.crossing):
			served[car.crossing] = true
		else:
			car.crossing = -1
			car.lane = null
	for index in picked:
		if served.has(index):
			continue
		for lane in _crossing_lanes(index, nearest[index][1]):
			var car := _idle_car()
			if car == null:
				return
			car.lane = lane
			car.crossing = index
			car.distance = 0.0
			car.speed = 0.0

func _crossing_lanes(index: int, line: Dictionary) -> Array:
	"""버스가 지나지 않는 축으로 교차로를 가로지르는 양방향 차선 둘."""
	if not _cross_lanes.has(index):
		var entry: Dictionary = _signals[index]
		var axis := 1 - int(line["axis"])
		var bearing := float(entry["axis_deg"][axis])
		var center := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		var half := float(entry.get("half_width", ViolationWatch.DEFAULT_HALF_WIDTH))
		var offset := float(line["offset"])
		_cross_lanes[index] = [
			LanePath.crossing(center, bearing, half, axis, offset),
			LanePath.crossing(center, bearing + 180.0, half, axis, offset)]
	return _cross_lanes[index]

func _idle_car() -> Car:
	for car in cars:
		if car.lane == null:
			return car
	return null

func _place_all() -> void:
	# Traffic 은 원점에 있어 transform 이 곧 전역이다. 트리 밖에서도 쓸 수 있다.
	for car in cars:
		if car.lane == null:
			car.body.transform = Transform3D(Basis(), Vector3(0.0, HIDDEN_Y, 0.0))
			continue
		var forward := car.lane.direction_at(car.distance)
		car.body.transform = Transform3D(Basis.looking_at(forward, Vector3.UP),
			car.lane.sample(car.distance))

func car_of(body: Object) -> Car:
	for car in cars:
		if car.body == body:
			return car
	return null

func hold(body: Object, seconds: float) -> void:
	"""그 차를 seconds 동안 세운다. 이미 더 길게 서 있으면 그대로 둔다."""
	var car := car_of(body)
	if car == null:
		return
	car.hold_s = maxf(car.hold_s, seconds)
	car.speed = 0.0

func police_sees(point: Vector3) -> bool:
	"""어느 경찰차든 point 를 전방 80 m 반구 안에 두고 있는가."""
	for car in cars:
		if not car.is_police:
			continue
		var to_point := point - car.body.global_position
		if to_point.length() > POLICE_SIGHT_M:
			continue
		# 고도트의 정면은 -Z 다.
		if (-car.body.global_transform.basis.z).dot(to_point) > 0.0:
			return true
	return false
```

- [ ] **Step 3: 통과 확인**

Run: `/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1; tests/game/run_game_tests.sh test_traffic`
Expected: `test_traffic: OK`. `stopped_at_red` 가 실패하면 seoul-100 첫 교차로들이 20 초 동안 녹색이었던 것이다 — `RUN_S` 를 40 으로 늘려 보고, 그래도 안 되면 멈추고 보고한다. `tight` 가 실패하면 재활용 직후 겹침이다 — 어느 차선(same/oncoming/cross)인지 찍어 보고 원인을 찾는다.

- [ ] **Step 4: 커밋**

```bash
git checkout -q project.godot
git add scripts/traffic.gd scripts/traffic.gd.uid tests/game/test_traffic.gd tests/game/test_traffic.gd.uid tests/game/test_traffic.tscn tests/game/run_game_tests.sh
git commit -m "feat: 노선 차량·교차 차량·경찰차를 굴리는 Traffic

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 경찰차를 `Traffic` 으로 옮기고 `PatrolCars` 삭제

**Files:**
- Delete: `scripts/patrol_cars.gd`, `scripts/patrol_cars.gd.uid`
- Modify: `scripts/violation_watch.gd` (`var patrol`, `_on_enter` 끝)
- Modify: `scripts/drive.gd:16, 68-75`
- Modify: `tests/game/test_violation.gd` (`_ready`, 순찰 테스트 셋)
- Modify: `tests/game/drive_smoke.gd:126`

**Interfaces:**
- Consumes: Task 4 `Traffic.build/cars/police_sees`.
- Produces: `ViolationWatch.traffic: Traffic`, `Drive.traffic: Traffic` (`Drive.patrol` 은 없어진다).

- [ ] **Step 1: 테스트를 새 API 로 바꾼다 (실패 테스트)**

`tests/game/test_violation.gd`:
- 맨 위 주석 첫 줄 `# 순찰 경찰차와 위반 판정.` → `# 경찰 시야와 위반 판정.`
- `_ready()` 에서 `_test_patrol_follows_route()` 줄을 지우고 `_test_patrol_sight()` → `_test_police_sight()`, `await _test_patrol_busts()` → `await _test_police_busts()`.
- `_test_patrol_follows_route` 함수 전체를 지운다. 경로 추종은 `test_traffic` 이 본다.
- `_test_patrol_sight` 를 아래로 바꾼다.

```gdscript
# 곧은 남북 노선 위 Traffic. 물리 처리를 끄고 테스트가 경찰차를 직접 놓는다.
func _make_traffic() -> Traffic:
	var data := RouteData.new()
	data.route = PackedVector3Array([Vector3(0.0, 0.0, 1000.0), Vector3(0.0, 0.0, -1000.0)])
	data.route_width = PackedFloat32Array([7.0, 7.0])
	var traffic := Traffic.new()
	traffic.build(data, null)
	add_child(traffic)
	traffic.set_physics_process(false)
	# 경찰차 한 대만 남기고 나머지는 멀리 치운다.
	var first := true
	for car in traffic.cars:
		if car.is_police and first:
			first = false
			continue
		car.body.global_position = Vector3(0.0, 0.0, 100000.0)
	return traffic

func _police_body(traffic: Traffic) -> Node3D:
	for car in traffic.cars:
		if car.is_police:
			return car.body
	return null

func _test_police_sight() -> void:
	var traffic := _make_traffic()
	var body := _police_body(traffic)
	body.global_position = Vector3.ZERO
	body.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)   # 북(-Z)을 본다
	ok(traffic.police_sees(Vector3(0.0, 0.0, -50.0)), "전방 50 m 를 못 본다")
	ok(not traffic.police_sees(Vector3(0.0, 0.0, -200.0)), "전방 200 m 를 본다")
	ok(not traffic.police_sees(Vector3(0.0, 0.0, 50.0)), "후방 50 m 를 본다")
	traffic.queue_free()
```

- `_test_patrol_busts` 를 아래로 바꾼다.

```gdscript
func _test_police_busts() -> void:
	var made := _make_watch(false, TrafficSignal.Phase.RED)
	var watch: ViolationWatch = made[0]
	var mover: Node3D = made[1]
	var traffic := _make_traffic()
	# 경찰차를 교차로 남쪽 30 m 에 두고 북쪽(오는 버스 쪽)을 보게 한다.
	var body := _police_body(traffic)
	body.global_position = Vector3(0.0, 0.0, 30.0)
	body.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	watch.traffic = traffic
	await _drive_through(mover)
	ok(watch.is_busted, "경찰차 앞 위반인데 적발되지 않았다")
	watch.queue_free()
	mover.queue_free()
	traffic.queue_free()
```

`tests/game/drive_smoke.gd:126`:

```gdscript
	ok(drive.traffic != null, "Traffic 이 없다")
```

Run: `tests/game/run_game_tests.sh test_violation`
Expected: FAIL (`ViolationWatch` 에 `traffic` 없음).

- [ ] **Step 2: 구현**

`scripts/violation_watch.gd`: `var patrol: PatrolCars` → `var traffic: Traffic`. `_on_enter` 끝:

```gdscript
	if traffic != null and traffic.police_sees(bus.global_position):
```

`scripts/drive.gd`: `var patrol: PatrolCars` → `var traffic: Traffic`. `_ready` 의 patrol 블록과 watch 배선을 바꾼다.

```gdscript
	traffic = Traffic.new()
	traffic.build(data, bus)
	add_child(traffic)

	watch = ViolationWatch.new()
	watch.build(data.signals)
	watch.bus = bus
	watch.traffic = traffic
	add_child(watch)
```

파일을 지운다:

```bash
git rm -q scripts/patrol_cars.gd scripts/patrol_cars.gd.uid
grep -rn "PatrolCars\|patrol" scripts tests
```

Expected: grep 결과 없음(주석 포함). 남은 게 있으면 고친다.

- [ ] **Step 3: 통과 확인**

Run: `/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1; tests/game/run_game_tests.sh test_violation drive_smoke`
Expected: 둘 다 OK. `drive_smoke` 가 "주행 거리" 로 실패하면 버스 자율주행이 앞차에 막힌 것이다 — Task 6 Step 4 의 drive_smoke 충돌 끄기(`collision_layer = 0`)를 여기서 먼저 넣는다.

- [ ] **Step 4: 커밋**

```bash
git checkout -q project.godot
git add scripts/violation_watch.gd scripts/drive.gd tests/game/test_violation.gd tests/game/drive_smoke.gd
git commit -m "refactor: 경찰차를 Traffic 으로 옮기고 PatrolCars 삭제

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(`git rm` 으로 지운 두 파일은 이미 스테이징돼 있다. `git status --short` 로 이 여섯 개만 올라갔는지 본다.)

---

### Task 6: 사고 — `CrashWatch`, 점수, HUD, 배선

**Files:**
- Create: `scripts/crash_watch.gd`
- Create: `tests/game/test_crash.gd`, `tests/game/test_crash.tscn`
- Modify: `scripts/score_card.gd`
- Modify: `scripts/boarding_hud.gd`
- Modify: `scripts/drive.gd`
- Modify: `tests/game/test_score_card.gd`, `tests/game/drive_smoke.gd`, `tests/game/run_game_tests.sh`

**Interfaces:**
- Consumes: Task 4 `Traffic.car_of/hold/cars`, 기존 `BoardingWatch.is_boarding`.
- Produces: `CrashWatch.CRASH_STOP_S`, `CRASH_GRACE_S`, `signal crashed`, `build(bus: RigidBody3D, traffic: Traffic)`, `boarding: BoardingWatch`, `crashes: int`, `is_stopping: bool`. `ScoreCard.CRASH := -200`, `ScoreCard.tally(..., respawns: int, crashes: int = 0)`. `BoardingHud.on_crashed()`. `Drive.crash: CrashWatch`.

- [ ] **Step 1: 실패 테스트**

`tests/game/test_crash.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_crash.gd" id="1"]

[node name="TestCrash" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_crash.gd`:

```gdscript
extends TestCase
# 버스를 세워 둔 차에 밀어 넣어 사고 판정을 본다. 접촉 보고가 실제 물리에서
# 오는지가 요점이라 진짜 Bus 와 바닥을 쓴다.
# 첫 사고 -> 5 초 정지 -> 3 초 유예(계속 밀어도 안 셈) -> 둘째 사고.

const TIMEOUT_S := 40.0
const THROTTLE := 0.5

var bus: Bus
var traffic: Traffic
var crash: CrashWatch
var elapsed := 0.0
var stop_started := -1.0
var stop_ended := -1.0
var second_at := -1.0
var done := false

func _ready() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	add_child(ground)

	bus = Bus.new()
	bus.position = Vector3(0.0, 1.5, 0.0)
	add_child(bus)

	# 버스가 선 자리에서 북(-Z)으로 곧은 노선. 같은 방향 첫 차가 30 m 앞에 선다.
	var data := RouteData.new()
	data.route = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -1000.0)])
	data.route_width = PackedFloat32Array([7.0, 7.0])
	traffic = Traffic.new()
	traffic.build(data, bus)
	add_child(traffic)
	# 차를 전부 세워 둔다. 버스가 들이받을 과녁이다.
	for car in traffic.cars:
		traffic.hold(car.body, 1000.0)

	crash = CrashWatch.new()
	crash.build(bus, traffic)
	add_child(crash)

func _physics_process(delta: float) -> void:
	if done or crash == null:
		return
	elapsed += delta
	if crash.is_stopping:
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		if stop_started < 0.0:
			stop_started = elapsed
	else:
		if stop_started >= 0.0 and stop_ended < 0.0:
			stop_ended = elapsed
		bus.apply_axes(0.0, THROTTLE, 0.0, false, delta)
	if crash.crashes >= 2 and second_at < 0.0:
		second_at = elapsed
	if second_at >= 0.0 or elapsed > TIMEOUT_S:
		_report()

func _report() -> void:
	done = true
	ok(stop_started >= 0.0, "사고가 한 번도 안 났다")
	ok(stop_ended >= 0.0, "사고 정지가 안 끝났다")
	equal_approx(stop_ended - stop_started, CrashWatch.CRASH_STOP_S, 0.1, "사고 정지 시간")
	ok(second_at >= 0.0, "유예가 끝난 뒤 다시 밀어도 사고가 안 세어졌다")
	ok(second_at - stop_ended >= CrashWatch.CRASH_GRACE_S - 0.05,
		"유예 %.2f 초 만에 다시 셌다" % (second_at - stop_ended))
	finish()
```

`tests/game/test_score_card.gd` 의 `finish()` 앞에:

```gdscript
	# 사고 1 회 -200. 감점 한도 150 을 넘으니 별 3 은 없다.
	card = ScoreCard.tally(600.0, 600.0, 0, 0, 0, 0, 0, 0, 1)
	ok(card.total == 800, "사고 %d" % card.total)
	ok(card.stars == 2, "사고 1 회인데 별 %d" % card.stars)
```

`run_game_tests.sh` 목록에서 `test_traffic` 뒤에 `test_crash`.

Run: `tests/game/run_game_tests.sh test_crash test_score_card`
Expected: 둘 다 FAIL (`CrashWatch` 없음, `tally` 인자 수).

- [ ] **Step 2: `CrashWatch` 구현**

`scripts/crash_watch.gd`:

```gdscript
extends Node
class_name CrashWatch
# 버스가 교통 차량에 부딪혔는지 본다. 사고면 버스를 잠깐 세우고(브레이크는
# drive.gd 가 건다) 부딪힌 차도 세운다. 게임 오버는 없다 — 감점은 ScoreCard.

const CRASH_STOP_S := 5.0
const CRASH_GRACE_S := 3.0   # 정지가 끝난 뒤 이 동안의 접촉은 새 사고로 안 센다

signal crashed

var bus: RigidBody3D
var traffic: Traffic
var boarding: BoardingWatch
var crashes := 0

var is_stopping: bool:
	get:
		return _stop_left > 0.0

var _stop_left := 0.0
var _grace_left := 0.0

func build(bus_node: RigidBody3D, traffic_node: Traffic) -> void:
	bus = bus_node
	traffic = traffic_node
	# 접촉 보고는 기본으로 꺼져 있다. 켜야 get_colliding_bodies() 가 채워진다.
	bus.contact_monitor = true
	bus.max_contacts_reported = 4

func _physics_process(delta: float) -> void:
	if bus == null or traffic == null:
		return
	if _stop_left > 0.0:
		_stop_left = maxf(_stop_left - delta, 0.0)
		if _stop_left == 0.0:
			_grace_left = CRASH_GRACE_S
		return
	if _grace_left > 0.0:
		_grace_left = maxf(_grace_left - delta, 0.0)
		return
	# 승하차 중에는 버스가 서 있고 뒤차가 줄을 선다. 사고가 아니다.
	if boarding != null and boarding.is_boarding:
		return
	for body in bus.get_colliding_bodies():
		if traffic.car_of(body) == null:
			continue
		crashes += 1
		_stop_left = CRASH_STOP_S
		traffic.hold(body, CRASH_STOP_S)
		crashed.emit()
		return
```

- [ ] **Step 3: `ScoreCard` 구현**

`scripts/score_card.gd`: 상수 `RESPAWN` 다음 줄에 `const CRASH := -200`. 시그니처와 감점 줄:

```gdscript
static func tally(elapsed_s: float, deadline_s: float, boarded: int,
		violations: int, camera_violations: int, missed: int,
		left_behind: int, respawns: int, crashes: int = 0) -> ScoreCard:
```

```gdscript
	penalty += card._add("리스폰", respawns, RESPAWN)
	penalty += card._add("사고", crashes, CRASH)
```

Run: `/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1; tests/game/run_game_tests.sh test_crash test_score_card`
Expected: 둘 다 OK. `test_crash` 가 "사고가 한 번도 안 났다" 로 실패하면 `get_colliding_bodies()` 가 비어 있는 것이다 — 버스가 차까지 갔는지(`bus.global_position.z` 출력)부터 확인한다.

- [ ] **Step 4: HUD 와 배선**

`scripts/boarding_hud.gd`: 필드(`var _miss_left := 0.0` 다음):

```gdscript
var _crash_label: Label
var _crash_left := 0.0
```

`_ready()` 의 `add_child(box)` 바로 다음(가운데 위 첫 줄이 된다):

```gdscript

	_crash_label = Label.new()
	_crash_label.text = "사고 — %d초 정차" % int(CrashWatch.CRASH_STOP_S)
	_crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash_label.add_theme_font_size_override("font_size", 22)
	_crash_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_crash_label.visible = false
	box.add_child(_crash_label)
```

`on_stop_missed` 다음에:

```gdscript
func on_crashed() -> void:
	_crash_label.visible = true
	_crash_left = CrashWatch.CRASH_STOP_S
```

`_process` 맨 앞에:

```gdscript
	if _crash_left > 0.0:
		_crash_left = maxf(_crash_left - delta, 0.0)
		_crash_label.visible = _crash_left > 0.0
```

`scripts/drive.gd`:
- 필드 `var traffic: Traffic` 다음 줄에 `var crash: CrashWatch`.
- `_ready()` 의 `boarding.stop_missed.connect(boarding_hud.on_stop_missed)` 다음에:

```gdscript

	crash = CrashWatch.new()
	crash.build(bus, traffic)
	crash.boarding = boarding
	add_child(crash)
	crash.crashed.connect(boarding_hud.on_crashed)
```

- `_physics_process` 의 적발 블록(`if watch != null and watch.is_busted:` ... `return`) 다음, 승하차 블록 앞에:

```gdscript
	if crash != null and crash.is_stopping:
		# 사고. 정해진 시간 동안 브레이크만 건다. 시계는 흐른다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		return
```

- `_on_finished` 의 `tally` 호출 끝 인자를 `clock.respawns, crash.crashes)` 로.

`tests/game/drive_smoke.gd`:
- 필드 `var done := false` 다음에 `var start_distances: Array = []`.
- `_ready()` 의 `drive.set_physics_process(false)` 다음에:

```gdscript
	# 이 테스트의 자율주행은 앞차를 모른다. 차에 막히거나 사고 정지에 걸리지
	# 않게 충돌만 끈다. 차는 계속 달린다.
	if drive.traffic != null:
		for car in drive.traffic.cars:
			car.body.collision_layer = 0
		start_distances = drive.traffic.cars.map(func(car) -> float: return car.distance)
```

- `_report()` 의 `ok(drive.traffic != null, "Traffic 이 없다")` 다음에:

```gdscript
	ok(drive.crash != null, "CrashWatch 가 없다")
	if drive.traffic != null:
		var moved := false
		for index in drive.traffic.cars.size():
			if absf(drive.traffic.cars[index].distance - start_distances[index]) > 1.0:
				moved = true
		ok(moved, "교통 차량이 하나도 안 움직였다")
```

- [ ] **Step 5: 전체 게임 테스트**

Run: `tests/game/run_game_tests.sh`
Expected: 목록 전부 OK(20 개: 기존 15 + car_follow, lane_path, traffic, crash — `test_violation` 포함).

- [ ] **Step 6: 커밋**

```bash
git checkout -q project.godot
git add scripts/crash_watch.gd scripts/crash_watch.gd.uid scripts/score_card.gd scripts/boarding_hud.gd scripts/drive.gd tests/game/test_crash.gd tests/game/test_crash.gd.uid tests/game/test_crash.tscn tests/game/test_score_card.gd tests/game/drive_smoke.gd tests/game/run_game_tests.sh
git commit -m "feat: 교통 차량과 부딪히면 사고로 감점하고 5초 정차

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: README, 성능, 육안 확인

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README**

"교차로에는 신호등이…" 문단의 둘째·셋째 문장을 바꾼다:

```markdown
교차로에는 신호등이 서 있고 두 축이 반주기씩 번갈아 녹색이 된다. 적색에 정지선을
넘으면 위반이 세어져 좌상단에 표시된다. 카메라가 달린 교차로는 따로 세고, 도로를
달리는 경찰차(파란 차체, 붉은 경광등) 시야 안에서 위반하면 적발되어 주행이 끝난다.
이때 `R` 로 다시 시작한다.

버스 둘레에는 같은 방향 차와 마주 오는 차가 달리고, 가까운 신호 교차로에는 가로
방향 차가 지나간다. 모든 차는 신호를 지키고 앞차와 간격을 둔다. 버스가 차와
부딪히면 사고로 세어져 5 초 동안 멈춘다. 적색에 교차로로 뛰어들면 가로 방향 차가
제때 못 서서 부딪힐 수 있다.
```

점수 문장의 `리스폰 −30.` 을 `리스폰 −30, 사고 −200.` 으로 바꾼다.

테스트 설명 `구간과 마감·점수·시계·주행 스모크` 를 `구간과 마감·점수·시계·교통 차량·사고·주행 스모크` 로 바꾼다.

문서 목록 끝에:

```markdown
- 설계: `docs/superpowers/specs/2026-09-25-traffic-ai-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-25-traffic-ai.md`
```

- [ ] **Step 2: 전체 테스트**

```bash
python3 -m unittest discover -s tests -t .
tests/game/run_game_tests.sh
git checkout -q project.godot
```

Expected: 파이썬 OK(152), 게임 전부 OK.

- [ ] **Step 3: 성능 (창 모드)**

Run: `/opt/homebrew/bin/godot res://tests/game/measure_fps.tscn -- --route=seoul-100`
Expected: 평균 60 이상, 최저 55 이상(기준). 떨어지면 `Traffic.CROSS_MAX`/`CROSS_SITES` 를 4/2 로 줄여 다시 잰다. 결과 숫자를 기록한다.

- [ ] **Step 4: 육안 확인 캡처**

임시 `tests/game/capture.gd/.tscn` 로 seoul-100 의 첫 신호 교차로 근처(버스를 `traffic.same_lane.stops[0].at_m - 40` 에 놓음)를 2~3 초 돌린 뒤 스크린샷을 스크래치패드에 저장해 본다. 확인할 것: 마주 오는 차가 반대편 차선에 있다(중앙선 위나 인도 위가 아님), 교차 차량이 도로 위를 가로지른다(건물 속이 아님), 경찰차가 파랗다. 교차 차선이 건물을 지나면 `LanePath.CROSS_MAX_M` 을 30 으로 줄인다(spec "실패와 경계"). 끝나면 임시 파일을 지운다.

- [ ] **Step 5: 커밋**

```bash
git checkout -q project.godot
git add README.md
# Step 3·4 에서 상수를 바꿨으면 그 파일도 이름을 적어 add
git commit -m "docs: README 에 교통 차량과 사고 설명

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
