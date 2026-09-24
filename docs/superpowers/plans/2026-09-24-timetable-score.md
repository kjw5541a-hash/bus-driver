# 시간표·점수 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 노선을 정류장 10곳 구간으로 잘라, 구간마다 자동 계산한 마감 안에 끝 정류장까지 가면 점수와 별 등급을 매긴다.

**Architecture:** `RouteData.slice()` 가 구간만 담은 새 `RouteData` 를 만들고 주행 씬의 나머지는 그것만 본다. 마감(`Timetable`)과 점수(`ScoreCard`)는 트리 없이 도는 순수 계산, 시계(`RunClock`)는 노드, 화면은 `ClockHud`·`ResultPanel` 두 CanvasLayer 다.

**Tech Stack:** Godot 4.7.2 GDScript, 헤드리스 테스트 러너 `tests/game/run_game_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-24-timetable-score-design.md`

## Global Constraints

- 베이크 파이프라인(`tools/osmbake/`)과 `assets/routes/` 는 건드리지 않는다.
- 주석·UI 문자열은 한국어. 커밋 메시지는 기존 관례(`feat:`/`docs:` + 한국어 요약).
- 커밋 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `git add` 는 파일 이름을 하나씩. `-A`/`.` 금지.
- Godot 을 돌리면 `project.godot` 에 헤더 주석이 붙는다. 커밋 전 `git checkout -q project.godot`.
- 새 스크립트의 `.gd.uid` 는 러너의 `--import` 가 만든다. 스크립트와 같이 커밋한다.
- Godot 은 파싱 에러에도 0 으로 끝난다. 통과 판정은 러너가 `TEST_OK` 로 한다.
- 구간 상수: `SECTION_STOPS = 10`, `SECTION_MIN_STOPS = 5`, `LEAD_IN_M = 60.0`, `SECTION_SIGNAL_M = 30.0`.
- 마감 상수: `BASE_SPEED_MPS = 32 km/h`, `WALK_GUESS_M = 3.0`, 10 초 단위 올림.
- 점수표: 완주 +1000, 승객 +20, 일찍 초당 +2, 초과 초당 −5, 위반 −50, 카메라 −150, 놓친 정류장 −100, 못 태운 승객 −10, 리스폰 −30, 별 3 감점 한도 150.

## 파일 구조

| 파일 | 역할 |
|---|---|
| `scripts/passenger_plan.gd` (수정) | 대기 인원 분포를 상수 `WAITING_MIN`/`WAITING_MAX` 로 뺀다 |
| `scripts/route_data.gd` (수정) | `sections()`, `slice()`, `length_m()`, `distance_to_route()`, `selected_section` |
| `scripts/timetable.gd` (생성) | 마감 계산, `m:ss` 포맷 |
| `scripts/score_card.gd` (생성) | 점수표와 별 |
| `scripts/run_clock.gd` (생성) | 경과 시간, 탑승 누적, 리스폰 수, 완주 판정 |
| `scripts/clock_hud.gd` (생성) | 오른쪽 위 남은 시간 |
| `scripts/result_panel.gd` (생성) | 완주 결과 화면과 버튼 |
| `scripts/drive.gd` (수정) | 구간 자르기, 새 노드 배선, 완주 후 정지 |
| `scripts/menu.gd` (수정) | 노선 → 구간 목록 |
| `tests/game/test_sections.*` (생성) | 구간·자르기·마감 |
| `tests/game/test_score_card.*` (생성) | 점수 |
| `tests/game/test_run_clock.*` (생성) | 시계와 시간 표시 |
| `tests/game/drive_smoke.gd` (수정) | 배선 확인 |
| `tests/game/run_game_tests.sh` (수정) | 새 씬 등록 |
| `README.md` (수정) | 구간·마감·점수 설명과 문서 링크 |

---

### Task 1: 구간 나누기와 자르기

**Files:**
- Modify: `scripts/passenger_plan.gd` (상수 추가, `build()` 안 `randi_range(-3, 8)`)
- Modify: `scripts/route_data.gd`
- Create: `tests/game/test_sections.gd`, `tests/game/test_sections.tscn`
- Modify: `tests/game/run_game_tests.sh` (scenes 목록)

**Interfaces:**
- Produces:
  - `PassengerPlan.WAITING_MIN := -3`, `PassengerPlan.WAITING_MAX := 8`
  - `static var RouteData.selected_section := 0`
  - `RouteData.section: int`, `RouteData.section_count: int`
  - `RouteData.sections() -> Array` (원소 `Vector2i(첫 정류장, 끝 정류장)`)
  - `RouteData.slice(section: int) -> RouteData`
  - `RouteData.length_m() -> float`
  - `RouteData.distance_to_route(point: Vector3) -> float`

- [ ] **Step 1: 대기 인원 분포를 상수로**

`scripts/passenger_plan.gd` 의 `WALK_SPEED_MPS` 다음 줄에 추가:

```gdscript
# 대기 인원은 maxi(0, randi_range(WAITING_MIN, WAITING_MAX)) 다. 0 명이 1/3,
# 평균 2.9 명. Timetable 이 같은 분포로 기대 정차 시간을 낸다.
const WAITING_MIN := -3
const WAITING_MAX := 8
```

`build()` 안의 줄을 바꾼다:

```gdscript
		_waiting.append(maxi(0, randi_range(WAITING_MIN, WAITING_MAX)))
```

- [ ] **Step 2: 실패하는 테스트 쓰기**

`tests/game/test_sections.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_sections.gd" id="1"]

[node name="TestSections" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_sections.gd`:

```gdscript
extends TestCase
# 구간 경계와 자르기. 합성 데이터로 규칙을, 실데이터로 구간 수를 본다.

func _ready() -> void:
	_test_bounds()
	_test_slice()
	_test_real_routes()
	finish()

# 정류장 n 곳을 +X 축 직선 위 100 m 간격(50, 150, ...)에 놓는다.
func _synthetic(stop_count: int) -> RouteData:
	var data := RouteData.new()
	data.id = "test"
	for index in stop_count + 1:
		data.route.append(Vector3(index * 100.0, 0.0, 0.0))
	for index in stop_count:
		data.stops.append({"name": "정류장%d" % index,
			"x": index * 100.0 + 50.0, "z": 5.0,
			"progress_m": index * 100.0 + 50.0})
	data.signals = [
		{"x": 1500.0, "z": 0.0},    # 구간 1 경로 위
		{"x": 1500.0, "z": 100.0},  # 구간 1 범위지만 경로에서 100 m
		{"x": 300.0, "z": 0.0},     # 구간 0
	]
	data._build_stop_targets()
	return data

func _test_bounds() -> void:
	ok(_synthetic(25).sections() == [Vector2i(0, 10), Vector2i(10, 20), Vector2i(20, 24)],
		"25 곳 구간이 틀렸다: %s" % str(_synthetic(25).sections()))
	# 꼬리 20~22 는 3 곳이라 앞 구간에 붙는다.
	ok(_synthetic(23).sections() == [Vector2i(0, 10), Vector2i(10, 22)],
		"23 곳 구간이 틀렸다: %s" % str(_synthetic(23).sections()))
	ok(_synthetic(4).sections() == [Vector2i(0, 3)],
		"4 곳 구간이 틀렸다: %s" % str(_synthetic(4).sections()))
	ok(_synthetic(1).sections().is_empty(), "1 곳이면 구간이 없어야 한다")

func _test_slice() -> void:
	var data := _synthetic(25)
	var part := data.slice(1)
	ok(part != data, "원본을 그대로 돌려줬다")
	ok(part.section == 1 and part.section_count == 3,
		"구간 번호가 틀렸다: %d/%d" % [part.section, part.section_count])
	ok(part.stops.size() == 11, "정류장이 %d 곳이다" % part.stops.size())
	equal_approx(float(part.stops[0]["progress_m"]), RouteData.LEAD_IN_M, 0.01,
		"첫 정류장 진행도가 앞 여유와 다르다")
	equal_approx(part.route[0].x, 990.0, 0.01, "잘린 시작점")
	equal_approx(part.route[part.route.size() - 1].x, 2050.0, 0.01, "잘린 끝점")
	equal_approx(part.length_m(), 1060.0, 0.01, "잘린 길이")
	ok(part.stop_targets.size() == 11, "정차 목표점을 다시 안 만들었다")
	equal_approx(part.stop_targets[0].x, 1050.0, 0.01, "첫 정차 목표점")
	ok(part.signals.size() == 1, "신호가 %d 개다" % part.signals.size())
	# 원본은 그대로다.
	equal_approx(float(data.stops[10]["progress_m"]), 1050.0, 0.01, "원본 정류장이 바뀌었다")
	# 범위 밖 구간 번호는 0 번이다.
	ok(data.slice(9).section == 0, "범위 밖 구간이 0 번이 아니다")
	# 첫 구간은 노선 시작점을 넘어가지 않는다.
	equal_approx(data.slice(0).route[0].x, 0.0, 0.01, "첫 구간 시작점")

func _test_real_routes() -> void:
	var expected := {"seoul-100": 6, "seoul-654": 8, "seoul-seodaemun03": 2}
	for route_id in expected:
		var data := RouteData.load_route(route_id)
		ok(data != null, "%s 를 읽지 못했다" % route_id)
		if data == null:
			continue
		var bounds := data.sections()
		ok(bounds.size() == expected[route_id],
			"%s 구간이 %d 개다" % [route_id, bounds.size()])
		for index in bounds.size():
			var part := data.slice(index)
			for entry in part.signals:
				var point := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
				ok(part.distance_to_route(point) <= RouteData.SECTION_SIGNAL_M + 0.01,
					"%s 구간 %d 신호가 경로에서 멀다" % [route_id, index])
```

`tests/game/run_game_tests.sh` 의 scenes 목록 끝(`drive_smoke` 앞)에 `test_sections` 를 넣는다:

```bash
	scenes=(test_route_data test_city test_input test_turn_radius test_brake test_nav_line test_traffic_signal test_violation test_passenger_plan test_boarding test_camera_view test_sections drive_smoke)
```

- [ ] **Step 3: 실패 확인**

Run: `tests/game/run_game_tests.sh test_sections; git checkout -q project.godot`
Expected: `TEST_OK` 없음 (`sections` 가 없어 파싱 에러)

- [ ] **Step 4: RouteData 구현**

`scripts/route_data.gd` 의 `static var selected_id` 다음에:

```gdscript
# 메뉴가 고른 구간. selected_id 와 같은 이유로 static 이다.
static var selected_section := 0

# 구간. 한 판을 10 분 안팎으로 만들려고 정류장 10 곳씩 자른다. 경계 정류장은
# 양쪽 구간이 함께 쓴다 — 이어 달리면 실제 노선처럼 끊김이 없다.
const SECTION_STOPS := 10
const SECTION_MIN_STOPS := 5     # 이보다 짧은 꼬리는 앞 구간에 붙인다
const LEAD_IN_M := 60.0          # 첫 정류장 앞 여유. 출발하자마자 서지 않게
const SECTION_SIGNAL_M := 30.0   # 잘린 경로에서 이만큼 안의 신호만 남긴다
```

`var stop_targets` 다음에:

```gdscript
# slice() 가 채운다. 자르지 않은 원본은 0 / 1 이다.
var section := 0
var section_count := 1
```

파일 끝에:

```gdscript
func sections() -> Array:
	"""구간마다 Vector2i(첫 정류장, 끝 정류장). 정류장이 2 곳 미만이면 빈 배열."""
	var last := stops.size() - 1
	var bounds: Array = []
	if last < 1:
		return bounds
	var start := 0
	while start < last:
		var end := mini(start + SECTION_STOPS, last)
		bounds.append(Vector2i(start, end))
		start = end
	var tail: Vector2i = bounds[bounds.size() - 1]
	if bounds.size() > 1 and tail.y - tail.x + 1 < SECTION_MIN_STOPS:
		bounds.pop_back()
		bounds[bounds.size() - 1] = Vector2i(bounds[bounds.size() - 1].x, tail.y)
	return bounds

func slice(index: int) -> RouteData:
	"""index 번 구간만 담은 새 RouteData. 범위 밖이면 0 번. 구간이 없으면 자신."""
	var bounds := sections()
	if bounds.is_empty():
		return self
	if index < 0 or index >= bounds.size():
		index = 0
	var range_of: Vector2i = bounds[index]
	var start_m := maxf(0.0, float(stops[range_of.x].get("progress_m", 0.0)) - LEAD_IN_M)
	var end_m := float(stops[range_of.y].get("progress_m", 0.0))

	var part := RouteData.new()
	part.id = id
	part.display_name = display_name
	part.from_name = from_name
	part.to_name = to_name
	part.chunks = chunks
	part.section = index
	part.section_count = bounds.size()
	part.route = _route_between(start_m, end_m)
	for stop_index in range(range_of.x, range_of.y + 1):
		var stop: Dictionary = stops[stop_index].duplicate()
		stop["progress_m"] = float(stop.get("progress_m", 0.0)) - start_m
		part.stops.append(stop)
	for entry in signals:
		var point := Vector3(float(entry["x"]), 0.0, float(entry["z"]))
		if part.distance_to_route(point) <= SECTION_SIGNAL_M:
			part.signals.append(entry)
	part._build_stop_targets()
	return part

func length_m() -> float:
	var total := 0.0
	for index in range(1, route.size()):
		total += route[index - 1].distance_to(route[index])
	return total

func distance_to_route(point: Vector3) -> float:
	var best := INF
	for index in range(1, route.size()):
		var foot := Geometry3D.get_closest_point_to_segment(point, route[index - 1], route[index])
		best = minf(best, foot.distance_to(point))
	return best

func _route_between(start_m: float, end_m: float) -> PackedVector3Array:
	var part := PackedVector3Array([point_at_progress(start_m)])
	var travelled := 0.0
	for index in range(1, route.size()):
		travelled += route[index - 1].distance_to(route[index])
		if travelled > start_m and travelled < end_m:
			part.append(route[index])
	part.append(point_at_progress(end_m))
	return part
```

- [ ] **Step 5: 통과 확인**

Run: `tests/game/run_game_tests.sh test_sections test_passenger_plan test_route_data; git checkout -q project.godot`
Expected: 셋 다 `TEST_OK`

- [ ] **Step 6: 커밋**

```bash
git add scripts/passenger_plan.gd scripts/route_data.gd tests/game/test_sections.gd tests/game/test_sections.gd.uid tests/game/test_sections.tscn tests/game/run_game_tests.sh
git commit -m "feat: RouteData 가 노선을 정류장 10곳 구간으로 자른다"
```

---

### Task 2: 마감 계산

**Files:**
- Create: `scripts/timetable.gd`
- Modify: `tests/game/test_sections.gd`

**Interfaces:**
- Consumes: `RouteData.length_m()`, `RouteData.slice()`, `PassengerPlan.WAITING_MIN/MAX`, `PassengerPlan.dwell_for()`, `TrafficSignal.GREEN_S/YELLOW_S`
- Produces:
  - `Timetable.expected_dwell() -> float`
  - `Timetable.signal_wait() -> float`
  - `Timetable.deadline_for(data: RouteData) -> float`
  - `Timetable.format_mmss(total_s: int) -> String`

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/game/test_sections.gd` 의 `_ready()` 에서 `finish()` 앞에 `_test_deadline()` 을 넣고, 파일 끝에:

```gdscript
func _test_deadline() -> void:
	# 0 명이 4/12, 1~8 명이 각 1/12. n 명이면 3 + 3/1.2 + 2n 초.
	equal_approx(Timetable.expected_dwell(), 116.0 / 12.0, 0.001, "기대 정차 시간")
	equal_approx(Timetable.signal_wait(), 8.25, 0.001, "기대 신호 대기")
	# 1000 m 직선, 정류장 3, 신호 2: 112.5 + 29 + 16.5 = 158 -> 160.
	var data := RouteData.new()
	data.route = PackedVector3Array([Vector3.ZERO, Vector3(1000.0, 0.0, 0.0)])
	data.stops = [{}, {}, {}]
	data.signals = [{}, {}]
	equal_approx(Timetable.deadline_for(data), 160.0, 0.001, "마감")
	ok(Timetable.format_mmss(462) == "7:42", "포맷: %s" % Timetable.format_mmss(462))
	ok(Timetable.format_mmss(60) == "1:00", "포맷: %s" % Timetable.format_mmss(60))
	ok(Timetable.format_mmss(5) == "0:05", "포맷: %s" % Timetable.format_mmss(5))
	# 실데이터 모든 구간이 5~16 분이다.
	for route_id in ["seoul-100", "seoul-654", "seoul-seodaemun03"]:
		var route := RouteData.load_route(route_id)
		if route == null:
			continue
		for index in route.sections().size():
			var deadline := Timetable.deadline_for(route.slice(index))
			ok(deadline >= 300.0 and deadline <= 960.0,
				"%s 구간 %d 마감 %.0f 초" % [route_id, index, deadline])
```

- [ ] **Step 2: 실패 확인**

Run: `tests/game/run_game_tests.sh test_sections; git checkout -q project.godot`
Expected: `TEST_OK` 없음 (`Timetable` 없음)

- [ ] **Step 3: 구현**

`scripts/timetable.gd`:

```gdscript
extends RefCounted
class_name Timetable
# 구간 마감. 노선 기하와 승객·신호 규칙에서 자동으로 낸다 — 노선을 다시
# 구워도, 규칙 숫자를 바꿔도 알아서 따라온다. 난이도는 BASE_SPEED_MPS 하나로
# 조절한다.

const BASE_SPEED_MPS := 32.0 / 3.6   # 정차·신호를 뺀 순수 주행 평균. 30 이면 100번 긴 구간이 16 분을 넘는다
const WALK_GUESS_M := 3.0            # 차선에 제대로 섰을 때 걸어오는 거리
const ROUND_S := 10.0

static func expected_dwell() -> float:
	"""정류장 한 곳의 기대 정차 시간. 0 명이면 서지 않으므로 0 이다."""
	var plan := PassengerPlan.new()
	var total := 0.0
	for draw in range(PassengerPlan.WAITING_MIN, PassengerPlan.WAITING_MAX + 1):
		var count := maxi(0, draw)
		if count > 0:
			total += plan.dwell_for(count, 0, WALK_GUESS_M, count)
	return total / float(PassengerPlan.WAITING_MAX - PassengerPlan.WAITING_MIN + 1)

static func signal_wait() -> float:
	"""신호 한 곳의 기대 대기. 적색일 확률 1/2 x 적색 평균 잔여."""
	return 0.5 * (TrafficSignal.GREEN_S + TrafficSignal.YELLOW_S) * 0.5

static func deadline_for(data: RouteData) -> float:
	var raw := data.length_m() / BASE_SPEED_MPS \
		+ data.stops.size() * expected_dwell() \
		+ data.signals.size() * signal_wait()
	return ceilf(raw / ROUND_S) * ROUND_S

static func format_mmss(total_s: int) -> String:
	return "%d:%02d" % [floori(total_s / 60.0), total_s % 60]
```

- [ ] **Step 4: 통과 확인**

Run: `tests/game/run_game_tests.sh test_sections; git checkout -q project.godot`
Expected: `TEST_OK`. 실패하면 구간별 마감 숫자가 찍힌다 — 범위를 벗어나면 멈추고 보고한다(상수를 임의로 바꾸지 않는다).

- [ ] **Step 5: 커밋**

```bash
git add scripts/timetable.gd scripts/timetable.gd.uid tests/game/test_sections.gd
git commit -m "feat: Timetable — 구간 마감을 길이·정류장·신호로 계산"
```

---

### Task 3: 점수

**Files:**
- Create: `scripts/score_card.gd`
- Create: `tests/game/test_score_card.gd`, `tests/game/test_score_card.tscn`
- Modify: `tests/game/run_game_tests.sh`

**Interfaces:**
- Produces:
  - `ScoreCard.tally(elapsed_s: float, deadline_s: float, boarded: int, violations: int, camera_violations: int, missed: int, left_behind: int, respawns: int) -> ScoreCard` (static)
  - `ScoreCard.lines: Array` — 원소 `{"label": String, "count": int, "points": int}`
  - `ScoreCard.total: int`, `ScoreCard.stars: int`, `ScoreCard.on_time: bool`

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/game/test_score_card.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_score_card.gd" id="1"]

[node name="TestScoreCard" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_score_card.gd`:

```gdscript
extends TestCase
# 점수표. 순수 계산이라 트리가 필요 없다.

func _ready() -> void:
	var card := ScoreCard.tally(600.0, 600.0, 0, 0, 0, 0, 0, 0)
	ok(card.total == 1000, "정각 완주 %d" % card.total)
	ok(card.stars == 3, "정각 완주 별 %d" % card.stars)
	ok(card.lines.size() == 1, "0 인 항목도 줄에 들어갔다: %s" % str(card.lines))

	ok(ScoreCard.tally(590.7, 600.0, 0, 0, 0, 0, 0, 0).total == 1018, "일찍 9 초")
	card = ScoreCard.tally(610.9, 600.0, 0, 0, 0, 0, 0, 0)
	ok(card.total == 950, "초과 10 초 %d" % card.total)
	ok(card.stars == 1 and not card.on_time, "초과면 별 1")

	ok(ScoreCard.tally(600.0, 600.0, 5, 0, 0, 0, 0, 0).total == 1100, "승객 5 명")
	# 위반 3 중 1 이 카메라: 2 x -50 + 1 x -150.
	ok(ScoreCard.tally(600.0, 600.0, 0, 3, 1, 0, 0, 0).total == 750, "위반")
	ok(ScoreCard.tally(600.0, 600.0, 0, 0, 0, 1, 0, 0).total == 900, "놓친 정류장")
	ok(ScoreCard.tally(600.0, 600.0, 0, 0, 0, 0, 2, 0).total == 980, "못 태운 승객")
	ok(ScoreCard.tally(600.0, 600.0, 0, 0, 0, 0, 0, 2).total == 940, "리스폰")

	# 별 경계. 감점은 10 단위로만 움직인다.
	ok(ScoreCard.tally(600.0, 600.0, 0, 3, 0, 0, 0, 0).stars == 3, "감점 150 이면 별 3")
	ok(ScoreCard.tally(600.0, 600.0, 0, 3, 0, 0, 1, 0).stars == 2, "감점 160 이면 별 2")
	# 일찍 도착 가산은 감점 한도 계산에 안 들어간다.
	ok(ScoreCard.tally(500.0, 600.0, 0, 3, 0, 0, 1, 0).stars == 2, "시간 가산이 감점을 덮었다")
	finish()
```

run_game_tests.sh scenes 목록에서 `test_sections` 뒤에 `test_score_card` 를 넣는다.

- [ ] **Step 2: 실패 확인**

Run: `tests/game/run_game_tests.sh test_score_card; git checkout -q project.godot`
Expected: `TEST_OK` 없음

- [ ] **Step 3: 구현**

`scripts/score_card.gd`:

```gdscript
extends RefCounted
class_name ScoreCard
# 구간 점수. 숫자만 받아 숫자를 낸다 — 판정은 각 Watch 가 이미 했다.
#
# 저울질: 카메라 없는 위반 한 번(-50)은 25 초를 번 것(+2 x 25)과 같다. 적색
# 대기는 평균 16.5 초, 최대 36 초라 해볼 만한 도박이다. 카메라 교차로는 대부분
# 손해다. 조정은 아래 숫자만 바꾼다.

const FINISH_POINTS := 1000
const PER_PASSENGER := 20
const EARLY_PER_S := 2
const LATE_PER_S := -5
const VIOLATION := -50
const CAMERA_VIOLATION := -150
const MISSED_STOP := -100
const LEFT_BEHIND := -10
const RESPAWN := -30
const THREE_STAR_PENALTY := 150   # 시간 항목을 뺀 감점 합이 이 이하면 별 3

var lines: Array = []
var total := 0
var stars := 1
var on_time := true

static func tally(elapsed_s: float, deadline_s: float, boarded: int,
		violations: int, camera_violations: int, missed: int,
		left_behind: int, respawns: int) -> ScoreCard:
	var card := ScoreCard.new()
	card._add("완주", 1, FINISH_POINTS)
	card._add("태운 승객", boarded, PER_PASSENGER)
	card.on_time = elapsed_s <= deadline_s
	if card.on_time:
		card._add("일찍 도착 (초)", floori(deadline_s - elapsed_s), EARLY_PER_S)
	else:
		card._add("마감 초과 (초)", floori(elapsed_s - deadline_s), LATE_PER_S)
	var penalty := 0
	penalty += card._add("신호 위반", violations - camera_violations, VIOLATION)
	penalty += card._add("카메라 단속", camera_violations, CAMERA_VIOLATION)
	penalty += card._add("놓친 정류장", missed, MISSED_STOP)
	penalty += card._add("못 태운 승객", left_behind, LEFT_BEHIND)
	penalty += card._add("리스폰", respawns, RESPAWN)
	if not card.on_time:
		card.stars = 1
	elif -penalty <= THREE_STAR_PENALTY:
		card.stars = 3
	else:
		card.stars = 2
	return card

func _add(label: String, count: int, per: int) -> int:
	"""count 가 0 이면 줄을 만들지 않는다. 더한 점수를 돌려준다."""
	if count <= 0:
		return 0
	var points := count * per
	lines.append({"label": label, "count": count, "points": points})
	total += points
	return points
```

- [ ] **Step 4: 통과 확인**

Run: `tests/game/run_game_tests.sh test_score_card; git checkout -q project.godot`
Expected: `TEST_OK`

- [ ] **Step 5: 커밋**

```bash
git add scripts/score_card.gd scripts/score_card.gd.uid tests/game/test_score_card.gd tests/game/test_score_card.gd.uid tests/game/test_score_card.tscn tests/game/run_game_tests.sh
git commit -m "feat: ScoreCard — 구간 점수표와 별 등급"
```

---

### Task 4: 시계와 남은 시간 HUD

**Files:**
- Create: `scripts/run_clock.gd`, `scripts/clock_hud.gd`
- Create: `tests/game/test_run_clock.gd`, `tests/game/test_run_clock.tscn`
- Modify: `tests/game/run_game_tests.sh`

**Interfaces:**
- Consumes: `Timetable.format_mmss(int)`
- Produces:
  - `RunClock` (Node): `signal finished`, `deadline_s: float`, `elapsed_s: float`, `boarded_total: int`, `respawns: int`, `is_running: bool`, `is_finished: bool`, `start(deadline_s: float, last_stop_index: int)`, `on_stop_served(stop_index: int, boarded: int)`, `on_busted()`
  - `ClockHud` (CanvasLayer): `update_clock(clock: RunClock)`, static `text_for(left_s: float) -> String`, `label_text: String` (읽기 전용 확인용)

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/game/test_run_clock.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_run_clock.gd" id="1"]

[node name="TestRunClock" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_run_clock.gd`:

```gdscript
extends TestCase
# 시계. BoardingWatch 대신 on_stop_served 를 직접 부른다 — drive.gd 가
# boarding_finished 를 이 호출로 옮겨 준다.

var _finished_count := 0

func _ready() -> void:
	await _test_runs_and_finishes()
	await _test_busted_stops()
	_test_text()
	finish()

func _make() -> RunClock:
	_finished_count = 0
	var clock := RunClock.new()
	clock.start(600.0, 3)
	clock.finished.connect(func() -> void: _finished_count += 1)
	add_child(clock)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return clock

func _test_runs_and_finishes() -> void:
	var clock := await _make()
	ok(clock.elapsed_s > 0.0, "시계가 안 돈다")
	clock.on_stop_served(1, 4)
	ok(clock.is_running and not clock.is_finished, "끝 정류장이 아닌데 멈췄다")
	ok(clock.boarded_total == 4, "탑승 누적 %d" % clock.boarded_total)
	clock.on_stop_served(3, 2)
	ok(clock.is_finished and not clock.is_running, "끝 정류장에서 안 멈췄다")
	ok(clock.boarded_total == 6, "탑승 누적 %d" % clock.boarded_total)
	ok(_finished_count == 1, "finished 가 %d 번 났다" % _finished_count)
	var frozen := clock.elapsed_s
	await get_tree().physics_frame
	await get_tree().physics_frame
	equal_approx(clock.elapsed_s, frozen, 0.0001, "멈춘 뒤에도 시간이 흐른다")
	clock.on_stop_served(3, 0)
	ok(_finished_count == 1, "finished 가 두 번 났다")
	clock.queue_free()

func _test_busted_stops() -> void:
	var clock := await _make()
	clock.on_busted()
	ok(not clock.is_running and not clock.is_finished, "적발은 완주가 아니다")
	var frozen := clock.elapsed_s
	await get_tree().physics_frame
	equal_approx(clock.elapsed_s, frozen, 0.0001, "적발 뒤에도 시간이 흐른다")
	clock.queue_free()

func _test_text() -> void:
	ok(ClockHud.text_for(461.3) == "남은 시간 7:42", ClockHud.text_for(461.3))
	ok(ClockHud.text_for(0.0) == "남은 시간 0:00", ClockHud.text_for(0.0))
	ok(ClockHud.text_for(-35.7) == "초과 +0:35", ClockHud.text_for(-35.7))
```

run_game_tests.sh scenes 목록에서 `test_score_card` 뒤에 `test_run_clock` 을 넣는다.

- [ ] **Step 2: 실패 확인**

Run: `tests/game/run_game_tests.sh test_run_clock; git checkout -q project.godot`
Expected: `TEST_OK` 없음

- [ ] **Step 3: 구현**

`scripts/run_clock.gd`:

```gdscript
extends Node
class_name RunClock
# 구간 시계. 첫 프레임부터 돌고, 끝 정류장 승하차가 끝나면 멈춘다. 승하차
# 시간도 시계에 들어간다 — 그 편차가 "이번 판은 빠듯한가"를 만든다.

signal finished

var deadline_s := 0.0
var elapsed_s := 0.0
var boarded_total := 0
var respawns := 0      # drive.respawn() 이 실제로 되돌렸을 때만 올린다
var is_running := true
var is_finished := false

var _last_stop_index := -1

func start(deadline: float, last_stop_index: int) -> void:
	deadline_s = deadline
	_last_stop_index = last_stop_index

func _physics_process(delta: float) -> void:
	if is_running:
		elapsed_s += delta

func on_stop_served(stop_index: int, boarded: int) -> void:
	if is_finished:
		return
	boarded_total += boarded
	if stop_index == _last_stop_index:
		is_running = false
		is_finished = true
		finished.emit()

func on_busted() -> void:
	is_running = false
```

`scripts/clock_hud.gd`:

```gdscript
extends CanvasLayer
class_name ClockHud
# 남은 시간. 오른쪽 위 — 위반 HUD 가 왼쪽 위, 승하차 HUD 가 가운데 위다.

var label_text: String:
	get: return _label.text if _label != null else ""

var _label: Label

func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.position = Vector2(-236.0, 16.0)
	_label.size = Vector2(220.0, 32.0)
	_label.add_theme_font_size_override("font_size", 24)
	add_child(_label)

func update_clock(clock: RunClock) -> void:
	if _label == null or clock == null:
		return
	var left := clock.deadline_s - clock.elapsed_s
	_label.text = text_for(left)
	_label.add_theme_color_override("font_color",
		Color.WHITE if left >= 0.0 else Color(1.0, 0.35, 0.3))

static func text_for(left_s: float) -> String:
	if left_s >= 0.0:
		return "남은 시간 " + Timetable.format_mmss(ceili(left_s))
	return "초과 +" + Timetable.format_mmss(floori(-left_s))
```

- [ ] **Step 4: 통과 확인**

Run: `tests/game/run_game_tests.sh test_run_clock; git checkout -q project.godot`
Expected: `TEST_OK`

- [ ] **Step 5: 커밋**

```bash
git add scripts/run_clock.gd scripts/run_clock.gd.uid scripts/clock_hud.gd scripts/clock_hud.gd.uid tests/game/test_run_clock.gd tests/game/test_run_clock.gd.uid tests/game/test_run_clock.tscn tests/game/run_game_tests.sh
git commit -m "feat: RunClock 과 ClockHud — 구간 시계와 남은 시간"
```

---

### Task 5: 결과 화면과 주행 씬 배선

**Files:**
- Create: `scripts/result_panel.gd`
- Modify: `scripts/drive.gd`
- Modify: `tests/game/drive_smoke.gd`

**Interfaces:**
- Consumes: Task 1~4 전부. `BoardingWatch.boarding_index`(boarding_finished 신호 안에서 아직 유효), `BoardingWatch.missed`, `BoardingWatch.left_behind`, `ViolationWatch.violations/camera_violations/busted`
- Produces:
  - `ResultPanel` (CanvasLayer): `signal next_requested`, `signal retry_requested`, `signal menu_requested`, `show_result(card: ScoreCard, title: String, has_next: bool)`, `line_count: int`
  - `Drive.clock: RunClock`, `Drive.clock_hud: ClockHud`, `Drive.result: ResultPanel`, `Drive.section_from_args() -> int`

- [ ] **Step 1: drive_smoke 에 단언 추가 (실패하는 테스트)**

`tests/game/drive_smoke.gd` 의 `_report()` 안, `finish()` 바로 앞에:

```gdscript
	# 구간·시계·결과 화면 배선.
	ok(drive.data.section == 0, "구간 0 으로 뜨지 않았다 (%d)" % drive.data.section)
	ok(drive.data.section_count > 1, "노선이 구간으로 안 잘렸다")
	ok(drive.clock != null and drive.clock.deadline_s > 0.0, "RunClock 마감이 없다")
	ok(drive.clock != null and drive.clock.elapsed_s > 0.0, "시계가 안 돈다")
	ok(drive.clock_hud != null, "ClockHud 가 없다")
	ok(drive.result != null and not drive.result.visible, "결과 화면이 처음부터 떠 있다")
	if drive.result != null:
		drive.result.show_result(ScoreCard.tally(100.0, 600.0, 3, 1, 0, 0, 0, 0),
			"테스트", true)
		ok(drive.result.visible and drive.result.line_count == 4,
			"결과 화면 줄이 %d 개다" % drive.result.line_count)
```

주의: 이 테스트는 `drive.set_physics_process(false)` 로 drive 의 물리 처리를 끈다. `RunClock` 은 별도 노드라 계속 돈다.

- [ ] **Step 2: 실패 확인**

Run: `tests/game/run_game_tests.sh drive_smoke; git checkout -q project.godot`
Expected: `TEST_OK` 없음

- [ ] **Step 3: ResultPanel 구현**

`scripts/result_panel.gd`:

```gdscript
extends CanvasLayer
class_name ResultPanel
# 구간 완주 결과. 점수 계산은 ScoreCard 가, 다음 동작은 drive.gd 가 한다.
# 적발은 ViolationHud 의 종료 화면이 맡는다.

signal next_requested
signal retry_requested
signal menu_requested

var line_count := 0

var _box: VBoxContainer
var _next: Button
var _has_next := false

func _ready() -> void:
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	_box = VBoxContainer.new()
	outer.add_child(_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	outer.add_child(buttons)
	_next = _button(buttons, "다음 구간 (Enter)", next_requested)
	_button(buttons, "다시 하기 (R)", retry_requested)
	_button(buttons, "메뉴", menu_requested)

func _button(parent: Control, text: String, emitted: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.pressed.connect(func() -> void: emitted.emit())
	parent.add_child(button)
	return button

func show_result(card: ScoreCard, title: String, has_next: bool) -> void:
	for child in _box.get_children():
		child.queue_free()
	_label(title, 28)
	line_count = 0
	for line in card.lines:
		_label("%s  x%d   %+d" % [line["label"], line["count"], line["points"]], 20)
		line_count += 1
	_label("총점 %d" % card.total, 30)
	_label("★".repeat(card.stars) + "☆".repeat(3 - card.stars), 40)
	_has_next = has_next
	_next.visible = has_next
	visible = true

func _label(text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	_box.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and _has_next:
		next_requested.emit()
	elif event.keycode == KEY_R:
		retry_requested.emit()
```

- [ ] **Step 4: drive.gd 배선**

`scripts/drive.gd` 머리 주석의 둘째 문단(“종점에 도착해도 아무 일도 일어나지 않는다 …”)을 바꾼다:

```gdscript
# 노선은 구간 하나로 잘라 싣는다. 끝 정류장 승하차가 끝나면 RunClock 이
# 멈추고 결과 화면이 뜬다.
```

변수 선언 끝(`var boarding_hud: BoardingHud` 다음)에:

```gdscript
var clock: RunClock
var clock_hud: ClockHud
var result: ResultPanel
```

`_ready()` 에서 `data = RouteData.load_route(route_id)` 의 null 검사 블록 바로 뒤에:

```gdscript
	data = data.slice(section_from_args())
```

`_ready()` 끝(`boarding.stop_missed.connect(...)` 다음)에:

```gdscript
	clock = RunClock.new()
	clock.start(Timetable.deadline_for(data), data.stops.size() - 1)
	add_child(clock)
	# boarding_index 는 boarding_finished 신호 안에서 아직 살아 있다.
	boarding.boarding_finished.connect(func(boarded: int, _alighted: int) -> void:
		clock.on_stop_served(boarding.boarding_index, boarded))
	watch.busted.connect(clock.on_busted)
	clock.finished.connect(_on_finished)

	clock_hud = ClockHud.new()
	add_child(clock_hud)

	result = ResultPanel.new()
	add_child(result)
	result.next_requested.connect(func() -> void:
		RouteData.selected_id = data.id
		RouteData.selected_section = data.section + 1
		get_tree().reload_current_scene())
	result.retry_requested.connect(func() -> void: get_tree().reload_current_scene())
	result.menu_requested.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
```

`route_id_from_args()` 다음에:

```gdscript
func section_from_args() -> int:
	"""--section=<n> 이 있으면 그것, 없으면 메뉴가 고른 구간. 범위 밖은 slice 가 0 으로."""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--section="):
			return int(argument.trim_prefix("--section="))
	return RouteData.selected_section

func _on_finished() -> void:
	var card := ScoreCard.tally(clock.elapsed_s, clock.deadline_s,
		clock.boarded_total, watch.violations, watch.camera_violations,
		boarding.missed, boarding.left_behind, clock.respawns)
	var title := "%s · 구간 %d/%d" % [data.display_name, data.section + 1, data.section_count]
	result.show_result(card, title, data.section < data.section_count - 1)
```

`_physics_process()` 에서 `if bus == null or input == null: return` 바로 뒤에:

```gdscript
	if clock_hud != null:
		clock_hud.update_clock(clock)
	if clock != null and clock.is_finished:
		# 완주. 결과 화면이 떠 있는 동안 버스를 붙잡는다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		return
```

`respawn()` 끝의 `bus.respawn_to(...)` 다음 줄에:

```gdscript
	if clock != null:
		clock.respawns += 1
```

- [ ] **Step 5: 통과 확인**

Run: `tests/game/run_game_tests.sh; git checkout -q project.godot`
Expected: 15 개 씬 전부 `OK`

- [ ] **Step 6: 커밋**

```bash
git add scripts/result_panel.gd scripts/result_panel.gd.uid scripts/drive.gd tests/game/drive_smoke.gd
git commit -m "feat: 구간 주행에 시계·남은 시간·결과 화면 배선"
```

---

### Task 6: 메뉴 구간 목록, README, 최종 확인

**Files:**
- Modify: `scripts/menu.gd`
- Modify: `README.md`

**Interfaces:**
- Consumes: `RouteData.sections()`, `RouteData.slice()`, `RouteData.selected_section`, `Timetable.deadline_for()`, `Timetable.format_mmss()`

- [ ] **Step 1: 메뉴**

`scripts/menu.gd` 를 다음으로 바꾼다:

```gdscript
extends Control
class_name Menu
# 노선 선택. 목록을 하드코딩하지 않고 assets/routes 를 훑어서 만든다 —
# 노선을 더 구우면 메뉴가 알아서 늘어난다. 노선을 누르면 구간 목록이 펼쳐진다.
# 꾸미는 일은 7번 서브프로젝트(배포) 것이다. 여기서는 고를 수만 있으면 된다.

var _routes := {}               # route_id -> RouteData
var _sections_box: VBoxContainer

func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 16)
	add_child(box)

	var title := Label.new()
	title.text = "노선 선택"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	for route_id in RouteData.list_route_ids():
		var data := RouteData.load_route(route_id)
		if data == null:
			continue
		_routes[route_id] = data
		var button := Button.new()
		button.text = "%s\n%s → %s" % [data.display_name, data.from_name, data.to_name]
		button.custom_minimum_size = Vector2(360, 72)
		button.pressed.connect(_on_route_chosen.bind(route_id))
		box.add_child(button)

	_sections_box = VBoxContainer.new()
	_sections_box.add_theme_constant_override("separation", 8)
	box.add_child(_sections_box)

func _on_route_chosen(route_id: String) -> void:
	RouteData.selected_id = route_id
	for child in _sections_box.get_children():
		child.queue_free()
	var data: RouteData = _routes[route_id]
	for index in maxi(1, data.sections().size()):
		var part := data.slice(index)
		var button := Button.new()
		button.text = "구간 %d · %s → %s · 마감 %s" % [index + 1,
			_stop_name(part, 0), _stop_name(part, part.stops.size() - 1),
			Timetable.format_mmss(int(Timetable.deadline_for(part)))]
		button.custom_minimum_size = Vector2(360, 48)
		button.pressed.connect(_on_section_chosen.bind(index))
		_sections_box.add_child(button)

func _stop_name(data: RouteData, index: int) -> String:
	if index < 0 or index >= data.stops.size():
		return ""
	return str(data.stops[index].get("name", ""))

func _on_section_chosen(index: int) -> void:
	RouteData.selected_section = index
	get_tree().change_scene_to_file("res://scenes/drive.tscn")
```

- [ ] **Step 2: 메뉴 눈으로 확인**

Run: `godot res://scenes/menu.tscn` (창 모드). seoul-654 를 눌러 구간 8 개가 뜨고 마감이 5~16 분인지, 구간을 누르면 주행 씬이 뜨고 오른쪽 위에 남은 시간이 줄어드는지 본다. 끝나면 `git checkout -q project.godot`.

- [ ] **Step 3: README**

`README.md` 의 정류장 문단(“정류장에는 대기 승객이 서 있다 …”) 다음에 문단을 추가한다:

```markdown
노선은 정류장 10곳 단위 구간으로 나뉜다. 메뉴에서 노선을 누르면 구간 목록과
마감이 뜬다. 마감은 구간 길이를 32 km/h 로 달리는 시간에 정류장당 기대 정차
시간(약 10 초)과 신호당 기대 대기(8.25 초)를 더해 자동으로 정한다. 오른쪽 위에
남은 시간이 줄고, 넘기면 초과 시간이 붉게 올라간다. 끝 정류장에서 승하차를 마치면
결과 화면이 뜬다 — 완주 1000 점에 태운 승객 1명당 +20, 일찍 도착 초당 +2, 초과
초당 −5, 신호 위반 −50, 카메라 단속 −150, 놓친 정류장 −100, 못 태운 승객 −10,
리스폰 −30. 마감 안에 들어오고 감점이 150 이하면 별 셋이다. 결과 화면에서
`Enter` 는 다음 구간, `R` 은 다시 하기다.
```

`run_game_tests.sh` 설명 문장(“노선 데이터·도시 로딩·…·주행 스모크를 검사한다.”)을 바꾼다:

```markdown
`run_game_tests.sh` 는 노선 데이터·도시 로딩·입력 매핑·회전 반경·내비 라인·구간과
마감·점수·시계·주행 스모크를 검사한다. 성능은 창이 필요해서 따로 잰다.
```

문서 목록 끝에:

```markdown
- 설계: `docs/superpowers/specs/2026-09-24-timetable-score-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-24-timetable-score.md`
```

- [ ] **Step 4: 전체 확인**

Run:
```bash
python3 -m unittest discover -s tests -t . 2>&1 | tail -2
tests/game/run_game_tests.sh 2>&1 | grep -E ": (OK|FAIL)"
git checkout -q project.godot
git status --short
```
Expected: 파이썬 `OK`, 게임 씬 15 개 `OK`, 상태에는 `scripts/menu.gd` 와 `README.md` 만.

- [ ] **Step 5: 커밋**

```bash
git add scripts/menu.gd README.md
git commit -m "feat: 메뉴에서 구간을 고르고 README 에 시간표·점수 설명"
```
