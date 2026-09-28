# 시간 흐름, 날씨, 가로등 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 주행 중 게임 시각이 흐르며 태양·하늘·그림자·노을이 바뀌고, 비가 오다 그치며(시야·마찰·교통 속도), 밤에는 bake 한 가로등이 켜진다.

**Architecture:** 순수 계산(SunPath, DayClock.advance, Atmosphere.palette, Weather.step, RainScreen.step)과 노드 적용을 나눠 헤드리스로 테스트한다. `drive.gd` 가 매 프레임 값을 넘겨 배선하고, 부품끼리는 서로 참조하지 않는다. 가로등 자리는 bake(`routing.place_streetlights`)가 JSON `streetlights` 로 내보낸다.

**Tech Stack:** Godot 4.7.2 GDScript, Python 3 + shapely 2.1 (`.venv/bin/python`).

**Spec:** `docs/superpowers/specs/2026-09-28-weather-daylight-design.md`

## Global Constraints

- 작업 디렉토리 `/Users/kjw5541/games/bus-driver`, 브랜치 `weather`.
- 파이썬은 항상 `.venv/bin/python`. 테스트: `.venv/bin/python -m unittest discover -s tests -t .`
- 게임 테스트: `tests/game/run_game_tests.sh <씬이름...>`. godot 실행 뒤마다 `git checkout -q project.godot`.
- `git add -A` / `git add .` 금지. 파일 이름을 명시해서 add.
- 커밋 메시지는 한국어, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- 코드 주석은 한국어 산문. 주변 코드처럼 "왜"를 적는다.
- 시각: 05:00~24:00, 게임 1시간 = 실제 120초(0.5 게임분/초). 24:00 에서 05:00 으로 넘어간다.
- 서울 37.57°N, 126.98°E, KST. 월드 축 +X 동, −Z 북(bake 투영과 같다).
- 비: 전환 30초, 바퀴 마찰 3.5 → 2.2, 교통 순항 40 → 30 km/h, 도로 roughness 0.95 → 0.25.
- 가로등: 30 m 간격, 10 m 안 중복 제거, OmniLight 풀 12개, 범위 18 m.
- 와이퍼 3초 간격, 한 번 닦는 데 0.4초.

## Review Focus

- `--time=` 값이 잘못됐을 때("25:00", "abc", "04:00"): 무작위 시각으로 시작해야 하며 05:00 미만·24:00 이상이 되면 안 된다. → Task 2 테스트.
- 프레임이 크게 튀어 한 번에 자정을 여러 번 넘을 때: 시각은 항상 [05:00, 24:00) 안이어야 한다. → Task 2 테스트.
- 구 JSON 이나 인도 없는 구간(가로등 0개): StreetLights 가 에러 없이 아무것도 안 켠다. → Task 6 테스트.
- 밤에 태양 고도가 음수일 때 조명이 땅 밑에서 위로 비추면 안 된다(빛 방향 y < 0). → Task 3 테스트.
- 비가 그친 뒤 화면: 빗물이 말라 오버레이가 꺼져야 한다(맑은 날 화면 흐림 없음). → Task 5 테스트.

---

### Task 1: 가로등 자리 bake

**Files:**
- Modify: `tools/osmbake/routing.py` (`_to_sidewalk` 에서 탐색부 분리, `place_streetlights` 추가)
- Modify: `tools/osmbake/emit.py` (`streetlights` 인자)
- Modify: `tools/osmbake/cli.py` (호출, 출력)
- Modify: `scripts/route_data.gd` (`streetlights` 필드, slice)
- Test: `tests/osmbake/test_routing.py`, `tests/game/test_route_data.gd`
- Re-bake: `assets/routes/route_*.glb/json`

**Interfaces:**
- Produces: `place_streetlights(path_xz, sidewalk, spacing_m=30.0, min_gap_m=10.0) -> list[list[float]]` — `[[x, z, yaw], ...]`. yaw 는 라디안, `Basis(Vector3.UP, yaw)` 의 −Z 가 도로 쪽.
- Produces: JSON 키 `"streetlights"`, `RouteData.streetlights: Array` (각 원소 `[x, z, yaw]`). slice 는 전체를 그대로 넘긴다.

- [ ] **Step 1: 실패하는 테스트** — `tests/osmbake/test_routing.py` 끝에 추가. import 줄에 `place_streetlights` 를 더한다.

```python
class TestStreetlights(unittest.TestCase):
    def setUp(self):
        self.projector = Projector(37.500, 127.000)
        # 정동쪽 약 176 m 직선. 우측은 +z, 좌측은 -z.
        self.path = project_path(
            [(37.500, 127.000), (37.500, 127.001), (37.500, 127.002)],
            self.projector)
        self.both = box(-10.0, 12.0, 300.0, 14.0).union(box(-10.0, -14.0, 300.0, -12.0))

    def test_양쪽_인도에_간격대로_선다(self):
        lights = place_streetlights(self.path, self.both)
        right = [l for l in lights if l[1] > 0]
        left = [l for l in lights if l[1] < 0]
        self.assertEqual(len(right), 6)   # 0, 30, ... 150 m
        self.assertEqual(len(left), 6)
        for x, z, yaw in right:
            self.assertAlmostEqual(z, 13.0, delta=0.3)
            self.assertAlmostEqual(yaw, 0.0, delta=0.05)       # -Z(도로)를 본다
        for x, z, yaw in left:
            self.assertAlmostEqual(z, -13.0, delta=0.3)
            self.assertAlmostEqual(abs(yaw), math.pi, delta=0.05)

    def test_인도_없는_쪽은_비운다(self):
        lights = place_streetlights(self.path, box(-10.0, 12.0, 300.0, 14.0))
        self.assertEqual(len(lights), 6)
        self.assertTrue(all(l[1] > 0 for l in lights))

    def test_가까운_자리는_하나만(self):
        lights = place_streetlights(self.path, self.both, spacing_m=4.0)
        for i, a in enumerate(lights):
            for b in lights[i + 1:]:
                self.assertGreaterEqual(math.hypot(a[0] - b[0], a[1] - b[1]), 10.0 - 1e-6)
```

`math` 가 import 안 돼 있으면 파일 위에 `import math` 를 더한다.

- [ ] **Step 2: 실패 확인**

Run: `.venv/bin/python -m unittest tests.osmbake.test_routing -k Streetlights`
Expected: ImportError `place_streetlights`

- [ ] **Step 3: 구현** — `routing.py`. `_to_sidewalk` 의 탐색부(`steps = ...` 부터 끝까지)를 `_sidewalk_mid` 로 떼고, `_to_sidewalk` 는 마지막을 `return _sidewalk_mid(sidewalk, (foot_x, foot_z), (right_x, right_z))` 로 바꾼다. 그 아래 `place_streetlights` 를 둔다.

```python
def _sidewalk_mid(sidewalk, foot: tuple[float, float],
                  normal: tuple[float, float]) -> tuple[float, float] | None:
    """foot 에서 normal 방향으로 처음 만나는 인도 구간의 한가운데. 없으면 None."""
    steps = int(SIDEWALK_SEARCH_M / SIDEWALK_STEP_M) + 1
    offsets = [i * SIDEWALK_STEP_M for i in range(steps)]
    inside = shapely.contains_xy(sidewalk,
                                 [foot[0] + normal[0] * o for o in offsets],
                                 [foot[1] + normal[1] * o for o in offsets])
    run = []
    for offset, hit in zip(offsets, inside):
        if hit:
            run.append(offset)
        elif run:
            break
    if not run:
        return None
    out = (run[0] + run[-1]) / 2.0
    return (foot[0] + normal[0] * out, foot[1] + normal[1] * out)


def place_streetlights(path_xz: list[tuple[float, float]], sidewalk,
                       spacing_m: float = 30.0,
                       min_gap_m: float = 10.0) -> list[list[float]]:
    """노선 양쪽 인도에 spacing_m 간격으로 가로등 자리 [x, z, yaw] 를 뽑는다.

    yaw 는 Basis(UP, yaw) 의 -Z 가 도로(노선) 쪽을 보게 하는 각이다. 급커브와
    교차로에서는 이웃 표본이 같은 인도 자리로 몰리므로 min_gap_m 안의 자리는
    먼저 놓인 하나만 남긴다.
    """
    lights: list[list[float]] = []
    walked = 0.0
    next_at = 0.0
    for index in range(len(path_xz) - 1):
        ax, az = path_xz[index]
        bx, bz = path_xz[index + 1]
        length = math.hypot(bx - ax, bz - az)
        if length < 1e-9:
            continue
        tx, tz = (bx - ax) / length, (bz - az) / length
        while next_at <= walked + length:
            t = next_at - walked
            foot = (ax + tx * t, az + tz * t)
            for normal in ((-tz, tx), (tz, -tx)):
                spot = _sidewalk_mid(sidewalk, foot, normal)
                if spot is None:
                    continue
                # ponytail: 전체 대조라 O(n²). 1,300 개에서 1초 안이다. 느려지면 STRtree.
                if any(math.hypot(spot[0] - l[0], spot[1] - l[1]) < min_gap_m
                       for l in lights):
                    continue
                yaw = math.atan2(-(foot[0] - spot[0]), -(foot[1] - spot[1]))
                lights.append([round(spot[0], 2), round(spot[1], 2), round(yaw, 3)])
            next_at += spacing_m
        walked += length
    return lights
```

- [ ] **Step 4: 통과 확인** — Step 2 명령. Expected: 3 tests OK. 이어서 전체 `.venv/bin/python -m unittest discover -s tests -t .` 도 OK(기존 정류장 테스트가 리팩터 후에도 통과).

- [ ] **Step 5: emit / cli / RouteData**

`emit.py`: 시그니처에 `streetlights=()` 를 `signals` 뒤에 추가, docstring 에 `streetlights: [[x, z, yaw], ...] 가로등 자리` 한 줄, payload 에 `"streetlights": [list(s) for s in streetlights],` 를 `"signals"` 다음에.

`cli.py`: `from .routing import (...)` 에 `place_streetlights` 추가. `stops = snap_stops(...)` 다음 줄에

```python
    streetlights = place_streetlights(route_xz, sidewalk_top)
```

`write_route_json(...)` 에 `streetlights=streetlights,` 추가, 마지막 print 의 `신호 후보 {len(signals)}개, ` 뒤에 `가로등 {len(streetlights)}개, ` 추가.

정류장과 같이 중심선 `route_xz` 를 쓴다(`drive_xz` 는 차로 오프셋이 들어가 좌우 탐색 기준이 한쪽으로 치우친다).

`route_data.gd`: `var signals: Array = []` 아래에 `var streetlights: Array = []`. `load_route` 의 `data.signals = ...` 아래에 `data.streetlights = parsed.get("streetlights", [])`. `slice` 의 `for entry in signals:` 앞에 `part.streetlights = streetlights` (전체를 넘긴다 — MultiMesh 한 번이라 싸다).

`tests/game/test_route_data.gd` 의 신호 검사 다음에:

```gdscript
	ok(data.streetlights.size() > 20, "가로등이 %d 개뿐이다" % data.streetlights.size())
	if not data.streetlights.is_empty():
		ok(data.streetlights[0].size() == 3, "가로등 계약이 [x, z, yaw] 가 아니다")
```

- [ ] **Step 6: 다시 굽고 확인**

Run: `for r in seoul-100 seoul-654 seoul-seodaemun03; do .venv/bin/python -m tools.osmbake.cli bake $r; done` (약 2.5분)
Expected: 각 줄에 `가로등 N개`. seoul-100 N 은 대략 800~1,500.
Run: `tests/game/run_game_tests.sh test_route_data test_sections drive_smoke; git checkout -q project.godot` — 모두 OK.

- [ ] **Step 7: 커밋**

```bash
git add tools/osmbake/routing.py tools/osmbake/emit.py tools/osmbake/cli.py scripts/route_data.gd tests/osmbake/test_routing.py tests/game/test_route_data.gd assets/routes/route_seoul-100.glb assets/routes/route_seoul-100.json assets/routes/route_seoul-654.glb assets/routes/route_seoul-654.json assets/routes/route_seoul-seodaemun03.glb assets/routes/route_seoul-seodaemun03.json
git commit -m "feat: 노선 양쪽 인도에 가로등 자리를 굽는다"
```

---

### Task 2: 게임 시각과 태양 위치

**Files:**
- Create: `scripts/sun_path.gd`, `scripts/day_clock.gd`
- Modify: `scripts/clock_hud.gd` (시각 라벨, 첫차 표시)
- Test: `tests/game/test_sun_path.gd/.tscn`, `tests/game/test_day_clock.gd/.tscn`, `tests/game/run_game_tests.sh` 목록

**Interfaces:**
- Produces: `SunPath.angles(day_of_year: int, minutes_kst: float) -> Vector2` (x 고도°, y 방위° 북0 동90), `SunPath.direction(elevation_deg, azimuth_deg) -> Vector3` (태양 쪽 단위벡터), `SunPath.today() -> int`.
- Produces: `DayClock` (Node) — `minutes: float`, `signal rolled_over`, `advance(delta_s)`, `start(start_minutes: float)`, `static minutes_from_args(args: PackedStringArray) -> float` (없거나 잘못되면 -1), `static hhmm(minutes) -> String`, 상수 `FIRST_BUS := 300.0`, `LAST := 1440.0`, `SPEED := 0.5`.
- Produces: `ClockHud.update_time(minutes: float)`, `ClockHud.show_first_bus()`, `ClockHud.time_text: String`.

- [ ] **Step 1: 실패하는 테스트**

`tests/game/test_sun_path.gd`:

```gdscript
extends TestCase
# 태양 위치 공식. 서울 기준 교과서 값과 비교한다.

func _ready() -> void:
	# 하지(172일) 태양 남중은 KST 12:32 쯤, 고도 90 - 37.57 + 23.44 = 75.9°.
	equal_approx(SunPath.angles(172, 752.0).x, 75.9, 1.0, "하지 남중 고도")
	# 동지(355일) 남중 고도 90 - 37.57 - 23.44 = 29.0°.
	equal_approx(SunPath.angles(355, 752.0).x, 29.0, 1.0, "동지 남중 고도")
	# 춘분(80일) 일몰은 KST 18:30 전후.
	ok(SunPath.angles(80, 18 * 60 + 15).x > 0.0, "춘분 18:15 에 해가 졌다")
	ok(SunPath.angles(80, 18 * 60 + 45).x < 0.0, "춘분 18:45 에 해가 떠 있다")
	# 오전은 동쪽(방위 < 180), 오후는 서쪽.
	ok(SunPath.angles(172, 9 * 60).y < 180.0, "오전 방위가 서쪽이다")
	ok(SunPath.angles(172, 16 * 60).y > 180.0, "오후 방위가 동쪽이다")
	# 방위 90°(동)는 +X, 고도 0 이면 y 0.
	var east := SunPath.direction(0.0, 90.0)
	ok(east.distance_to(Vector3(1, 0, 0)) < 0.001, "동쪽 벡터가 %s" % east)
	var north := SunPath.direction(0.0, 0.0)
	ok(north.distance_to(Vector3(0, 0, -1)) < 0.001, "북쪽 벡터가 %s" % north)
	ok(SunPath.today() >= 1 and SunPath.today() <= 366, "오늘 날짜 %d" % SunPath.today())
	finish()
```

`tests/game/test_day_clock.gd`:

```gdscript
extends TestCase
# 게임 시각. _process 대신 advance 를 직접 불러 프레임과 무관하게 본다.

var _rolls := 0

func _ready() -> void:
	var clock := DayClock.new()
	clock.rolled_over.connect(func() -> void: _rolls += 1)
	clock.start(23 * 60 + 59)
	clock.advance(2.0)   # 1 게임분 = 2 실제 초. 24:00 을 넘는다
	equal_approx(clock.minutes, DayClock.FIRST_BUS, 0.01, "자정에 05:00 으로 안 넘어갔다")
	ok(_rolls == 1, "rolled_over 가 %d 번" % _rolls)
	clock.advance(120.0)
	equal_approx(clock.minutes, DayClock.FIRST_BUS + 60.0, 0.01, "1시간이 120초가 아니다")
	# 프레임이 크게 튀어도 범위 안.
	clock.start(1430.0)
	clock.advance(10000.0)
	ok(clock.minutes >= DayClock.FIRST_BUS and clock.minutes < DayClock.LAST,
		"시각이 범위 밖 %.1f" % clock.minutes)
	# 인자 해석.
	equal_approx(DayClock.minutes_from_args(PackedStringArray(["--time=17:42"])), 1062.0, 0.01, "17:42")
	for bad in ["--time=25:00", "--time=abc", "--time=04:00", "--time=24:00"]:
		ok(DayClock.minutes_from_args(PackedStringArray([bad])) < 0.0, "%s 를 받아들였다" % bad)
	ok(DayClock.minutes_from_args(PackedStringArray()) < 0.0, "인자 없는데 값이 나왔다")
	# start 에 음수를 주면 범위 안 무작위.
	for i in 20:
		clock.start(-1.0)
		ok(clock.minutes >= DayClock.FIRST_BUS and clock.minutes < DayClock.LAST,
			"무작위 시작 %.1f" % clock.minutes)
	ok(DayClock.hhmm(1062.0) == "17:42", "hhmm %s" % DayClock.hhmm(1062.0))
	ok(DayClock.hhmm(300.0) == "05:00", "hhmm %s" % DayClock.hhmm(300.0))
	clock.free()
	finish()
```

각 `.tscn` 은 기존 형식 그대로(노드 이름만 다르게):

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_sun_path.gd" id="1"]

[node name="TestSunPath" type="Node3D"]
script = ExtResource("1")
```

`run_game_tests.sh` 의 `scenes=(...)` 목록 `drive_smoke` 앞에 `test_sun_path test_day_clock` 추가.

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_sun_path test_day_clock; git checkout -q project.godot`. Expected: FAIL(SunPath / DayClock 없음).

- [ ] **Step 3: 구현**

`scripts/sun_path.gd`:

```gdscript
extends RefCounted
class_name SunPath
# 서울에서 본 태양 고도·방위. 균시차는 무시한다(±16분) — 게임에서 해 지는
# 시각이 몇 분 틀려도 아무도 모른다.

const LATITUDE_DEG := 37.57
const LONGITUDE_DEG := 126.98
const ZONE_MERIDIAN_DEG := 135.0   # KST = UTC+9

static func angles(day_of_year: int, minutes_kst: float) -> Vector2:
	"""(고도, 방위) 도. 방위는 북 0°, 동 90°."""
	var declination := deg_to_rad(23.44 * sin(deg_to_rad(360.0 / 365.0 * (284 + day_of_year))))
	# 서울은 표준 자오선보다 서쪽이라 태양시가 KST 보다 약 32분 늦다.
	var solar_minutes := minutes_kst - (ZONE_MERIDIAN_DEG - LONGITUDE_DEG) * 4.0
	var hour_angle := deg_to_rad(15.0 * (solar_minutes / 60.0 - 12.0))
	var latitude := deg_to_rad(LATITUDE_DEG)
	var elevation := asin(sin(latitude) * sin(declination)
		+ cos(latitude) * cos(declination) * cos(hour_angle))
	# 남쪽 기준 서쪽으로 잰 방위에 180° 를 더해 북쪽 기준으로 바꾼다.
	var azimuth := atan2(sin(hour_angle),
		cos(hour_angle) * sin(latitude) - tan(declination) * cos(latitude)) + PI
	return Vector2(rad_to_deg(elevation), fposmod(rad_to_deg(azimuth), 360.0))

static func direction(elevation_deg: float, azimuth_deg: float) -> Vector3:
	"""태양 쪽 단위벡터. +X 동, -Z 북이다(bake 투영과 같다)."""
	var e := deg_to_rad(elevation_deg)
	var a := deg_to_rad(azimuth_deg)
	return Vector3(cos(e) * sin(a), sin(e), -cos(e) * cos(a))

static func today() -> int:
	var date := Time.get_date_dict_from_system()
	var start := Time.get_unix_time_from_datetime_dict(
		{"year": date["year"], "month": 1, "day": 1})
	var now := Time.get_unix_time_from_datetime_dict(
		{"year": date["year"], "month": date["month"], "day": date["day"]})
	return int((now - start) / 86400) + 1
```

`scripts/day_clock.gd`:

```gdscript
extends Node
class_name DayClock
# 게임 속 시각(분). 남은 시간(RunClock)과는 별개로 흐른다 — 마감에는
# 영향이 없고 해·하늘·가로등만 움직인다.
#
# 새벽에는 버스가 다니지 않으니 24:00 이 되면 첫차 05:00 으로 넘긴다.

signal rolled_over

const FIRST_BUS := 300.0   # 05:00
const LAST := 1440.0       # 24:00
const SPEED := 0.5         # 게임 분 / 실제 초. 게임 1시간이 실제 2분이다

var minutes := FIRST_BUS

func start(start_minutes: float) -> void:
	"""음수면 [05:00, 24:00) 에서 무작위로 고른다."""
	minutes = start_minutes if start_minutes >= 0.0 else randf_range(FIRST_BUS, LAST)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta_s: float) -> void:
	minutes += SPEED * delta_s
	if minutes >= LAST:
		# 한 번에 여러 날을 넘는 큰 delta 도 첫차 이후 하루 운행 시간 안에 접는다.
		minutes = FIRST_BUS + fposmod(minutes - LAST, LAST - FIRST_BUS)
		rolled_over.emit()

static func minutes_from_args(args: PackedStringArray) -> float:
	"""--time=HH:MM. 없거나 운행 시간(05:00~23:59) 밖이면 -1."""
	for argument in args:
		if not argument.begins_with("--time="):
			continue
		var parts := argument.trim_prefix("--time=").split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return -1.0
		var value := int(parts[0]) * 60.0 + int(parts[1])
		if int(parts[1]) > 59 or value < FIRST_BUS or value >= LAST:
			return -1.0
		return value
	return -1.0

static func hhmm(value: float) -> String:
	var whole := int(value)
	return "%02d:%02d" % [whole / 60, whole % 60]
```

`scripts/clock_hud.gd`: `var _label: Label` 아래에 필드와 `_ready` 끝에 라벨을 더하고, 함수 둘을 추가한다.

```gdscript
const FIRST_BUS_NOTICE_S := 3.0

var time_text: String:
	get: return _time.text if _time != null else ""

var _time: Label
var _notice_left := 0.0
```

`_ready` 끝:

```gdscript
	# 게임 시각. 남은 시간 바로 아래.
	_time = Label.new()
	_time.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time.position = Vector2(-236.0, 50.0)
	_time.size = Vector2(220.0, 28.0)
	_time.add_theme_font_size_override("font_size", 20)
	add_child(_time)
```

함수:

```gdscript
func update_time(minutes: float, delta: float = 0.0) -> void:
	if _time == null:
		return
	_notice_left = maxf(0.0, _notice_left - delta)
	_time.text = "첫차 05:00" if _notice_left > 0.0 else DayClock.hhmm(minutes)

func show_first_bus() -> void:
	_notice_left = FIRST_BUS_NOTICE_S
```

`test_day_clock.gd` 의 `clock.free()` 앞에 HUD 확인을 더한다:

```gdscript
	var hud := ClockHud.new()
	add_child(hud)
	hud.update_time(1062.0)
	ok(hud.time_text == "17:42", "HUD 시각 %s" % hud.time_text)
	hud.show_first_bus()
	hud.update_time(300.0, 1.0)
	ok(hud.time_text == "첫차 05:00", "첫차 표시 %s" % hud.time_text)
	hud.update_time(301.0, 3.0)
	ok(hud.time_text == "05:01", "첫차 표시가 안 사라졌다 %s" % hud.time_text)
	hud.queue_free()
```

- [ ] **Step 4: 통과 확인** — Step 2 명령. Expected: 둘 다 OK.

- [ ] **Step 5: 커밋**

```bash
git add scripts/sun_path.gd scripts/sun_path.gd.uid scripts/day_clock.gd scripts/day_clock.gd.uid scripts/clock_hud.gd tests/game/test_sun_path.gd tests/game/test_sun_path.tscn tests/game/test_day_clock.gd tests/game/test_day_clock.tscn tests/game/run_game_tests.sh
git commit -m "feat: 게임 시각과 서울 태양 위치를 계산한다"
```

(`.uid` 파일이 생기지 않았으면 그 이름은 뺀다. `git status --short` 로 확인. 테스트 `.gd.uid` 도 생겼으면 함께 add.)

---

### Task 3: 하늘·햇빛·노을 (Atmosphere) + drive 배선

**Files:**
- Create: `scripts/atmosphere.gd`
- Modify: `scripts/drive.gd` (고정 태양 교체, DayClock·Atmosphere 배선)
- Test: `tests/game/test_atmosphere.gd/.tscn`, `run_game_tests.sh`

**Interfaces:**
- Consumes: `SunPath.direction`, `DayClock`, `ClockHud.update_time/show_first_bus`.
- Produces: `Atmosphere` (Node3D) — `sun: DirectionalLight3D`, `environment: Environment`, `apply(elevation_deg, azimuth_deg, rain: float)`, `static palette(elevation_deg, rain) -> Dictionary` 키 `sky_top`, `horizon`, `sun_color` (Color), `sun_energy`, `ambient` (float).
- Produces: `drive.gd` 필드 `day_clock: DayClock`, `atmosphere: Atmosphere`, `day_of_year: int`. `drive._process(delta)` 이 매 프레임 `_update_environment(delta)` 를 부른다 — Task 4·6 이 이 함수에 줄을 더한다.

- [ ] **Step 1: 실패하는 테스트** — `tests/game/test_atmosphere.gd`:

```gdscript
extends TestCase
# 하늘 색 보간과 조명 방향.

func _ready() -> void:
	var sunset := Atmosphere.palette(0.0, 0.0)
	ok(sunset["horizon"].r > sunset["horizon"].b + 0.3, "고도 0 에 노을이 없다 %s" % sunset["horizon"])
	var noon := Atmosphere.palette(60.0, 0.0)
	var night := Atmosphere.palette(-15.0, 0.0)
	ok(night["sun_energy"] < noon["sun_energy"] * 0.2, "밤이 충분히 어둡지 않다")
	ok(noon["horizon"].b >= noon["horizon"].r, "한낮 지평선이 붉다")
	var wet := Atmosphere.palette(60.0, 1.0)
	ok(wet["sun_energy"] < noon["sun_energy"], "비 오는데 햇빛이 그대로다")
	# 키 사이는 연속이다.
	var a := Atmosphere.palette(2.49, 0.0)
	var b := Atmosphere.palette(2.51, 0.0)
	equal_approx(a["sun_energy"], b["sun_energy"], 0.01, "보간이 끊긴다")

	var atmosphere := Atmosphere.new()
	add_child(atmosphere)
	atmosphere.apply(30.0, 180.0, 0.0)
	# DirectionalLight 는 -Z 로 비춘다. 남쪽 하늘의 해는 북쪽(-Z)·아래로 비춘다.
	var forward := -atmosphere.sun.global_basis.z
	ok(forward.y < 0.0 and forward.z < 0.0, "낮 빛 방향 %s" % forward)
	atmosphere.apply(-20.0, 330.0, 0.0)
	forward = -atmosphere.sun.global_basis.z
	ok(forward.y < 0.0, "밤에 빛이 땅 밑에서 올라온다 %s" % forward)
	ok(atmosphere.sun.shadow_enabled, "그림자가 꺼졌다")
	atmosphere.apply(30.0, 180.0, 1.0)
	ok(atmosphere.environment.fog_enabled, "비 오는데 안개가 없다")
	atmosphere.apply(30.0, 180.0, 0.0)
	ok(not atmosphere.environment.fog_enabled, "맑은데 안개가 있다")
	finish()
```

`.tscn` 은 Task 2 와 같은 형식(`TestAtmosphere`), `run_game_tests.sh` 목록에 `test_atmosphere` 추가.

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_atmosphere; git checkout -q project.godot`. Expected: FAIL.

- [ ] **Step 3: 구현** — `scripts/atmosphere.gd`:

```gdscript
extends Node3D
class_name Atmosphere
# 해(DirectionalLight3D)와 하늘(ProceduralSky). 태양 고도에 따라 색을 섞고,
# 고도 -6°~+10° 에서 노을을 낸다. 해가 지면 같은 조명을 약한 달빛으로 쓴다
# — 빛 하나로 그림자를 계속 낸다.

const MOON_ELEVATION_DEG := 50.0
const MOON_AZIMUTH_DEG := 200.0
const RAIN_GREY := Color(0.36, 0.38, 0.41)
const RAIN_SUN_CUT := 0.6       # 비 1 에서 햇빛을 이만큼 줄인다
const RAIN_FOG_DENSITY := 0.006
const SHADOW_DISTANCE_M := 200.0

# [고도°, 하늘 위, 지평선, 햇빛 색, 햇빛 에너지, 주변광 에너지]
const KEYS := [
	[-12.0, Color(0.01, 0.015, 0.04), Color(0.03, 0.04, 0.08), Color(0.6, 0.7, 1.0), 0.08, 0.12],
	[-6.0, Color(0.05, 0.07, 0.18), Color(0.35, 0.2, 0.25), Color(0.7, 0.7, 1.0), 0.1, 0.2],
	[0.0, Color(0.2, 0.25, 0.5), Color(1.0, 0.45, 0.2), Color(1.0, 0.45, 0.2), 0.6, 0.35],
	[5.0, Color(0.3, 0.4, 0.7), Color(1.0, 0.6, 0.35), Color(1.0, 0.65, 0.4), 0.9, 0.5],
	[10.0, Color(0.35, 0.5, 0.8), Color(0.9, 0.75, 0.6), Color(1.0, 0.85, 0.7), 1.1, 0.6],
	[20.0, Color(0.3, 0.5, 0.85), Color(0.7, 0.8, 0.9), Color(1.0, 0.98, 0.95), 1.3, 0.7],
]

var sun: DirectionalLight3D
var environment: Environment
var _sky: ProceduralSkyMaterial

func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = SHADOW_DISTANCE_M
	add_child(sun)
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

static func palette(elevation_deg: float, rain: float) -> Dictionary:
	var low: Array = KEYS[0]
	var high: Array = KEYS[-1]
	for index in KEYS.size() - 1:
		if elevation_deg >= KEYS[index][0] and elevation_deg <= KEYS[index + 1][0]:
			low = KEYS[index]
			high = KEYS[index + 1]
			break
	var t := 0.0
	if high[0] > low[0]:
		t = clampf((elevation_deg - low[0]) / (high[0] - low[0]), 0.0, 1.0)
	elif elevation_deg > low[0]:
		t = 1.0
	var out := {
		"sky_top": (low[1] as Color).lerp(high[1], t),
		"horizon": (low[2] as Color).lerp(high[2], t),
		"sun_color": (low[3] as Color).lerp(high[3], t),
		"sun_energy": lerpf(low[4], high[4], t),
		"ambient": lerpf(low[5], high[5], t),
	}
	# 비는 하늘을 회색으로 덮고 해를 가린다. 밤하늘은 원래 어두워 덜 섞는다.
	var grey := RAIN_GREY * clampf(out["ambient"] / 0.7, 0.1, 1.0)
	out["sky_top"] = (out["sky_top"] as Color).lerp(grey, rain * 0.8)
	out["horizon"] = (out["horizon"] as Color).lerp(grey, rain * 0.8)
	out["sun_energy"] = out["sun_energy"] * (1.0 - RAIN_SUN_CUT * rain)
	return out

func apply(elevation_deg: float, azimuth_deg: float, rain: float) -> void:
	var colors := palette(elevation_deg, rain)
	var toward := SunPath.direction(elevation_deg, azimuth_deg)
	if elevation_deg < 0.0:
		toward = SunPath.direction(MOON_ELEVATION_DEG, MOON_AZIMUTH_DEG)
	# look_at 은 -Z 를 목표로 돌린다. 빛은 해에서 땅으로 가므로 해 반대쪽을 본다.
	sun.global_transform = Transform3D(Basis.looking_at(-toward, Vector3.UP), Vector3.ZERO)
	sun.light_color = colors["sun_color"]
	sun.light_energy = colors["sun_energy"]
	_sky.sky_top_color = colors["sky_top"]
	_sky.sky_horizon_color = colors["horizon"]
	_sky.ground_horizon_color = colors["horizon"]
	_sky.ground_bottom_color = (colors["sky_top"] as Color).darkened(0.5)
	environment.ambient_light_energy = colors["ambient"]
	environment.fog_enabled = rain > 0.01
	environment.fog_light_color = colors["horizon"]
	environment.fog_density = RAIN_FOG_DENSITY * rain
```

주의: 태양 고도 90° 근처면 `Basis.looking_at` 이 UP 과 평행해 실패하지만 서울 최대 고도가 76° 라 생기지 않는다.

`scripts/drive.gd`:
- 필드 목록 끝(`var result: ResultPanel` 아래)에:

```gdscript
var day_clock: DayClock
var atmosphere: Atmosphere
var day_of_year := 1
```

- `_ready` 의 고정 태양 4줄(`var light := DirectionalLight3D.new()` ~ `add_child(light)`)을 다음으로 바꾼다:

```gdscript
	atmosphere = Atmosphere.new()
	add_child(atmosphere)
	day_clock = DayClock.new()
	day_clock.start(DayClock.minutes_from_args(OS.get_cmdline_user_args()))
	add_child(day_clock)
	day_of_year = SunPath.today()
```

- `clock_hud = ClockHud.new()` / `add_child(clock_hud)` 다음 줄에:

```gdscript
	day_clock.rolled_over.connect(clock_hud.show_first_bus)
```

- 파일 끝에 추가:

```gdscript
func _process(delta: float) -> void:
	if day_clock == null:
		return
	_update_environment(delta)

func _update_environment(delta: float) -> void:
	"""시각·날씨를 하늘과 조명에 넘긴다. 부품끼리는 서로 모른다."""
	var sun := SunPath.angles(day_of_year, day_clock.minutes)
	atmosphere.apply(sun.x, sun.y, 0.0)
	clock_hud.update_time(day_clock.minutes, delta)
```

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh test_atmosphere drive_smoke test_camera_view; git checkout -q project.godot`. Expected: 모두 OK.

- [ ] **Step 5: 커밋**

```bash
git add scripts/atmosphere.gd scripts/atmosphere.gd.uid scripts/drive.gd tests/game/test_atmosphere.gd tests/game/test_atmosphere.tscn tests/game/run_game_tests.sh
git commit -m "feat: 시각에 따라 해 방향과 하늘 색이 바뀌고 노을이 진다"
```

---

### Task 4: 비 — 세기, 마찰, 교통 속도, 젖은 노면, 빗줄기

**Files:**
- Create: `scripts/weather.gd`
- Modify: `scripts/bus.gd` (`set_wet`), `scripts/car_follow.gd` (`cruise` 인자), `scripts/traffic.gd` (`cruise_scale`), `scripts/city.gd` (`set_wet`), `scripts/drive.gd`
- Test: `tests/game/test_weather.gd/.tscn`, `run_game_tests.sh`

**Interfaces:**
- Consumes: `drive._update_environment`, `Atmosphere.apply(..., rain)`.
- Produces: `Weather` (Node3D) — `rain: float` 0~1, `follow: Node3D`, `start(forced: int)` (-1 무작위 일정, 0 맑음 고정, 1 비 고정), `step(delta)`, `static rain_from_args(args) -> int`, 상수 `RAMP_S := 30.0`.
- Produces: `Bus.set_wet(amount)`, 상수 `Bus.DRY_GRIP := 3.5`, `Bus.WET_GRIP := 2.2`. `Traffic.cruise_scale: float`. `City.set_wet(amount)`, `City.road_materials() -> Array[BaseMaterial3D]`. `CarFollow.next_speed(..., delta, cruise := CRUISE_MPS)`.

- [ ] **Step 1: 실패하는 테스트** — `tests/game/test_weather.gd`:

```gdscript
extends TestCase
# 비 세기 전환과 그 효과.

func _ready() -> void:
	var weather := Weather.new()
	add_child(weather)
	weather.start(1)
	weather.rain = 0.0
	weather.step(Weather.RAMP_S / 2.0)
	equal_approx(weather.rain, 0.5, 0.01, "30초 전환의 중간")
	weather.step(Weather.RAMP_S)
	equal_approx(weather.rain, 1.0, 0.001, "비가 다 안 찼다")
	weather.step(600.0)
	equal_approx(weather.rain, 1.0, 0.001, "고정인데 비가 그쳤다")
	weather.start(-1)
	var changed := false
	var first := weather.rain
	for i in 1200:
		weather.step(1.0)
		ok(weather.rain >= 0.0 and weather.rain <= 1.0, "세기가 범위 밖")
		if absf(weather.rain - first) > 0.5:
			changed = true
	ok(changed, "20분 동안 날씨가 한 번도 안 바뀌었다")
	ok(Weather.rain_from_args(PackedStringArray(["--rain=1"])) == 1, "--rain=1")
	ok(Weather.rain_from_args(PackedStringArray(["--rain=0"])) == 0, "--rain=0")
	ok(Weather.rain_from_args(PackedStringArray(["--rain=x"])) == -1, "--rain=x")
	ok(Weather.rain_from_args(PackedStringArray()) == -1, "인자 없음")

	var bus := Bus.new()
	add_child(bus)
	bus.set_wet(1.0)
	for wheel in bus.find_children("*", "VehicleWheel3D", false, false):
		equal_approx(wheel.wheel_friction_slip, Bus.WET_GRIP, 0.001, "젖은 바퀴 마찰")
	bus.set_wet(0.0)
	for wheel in bus.find_children("*", "VehicleWheel3D", false, false):
		equal_approx(wheel.wheel_friction_slip, Bus.DRY_GRIP, 0.001, "마른 바퀴 마찰")

	var dry := CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, INF, TrafficSignal.Phase.GREEN, 1.0)
	var wet := CarFollow.next_speed(CarFollow.CRUISE_MPS, INF, INF, TrafficSignal.Phase.GREEN, 1.0,
		CarFollow.CRUISE_MPS * 0.75)
	ok(wet < dry, "비 오는데 순항 속도가 그대로")

	var city := City.new()
	add_child(city)
	city.load_city("seoul-seodaemun03")
	ok(not city.road_materials().is_empty(), "도로 재질을 못 찾았다")
	city.set_wet(1.0)
	for material in city.road_materials():
		equal_approx(material.roughness, City.WET_ROUGHNESS, 0.001, "젖은 도로 반사")
	city.set_wet(0.0)
	for material in city.road_materials():
		equal_approx(material.roughness, City.DRY_ROUGHNESS, 0.001, "마른 도로")
	finish()
```

`.tscn`(`TestWeather`)과 `run_game_tests.sh` 목록 추가.

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_weather; git checkout -q project.godot`. Expected: FAIL.

- [ ] **Step 3: 구현**

`scripts/weather.gd`:

```gdscript
extends Node3D
class_name Weather
# 비. 맑음과 비를 무작위 길이로 번갈아 두고, 세기(rain 0~1)는 RAMP_S 에
# 걸쳐 따라간다. 효과는 drive.gd 가 세기를 받아 각 부품에 넘긴다.
#
# 빗줄기는 카메라(follow)를 따라다니는 입자 상자 하나다. 도시 전체에 뿌릴
# 필요가 없다.

const RAMP_S := 30.0
const CLEAR_S := Vector2(120.0, 360.0)
const RAIN_S := Vector2(60.0, 240.0)
const START_RAIN_CHANCE := 0.3
const DROP_COUNT := 4000
const BOX := Vector3(40.0, 25.0, 40.0)

var rain := 0.0
var follow: Node3D

var _target := 0.0
var _forced := -1
var _left := 0.0
var _drops: GPUParticles3D

func _ready() -> void:
	_drops = GPUParticles3D.new()
	_drops.amount = DROP_COUNT
	_drops.lifetime = 1.2
	_drops.visibility_aabb = AABB(-BOX / 2.0, BOX)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(BOX.x / 2.0, 0.5, BOX.z / 2.0)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 3.0
	process.initial_velocity_min = 18.0
	process.initial_velocity_max = 22.0
	process.gravity = Vector3.ZERO
	_drops.process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.02, 0.6)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = look
	_drops.draw_pass_1 = streak
	_drops.amount_ratio = 0.0
	_drops.emitting = false
	add_child(_drops)

func start(forced: int) -> void:
	"""forced: -1 무작위 일정, 0 맑음 고정, 1 비 고정."""
	_forced = forced
	if forced >= 0:
		_target = float(forced)
	else:
		_target = 1.0 if randf() < START_RAIN_CHANCE else 0.0
		_left = _span()
	rain = _target

func _process(delta: float) -> void:
	step(delta)
	if follow != null:
		global_position = follow.global_position + Vector3.UP * (BOX.y / 2.0 - 3.0)

func step(delta: float) -> void:
	if _forced < 0:
		_left -= delta
		if _left <= 0.0:
			_target = 1.0 - _target
			_left = _span()
	rain = move_toward(rain, _target, delta / RAMP_S)
	if _drops != null:
		_drops.emitting = rain > 0.01
		_drops.amount_ratio = rain

func _span() -> float:
	var span := RAIN_S if _target > 0.5 else CLEAR_S
	return randf_range(span.x, span.y)

static func rain_from_args(args: PackedStringArray) -> int:
	"""--rain=0|1. 없거나 잘못되면 -1(무작위)."""
	for argument in args:
		if argument == "--rain=0":
			return 0
		if argument == "--rain=1":
			return 1
	return -1
```

`scripts/bus.gd`: 상수 목록에 추가

```gdscript
const DRY_GRIP := 3.5
const WET_GRIP := 2.2     # 비 1 에서 바퀴 마찰. 제동거리가 늘고 급커브에서 미끄러진다
```

바퀴 생성의 `wheel.wheel_friction_slip = 3.5` 를 `wheel.wheel_friction_slip = DRY_GRIP` 로, 파일 끝에:

```gdscript
func set_wet(amount: float) -> void:
	var grip := lerpf(DRY_GRIP, WET_GRIP, clampf(amount, 0.0, 1.0))
	for wheel in find_children("*", "VehicleWheel3D", false, false):
		wheel.wheel_friction_slip = grip
```

`scripts/car_follow.gd`: `next_speed` 시그니처를 `phase: TrafficSignal.Phase, delta: float, cruise: float = CRUISE_MPS) -> float:` 로 바꾸고 첫 줄 `var target := CRUISE_MPS` 를 `var target := cruise` 로.

`scripts/traffic.gd`: 상수 블록 아래 필드에 `var cruise_scale := 1.0   # 비가 오면 순항 속도를 줄인다` 추가. `car.speed = CarFollow.next_speed(car.speed, gap, stop_m, phase, delta)` 를 `car.speed = CarFollow.next_speed(car.speed, gap, stop_m, phase, delta, CarFollow.CRUISE_MPS * cruise_scale)` 로.

`scripts/city.gd`: 필드 아래에

```gdscript
const DRY_ROUGHNESS := 0.95   # bake 의 road 재질 값(glb.py MATERIALS)
const WET_ROUGHNESS := 0.25

var _road_materials: Array[BaseMaterial3D] = []
```

`load_city` 의 청크 루프 안(`chunk_nodes.append(node)` 다음)에:

```gdscript
		for surface in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.resource_name == "road" \
					and not _road_materials.has(material):
				_road_materials.append(material)
```

함수:

```gdscript
func road_materials() -> Array[BaseMaterial3D]:
	return _road_materials

func set_wet(amount: float) -> void:
	"""젖은 도로는 거칠기를 낮춰 하늘과 불빛을 비춘다."""
	var roughness := lerpf(DRY_ROUGHNESS, WET_ROUGHNESS, clampf(amount, 0.0, 1.0))
	for material in _road_materials:
		material.roughness = roughness
```

주의: 재질 이름이 glb 가져오기에서 `"road"` 가 아니면(`print(material.resource_name)` 으로 확인) 실제 이름에 맞춘다. glb 가져온 재질은 모든 청크가 공유해서 목록이 1~2개가 정상이다.

`scripts/drive.gd`: 필드 `var weather: Weather` 추가. `_ready` 에서 `day_of_year = SunPath.today()` 다음에:

```gdscript
	weather = Weather.new()
	add_child(weather)
	weather.start(Weather.rain_from_args(OS.get_cmdline_user_args()))
```

카메라를 만든 뒤(`add_child(camera)` 다음) `weather.follow = camera.view` 는 view 가 `_ready` 에서 생기므로 `weather.follow = bus` 로 둔다(카메라가 버스 20 m 안이라 상자 40 m 가 덮는다).

`_update_environment` 를 바꾼다:

```gdscript
func _update_environment(delta: float) -> void:
	"""시각·날씨를 하늘과 조명에 넘긴다. 부품끼리는 서로 모른다."""
	var sun := SunPath.angles(day_of_year, day_clock.minutes)
	atmosphere.apply(sun.x, sun.y, weather.rain)
	clock_hud.update_time(day_clock.minutes, delta)
	bus.set_wet(weather.rain)
	city.set_wet(weather.rain)
	if traffic != null:
		traffic.cruise_scale = lerpf(1.0, 0.75, weather.rain)
```

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh test_weather test_car_follow test_traffic test_brake test_turn_radius drive_smoke; git checkout -q project.godot`. Expected: 모두 OK.

- [ ] **Step 5: 커밋**

```bash
git add scripts/weather.gd scripts/weather.gd.uid scripts/bus.gd scripts/car_follow.gd scripts/traffic.gd scripts/city.gd scripts/drive.gd tests/game/test_weather.gd tests/game/test_weather.tscn tests/game/run_game_tests.sh
git commit -m "feat: 비가 오다 그치고, 비가 오면 미끄럽고 교통이 느려진다"
```

---

### Task 5: 화면 빗물과 자동 와이퍼

**Files:**
- Create: `scripts/rain_screen.gd`, `shaders/rain_screen.gdshader`
- Modify: `scripts/drive.gd`
- Test: `tests/game/test_rain_screen.gd/.tscn`, `run_game_tests.sh`

**Interfaces:**
- Consumes: `Weather.rain`, `drive._update_environment`.
- Produces: `RainScreen` (CanvasLayer) — `wetness: float`, `wipe_x: float`, `set_rain(amount)`, `step(delta)`, `is_shown() -> bool`, 상수 `WIPE_INTERVAL_S := 3.0`, `WIPE_S := 0.4`, `WET_RATE := 0.25`, `DRY_RATE := 0.1`.

- [ ] **Step 1: 실패하는 테스트** — `tests/game/test_rain_screen.gd`:

```gdscript
extends TestCase
# 빗물 쌓임과 와이퍼. 셰이더 모양은 창 모드 캡처로 본다.

func _ready() -> void:
	var screen := RainScreen.new()
	add_child(screen)
	ok(not screen.is_shown(), "맑은데 빗물이 보인다")
	screen.set_rain(1.0)
	screen.step(2.0)
	equal_approx(screen.wetness, 2.0 * RainScreen.WET_RATE, 0.01, "빗물이 안 쌓인다")
	ok(screen.is_shown(), "비 오는데 빗물이 안 보인다")
	# 3초가 되면 와이퍼가 좌→우로 쓴다.
	screen.step(1.0 + RainScreen.WIPE_S / 2.0)
	ok(screen.wipe_x > 0.3 and screen.wipe_x < 0.7, "와이퍼가 중간에 없다 %.2f" % screen.wipe_x)
	screen.step(RainScreen.WIPE_S)
	ok(screen.wetness < 0.05, "닦은 뒤에도 젖어 있다 %.2f" % screen.wetness)
	equal_approx(screen.wipe_x, 0.0, 0.001, "닦은 뒤 와이퍼 위치")
	# 비가 그치면 마르고 오버레이가 꺼진다. 와이퍼도 안 돈다.
	screen.step(2.0)
	screen.set_rain(0.0)
	for i in 100:
		screen.step(0.5)
	ok(screen.wetness == 0.0, "비가 그쳤는데 안 마른다 %.2f" % screen.wetness)
	ok(not screen.is_shown(), "마른 뒤에도 오버레이가 켜져 있다")
	ok(screen.wipe_x == 0.0, "맑은데 와이퍼가 돈다")
	finish()
```

`.tscn`(`TestRainScreen`)과 목록 추가.

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_rain_screen; git checkout -q project.godot`. Expected: FAIL.

- [ ] **Step 3: 구현**

`shaders/rain_screen.gdshader`:

```glsl
shader_type canvas_item;
// 화면에 맺힌 빗방울. 칸마다 방울 하나를 두고 wetness 가 클수록 더 많은 칸에
// 방울이 생긴다. 방울 자리는 뒤 화면을 굴절시키고, 전체를 흐리게 한다.
// wipe_x 보다 왼쪽은 와이퍼가 막 쓸고 간 자리라 맑다.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float wetness = 0.0;
uniform float wipe_x = 0.0;
uniform float seed = 0.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float wet = wetness * step(wipe_x, uv.x);
	vec2 grid = uv * vec2(24.0, 14.0);
	vec2 cell = floor(grid) + seed;
	vec2 d = fract(grid) - (0.2 + 0.6 * hash2(cell));
	float radius = 0.12 + 0.25 * hash2(cell + 7.0).x;
	float present = step(1.0 - wet, hash2(cell + 3.0).y);
	float drop = present * smoothstep(radius, radius * 0.6, length(d));
	vec3 color = textureLod(screen_tex, uv - d * drop * 0.04, wet * 2.5).rgb;
	COLOR = vec4(color, 1.0);
}
```

`scripts/rain_screen.gd`:

```gdscript
extends CanvasLayer
class_name RainScreen
# 앞유리(추격 시점에서는 렌즈)에 맺힌 빗물. 비 세기만큼 쌓이고, 와이퍼가
# WIPE_INTERVAL_S 마다 좌→우로 쓸어 0 으로 돌린다. 닦기 직전이 가장 흐리다.
# 비가 그치면 천천히 마르고, 다 마르면 오버레이를 꺼서 화면 복사 비용을 없앤다.

const WET_RATE := 0.25       # 비 1 에서 초당 쌓이는 양. 4초면 가득
const DRY_RATE := 0.1
const WIPE_INTERVAL_S := 3.0
const WIPE_S := 0.4
const SHADER := preload("res://shaders/rain_screen.gdshader")

var wetness := 0.0
var wipe_x := 0.0

var _rain := 0.0
var _since_wipe := 0.0
var _rect: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
	layer = 5   # HUD(10) 아래. 글자는 빗물에 안 가려진다
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)

func set_rain(amount: float) -> void:
	_rain = clampf(amount, 0.0, 1.0)

func is_shown() -> bool:
	return wetness > 0.001

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	if _rain > 0.01:
		wetness = minf(1.0, wetness + _rain * WET_RATE * delta)
		_since_wipe += delta
		if _since_wipe >= WIPE_INTERVAL_S:
			wipe_x = clampf((_since_wipe - WIPE_INTERVAL_S) / WIPE_S, 0.0, 1.0)
			if _since_wipe >= WIPE_INTERVAL_S + WIPE_S:
				wetness = 0.0
				wipe_x = 0.0
				_since_wipe = 0.0
				if _material != null:
					_material.set_shader_parameter("seed", randf() * 100.0)
	else:
		wetness = maxf(0.0, wetness - DRY_RATE * delta)
		wipe_x = 0.0
		_since_wipe = 0.0
	if _rect != null:
		_rect.visible = is_shown()
		_material.set_shader_parameter("wetness", wetness)
		_material.set_shader_parameter("wipe_x", wipe_x)
```

`scripts/drive.gd`: 필드 `var rain_screen: RainScreen`. `_ready` 의 `clock_hud` 생성 다음에:

```gdscript
	rain_screen = RainScreen.new()
	add_child(rain_screen)
```

`_update_environment` 끝에 `rain_screen.set_rain(weather.rain)`.

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh test_rain_screen drive_smoke; git checkout -q project.godot`. Expected: OK.

- [ ] **Step 5: 커밋**

```bash
git add scripts/rain_screen.gd scripts/rain_screen.gd.uid shaders/rain_screen.gdshader scripts/drive.gd tests/game/test_rain_screen.gd tests/game/test_rain_screen.tscn tests/game/run_game_tests.sh
git commit -m "feat: 비가 오면 화면에 빗물이 맺히고 와이퍼가 닦는다"
```

---

### Task 6: 가로등 표시와 밤 조명

**Files:**
- Create: `scripts/street_lights.gd`
- Modify: `scripts/drive.gd`
- Test: `tests/game/test_street_lights.gd/.tscn`, `run_game_tests.sh`

**Interfaces:**
- Consumes: `RouteData.streetlights` (Task 1), `drive._update_environment`.
- Produces: `StreetLights` (Node3D) — `target: Node3D`, `build(entries: Array)`, `set_night(amount)`, `update_pool(from: Vector3)`, `lit_positions() -> Array[Vector3]`, `static night_amount(elevation_deg) -> float`, 상수 `POOL := 12`, `RANGE_M := 18.0`, `POLE_HEIGHT_M := 8.0`, `ARM_M := 0.8`.

- [ ] **Step 1: 실패하는 테스트** — `tests/game/test_street_lights.gd`:

```gdscript
extends TestCase
# 가로등 풀. 밤에만, 대상에서 가장 가까운 자리만 실제 빛을 낸다.

func _ready() -> void:
	equal_approx(StreetLights.night_amount(20.0), 0.0, 0.001, "한낮이 밤이다")
	equal_approx(StreetLights.night_amount(-10.0), 1.0, 0.001, "한밤이 밤이 아니다")

	var empty := StreetLights.new()
	add_child(empty)
	empty.build([])
	empty.set_night(1.0)
	empty.update_pool(Vector3.ZERO)
	ok(empty.lit_positions().is_empty(), "가로등이 없는데 불이 켜졌다")

	var lights := StreetLights.new()
	add_child(lights)
	var entries := []
	for i in 30:
		entries.append([i * 30.0, 13.0, 0.0])
	lights.build(entries)
	lights.set_night(1.0)
	lights.update_pool(Vector3(300.0, 0.0, 0.0))
	var lit := lights.lit_positions()
	ok(lit.size() == StreetLights.POOL, "켜진 불이 %d 개" % lit.size())
	var nearest := INF
	for spot in lit:
		nearest = minf(nearest, Vector2(spot.x - 300.0, spot.z).length())
	ok(nearest < 15.0, "가장 가까운 가로등이 안 켜졌다 %.1f" % nearest)
	for spot in lit:
		ok(absf(spot.x - 300.0) <= 6 * 30.0 + 1.0, "먼 가로등이 켜졌다 %s" % spot)
	lights.set_night(0.0)
	ok(lights.lit_positions().is_empty(), "낮인데 불이 켜져 있다")
	finish()
```

`.tscn`(`TestStreetLights`)과 목록 추가.

- [ ] **Step 2: 실패 확인** — `tests/game/run_game_tests.sh test_street_lights; git checkout -q project.godot`. Expected: FAIL.

- [ ] **Step 3: 구현** — `scripts/street_lights.gd`:

```gdscript
extends Node3D
class_name StreetLights
# 가로등. 기둥과 전등 머리는 MultiMesh 두 개로 한 번에 그린다(노선당 약
# 1,000 개). 실제 빛(OmniLight3D)은 POOL 개만 두고 target 에서 가까운 자리로
# 옮겨 다닌다 — 수천 개를 다 켜면 모바일이 버티지 못한다.

const POOL := 12
const RANGE_M := 18.0
const POLE_HEIGHT_M := 8.0
const ARM_M := 0.8              # 기둥에서 도로 쪽으로 전등 머리가 나온 거리
const CURB_Y := 0.15            # 인도 윗면
const UPDATE_S := 0.5
const LIGHT_COLOR := Color(1.0, 0.85, 0.6)
const LIGHT_ENERGY := 2.0

var target: Node3D

var _heads: PackedVector3Array = []
var _pool: Array[OmniLight3D] = []
var _head_material: StandardMaterial3D
var _night := 0.0
var _since_update := UPDATE_S

static func night_amount(elevation_deg: float) -> float:
	"""고도 +2° 에서 켜지기 시작해 -4° 에서 다 켜진다."""
	return clampf((2.0 - elevation_deg) / 6.0, 0.0, 1.0)

func build(entries: Array) -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.12
	pole_mesh.height = POLE_HEIGHT_M
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.35, 0.36, 0.38)
	pole_mesh.material = pole_material
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.35, 0.15, 1.0)
	_head_material = StandardMaterial3D.new()
	_head_material.albedo_color = Color(0.3, 0.3, 0.3)
	_head_material.emission_enabled = true
	_head_material.emission = LIGHT_COLOR
	_head_material.emission_energy_multiplier = 0.0
	head_mesh.material = _head_material

	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = pole_mesh
	poles.instance_count = entries.size()
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	heads.mesh = head_mesh
	heads.instance_count = entries.size()
	for index in entries.size():
		var entry: Array = entries[index]
		var basis := Basis(Vector3.UP, float(entry[2]))
		var base := Vector3(float(entry[0]), CURB_Y, float(entry[1]))
		poles.set_instance_transform(index,
			Transform3D(basis, base + Vector3.UP * POLE_HEIGHT_M / 2.0))
		# 머리는 기둥 꼭대기에서 도로 쪽(-Z)으로 ARM_M 나온다.
		var head := base + Vector3.UP * POLE_HEIGHT_M + basis * Vector3(0.0, 0.0, -ARM_M)
		heads.set_instance_transform(index, Transform3D(basis, head))
		_heads.append(head)
	for multimesh in [poles, heads]:
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		add_child(instance)

	for i in POOL:
		var light := OmniLight3D.new()
		light.omni_range = RANGE_M
		light.light_color = LIGHT_COLOR
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_pool.append(light)

func set_night(amount: float) -> void:
	_night = clampf(amount, 0.0, 1.0)
	if _head_material != null:
		_head_material.emission_energy_multiplier = 4.0 * _night
	if _night <= 0.0:
		for light in _pool:
			light.visible = false

func _process(delta: float) -> void:
	_since_update += delta
	if target == null or _since_update < UPDATE_S:
		return
	_since_update = 0.0
	update_pool(target.global_position)

func update_pool(from: Vector3) -> void:
	if _night <= 0.0 or _heads.is_empty():
		for light in _pool:
			light.visible = false
		return
	# ponytail: 매번 전체 정렬. 1,300 개를 0.5초마다라 무시할 만하다. 느려지면 격자 칸.
	var order := range(_heads.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return _heads[a].distance_squared_to(from) < _heads[b].distance_squared_to(from))
	for i in _pool.size():
		var light := _pool[i]
		light.visible = i < order.size()
		if light.visible:
			light.position = _heads[order[i]] + Vector3.DOWN * 0.3
			light.light_energy = LIGHT_ENERGY * _night

func lit_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for light in _pool:
		if light.visible:
			out.append(light.position)
	return out
```

`scripts/drive.gd`: 필드 `var street_lights: StreetLights`. `_ready` 에서 `nav` 를 붙인 다음(`add_child(nav)` 다음)에:

```gdscript
	street_lights = StreetLights.new()
	street_lights.build(data.streetlights)
	add_child(street_lights)
```

버스를 만든 뒤(`_place_at_start()` 다음) `street_lights.target = bus`. `_update_environment` 에서 `atmosphere.apply(...)` 다음 줄에 `street_lights.set_night(StreetLights.night_amount(sun.x))`.

- [ ] **Step 4: 통과 확인** — `tests/game/run_game_tests.sh; git checkout -q project.godot` (전체). Expected: 모든 씬 OK. 이어서 `.venv/bin/python -m unittest discover -s tests -t .` OK.

- [ ] **Step 5: 커밋**

```bash
git add scripts/street_lights.gd scripts/street_lights.gd.uid scripts/drive.gd tests/game/test_street_lights.gd tests/game/test_street_lights.tscn tests/game/run_game_tests.sh
git commit -m "feat: 가로등을 세우고 밤에는 버스 근처 가로등이 빛난다"
```

---

### Task 7: 창 모드 확인과 성능

**Files:**
- Modify(필요할 때만): `scripts/atmosphere.gd` 상수(색, 그림자 거리), `scripts/street_lights.gd` 상수, `shaders/rain_screen.gdshader`
- 임시(커밋 안 함): 스크래치패드의 캡처 씬

- [ ] **Step 1: 캡처** — 샌드박스 밖(`dangerouslyDisableSandbox`)에서, 게임 메인 씬 대신 drive 씬을 직접 띄워 약 5초 뒤 화면을 저장하는 임시 스크립트로 네 장면을 찍는다: `--route=seoul-100 --time=13:00 --rain=0`, `--time=` 을 오늘 일몰 시각 근처(SunPath 로 고도 ≈ 2° 되는 분을 구해 넣는다), `--time=22:00 --rain=0`, `--time=22:00 --rain=1`. 임시 스크립트는 `tests/game/` 에 두었다면 끝나고 지운다.

확인할 것: 한낮 그림자 방향이 해 반대쪽, 노을 지평선이 주황, 밤에 가로등 머리가 빛나고 버스 근처 도로가 밝음, 비 오는 밤에 빗줄기·화면 빗물·젖은 노면 반사. 어긋나면 해당 상수를 고치고 다시 찍는다.

- [ ] **Step 2: fps** — `godot res://tests/game/measure_fps.tscn -- --route=seoul-100 --time=13:00 --rain=0` 와 `... --time=22:00 --rain=1` (샌드박스 밖). `measure_fps` 가 drive 를 쓰므로 인자가 그대로 넘어간다. 기준 평균 60 / 최저 55. 못 미치면 `Weather.DROP_COUNT` 를 줄이거나 `StreetLights.POOL` 을 8 로 내린다.

- [ ] **Step 3: 전체 테스트** — `tests/game/run_game_tests.sh; git checkout -q project.godot` 와 파이썬 테스트, `tests/bake/run_verify.sh seoul-seodaemun03`.

- [ ] **Step 4: 조정이 있었다면 커밋**

```bash
git add <고친 파일들>
git commit -m "fix: 창 모드 확인 후 하늘·가로등·빗물 값을 맞춘다"
```
