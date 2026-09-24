# 정류장·승객 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 정류장에 대기 승객을 세우고, 정차하면 승하차에 시간이 들게 해서 이 게임의 핵심 루프 앞 절반을 완성한다.

**Architecture:** 4번 서브프로젝트(신호·위반)와 같은 분리를 따른다 — 승객 규칙은 노드가 아닌 순수 객체(`PassengerPlan`), 보이는 것은 `StopField`, 판정은 `BoardingWatch`, 표시는 `BoardingHud`. 베이크는 건드리지 않는다. 정차 목표점은 OSM 정류장 노드가 아니라 노선 폴리라인 위의 `progress_m` 지점이다.

**Tech Stack:** Godot 4.7.2 (GDScript), 헤드리스 테스트 러너 `tests/game/run_game_tests.sh`

**Spec:** `docs/superpowers/specs/2026-09-24-stops-passengers-design.md`

## Global Constraints

- Godot 실행 파일은 `/opt/homebrew/bin/godot`. 스크립트를 새로 만들거나 `.tscn` 을 추가하면 먼저 `/opt/homebrew/bin/godot --headless --import` 를 돌려야 테스트 러너가 찾는다.
- **Godot 은 GDScript 파싱 오류가 나도 종료 코드 0 을 낸다.** 테스트 통과 판정은 오직 출력에 `TEST_OK` 가 찍히는 것으로 한다. 러너가 이미 그렇게 한다.
- 좌표계: x=동, z=**남**, y=위. 지형은 평지라 y=0. 원점은 노선 bbox 중심.
- 고도트의 정면은 로컬 **-Z** 다. 버스 전방은 `-bus.global_transform.basis.z`.
- **`add_child()` 로 갓 붙인 노드는 그 프레임의 `physics_frame` 신호가 뜬 뒤에야 첫 `_physics_process` 를 받는다.** 테스트에서 위치를 잡으려면 `await get_tree().physics_frame` 를 **두 번** 해야 한다.
- **`build()` 는 `add_child()` 전에 불린다.** 그 안에서 `global_position` 이나 `look_at` 을 쓰면 "Node not inside tree" 로 죽는다. `Transform3D` 를 직접 짜거나 `_ready()` 로 미룬다.
- **코드로 붙인 노드는 이름이 `@Camera3D@7` 같은 꼴이다.** `get_node("Camera3D")` 로 못 찾는다. 필요하면 참조를 변수로 내놓는다(`ChaseCamera.view` 가 그 예다).
- `for x in [1.0, -1.0]` 는 Variant 를 낸다. `var y := expr * x` 가 타입 추론 실패로 파싱 에러가 난다. `for i in 2` + 삼항으로 쓴다.
- 코드 주석과 사용자에게 보이는 문자열은 한국어.
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` 를 붙인다.
- `git add -A` / `git add .` 금지. 파일을 이름으로 하나씩 추가한다.

### 스펙이 정한 상수 (그대로 쓸 것)

```
정원                CAPACITY = 60
정차 반경           STOP_RADIUS_M = 15.0
정차 속도 문턱      STOP_SPEED_MPS = 0.5
문 개폐             DOOR_S = 3.0
1인 탑승            BOARD_S = 1.2
1인 하차            ALIGHT_S = 0.8
보행 속도           WALK_SPEED_MPS = 1.2
대기 인원 뽑기      maxi(0, randi_range(-3, 8))
dwell = DOOR_S + walk_s + maxf(board_n * BOARD_S, alight_n * ALIGHT_S)
walk_s = (버스 정지 위치 ~ 정차 목표점 거리) / WALK_SPEED_MPS, 대기 0명이면 0
```

### 스펙이 정한 판정 규칙

- **서야 하는 정류장만 센다.** 대기 인원도 하차 예정도 없는 정류장은 그냥 지나가는 것이 정상이다. 놓침(`stop_missed`)으로 세지 않는다. 종점은 언제나 서야 하는 정류장이다.
- **되돌아가서 다시 서면 승하차가 진행된다.** 돌아가는 데 드는 시간이 이미 벌이다. 다만 놓침은 정류장당 한 번만 센다.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `scripts/passenger_plan.gd` (신규) | 대기 인원 생성, 목적지 배정, 정원 처리, dwell 계산. `RefCounted` — 트리 밖 순수 로직 |
| `scripts/stop_field.gd` (신규) | 정류장 표지판과 대기 승객 캡슐. 거리 컬링. `Node3D` |
| `scripts/boarding_watch.gd` (신규) | 정차 판정과 승하차 타이머. `PassengerPlan` 소유. `Node` |
| `scripts/boarding_hud.gd` (신규) | 상단 중앙 표시. `CanvasLayer` |
| `scripts/route_data.gd` (수정) | 정차 목표점(`stop_targets`) 계산 추가 |
| `scripts/drive.gd` (수정) | 네 노드 배선, 승하차 중 조작 차단, 리스폰 차단 |
| `tests/game/test_passenger_plan.{gd,tscn}` (신규) | `PassengerPlan` 순수 로직 |
| `tests/game/test_boarding.{gd,tscn}` (신규) | `BoardingWatch` 판정 |
| `tests/game/test_route_data.gd` (수정) | `stop_targets` 계약 |
| `tests/game/drive_smoke.gd` (수정) | 배선과 `StopField` 컬링 |
| `tests/game/run_game_tests.sh` (수정) | 새 씬 둘 등록 |
| `README.md` (수정) | 조작·문서 목록 |

---

## Task 1: 정차 목표점

**Files:**
- Modify: `scripts/route_data.gd`
- Test: `tests/game/test_route_data.gd`

**Interfaces:**
- Consumes: 없음(첫 태스크)
- Produces: `RouteData.stop_targets: PackedVector3Array` — `stops[i]` 와 같은 순서, 노선 폴리라인 위의 `progress_m` 지점. `RouteData.point_at_progress(distance_m: float) -> Vector3`

**배경:** OSM `bus_stop` 노드는 도로 옆 인도에 있다. seoul-100 의 114개를 노선 중심선까지 재면 중앙값 6.9 m, 최대 28.6 m 다. 걸어오는 시간을 노드까지 재면 차선에 완벽히 세워도 매번 페널티가 붙는다. 그래서 정차 목표점은 노선 위의 점이다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_route_data.gd` 의 신호 계약 검사 마지막 줄(`"신호 카메라 필드가 없다: %s"` 로 끝나는 `ok(...)`) **다음**에 붙인다:

```gdscript

	# 정차 목표점은 노선 위의 점이다. OSM 정류장 노드는 인도에 있어서
	# 그대로 쓰면 차선에 제대로 세워도 걸어오는 시간이 붙는다.
	ok(data.stop_targets.size() == data.stops.size(),
		"정차 목표점이 %d 개인데 정류장은 %d 곳이다"
		% [data.stop_targets.size(), data.stops.size()])
	var worst := 0.0
	for index in range(data.stops.size()):
		var target: Vector3 = data.stop_targets[index]
		var nearest: Vector3 = data.route[data.nearest_index(target)]
		worst = maxf(worst, target.distance_to(nearest))
	# 경로점 간격이 수 m 라 목표점은 항상 어느 경로점 바로 곁에 있다.
	ok(worst < 30.0, "정차 목표점이 노선에서 %.1f m 떨어졌다" % worst)

	# progress_m 이 노선 길이를 넘으면 마지막 점으로 자른다.
	var last: Vector3 = data.route[data.route.size() - 1]
	ok(data.point_at_progress(1.0e9).distance_to(last) < 0.01,
		"노선 끝을 넘는 진행거리를 자르지 않았다")
	ok(data.point_at_progress(-5.0).distance_to(data.route[0]) < 0.01,
		"음수 진행거리를 0 으로 자르지 않았다")
```

- [ ] **Step 2: 실패를 확인한다**

```bash
/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1
tests/game/run_game_tests.sh test_route_data
```

기대: `test_route_data: FAIL`. 출력에 `Invalid access to property or key 'stop_targets'` 가 섞여 나온다.

- [ ] **Step 3: 최소 구현**

`scripts/route_data.gd` 에서 `var signals: Array = []` 다음 줄에 추가:

```gdscript
# 정차 목표점. stops 와 같은 순서다. 자세한 이유는 point_at_progress 를 보라.
var stop_targets: PackedVector3Array = []
```

`load_route` 안에서 `data.signals = parsed.get("signals", [])` 다음, `return data` 앞에 추가:

```gdscript
	data._build_stop_targets()
```

파일 끝(`nearest_index` 다음)에 추가:

```gdscript
func point_at_progress(distance_m: float) -> Vector3:
	"""노선 시작점에서 distance_m 만큼 간 지점.

	정류장 좌표(x, z)는 OSM bus_stop 노드, 곧 도로 옆 인도다. 버스가 차선에
	제대로 서도 중앙값 6.9 m, 최대 28.6 m 떨어져 있어 그대로 쓰면 피할 수
	없는 페널티가 된다. 정차 목표점은 이 함수가 내는 노선 위의 점이다.
	"""
	if route.size() == 0:
		return Vector3.ZERO
	if route.size() == 1 or distance_m <= 0.0:
		return route[0]
	var remaining := distance_m
	for index in range(1, route.size()):
		var span := route[index - 1].distance_to(route[index])
		if remaining <= span:
			var ratio := remaining / maxf(span, 0.001)
			return route[index - 1].lerp(route[index], ratio)
		remaining -= span
	# progress_m 이 노선 길이를 넘었다. 종점으로 자른다.
	return route[route.size() - 1]

func _build_stop_targets() -> void:
	stop_targets = PackedVector3Array()
	for stop in stops:
		stop_targets.append(point_at_progress(float(stop.get("progress_m", 0.0))))
```

- [ ] **Step 4: 통과를 확인한다**

```bash
tests/game/run_game_tests.sh test_route_data
```

기대: `test_route_data: OK`

- [ ] **Step 5: 커밋**

```bash
git add scripts/route_data.gd tests/game/test_route_data.gd
git commit -m "feat: RouteData 가 정차 목표점을 낸다

정류장 좌표는 도로 옆 인도의 OSM 노드다. 중앙값 6.9 m, 최대 28.6 m
떨어져 있어 걸어오는 시간을 그대로 재면 차선에 제대로 세워도 피할 수
없는 페널티가 붙는다. progress_m 으로 노선 위의 점을 뽑아 쓴다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 2: PassengerPlan — 승객 규칙

**Files:**
- Create: `scripts/passenger_plan.gd`
- Create: `tests/game/test_passenger_plan.gd`, `tests/game/test_passenger_plan.tscn`
- Modify: `tests/game/run_game_tests.sh:26`

**Interfaces:**
- Consumes: 없음
- Produces:
  - 상수 `PassengerPlan.CAPACITY := 60`, `DOOR_S := 3.0`, `BOARD_S := 1.2`, `ALIGHT_S := 0.8`, `WALK_SPEED_MPS := 1.2`
  - `build(stop_count: int) -> void`
  - `waiting_at(index: int) -> int`
  - `needs_stop(index: int) -> bool` — 대기 인원이나 하차 예정이 있거나 종점이다
  - `serve(index: int, walk_distance_m: float) -> Dictionary` — `{"boarded": int, "alighted": int, "dwell": float}`. 해당 정류장의 승하차를 확정하고 상태를 갱신한다
  - `dwell_for(board_n: int, alight_n: int, walk_distance_m: float, waiting_n: int) -> float` — 순수 계산
  - `force_waiting(index: int, count: int) -> void` — 테스트가 난수를 고정할 때만 쓴다
  - `var onboard: int`, `var left_behind: int`

**설계 메모:** 승객 객체는 만들지 않는다. `_destined[i]` 에 "i번 정류장에서 내릴 사람 수"만 센다. 목적지는 태울 때 뽑는다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_passenger_plan.gd`:

```gdscript
extends TestCase
# PassengerPlan 순수 로직. 노드가 아니라 트리도 대기도 필요 없다.

func _ready() -> void:
	_test_waiting_range()
	_test_destinations_are_ahead()
	_test_capacity_leaves_people()
	_test_terminus_empties_bus()
	_test_needs_stop()
	_test_dwell_formula()
	finish()

func _test_waiting_range() -> void:
	var plan := PassengerPlan.new()
	plan.build(200)
	var zero_count := 0
	for index in 200:
		var waiting := plan.waiting_at(index)
		ok(waiting >= 0 and waiting <= 8,
			"%d 번 정류장 대기 인원이 %d 명이다" % [index, waiting])
		if waiting == 0:
			zero_count += 1
	# maxi(0, randi_range(-3, 8)) 이라 0 명이 4/12 다. 200 표본이면
	# 40~95 사이에 들어온다 — 균등 분포(22 명)와 확실히 갈린다.
	ok(zero_count > 40 and zero_count < 95,
		"200 곳 중 빈 정류장이 %d 곳이다" % zero_count)

func _test_destinations_are_ahead() -> void:
	var plan := PassengerPlan.new()
	plan.build(10)
	plan.force_waiting(0, 6)
	# 0 번에서 태운 사람은 1~9 번 어딘가에서 내린다. 끝까지 훑으며 하차
	# 인원을 합하면 태운 만큼이어야 한다.
	var boarded := int(plan.serve(0, 0.0)["boarded"])
	ok(boarded == 6, "6 명이 기다렸는데 %d 명만 탔다" % boarded)
	var alighted_total := 0
	for index in range(1, 10):
		alighted_total += int(plan.serve(index, 0.0)["alighted"])
	ok(alighted_total >= boarded,
		"0 번에서 %d 명 태웠는데 뒤에서 %d 명만 내렸다"
		% [boarded, alighted_total])
	ok(plan.onboard == 0, "종점까지 훑었는데 %d 명이 남았다" % plan.onboard)

func _test_capacity_leaves_people() -> void:
	var plan := PassengerPlan.new()
	plan.build(40)
	# 앞쪽 30 곳에 8 명씩 세운다. 목적지가 뒤쪽이라 앞에서는 거의 내리지
	# 않아 정원 60 명이 반드시 찬다.
	for index in 30:
		plan.force_waiting(index, 8)
	for index in 30:
		plan.serve(index, 0.0)
	ok(plan.onboard <= PassengerPlan.CAPACITY,
		"탑승 인원이 정원을 넘었다: %d" % plan.onboard)
	ok(plan.left_behind > 0,
		"정원이 찼는데 못 탄 사람이 %d 명이다" % plan.left_behind)

func _test_terminus_empties_bus() -> void:
	var plan := PassengerPlan.new()
	plan.build(5)
	for index in 4:
		plan.force_waiting(index, 3)
		plan.serve(index, 0.0)
	var remaining := plan.onboard
	var last := plan.serve(4, 0.0)
	ok(plan.onboard == 0, "종점 하차 뒤에 %d 명이 남았다" % plan.onboard)
	ok(int(last["alighted"]) == remaining,
		"종점에서 %d 명이 남아 있었는데 %d 명만 내렸다"
		% [remaining, int(last["alighted"])])
	ok(int(last["boarded"]) == 0, "종점에서 사람이 탔다")

func _test_needs_stop() -> void:
	var plan := PassengerPlan.new()
	plan.build(4)
	for index in 4:
		plan.force_waiting(index, 0)
	ok(not plan.needs_stop(1), "아무도 없는 정류장에 서야 한다고 한다")
	ok(plan.needs_stop(3), "종점에 안 서도 된다고 한다")
	plan.force_waiting(1, 2)
	ok(plan.needs_stop(1), "대기 인원이 있는데 안 서도 된다고 한다")
	# 1 번에서 태우면 목적지는 2 나 3 이다. 둘 중 하나는 서야 한다.
	plan.serve(1, 0.0)
	ok(plan.needs_stop(2) or plan.needs_stop(3),
		"태운 사람이 내릴 정류장이 없다")

func _test_dwell_formula() -> void:
	var plan := PassengerPlan.new()
	# 아무도 없으면 문 개폐뿐이다.
	equal_approx(plan.dwell_for(0, 0, 0.0, 0), PassengerPlan.DOOR_S, 0.001,
		"빈 정류장 정차 시간")
	# 탑승과 하차는 동시다. 합이 아니라 max 다.
	equal_approx(plan.dwell_for(5, 5, 0.0, 5),
		PassengerPlan.DOOR_S + 5.0 * PassengerPlan.BOARD_S, 0.001,
		"탑승·하차 동시 진행")
	# 걸어오는 시간은 대기 인원이 있을 때만 붙는다.
	equal_approx(plan.dwell_for(0, 3, 12.0, 0),
		PassengerPlan.DOOR_S + 3.0 * PassengerPlan.ALIGHT_S, 0.001,
		"대기 0 명인데 걸어오는 시간이 붙었다")
	equal_approx(plan.dwell_for(3, 0, 12.0, 3),
		PassengerPlan.DOOR_S + 12.0 / PassengerPlan.WALK_SPEED_MPS
		+ 3.0 * PassengerPlan.BOARD_S, 0.001,
		"걸어오는 시간")
```

`tests/game/test_passenger_plan.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_passenger_plan.gd" id="1"]

[node name="TestPassengerPlan" type="Node3D"]
script = ExtResource("1")
```

`tests/game/run_game_tests.sh:26` 의 `scenes=(...)` 에서 `test_camera_view` 앞에 `test_passenger_plan` 을 넣는다:

```bash
	scenes=(test_route_data test_city test_input test_turn_radius test_nav_line test_traffic_signal test_violation test_passenger_plan test_camera_view drive_smoke)
```

- [ ] **Step 2: 실패를 확인한다**

```bash
/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1
tests/game/run_game_tests.sh test_passenger_plan
```

기대: `test_passenger_plan: FAIL`. `Identifier "PassengerPlan" not declared` 가 나온다.

- [ ] **Step 3: 최소 구현**

`scripts/passenger_plan.gd`:

```gdscript
extends RefCounted
class_name PassengerPlan
# 승객 규칙 전부. 노드가 아니라서 테스트가 트리 없이 바로 돌린다.
#
# 승객 객체는 만들지 않는다. _destined[i] 에 "i 번 정류장에서 내릴 사람 수"만
# 센다. 60 명이 각자 객체일 이유가 없다.

const CAPACITY := 60              # 서울 저상버스 입석 포함
const DOOR_S := 3.0               # 문 개폐. 승객이 0 명이어도 든다
const BOARD_S := 1.2              # 1 인 탑승. 교통카드 찍는 시간
const ALIGHT_S := 0.8             # 1 인 하차
const WALK_SPEED_MPS := 1.2

var onboard := 0
var left_behind := 0

var _waiting: PackedInt32Array = []
var _destined: PackedInt32Array = []
var _stop_count := 0

func build(stop_count: int) -> void:
	"""정류장마다 대기 인원을 뽑는다. 매 플레이 새로 뽑는다."""
	_stop_count = stop_count
	_waiting = PackedInt32Array()
	_destined = PackedInt32Array()
	for _index in stop_count:
		# 균등 분포로 뽑으면 정류장 114 곳 중 101 곳에 사람이 있어 계속 선다.
		# 이 식은 0 명이 1/3, 평균 2.9 명이다.
		_waiting.append(maxi(0, randi_range(-3, 8)))
		_destined.append(0)

func waiting_at(index: int) -> int:
	if index < 0 or index >= _waiting.size():
		return 0
	return _waiting[index]

func force_waiting(index: int, count: int) -> void:
	"""대기 인원을 정한다. 난수를 고정해야 하는 테스트 전용이다."""
	if index < 0 or index >= _waiting.size():
		return
	_waiting[index] = count

func needs_stop(index: int) -> bool:
	"""서야 하는 정류장인가. 탈 사람도 내릴 사람도 없으면 지나가는 게 맞다."""
	if index < 0 or index >= _stop_count:
		return false
	if index == _stop_count - 1:
		# 종점에서는 남은 전원이 내린다. 빈 버스여도 도착은 해야 한다.
		return true
	return _waiting[index] > 0 or _destined[index] > 0

func dwell_for(board_n: int, alight_n: int, walk_distance_m: float,
		waiting_n: int) -> float:
	"""정차 시간. 탑승과 하차는 앞문·뒷문으로 동시에 이뤄진다."""
	var walk_s := 0.0
	if waiting_n > 0:
		walk_s = walk_distance_m / WALK_SPEED_MPS
	return DOOR_S + walk_s + maxf(board_n * BOARD_S, alight_n * ALIGHT_S)

func serve(index: int, walk_distance_m: float) -> Dictionary:
	"""index 번 정류장의 승하차를 확정한다. 상태가 여기서 바뀐다."""
	if index < 0 or index >= _stop_count:
		return {"boarded": 0, "alighted": 0, "dwell": DOOR_S}

	var is_terminus := index == _stop_count - 1
	var alighted := onboard if is_terminus else _destined[index]
	onboard -= alighted
	_destined[index] = 0

	var waiting := _waiting[index]
	# 종점에서는 아무도 타지 않는다.
	var boarded := 0 if is_terminus else mini(waiting, CAPACITY - onboard)
	left_behind += waiting - boarded
	_waiting[index] = 0
	onboard += boarded
	for _rider in boarded:
		_destined[_pick_destination(index)] += 1

	return {"boarded": boarded, "alighted": alighted,
		"dwell": dwell_for(boarded, alighted, walk_distance_m, waiting)}

func _pick_destination(from_index: int) -> int:
	"""뒤쪽에 남은 정류장 중 균등 랜덤. 뒤가 없으면 종점이다."""
	if from_index >= _stop_count - 1:
		return _stop_count - 1
	return randi_range(from_index + 1, _stop_count - 1)
```

- [ ] **Step 4: 통과를 확인한다**

```bash
tests/game/run_game_tests.sh test_passenger_plan
```

기대: `test_passenger_plan: OK`

- [ ] **Step 5: 커밋**

```bash
git add scripts/passenger_plan.gd tests/game/test_passenger_plan.gd \
  tests/game/test_passenger_plan.gd.uid tests/game/test_passenger_plan.tscn \
  tests/game/run_game_tests.sh
git commit -m "feat: PassengerPlan — 대기 인원, 목적지, 정원, 정차 시간

승객 객체를 만들지 않는다. 정류장별 하차 예정 인원만 센다. 목적지는
태울 때 뒤쪽 남은 정류장 중 균등 랜덤으로 뽑아, 탑승 인원이 노선
내내 오르내리는 것과 정원 초과가 공짜로 딸려 온다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 3: BoardingWatch — 정차 판정과 타이머

**Files:**
- Create: `scripts/boarding_watch.gd`
- Create: `tests/game/test_boarding.gd`, `tests/game/test_boarding.tscn`
- Modify: `tests/game/run_game_tests.sh:26`

**Interfaces:**
- Consumes: `PassengerPlan.new()`, `plan.build(stop_count)`, `plan.waiting_at(index)`, `plan.needs_stop(index)`, `plan.force_waiting(index, count)`, `plan.serve(index, walk_distance_m) -> {"boarded","alighted","dwell"}`, `plan.onboard`, `plan.left_behind`
- Produces:
  - 상수 `BoardingWatch.STOP_RADIUS_M := 15.0`, `STOP_SPEED_MPS := 0.5`
  - `build(targets: PackedVector3Array) -> void`
  - `var bus: Node3D`, `var plan: PassengerPlan`
  - `var served := 0`, `var missed := 0`, `var is_boarding := false`, `var boarding_left := 0.0`, `var boarding_total := 0.0`, `var next_index := 0`
  - 읽기 전용 `onboard: int`, `left_behind: int` (`plan` 에 위임)
  - `distance_to_next() -> float`, `stop_name_at(index: int, stops: Array) -> String`
  - `signal boarding_started(stop_index: int)`
  - `signal boarding_finished(boarded: int, alighted: int)`
  - `signal stop_missed(stop_index: int)`

**설계 메모 1 — 속도 측정:** 테스트는 버스 대신 빈 `Node3D` 를 옮긴다. `Node3D` 에는 `linear_velocity` 가 없으므로 **직전 프레임 위치와의 차이**로 속도를 잰다. 실제 `Bus`(VehicleBody3D)에서도 같은 값이 나온다.

**설계 메모 2 — 진행 판정:** `ViolationWatch` 의 격자 인덱스는 쓰지 않는다. 정류장은 노선 순서대로 지나가므로 **`next_index` 앞뒤의 작은 창**만 보면 된다. 창 안에서 가장 가까운 정류장이 `next_index` 보다 뒤라면 그 사이 정류장들은 지나간 것이다. 반경 이탈로 판정하지 않는 이유: 반경 15 m 밖으로 크게 우회해 지나가면 반경에 아예 들어오지 않아 영영 놓침이 안 잡힌다.

창을 `next_index` 뒤쪽 `BACK_WINDOW` 개까지 늘려 두면 되돌아가 다시 서는 것이 그대로 된다. 처리 여부는 `_done` 집합이 쥐고 있어 `next_index` 가 어디를 가리키든 이중 처리가 없다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_boarding.gd`:

```gdscript
extends TestCase
# 정차 판정. 버스 대신 빈 Node3D 를 옮겨서 판정만 본다 — 물리를 끼우면
# 테스트가 느리고 불안정해진다.

var _started: Array = []
var _finished: Array = []
var _missed: Array = []

func _ready() -> void:
	await _test_far_away_does_not_start()
	await _test_moving_does_not_start()
	await _test_stopped_starts()
	await _test_nearest_of_overlapping()
	await _test_passing_by_is_missed()
	await _test_empty_stop_is_not_missed()
	await _test_timer_finishes_and_boards()
	finish()

# 정류장 네 곳을 30 m 간격으로 +X 축에 놓는다. 마지막이 종점이다.
func _targets() -> PackedVector3Array:
	return PackedVector3Array([Vector3.ZERO, Vector3(30.0, 0.0, 0.0),
		Vector3(60.0, 0.0, 0.0), Vector3(90.0, 0.0, 0.0)])

func _make(waiting: Array) -> Array:
	_started = []
	_finished = []
	_missed = []
	var bus := Node3D.new()
	add_child(bus)
	var watch := BoardingWatch.new()
	watch.build(_targets())
	# 난수를 고정한다. 안 그러면 대기 0 명이 나와 판정 테스트가 흔들린다.
	for index in range(waiting.size()):
		watch.plan.force_waiting(index, int(waiting[index]))
	watch.bus = bus
	watch.boarding_started.connect(
		func(i: int) -> void: _started.append(i))
	watch.boarding_finished.connect(
		func(b: int, a: int) -> void: _finished.append([b, a]))
	watch.stop_missed.connect(
		func(i: int) -> void: _missed.append(i))
	add_child(watch)
	# 갓 add_child 한 노드는 이번 physics_frame 이 뜬 뒤에야 첫
	# _physics_process 를 받는다. 두 번 기다려야 기준 위치가 잡힌다.
	await get_tree().physics_frame
	await get_tree().physics_frame
	return [watch, bus]

# 같은 자리에 머무르게 해서 속도 0 을 만든다.
func _hold(bus: Node3D, position: Vector3, frames: int) -> void:
	for _frame in frames:
		bus.global_position = position
		await get_tree().physics_frame

func _drop(made: Array) -> void:
	made[0].queue_free()
	made[1].queue_free()

func _test_far_away_does_not_start() -> void:
	var made := await _make([4, 4, 4, 4])
	await _hold(made[1], Vector3(0.0, 0.0, 300.0), 4)
	ok(not made[0].is_boarding, "정류장에서 300 m 떨어졌는데 승하차가 시작됐다")
	_drop(made)

func _test_moving_does_not_start() -> void:
	var made := await _make([4, 4, 4, 4])
	var bus: Node3D = made[1]
	# 프레임마다 1 m 씩 옮기면 60 m/s 다. 문턱 0.5 m/s 를 한참 넘는다.
	for step in 6:
		bus.global_position = Vector3(-3.0 + step, 0.0, 0.0)
		await get_tree().physics_frame
	ok(not made[0].is_boarding, "주행 중인데 승하차가 시작됐다")
	_drop(made)

func _test_stopped_starts() -> void:
	var made := await _make([4, 4, 4, 4])
	await _hold(made[1], Vector3(2.0, 0.0, 0.0), 4)
	ok(made[0].is_boarding, "정류장 앞에 섰는데 승하차가 시작되지 않았다")
	ok(made[0].boarding_left > 0.0, "남은 승하차 시간이 0 이다")
	ok(_started == [0], "시작 신호가 %s 다" % str(_started))
	_drop(made)

func _test_nearest_of_overlapping() -> void:
	var made := await _make([4, 4, 4, 4])
	# 0 번(0 m)과 1 번(30 m) 사이 18 m 지점. 1 번이 12 m 로 더 가깝다.
	await _hold(made[1], Vector3(18.0, 0.0, 0.0), 4)
	ok(made[0].is_boarding, "겹친 구간에서 승하차가 시작되지 않았다")
	ok(_started == [1], "가까운 1 번이 아니라 %s 를 잡았다" % str(_started))
	_drop(made)

func _test_passing_by_is_missed() -> void:
	var made := await _make([4, 4, 4, 4])
	var bus: Node3D = made[1]
	# 0 번과 1 번을 속도를 유지한 채 지나쳐 2 번 근처까지 간다.
	for step in 16:
		bus.global_position = Vector3(-10.0 + step * 5.0, 0.0, 0.0)
		await get_tree().physics_frame
	ok(_missed.has(0) and _missed.has(1),
		"0·1 번을 지나쳤는데 놓침이 %s 다" % str(_missed))
	ok(made[0].missed == _missed.size(),
		"놓침 수 %d 와 신호 수 %d 가 다르다" % [made[0].missed, _missed.size()])
	_drop(made)

func _test_empty_stop_is_not_missed() -> void:
	# 1 번에만 사람이 없다. 지나쳐도 놓침이 아니다.
	var made := await _make([4, 0, 4, 4])
	var bus: Node3D = made[1]
	for step in 16:
		bus.global_position = Vector3(-10.0 + step * 5.0, 0.0, 0.0)
		await get_tree().physics_frame
	ok(not _missed.has(1),
		"탈 사람도 내릴 사람도 없는 정류장을 놓침으로 셌다: %s" % str(_missed))
	_drop(made)

func _test_timer_finishes_and_boards() -> void:
	var made := await _make([4, 4, 4, 4])
	var watch: BoardingWatch = made[0]
	var bus: Node3D = made[1]
	await _hold(bus, Vector3(1.0, 0.0, 0.0), 3)
	ok(watch.is_boarding, "승하차가 시작되지 않았다")
	# 문 3 초 + 걸어오기 1 초 미만 + 4 명 4.8 초 = 9 초 남짓이다.
	# 물리 프레임 60 Hz 라 900 프레임(15 초)이면 무조건 끝난다.
	for _frame in 900:
		bus.global_position = Vector3(1.0, 0.0, 0.0)
		await get_tree().physics_frame
		if not watch.is_boarding:
			break
	ok(_finished.size() == 1,
		"완료 신호가 %d 번 났다 (남은 %.2f 초)"
		% [_finished.size(), watch.boarding_left])
	ok(watch.served == 1, "처리한 정류장이 %d 곳이다" % watch.served)
	ok(watch.onboard == 4, "4 명이 기다렸는데 %d 명이 탔다" % watch.onboard)
	ok(watch.next_index == 1, "다음 정류장이 %d 번이다" % watch.next_index)
	_drop(made)
```

`tests/game/test_boarding.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_boarding.gd" id="1"]

[node name="TestBoarding" type="Node3D"]
script = ExtResource("1")
```

`tests/game/run_game_tests.sh:26` 의 `scenes=(...)` 에서 `test_passenger_plan` 뒤에 `test_boarding` 을 넣는다:

```bash
	scenes=(test_route_data test_city test_input test_turn_radius test_nav_line test_traffic_signal test_violation test_passenger_plan test_boarding test_camera_view drive_smoke)
```

- [ ] **Step 2: 실패를 확인한다**

```bash
/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1
tests/game/run_game_tests.sh test_boarding
```

기대: `test_boarding: FAIL`. `Identifier "BoardingWatch" not declared` 가 나온다.

- [ ] **Step 3: 최소 구현**

`scripts/boarding_watch.gd`:

```gdscript
extends Node
class_name BoardingWatch
# 정차를 판정하고 승하차 시간을 흘린다. 그리지 않는다 — 표시는
# BoardingHud 의 일이다. 승객 규칙도 여기 없다 — PassengerPlan 의 일이다.
#
# ViolationWatch 처럼 격자 인덱스를 쓰지 않는다. 정류장은 노선 순서대로
# 지나가므로 next_index 앞뒤의 작은 창만 보면 된다.

const STOP_RADIUS_M := 15.0
const STOP_SPEED_MPS := 0.5
const AHEAD_WINDOW := 4      # next_index 부터 앞으로 보는 개수
const BACK_WINDOW := 2       # 되돌아가 다시 서는 것을 허용하는 깊이

signal boarding_started(stop_index: int)
signal boarding_finished(boarded: int, alighted: int)
signal stop_missed(stop_index: int)

var bus: Node3D
var plan: PassengerPlan

var served := 0
var missed := 0
var is_boarding := false
var boarding_left := 0.0
var boarding_total := 0.0    # 진행 바가 비율을 내려면 전체 길이도 있어야 한다
var next_index := 0

# 5번 서브프로젝트가 한 군데서 다 읽도록 plan 의 값을 그대로 내놓는다.
var onboard: int:
	get: return plan.onboard if plan != null else 0
var left_behind: int:
	get: return plan.left_behind if plan != null else 0

var _targets: PackedVector3Array = []
var _boarding_index := -1
var _pending := {}           # 진행 중인 정차의 serve() 결과
var _done := {}              # 승하차를 마친 정류장
var _missed_once := {}       # 놓침은 정류장당 한 번만 센다
var _last_position := Vector3.ZERO
var _has_last := false

func build(targets: PackedVector3Array) -> void:
	_targets = targets
	plan = PassengerPlan.new()
	plan.build(targets.size())

func _physics_process(delta: float) -> void:
	if bus == null or _targets.is_empty():
		return
	var here := bus.global_position

	if is_boarding:
		_tick(delta)
		_last_position = here
		return

	# 속도를 위치 차이로 잰다. bus 가 VehicleBody3D 든 빈 Node3D 든 된다.
	var speed := 0.0
	if _has_last and delta > 0.0:
		speed = _last_position.distance_to(here) / delta
	_last_position = here
	_has_last = true

	# 창 안에서 가장 가까운 정류장을 찾는다. 반경이 겹쳐도 가까운 쪽을 잡는다.
	var first := maxi(0, next_index - BACK_WINDOW)
	var best := -1
	var best_distance := INF
	for offset in BACK_WINDOW + AHEAD_WINDOW:
		var index := first + offset
		if index >= _targets.size():
			break
		var distance := _targets[index].distance_to(here)
		if distance < best_distance:
			best_distance = distance
			best = index
	if best < 0:
		return

	# 가장 가까운 정류장이 next_index 보다 뒤라면 그 사이는 지나간 것이다.
	# 반경 이탈로 판정하지 않는 이유는 반경 15 m 밖으로 우회하면 애초에
	# 들어온 적이 없어 놓침이 영영 안 잡히기 때문이다.
	while next_index < best:
		_pass(next_index)
		next_index += 1

	if best_distance <= STOP_RADIUS_M and speed < STOP_SPEED_MPS \
			and not _done.has(best) and plan.needs_stop(best):
		_start(best, best_distance)

func _pass(index: int) -> void:
	"""정류장을 지나갔다. 서야 했던 곳만 놓침으로 센다."""
	if _done.has(index) or _missed_once.has(index):
		return
	if not plan.needs_stop(index):
		# 탈 사람도 내릴 사람도 없다. 지나가는 것이 정상이다.
		return
	_missed_once[index] = true
	missed += 1
	stop_missed.emit(index)

func _start(index: int, walk_distance_m: float) -> void:
	_pending = plan.serve(index, walk_distance_m)
	_boarding_index = index
	boarding_total = float(_pending["dwell"])
	boarding_left = boarding_total
	is_boarding = true
	boarding_started.emit(index)

func _tick(delta: float) -> void:
	boarding_left -= delta
	if boarding_left > 0.0:
		return
	is_boarding = false
	boarding_left = 0.0
	boarding_total = 0.0
	served += 1
	_done[_boarding_index] = true
	next_index = maxi(next_index, _boarding_index + 1)
	boarding_finished.emit(int(_pending["boarded"]), int(_pending["alighted"]))
	_boarding_index = -1
	_pending = {}

func distance_to_next() -> float:
	"""다음 정류장까지 남은 거리. 종점을 지나면 -1."""
	if bus == null or next_index >= _targets.size():
		return -1.0
	return _targets[next_index].distance_to(bus.global_position)

func stop_name_at(index: int, stops: Array) -> String:
	"""HUD 가 쓰는 편의 함수. 범위를 벗어나면 빈 문자열이다."""
	if index < 0 or index >= stops.size():
		return ""
	return str(stops[index].get("name", ""))
```

- [ ] **Step 4: 통과를 확인한다**

```bash
tests/game/run_game_tests.sh test_boarding
```

기대: `test_boarding: OK`

`_test_nearest_of_overlapping` 이 `_started == [0]` 으로 실패하면 창의 시작이 `next_index - BACK_WINDOW` 가 아니라 `next_index` 인지 보라. `_test_passing_by_is_missed` 가 0 번을 못 잡으면 `while next_index < best` 가 `_pass` 를 부르기 전에 `next_index` 를 올리고 있지 않은지 보라.

- [ ] **Step 5: 커밋**

```bash
git add scripts/boarding_watch.gd tests/game/test_boarding.gd \
  tests/game/test_boarding.gd.uid tests/game/test_boarding.tscn \
  tests/game/run_game_tests.sh
git commit -m "feat: BoardingWatch — 정차 판정과 승하차 타이머

정류장 반경 15 m 안에서 속도 0.5 m/s 미만이면 승하차가 시작된다.
지나침은 반경 이탈이 아니라 '가장 가까운 정류장이 앞으로 갔는가' 로
판정한다 — 반경 밖으로 우회하면 애초에 들어온 적이 없어 이탈로는
영영 안 잡힌다. 탈 사람도 내릴 사람도 없는 정류장은 지나가는 것이
정상이라 놓침으로 세지 않는다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 4: StopField — 정류장과 대기 승객

**Files:**
- Create: `scripts/stop_field.gd`

**Interfaces:**
- Consumes: `RouteData.stops: Array` (`name`, `x`, `z`, `progress_m`, `osm_node` 키), `PassengerPlan.waiting_at(index) -> int`, `TrafficSignal.cell_of(x, z)`, `TrafficSignal.cells_near(position, radius)`
- Produces:
  - `StopField.UPDATE_RADIUS_M := 200.0`
  - `build(stops: Array, plan: PassengerPlan) -> void`
  - `var target: Node3D`
  - `var sign_count := 0`, `var rider_count := 0`, `var updated_count := 0`
  - `clear_riders(index: int) -> void` — 그 정류장 캡슐을 숨긴다

**설계 메모:** `SignalField` 를 그대로 베낀다 — 공유 머티리얼, 격자 + 거리 컬링, 충돌면 없음. 표지판과 승객은 **OSM 노드 좌표**(`stop["x"]`, `stop["z"]`)에 세운다. 보이는 것은 인도 위에 있어야 한다. 정차 목표점은 판정용이지 표시용이 아니다.

`build()` 는 `add_child()` 전에 불리므로 `global_position` 을 쓰면 죽는다. `SignalField` 처럼 로컬 `Transform3D` 를 직접 짠다 — `StopField` 자신이 원점에 단위 변환으로 있으므로 로컬이 곧 전역이다.

- [ ] **Step 1: 구현**

`scripts/stop_field.gd`:

```gdscript
extends Node3D
class_name StopField
# 정류장 표지판과 대기 승객. 판정은 여기서 하지 않는다 — BoardingWatch 의
# 일이다.
#
# 표지판과 승객은 OSM bus_stop 노드 좌표에 세운다. 정차 목표점은 노선 위에
# 있지만 그건 판정용이고, 보이는 것은 인도 위에 있어야 한다.
#
# 충돌면은 붙이지 않는다. 버스가 승객을 들이받아 주행이 막히는 쪽이 더 나쁘다.

const UPDATE_RADIUS_M := 200.0
const POLE_HEIGHT := 2.6
const SIGN_SIZE := Vector3(0.9, 0.5, 0.08)
const RIDER_HEIGHT := 1.7
const RIDER_RADIUS := 0.22
const RIDER_SPACING := 0.6
const RIDERS_PER_ROW := 4

var target: Node3D
var sign_count := 0
var rider_count := 0
var updated_count := 0

# [{"node": Node3D, "riders": Array[MeshInstance3D]}]
var _stops: Array = []
var _grid: Dictionary = {}     # Vector2i -> PackedInt32Array(_stops 인덱스)

var _pole_mesh: CylinderMesh
var _sign_mesh: BoxMesh
var _rider_mesh: CapsuleMesh
var _pole_material: StandardMaterial3D
var _sign_material: StandardMaterial3D
var _rider_material: StandardMaterial3D

func build(stops: Array, plan: PassengerPlan) -> void:
	_make_shared_resources()
	for index in range(stops.size()):
		var stop: Dictionary = stops[index]
		var here := Vector3(float(stop.get("x", 0.0)), 0.0,
			float(stop.get("z", 0.0)))
		var waiting := 0
		if plan != null:
			waiting = plan.waiting_at(index)
		_add_stop(index, here, waiting)

func _make_shared_resources() -> void:
	# 대기 승객이 노선 전체에 300 명 넘는다. 개별 머티리얼을 만들면 안 된다.
	_pole_mesh = CylinderMesh.new()
	_pole_mesh.top_radius = 0.06
	_pole_mesh.bottom_radius = 0.06
	_pole_mesh.height = POLE_HEIGHT
	_pole_mesh.radial_segments = 6

	_sign_mesh = BoxMesh.new()
	_sign_mesh.size = SIGN_SIZE

	_rider_mesh = CapsuleMesh.new()
	_rider_mesh.radius = RIDER_RADIUS
	_rider_mesh.height = RIDER_HEIGHT
	_rider_mesh.radial_segments = 6
	_rider_mesh.rings = 2

	_pole_material = StandardMaterial3D.new()
	_pole_material.albedo_color = Color(0.30, 0.32, 0.34)

	_sign_material = StandardMaterial3D.new()
	_sign_material.albedo_color = Color(0.10, 0.35, 0.70)

	_rider_material = StandardMaterial3D.new()
	_rider_material.albedo_color = Color(0.85, 0.72, 0.55)

func _add_stop(index: int, here: Vector3, waiting: int) -> void:
	var node := Node3D.new()
	# build() 는 add_child() 전에 불리므로 global_position 을 쓸 수 없다.
	# StopField 자신이 원점에 단위 변환으로 있어 로컬이 곧 전역이다.
	node.transform = Transform3D(Basis.IDENTITY, here)
	add_child(node)

	var pole := MeshInstance3D.new()
	pole.mesh = _pole_mesh
	pole.material_override = _pole_material
	pole.position = Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)
	node.add_child(pole)

	var board := MeshInstance3D.new()
	board.mesh = _sign_mesh
	board.material_override = _sign_material
	board.position = Vector3(0.0, POLE_HEIGHT, 0.0)
	node.add_child(board)
	sign_count += 1

	var riders: Array = []
	for rider_index in waiting:
		var rider := MeshInstance3D.new()
		rider.mesh = _rider_mesh
		rider.material_override = _rider_material
		# 표지판 옆에 두 줄로 세운다.
		var column := rider_index % RIDERS_PER_ROW
		var row := rider_index / RIDERS_PER_ROW
		rider.position = Vector3((column - 1.5) * RIDER_SPACING,
			RIDER_HEIGHT * 0.5, 0.8 + row * RIDER_SPACING)
		node.add_child(rider)
		riders.append(rider)
		rider_count += 1

	_stops.append({"node": node, "riders": riders})
	var cell := TrafficSignal.cell_of(here.x, here.z)
	if not _grid.has(cell):
		_grid[cell] = PackedInt32Array()
	_grid[cell].append(index)

func clear_riders(index: int) -> void:
	"""승객이 탔다. 캡슐을 치운다."""
	if index < 0 or index >= _stops.size():
		return
	for rider in _stops[index]["riders"]:
		rider.visible = false

func _physics_process(_delta: float) -> void:
	if target == null or _stops.is_empty():
		return
	# 먼 정류장은 통째로 숨긴다. seoul-100 은 정류장 114 곳에 승객 300 명이
	# 넘어서 전부 그리면 낭비다.
	updated_count = 0
	var near := {}
	for cell in TrafficSignal.cells_near(target.global_position, UPDATE_RADIUS_M):
		if not _grid.has(cell):
			continue
		for index in _grid[cell]:
			near[index] = true
	for index in range(_stops.size()):
		var wanted: bool = near.has(index)
		var node: Node3D = _stops[index]["node"]
		if node.visible != wanted:
			node.visible = wanted
		if wanted:
			updated_count += 1
```

- [ ] **Step 2: 파싱을 확인한다**

새 스크립트만으로는 도는 테스트가 없다. 임포트와 파싱만 본다. `class_name` 이라 프로젝트 전체 파싱 대상이다.

```bash
/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1
tests/game/run_game_tests.sh test_passenger_plan 2>&1 | grep -E "SCRIPT ERROR|Parse Error|: (OK|FAIL)"
```

기대: `test_passenger_plan: OK` 만 나오고 `Parse Error` 는 없다.

- [ ] **Step 3: 커밋**

```bash
git add scripts/stop_field.gd
git commit -m "feat: StopField — 정류장 표지판과 대기 승객

대기 인원이 멀리서 보여야 '다음 신호 파랑일 때 밀어붙일까' 를 미리
정할 수 있다. SignalField 와 같은 격자 거리 컬링으로 200 m 밖 정류장은
통째로 숨긴다. 충돌면은 붙이지 않는다 — 버스가 승객에 걸려 서는 쪽이
더 나쁘다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 5: BoardingHud — 상단 중앙 표시

**Files:**
- Create: `scripts/boarding_hud.gd`

**Interfaces:**
- Consumes: `BoardingWatch` 의 시그널 셋
- Produces:
  - `set_route(stops: Array) -> void`
  - `on_boarding_started(stop_index: int) -> void`
  - `on_boarding_finished(boarded: int, alighted: int) -> void`
  - `on_stop_missed(stop_index: int) -> void`
  - `update_status(next_name: String, distance_m: float, onboard: int, boarding_left: float, boarding_total: float) -> void`

**설계 메모:** `ViolationHud` 가 좌상단에 `layer = 10` 으로 있고, 터치 컨트롤이 아래와 양옆을 쓴다. 상단 중앙만 쓰고 `layer = 9` 로 둬서 적발 패널이 위에 오게 한다.

- [ ] **Step 1: 구현**

`scripts/boarding_hud.gd`:

```gdscript
extends CanvasLayer
class_name BoardingHud
# 다음 정류장, 탑승 인원, 승하차 진행을 보여준다. 판정하지 않는다 —
# BoardingWatch 의 일이다.
#
# 좌상단은 ViolationHud 가, 아래와 양옆은 터치 컨트롤이 쓴다. 상단 중앙만
# 쓴다. 적발 패널이 위에 오도록 layer 는 ViolationHud(10) 보다 낮게 둔다.

const MISS_FLASH_S := 1.5

var _stops: Array = []
var _next_label: Label
var _onboard_label: Label
var _progress: ProgressBar
var _miss_label: Label
var _miss_left := 0.0

func _ready() -> void:
	layer = 9

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -200.0
	box.offset_right = 200.0
	box.offset_top = 12.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_next_label = Label.new()
	_next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_next_label)

	_onboard_label = Label.new()
	_onboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_onboard_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_onboard_label)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(320.0, 18.0)
	_progress.show_percentage = false
	_progress.visible = false
	box.add_child(_progress)

	_miss_label = Label.new()
	_miss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_miss_label.add_theme_font_size_override("font_size", 18)
	_miss_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_miss_label.visible = false
	box.add_child(_miss_label)

func set_route(stops: Array) -> void:
	_stops = stops

func update_status(next_name: String, distance_m: float, onboard: int,
		boarding_left: float, boarding_total: float) -> void:
	if distance_m < 0.0:
		_next_label.text = "종점"
	else:
		_next_label.text = "다음 %s · %d m" % [next_name, int(distance_m)]
	_onboard_label.text = "탑승 %d명" % onboard
	if boarding_left > 0.0 and boarding_total > 0.0:
		_progress.visible = true
		_progress.value = 100.0 * (1.0 - boarding_left / boarding_total)
	else:
		_progress.visible = false

func on_boarding_started(stop_index: int) -> void:
	_next_label.text = "%s 승하차 중" % _name_of(stop_index)

func on_boarding_finished(boarded: int, alighted: int) -> void:
	_progress.visible = false
	_onboard_label.text = "탄 사람 %d · 내린 사람 %d" % [boarded, alighted]

func on_stop_missed(stop_index: int) -> void:
	_miss_label.text = "%s 통과" % _name_of(stop_index)
	_miss_label.visible = true
	_miss_left = MISS_FLASH_S

func _name_of(stop_index: int) -> String:
	if stop_index < 0 or stop_index >= _stops.size():
		return ""
	return str(_stops[stop_index].get("name", ""))

func _process(delta: float) -> void:
	if _miss_left <= 0.0:
		return
	_miss_left = maxf(_miss_left - delta, 0.0)
	if _miss_left == 0.0:
		_miss_label.visible = false
```

- [ ] **Step 2: 파싱을 확인한다**

```bash
/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1
tests/game/run_game_tests.sh test_boarding 2>&1 | grep -E "SCRIPT ERROR|Parse Error|: (OK|FAIL)"
```

기대: `test_boarding: OK` 만 나오고 `Parse Error` 는 없다.

- [ ] **Step 3: 커밋**

```bash
git add scripts/boarding_hud.gd
git commit -m "feat: BoardingHud — 다음 정류장과 승하차 진행 표시

좌상단은 위반 HUD, 아래와 양옆은 터치 컨트롤이 쓰므로 상단 중앙만
쓴다. 적발 패널이 위에 오도록 layer 를 ViolationHud 보다 낮게 둔다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 6: 배선과 회귀 검증

**Files:**
- Modify: `scripts/drive.gd`
- Modify: `tests/game/drive_smoke.gd`

**Interfaces:**
- Consumes: Task 1~5 의 산출물 전부
- Produces: `Drive.stop_field: StopField`, `Drive.boarding: BoardingWatch`, `Drive.boarding_hud: BoardingHud`

- [ ] **Step 1: drive.gd 에 필드를 더한다**

`scripts/drive.gd` 의 `var hud: ViolationHud` 다음 줄에:

```gdscript
var stop_field: StopField
var boarding: BoardingWatch
var boarding_hud: BoardingHud
```

- [ ] **Step 2: drive.gd 의 _ready 끝에 배선을 더한다**

`watch.busted.connect(hud.on_busted)` 다음(`_ready` 의 마지막)에:

```gdscript

	boarding = BoardingWatch.new()
	boarding.build(data.stop_targets)
	boarding.bus = bus
	add_child(boarding)

	stop_field = StopField.new()
	stop_field.build(data.stops, boarding.plan)
	stop_field.target = bus
	add_child(stop_field)

	boarding_hud = BoardingHud.new()
	add_child(boarding_hud)
	boarding_hud.set_route(data.stops)
	boarding.boarding_started.connect(boarding_hud.on_boarding_started)
	boarding.boarding_started.connect(stop_field.clear_riders)
	boarding.boarding_finished.connect(boarding_hud.on_boarding_finished)
	boarding.stop_missed.connect(boarding_hud.on_stop_missed)
```

- [ ] **Step 3: drive.gd 의 _physics_process 에 승하차 게이트를 더한다**

적발 게이트(`if watch != null and watch.is_busted:` 블록의 `return`) **다음**, `input.poll(...)` **앞**에:

```gdscript
	if boarding != null and boarding.is_boarding:
		# 문이 열려 있다. 브레이크만 걸어 버스를 붙잡는다. 승하차 시간을
		# 주행으로 건너뛸 수 없어야 시간 압박이 성립한다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		_update_boarding_hud()
		return
```

그리고 `_physics_process` 의 리스폰 처리 바로 앞(`var respawn_asked := input.take_respawn()` 앞)에:

```gdscript
	_update_boarding_hud()
```

`respawn()` 함수 **앞**에 새 함수를 더한다:

```gdscript
func _update_boarding_hud() -> void:
	if boarding == null or boarding_hud == null:
		return
	boarding_hud.update_status(
		boarding.stop_name_at(boarding.next_index, data.stops),
		boarding.distance_to_next(), boarding.onboard,
		boarding.boarding_left, boarding.boarding_total)
```

- [ ] **Step 4: 승하차 중 리스폰을 막는다**

`scripts/drive.gd` 의 `respawn()` 본문 첫 줄에:

```gdscript
	if boarding != null and boarding.is_boarding:
		# 리스폰으로 승하차 시간을 건너뛸 수 없다.
		return
```

- [ ] **Step 5: drive_smoke 에 검증을 더한다**

`tests/game/drive_smoke.gd:139` 의 신호 기둥 충돌면 검사 다음, `finish()` 바로 앞에 (들여쓰기는 탭 하나):

```gdscript

	# 정류장이 섰는지, 컬링이 실제로 도는지 본다.
	ok(drive.stop_field != null, "StopField 가 없다")
	ok(drive.boarding != null, "BoardingWatch 가 없다")
	ok(drive.boarding_hud != null, "BoardingHud 가 없다")
	ok(drive.data.stop_targets.size() == drive.data.stops.size(),
		"정차 목표점이 %d 개인데 정류장은 %d 곳이다"
		% [drive.data.stop_targets.size(), drive.data.stops.size()])
	ok(drive.stop_field.sign_count == drive.data.stops.size(),
		"표지판이 %d 개인데 정류장은 %d 곳이다"
		% [drive.stop_field.sign_count, drive.data.stops.size()])
	ok(drive.stop_field.updated_count > 0, "정류장을 하나도 안 보였다")
	ok(drive.stop_field.updated_count < drive.data.stops.size(),
		"거리 컬링이 안 걸려 정류장 %d 곳을 전부 보였다"
		% drive.data.stops.size())
	# 승객에 충돌면이 붙으면 버스가 사람을 들이받고 주행이 막힌다.
	ok(drive.stop_field.find_children("*", "StaticBody3D", true, false).is_empty(),
		"정류장에 충돌면이 붙었다")
```

- [ ] **Step 6: 전체 테스트를 돌린다**

```bash
/opt/homebrew/bin/godot --headless --import >/dev/null 2>&1
tests/game/run_game_tests.sh
```

기대: 11개 씬 전부 `OK`.

`drive_smoke` 는 `drive.set_physics_process(false)` 로 `drive.gd` 의 `_physics_process` 를 꺼 두고 직접 버스를 민다. 승하차 게이트는 `drive.gd` 안에 있으므로 스모크 주행을 막지 않는다 — `BoardingWatch` 가 승하차를 시작해도 버스는 계속 간다. 따라서 주행 거리 단언이 승하차 때문에 깨질 일은 없다. `updated_count` 가 정류장 전체와 같게 나오면 격자 계산(`TrafficSignal.cell_of` 에 넘기는 좌표)을 보라.

- [ ] **Step 7: 커밋**

```bash
git add scripts/drive.gd tests/game/drive_smoke.gd
git commit -m "feat: 정류장·승객을 주행 씬에 배선

승하차 중에는 브레이크만 걸어 버스를 붙잡고 리스폰도 막는다.
승하차 시간을 주행이나 리스폰으로 건너뛸 수 있으면 시간 압박이
성립하지 않는다.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Task 7: 성능 확인과 문서

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 파이썬 테스트가 안 깨졌는지 본다**

베이크는 안 건드렸지만 확인은 싸다.

```bash
python3 -m unittest discover -s tests -t . 2>&1 | grep -E "^(OK|FAILED|Ran )"
```

기대: `Ran 139 tests` / `OK`

- [ ] **Step 2: 노선 검증**

```bash
tests/bake/run_verify.sh 2>&1 | grep -E "VERIFY_OK|: (OK|FAIL)"
```

기대: 세 노선 모두 `OK`.

- [ ] **Step 3: fps 재측정**

`measure_fps.gd` 는 **창 모드 전용**이다 — 헤드리스는 렌더링을 안 해서 숫자가 의미 없다. `--headless` 없이 돌린다. 약 33초 걸린다.

```bash
/opt/homebrew/bin/godot res://tests/game/measure_fps.tscn -- --route=seoul-100 2>&1 | grep -i fps
```

기준: 평균 60 이상, 최저 55 이상. 직전 측정은 평균 120.0 / 최저 119.0 이었다. 정류장 114곳에 승객 300여 명이 늘었으니 떨어질 수 있다. 기준 밑으로 내려가면 `StopField.UPDATE_RADIUS_M` 을 120 으로 줄여 다시 재라.

창을 띄울 수 없는 환경이면 이 단계를 건너뛰고 사용자에게 직접 돌려 달라고 알린다 — 조용히 통과로 처리하지 않는다.

- [ ] **Step 4: README 를 고친다**

`## 게임 실행` 절의 신호·위반 문단 **다음**에 문단을 더한다:

```markdown
정류장에는 대기 승객이 서 있다. 정류장 앞 15 m 안에서 멈추면 승하차가 시작되고
그동안 버스는 움직이지 않는다. 걸리는 시간은 타는 사람과 내리는 사람 수, 그리고
정류장에서 얼마나 떨어져 섰는지로 달라진다. 탈 사람도 내릴 사람도 없는 정류장은
그냥 지나가면 된다. 대기 인원은 매 플레이 새로 정해진다.
```

`## 문서` 절 끝에 두 줄을 더한다:

```markdown
- 설계: `docs/superpowers/specs/2026-09-24-stops-passengers-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-24-stops-passengers.md`
```

- [ ] **Step 5: 커밋과 정리**

```bash
git add README.md
git commit -m "docs: README 에 정류장·승하차 설명 추가

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git status --porcelain
```

기대: `git status --porcelain` 이 비어 있다. `.uid` 파일이 남아 있으면 이름을 적어 개별로 추가해 커밋한다. **`git add -A` 나 `git add .` 은 쓰지 않는다.**
