# 버스 물리 + 입력 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1번 서브프로젝트가 구운 도시 위를 사람이 직접 모는 세미 리얼 버스를 만든다.

**Architecture:** Godot 4.7 `VehicleBody3D` 를 확장한 버스에 축 세 개(조향/가속/제동)만 먹인다. 플랫폼 입력(PC 키보드 / 안드로이드 터치)은 `bus_input.gd` 가 혼자 흡수해 그 축으로 번역한다. 씬은 둘 — 노선 고르는 메뉴와 주행 씬 — 이고, 주행 씬이 도시·버스·카메라·내비 라인을 조립한다.

**Tech Stack:** Godot 4.7.2, GDScript. 테스트 프레임워크 없음 — 헤드리스로 씬을 띄워 `TEST_OK` / `TEST_FAIL` 을 찍고 종료하는 1번의 패턴을 재활용한다.

**Spec:** `docs/superpowers/specs/2026-09-23-bus-physics-input-design.md`

## Global Constraints

전부 spec 에서 그대로 옮긴 값이다. 추측으로 바꾸지 말 것.

- **좌표계**: 로컬 평면 미터. x 동쪽, z 남쪽, y 는 0 고정.
- **`engine_force` 부호가 반대다**: Godot 4.7 `VehicleBody3D` 는 **음수** `engine_force` 가 차량 전방(로컬 −Z)으로 민다. 그 상태에서 `steering` 부호도 뒤집힌다. 1번 서브프로젝트의 실측이다.
- **서스펜션**: `suspension_stiffness = 150.0`, `suspension_max_force = 80000.0`, `damping_compression = 3.7`, `damping_relaxation = 6.1`, `wheel_friction_slip = 3.5`, `wheel_radius = 0.5`, `suspension_travel = 0.35`. 12 t 차량은 기본값으로 주저앉는다.
- **차체**: 질량 12000 kg. 충돌 상자 `Vector3(2.5, 3.0, 11.0)`, 중심 `y = 2.0`(밑면이 지면에 닿으면 바퀴가 일을 못 한다).
- **바퀴 위치**: 앞 `z = -3.6`(조향), 뒤 `z = 3.0`(구동), 좌우 `x = ±1.1`, `y = 0.2`. 휠베이스 6.6 m.
- **회전 반경 9–11 m**. `MAX_STEERING = 0.62` rad 은 시작값이고, 반경이 기준이다.
- **한국어**: 모든 주석·출력·문서는 한국어.
- **테스트 프레임워크 금지**: GUT 등을 추가하지 않는다.
- **청크 거리 컬링 금지**: 8번 태스크의 측정이 요구할 때만 넣는다.
- **`tests/bake/` 를 건드리지 않는다**: 1번의 검증 하네스는 검증된 자산이다. `city.gd` 는 거기서 코드를 옮기는 게 아니라 새로 쓴다.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `scripts/route_data.gd` | `route_<id>.json` 을 읽는 유일한 곳. 노선 목록, 선택된 노선 id 보관 |
| `scripts/city.gd` | `.glb` 인스턴스화, 충돌 메쉬 생성, 무한 바닥 평면 |
| `scripts/bus_input.gd` | PC 키보드 / 터치 → 축 세 개 + 플래그 둘 |
| `scripts/bus.gd` | `VehicleBody3D` 확장. 축을 물리로 번역, 리스폰 |
| `scripts/nav_line.gd` | 경로 폴리라인 → 지면 위 반투명 리본 |
| `scripts/chase_camera.gd` | 버스를 지연 추종하는 스프링암 카메라 |
| `scripts/drive.gd` + `scenes/drive.tscn` | 주행 씬 조립 |
| `scripts/menu.gd` + `scenes/menu.tscn` | 노선 선택 |
| `tests/game/test_case.gd` | 단언 헬퍼. `TEST_OK` / `TEST_FAIL` 출력 |
| `tests/game/*.tscn` + `*.gd` | 테스트 씬들 |
| `tests/game/run_game_tests.sh` | 헤드리스 테스트 전체 실행 |

---

### Task 1: 테스트 하네스와 노선 데이터

**Files:**
- Create: `scripts/route_data.gd`
- Create: `tests/game/test_case.gd`
- Create: `tests/game/test_route_data.gd`, `tests/game/test_route_data.tscn`
- Create: `tests/game/run_game_tests.sh`

**Interfaces:**
- Consumes: `assets/routes/route_<id>.json` (1번의 데이터 계약)
- Produces:
  - `RouteData.load_route(route_id: String) -> RouteData` (실패 시 `null`)
  - `RouteData.list_route_ids() -> PackedStringArray` (정렬됨)
  - `RouteData.selected_id: String` (static, 기본 `"seoul-100"`)
  - 인스턴스 필드 `id`, `display_name`, `from_name`, `to_name`, `route: PackedVector3Array`, `stops: Array`, `chunks: Array`
  - `nearest_index(point: Vector3) -> int`
  - `TestCase.ok(condition: bool, message: String) -> void`, `TestCase.finish() -> void`

- [ ] **Step 1: 단언 헬퍼를 쓴다**

`tests/game/test_case.gd`:

```gdscript
extends Node
class_name TestCase
# 헤드리스 테스트 공통 뼈대. 1번의 tests/bake/verify.gd 패턴을 따른다 —
# 실패를 모았다가 마지막에 TEST_OK / TEST_FAIL 을 찍고 종료 코드로 알린다.
# GUT 같은 프레임워크를 쓰지 않는 이유는 의존성을 늘리지 않기 위해서다.

var failures: Array[String] = []

func ok(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func equal_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (실제 %.4f, 기대 %.4f ± %.4f)" % [message, actual, expected, tolerance])

func finish() -> void:
	if failures.is_empty():
		print("TEST_OK")
		get_tree().quit(0)
		return
	for failure in failures:
		print("TEST_FAIL: %s" % failure)
	get_tree().quit(1)
```

- [ ] **Step 2: 실패하는 테스트를 쓴다**

`tests/game/test_route_data.gd`:

```gdscript
extends TestCase
# route_data.gd 가 1번의 실제 산출물을 읽는지 본다. 가짜 데이터로 테스트하면
# 데이터 계약이 어긋나도 모른다.

func _ready() -> void:
	var data := RouteData.load_route("seoul-seodaemun03")
	ok(data != null, "seoul-seodaemun03 을 읽지 못했다")
	if data == null:
		finish()
		return

	ok(data.id == "seoul-seodaemun03", "id 가 틀렸다: %s" % data.id)
	ok(data.display_name != "", "표시 이름이 비었다")
	ok(data.from_name != "", "기점 이름이 비었다")
	ok(data.to_name != "", "종점 이름이 비었다")
	ok(data.route.size() > 100, "경로점이 %d 개뿐이다" % data.route.size())
	ok(data.stops.size() > 10, "정류장이 %d 개뿐이다" % data.stops.size())
	ok(data.chunks.size() > 0, "청크가 없다")

	# 경로는 (x, z) 평면이다. y 는 전부 0 이어야 한다.
	for point in data.route:
		if point.y != 0.0:
			ok(false, "경로점의 y 가 0 이 아니다: %f" % point.y)
			break

	# 청크는 1번 계약대로 name/min/max 를 가진 사전이다.
	var chunk = data.chunks[0]
	ok(chunk.has("name") and chunk.has("min") and chunk.has("max"),
		"청크 계약이 다르다: %s" % str(chunk))

	# nearest_index 는 경로 위의 점에 대해 그 점 자신을 찾아야 한다.
	var probe: Vector3 = data.route[7]
	ok(data.nearest_index(probe) == 7, "nearest_index 가 자기 자신을 못 찾는다")
	# 경로에서 살짝 떨어진 점도 같은 인덱스로 붙어야 한다.
	ok(data.nearest_index(probe + Vector3(0.5, 0.0, 0.5)) == 7,
		"nearest_index 가 근처 점을 못 붙인다")

	ok(RouteData.list_route_ids().size() >= 3,
		"노선 목록이 %d 개다" % RouteData.list_route_ids().size())

	finish()
```

`tests/game/test_route_data.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_route_data.gd" id="1"]

[node name="TestRouteData" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: 테스트 실행기를 쓴다**

`tests/game/run_game_tests.sh`:

```bash
#!/usr/bin/env bash
# 게임 쪽 헤드리스 테스트 전체 실행.
#   tests/game/run_game_tests.sh
# 씬 이름을 인자로 주면 그것만 돈다:
#   tests/game/run_game_tests.sh test_input
set -euo pipefail
cd "$(dirname "$0")/../.."

# Godot 실행 파일: 환경변수로 덮어쓸 수 있게 하고, PATH 에 없으면
# 이 기계에 설치된 경로로 폴백한다. 둘 다 없으면 바로 에러로 종료.
GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="godot"
	elif [ -x /opt/homebrew/bin/godot ]; then
		GODOT_BIN="/opt/homebrew/bin/godot"
	else
		echo "godot 실행 파일을 찾을 수 없다. GODOT 환경변수로 경로를 지정하라." >&2
		exit 1
	fi
fi

if [ $# -gt 0 ]; then
	scenes=("$@")
else
	scenes=(test_route_data)
fi

"$GODOT_BIN" --headless --import >/dev/null 2>&1 || true

failed=0
for scene in "${scenes[@]}"; do
	echo "=== $scene ==="
	# --quit-after 는 씬이 스스로 종료하지 못했을 때의 안전망 프레임 상한.
	if "$GODOT_BIN" --headless --fixed-fps 60 --quit-after 200000 \
			"res://tests/game/${scene}.tscn"; then
		echo "$scene: OK"
	else
		echo "$scene: FAIL"
		failed=1
	fi
done
exit $failed
```

실행 권한을 준다: `chmod +x tests/game/run_game_tests.sh`

- [ ] **Step 4: 테스트가 실패하는지 확인**

Run: `tests/game/run_game_tests.sh`
Expected: FAIL. `Parse Error: Identifier "RouteData" not declared` 류의 에러.

- [ ] **Step 5: route_data.gd 를 쓴다**

`scripts/route_data.gd`:

```gdscript
extends RefCounted
class_name RouteData
# route_<id>.json 을 읽는 유일한 지점. 1번 서브프로젝트의 데이터 계약이
# 코드 전체에 흩어지지 않게 여기서만 키 이름을 안다.

# 메뉴가 고른 노선을 주행 씬에 넘기는 통로. 씬 전환 사이에 값을 나를
# 오토로드를 따로 만들지 않으려고 static 변수를 쓴다.
static var selected_id := "seoul-100"

var id := ""
var display_name := ""
var from_name := ""
var to_name := ""
var route: PackedVector3Array = []
var stops: Array = []
var chunks: Array = []

static func load_route(route_id: String) -> RouteData:
	var raw := FileAccess.get_file_as_string("res://assets/routes/route_%s.json" % route_id)
	if raw == "":
		return null
	# JSON.parse_string 은 실패하면 null 을 돌려준다. 타입 지정된 변수에 바로
	# 대입하면 그 대입 자체가 런타임 에러라, 타입 없는 변수로 먼저 받는다.
	var parsed = JSON.parse_string(raw)
	if parsed == null:
		return null

	var data := RouteData.new()
	data.id = str(parsed.get("id", route_id))
	data.display_name = str(parsed.get("name", route_id))
	data.from_name = str(parsed.get("from", ""))
	data.to_name = str(parsed.get("to", ""))
	for point in parsed.get("route", []):
		# 산출물은 (x, z) 쌍이다. y 는 평지라 0 이다.
		data.route.append(Vector3(point[0], 0.0, point[1]))
	data.stops = parsed.get("stops", [])
	data.chunks = parsed.get("chunks", [])
	return data

static func list_route_ids() -> PackedStringArray:
	"""assets/routes 를 훑어 노선 id 를 낸다. 노선을 더 구우면 알아서 늘어난다."""
	var ids := PackedStringArray()
	var dir := DirAccess.open("res://assets/routes")
	if dir == null:
		return ids
	for file in dir.get_files():
		if file.begins_with("route_") and file.ends_with(".json"):
			ids.append(file.trim_prefix("route_").trim_suffix(".json"))
	ids.sort()
	return ids

func nearest_index(point: Vector3) -> int:
	"""point 에 가장 가까운 경로점의 인덱스. 리스폰 위치를 정할 때 쓴다."""
	var best := 0
	var best_distance := INF
	for i in range(route.size()):
		var distance := route[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best
```

- [ ] **Step 6: 테스트가 통과하는지 확인**

Run: `tests/game/run_game_tests.sh`
Expected: `TEST_OK`, `test_route_data: OK`, 종료 코드 0

- [ ] **Step 7: 커밋**

```bash
git add scripts/route_data.gd tests/game/test_case.gd tests/game/test_route_data.gd \
        tests/game/test_route_data.tscn tests/game/run_game_tests.sh
git commit -m "feat: 노선 데이터 로더와 게임 테스트 하네스"
```

---

### Task 2: 도시 로딩과 바닥 평면

**Files:**
- Create: `scripts/city.gd`
- Create: `tests/game/test_city.gd`, `tests/game/test_city.tscn`
- Modify: `tests/game/run_game_tests.sh` (기본 씬 목록에 `test_city` 추가)

**Interfaces:**
- Consumes: `RouteData.load_route(route_id) -> RouteData`, 필드 `route`, `chunks`
- Produces:
  - `City` 는 `Node3D` 다. `load_city(route_id: String) -> bool`
  - `chunk_nodes: Array[Node3D]` — 청크별 `MeshInstance3D` 목록. 8번 태스크에서 거리 컬링이 필요해지면 여기를 쓴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_city.gd`:

```gdscript
extends TestCase
# 구운 .glb 가 충돌 가능한 도시로 올라오는지, 도로 밖이 허공이 아닌지 본다.

func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var world := City.new()
	root.add_child(world)

	var data := RouteData.load_route("seoul-seodaemun03")
	ok(data != null, "노선 데이터를 읽지 못했다")
	if data == null:
		finish()
		return

	ok(world.load_city("seoul-seodaemun03"), "도시를 올리지 못했다")
	ok(world.chunk_nodes.size() > 0, "청크 노드가 없다")

	# 물리 서버가 새로 붙은 충돌체를 인식할 때까지 한 틱 기다린다.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := world.get_world_3d().direct_space_state

	# 경로 첫 점 아래에는 도로가 있어야 한다.
	ok(_ray_hit_y(space, data.route[0]) > -0.5,
		"경로 첫 점 아래에 지면이 없다")

	# 도로에서 한참 떨어진 곳도 바닥 평면이 받아야 한다. 이게 없으면
	# 플레이어가 도로를 벗어나는 순간 허공으로 떨어진다.
	var far_point: Vector3 = data.route[0] + Vector3(3000.0, 0.0, 3000.0)
	ok(_ray_hit_y(space, far_point) > -0.5,
		"도로 밖에 바닥이 없다 — 벗어나면 추락한다")

	finish()

func _ray_hit_y(space: PhysicsDirectSpaceState3D, point: Vector3) -> float:
	"""point 위 30 m 에서 아래로 쏜 레이가 맞은 높이. 안 맞으면 -999."""
	var origin := Vector3(point.x, 30.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 60.0)
	var hit := space.intersect_ray(query)
	return -999.0 if hit.is_empty() else float(hit["position"].y)
```

`tests/game/test_city.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_city.gd" id="1"]

[node name="TestCity" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

`run_game_tests.sh` 의 `scenes=(test_route_data)` 를 `scenes=(test_route_data test_city)` 로 바꾼다.

Run: `tests/game/run_game_tests.sh test_city`
Expected: FAIL. `scripts/city.gd` 가 없다는 에러.

- [ ] **Step 3: city.gd 를 쓴다**

`scripts/city.gd`:

```gdscript
extends Node3D
class_name City
# 구운 .glb 를 올리고 충돌면을 만든다. 청크 노드 목록을 쥔 유일한 곳이라,
# 거리 컬링이 필요해지면 들어갈 자리도 여기다(현재는 측정 결과상 불필요).

var chunk_nodes: Array[Node3D] = []

func load_city(route_id: String) -> bool:
	var scene: PackedScene = load("res://assets/routes/route_%s.glb" % route_id)
	if scene == null:
		push_error("glb 를 읽지 못했다: %s" % route_id)
		return false
	var instance := scene.instantiate()
	add_child(instance)
	for node in instance.find_children("*", "MeshInstance3D", true):
		# 구운 메쉬에는 충돌체가 없다. 삼각형 메쉬 충돌을 붙여야 바퀴가 닿는다.
		node.create_trimesh_collision()
		chunk_nodes.append(node)
	_add_ground()
	return true

func _add_ground() -> void:
	# 1번 산출물의 충돌면은 도로 리본과 건물뿐이라 도로 밖은 허공이다.
	# 무한 평면 하나를 y=0 에 깔아 도로를 벗어나도 맨땅을 달리게 한다.
	# WorldBoundaryShape3D 의 기본 평면이 y=0, 법선 +Y 다. 도로 리본도
	# y=0 이라 턱이 생기지 않는다.
	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)
```

- [ ] **Step 4: 테스트가 통과하는지 확인**

Run: `tests/game/run_game_tests.sh`
Expected: 두 씬 모두 `TEST_OK`, 종료 코드 0

- [ ] **Step 5: 커밋**

```bash
git add scripts/city.gd tests/game/test_city.gd tests/game/test_city.tscn \
        tests/game/run_game_tests.sh
git commit -m "feat: 도시 로딩과 무한 바닥 평면"
```

---

### Task 3: 입력 계층

**Files:**
- Create: `scripts/bus_input.gd`
- Create: `tests/game/test_input.gd`, `tests/game/test_input.tscn`
- Modify: `project.godot` (입력 맵, 터치 에뮬레이션)
- Modify: `tests/game/run_game_tests.sh` (씬 목록에 `test_input`)

**Interfaces:**
- Consumes: 없음
- Produces:
  - `BusInput` 은 `Node` 다. 매 물리 프레임 `poll(speed: float) -> void` 를 부르면 아래 필드가 갱신된다.
  - `steer: float` (−1..1, 왼쪽이 음수), `throttle: float` (0..1), `brake: float` (0..1), `reverse: bool`
  - `take_respawn() -> bool` — 이번 프레임에 리스폰이 눌렸으면 `true` 를 내고 플래그를 지운다
  - `static steer_from_touch(origin_x: float, current_x: float, screen_width: float) -> float`
  - `static next_reverse(current: bool, speed: float, brake_held: bool, throttle_held: bool) -> bool`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_input.gd`:

```gdscript
extends TestCase
# 축 계산은 순수 계산이라 헤드리스로 단언할 수 있다. 실제 입력 이벤트가 아니라
# 계산 함수를 직접 부른다 — 이벤트 주입은 플랫폼에 의존해 헤드리스에서 불안정하다.

const SCREEN := 1000.0   # 화면 폭. 15% = 150 px 가 최대 조향

func _ready() -> void:
	# 중립
	equal_approx(BusInput.steer_from_touch(500.0, 500.0, SCREEN), 0.0, 0.001,
		"터치 변위 0 이 중립이 아니다")
	# 절반(7.5%)
	equal_approx(BusInput.steer_from_touch(500.0, 575.0, SCREEN), 0.5, 0.001,
		"변위 7.5% 가 0.5 가 아니다")
	# 최대(15%)
	equal_approx(BusInput.steer_from_touch(500.0, 650.0, SCREEN), 1.0, 0.001,
		"변위 15% 가 1.0 이 아니다")
	# 최대를 넘겨도 1.0 을 넘지 않는다
	equal_approx(BusInput.steer_from_touch(500.0, 800.0, SCREEN), 1.0, 0.001,
		"변위 30% 가 1.0 을 넘었다")
	# 왼쪽은 음수
	equal_approx(BusInput.steer_from_touch(500.0, 425.0, SCREEN), -0.5, 0.001,
		"왼쪽 변위가 음수가 아니다")

	# 후진 전환: 정지 상태에서 제동을 누르면 켜진다
	ok(BusInput.next_reverse(false, 0.1, true, false),
		"정지 상태 제동이 후진으로 전환되지 않았다")
	# 주행 중 제동은 후진이 아니다
	ok(not BusInput.next_reverse(false, 8.0, true, false),
		"주행 중 제동이 후진으로 전환됐다")
	# 아무것도 안 누르면 그대로
	ok(not BusInput.next_reverse(false, 0.0, false, false),
		"입력 없이 후진이 켜졌다")
	# 후진 중 가속을 누르면 전진으로 복귀
	ok(not BusInput.next_reverse(true, 3.0, false, true),
		"후진 중 가속이 전진으로 복귀시키지 못했다")
	# 후진 중 제동만 누르면 후진 유지
	ok(BusInput.next_reverse(true, 3.0, true, false),
		"후진 중 제동이 후진을 풀었다")

	# 터치를 떼면 중립으로 돌아간다
	var input := BusInput.new()
	add_child(input)
	input._begin_touch(0, 500.0, SCREEN)
	input._move_touch(0, 650.0)
	input.poll(0.0)
	equal_approx(input.steer, 1.0, 0.001, "터치 조향이 축에 반영되지 않았다")
	input._end_touch(0)
	input.poll(0.0)
	equal_approx(input.steer, 0.0, 0.001, "터치를 뗐는데 중립으로 안 돌아갔다")

	# 키보드 축. 헤드리스에도 Input.action_press 로 눌린 상태를 만들 수 있다.
	Input.action_press("bus_steer_right")
	input.poll(0.0)
	equal_approx(input.steer, 1.0, 0.001, "D 가 steer +1 을 내지 않는다")
	Input.action_release("bus_steer_right")

	Input.action_press("bus_steer_left")
	input.poll(0.0)
	equal_approx(input.steer, -1.0, 0.001, "A 가 steer -1 을 내지 않는다")
	Input.action_release("bus_steer_left")

	Input.action_press("bus_throttle")
	input.poll(0.0)
	equal_approx(input.throttle, 1.0, 0.001, "W 가 throttle 1 을 내지 않는다")
	Input.action_release("bus_throttle")

	finish()
```

`tests/game/test_input.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_input.gd" id="1"]

[node name="TestInput" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

`run_game_tests.sh` 의 씬 목록을 `scenes=(test_route_data test_city test_input)` 로 바꾼다.

Run: `tests/game/run_game_tests.sh test_input`
Expected: FAIL. `BusInput` 미정의.

- [ ] **Step 3: 입력 맵과 터치 에뮬레이션을 설정한다**

`project.godot` 에 아래를 더한다. `[input]` 섹션이 없으면 만든다.

```
[input_devices]

pointing/emulate_touch_from_mouse=true

[input]

bus_throttle={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":87)]
}
bus_brake={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":83)]
}
bus_steer_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":65)]
}
bus_steer_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":68)]
}
bus_respawn={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":82)]
}
```

`physical_keycode` 값은 W=87, S=83, A=65, D=68, R=82 다. 물리 키코드를 쓰는 이유는 한글/다국어 자판에서도 같은 자리가 먹게 하기 위해서다.

이 형식이 손으로 쓰기 까다로우면 Godot 에디터의 프로젝트 설정 → 입력 맵에서 같은 이름으로 만들어도 된다. 결과 파일이 같으면 된다.

- [ ] **Step 4: bus_input.gd 를 쓴다**

`scripts/bus_input.gd`:

```gdscript
extends Node
class_name BusInput
# 플랫폼 입력을 축 세 개와 플래그 둘로 번역한다. bus.gd 는 PC 냐 터치냐를
# 모른다. 이 경계 덕분에 축 계산을 헤드리스로 테스트할 수 있고, 5번
# 서브프로젝트의 HUD 도 같은 통로로 계기판을 그린다.

# 화면 폭의 이만큼을 끌면 최대 조향. 고정 위치 스틱이 아니라 손가락을 댄
# 지점을 중립으로 잡는다 — 화면을 안 보고 엄지를 내리면 고정 스틱은 빗나간다.
const TOUCH_FULL_LOCK_RATIO := 0.15
# 이보다 느릴 때만 후진으로 전환한다. 달리는 중에 제동을 밟았다고 후진이
# 걸리면 안 된다.
const REVERSE_SPEED_MAX := 0.5

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var reverse := false

var _respawn_pressed := false
# 조향을 맡은 손가락. -1 이면 아무도 안 잡고 있다.
var _steer_touch := -1
var _touch_origin_x := 0.0
var _touch_steer := 0.0
var _screen_width := 1152.0
# 터치 버튼이 눌러주는 값. UI 버튼이 직접 쓴다.
var touch_throttle := false
var touch_brake := false
var touch_reverse_toggle := false

static func steer_from_touch(origin_x: float, current_x: float,
		screen_width: float) -> float:
	"""손가락 가로 변위를 -1..1 조향축으로. 화면 폭의 15% 가 최대 조향."""
	var full := maxf(screen_width * TOUCH_FULL_LOCK_RATIO, 1.0)
	return clampf((current_x - origin_x) / full, -1.0, 1.0)

static func next_reverse(current: bool, speed: float, brake_held: bool,
		throttle_held: bool) -> bool:
	"""후진 상태 전이. 정지 상태 제동으로 켜지고, 가속으로 꺼진다."""
	if current:
		return not throttle_held
	return brake_held and speed < REVERSE_SPEED_MAX

func poll(speed: float) -> void:
	"""매 물리 프레임 호출. 축과 플래그를 갱신한다."""
	var keyboard_steer := Input.get_axis("bus_steer_left", "bus_steer_right")
	# 터치가 잡고 있으면 터치가 이긴다. 둘 다 없으면 0 으로 돌아간다.
	steer = _touch_steer if _steer_touch != -1 else keyboard_steer

	var throttle_held := Input.is_action_pressed("bus_throttle") or touch_throttle
	var brake_held := Input.is_action_pressed("bus_brake") or touch_brake

	if touch_reverse_toggle:
		# 터치는 전용 토글 버튼이다. 한 번 누르면 한 번 뒤집는다.
		touch_reverse_toggle = false
		reverse = not reverse
	else:
		reverse = next_reverse(reverse, speed, brake_held, throttle_held)

	throttle = 1.0 if throttle_held else 0.0
	brake = 1.0 if brake_held else 0.0

	if Input.is_action_just_pressed("bus_respawn"):
		_respawn_pressed = true

func take_respawn() -> bool:
	"""리스폰 요청을 꺼내간다. 한 번 꺼내면 지워진다."""
	var pressed := _respawn_pressed
	_respawn_pressed = false
	return pressed

func _unhandled_input(event: InputEvent) -> void:
	# 화면 왼쪽 절반만 조향을 받는다. 오른쪽은 버튼 영역이다.
	if event is InputEventScreenTouch:
		var width := float(get_viewport().get_visible_rect().size.x)
		if event.pressed:
			if event.position.x < width * 0.5 and _steer_touch == -1:
				_begin_touch(event.index, event.position.x, width)
		elif event.index == _steer_touch:
			_end_touch(event.index)
	elif event is InputEventScreenDrag and event.index == _steer_touch:
		_move_touch(event.index, event.position.x)

func _begin_touch(index: int, x: float, screen_width: float) -> void:
	_steer_touch = index
	_touch_origin_x = x
	_screen_width = screen_width
	_touch_steer = 0.0

func _move_touch(index: int, x: float) -> void:
	if index != _steer_touch:
		return
	_touch_steer = steer_from_touch(_touch_origin_x, x, _screen_width)

func _end_touch(index: int) -> void:
	if index != _steer_touch:
		return
	_steer_touch = -1
	_touch_steer = 0.0
```

- [ ] **Step 5: 테스트가 통과하는지 확인**

Run: `tests/game/run_game_tests.sh`
Expected: 세 씬 모두 `TEST_OK`, 종료 코드 0

- [ ] **Step 6: 커밋**

```bash
git add scripts/bus_input.gd tests/game/test_input.gd tests/game/test_input.tscn \
        tests/game/run_game_tests.sh project.godot
git commit -m "feat: PC 키보드와 터치를 합치는 입력 계층"
```

---

### Task 4: 버스 물리와 회전 반경

**Files:**
- Create: `scripts/bus.gd`
- Create: `tests/game/test_turn_radius.gd`, `tests/game/test_turn_radius.tscn`
- Modify: `tests/game/run_game_tests.sh` (씬 목록에 `test_turn_radius`)

**Interfaces:**
- Consumes: 없음 (축은 인자로 받는다)
- Produces:
  - `Bus` 는 `VehicleBody3D` 다. 노드를 만들면 `_ready()` 에서 바퀴·충돌체·차체 메쉬를 스스로 붙인다.
  - `apply_axes(steer_axis: float, throttle: float, brake_axis: float, reverse: bool, delta: float) -> void`
  - `respawn_to(point: Vector3, look_target: Vector3) -> void`
  - `static steer_limit(speed: float) -> float`
  - 상수 `MAX_STEERING`, `MAX_SPEED`, `ENGINE_FORCE`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_turn_radius.gd`:

```gdscript
extends TestCase
# 이 서브프로젝트의 핵심 숫자를 지킨다. 회전 반경이 실제 시내버스 수준이라야
# 급한 코너에서 후진이 필요해지고, 그 긴장이 게임의 재미다.
# 빈 평면 위에서 조향을 최대로 고정하고 저속으로 돌려 궤적의 반경을 잰다.

const RADIUS_MIN := 9.0
const RADIUS_MAX := 11.0
const SETTLE_SECONDS := 3.0    # 서스펜션이 가라앉고 속도가 붙을 때까지
const MEASURE_SECONDS := 25.0  # 저속으로 한 바퀴 이상 돌 시간

var bus: Bus
var elapsed := 0.0
var samples: Array[Vector3] = []
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

func _physics_process(delta: float) -> void:
	if done or bus == null:
		return
	elapsed += delta
	# 조향 최대(오른쪽), 저속 유지. 속도가 붙으면 속도 감응 조향이 각을 좁혀
	# 반경이 커지므로 천천히 돈다.
	var throttle := 1.0 if bus.linear_velocity.length() < 3.0 else 0.0
	bus.apply_axes(1.0, throttle, 0.0, false, delta)

	if elapsed > SETTLE_SECONDS:
		samples.append(bus.global_position)
	if elapsed > SETTLE_SECONDS + MEASURE_SECONDS:
		_measure()

func _measure() -> void:
	done = true
	ok(samples.size() > 100, "표본이 %d 개뿐이다" % samples.size())
	if samples.size() <= 100:
		finish()
		return

	# 원 궤적의 반경 = (x 폭 + z 폭) / 4. 한 바퀴를 다 돌지 않아도
	# 바운딩 박스가 원의 지름에 수렴하도록 충분히 돌린다.
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in samples:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var radius := ((max_x - min_x) + (max_z - min_z)) / 4.0
	print("회전 반경 %.2f m (x 폭 %.2f, z 폭 %.2f)"
		% [radius, max_x - min_x, max_z - min_z])
	ok(radius >= RADIUS_MIN and radius <= RADIUS_MAX,
		"회전 반경 %.2f m 가 %.0f–%.0f m 밖이다" % [radius, RADIUS_MIN, RADIUS_MAX])

	# 속도 감응 조향이 실제로 각을 좁히는지도 같이 본다.
	ok(Bus.steer_limit(0.0) > Bus.steer_limit(16.7),
		"속도가 올라도 조향각이 안 좁아진다")
	equal_approx(Bus.steer_limit(0.0), Bus.MAX_STEERING, 0.001,
		"정지 상태에서 최대 조향각을 다 못 쓴다")
	equal_approx(Bus.steer_limit(16.7), Bus.MAX_STEERING * 0.3, 0.001,
		"60 km/h 에서 조향각이 30% 가 아니다")

	finish()
```

`tests/game/test_turn_radius.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_turn_radius.gd" id="1"]

[node name="TestTurnRadius" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

`run_game_tests.sh` 씬 목록에 `test_turn_radius` 를 더한다.

Run: `tests/game/run_game_tests.sh test_turn_radius`
Expected: FAIL. `Bus` 미정의.

- [ ] **Step 3: bus.gd 를 쓴다**

`scripts/bus.gd`:

```gdscript
extends VehicleBody3D
class_name Bus
# 세미 리얼 12 t 시내버스. 축 세 개만 받아 물리로 번역한다.
#
# 아래 숫자 중 서스펜션과 engine_force 부호는 1번 서브프로젝트에서 실측으로
# 얻은 값이다. 하드웨어 특성처럼 다루고 추측으로 바꾸지 않는다.

const MASS := 12000.0
const ENGINE_FORCE := 30000.0
const BRAKE_FORCE := 40.0
const MAX_SPEED := 19.4                      # m/s, 70 km/h
const REVERSE_SPEED_LIMIT := MAX_SPEED * 0.3
# 회전 반경 9–11 m 를 내는 최대 조향각. 자전거 모델 R = L / tan(δ) 에
# 휠베이스 6.6 m 를 넣으면 δ 가 0.6–0.65 rad 이다. 반경이 기준이고 이 값은
# 그 기준을 맞추는 손잡이다 — test_turn_radius 가 지킨다.
const MAX_STEERING := 0.62
const STEER_RATE := 1.5                      # rad/s. 조향 변화 속도 상한
const STEER_SPEED_FULL := 16.7               # m/s, 60 km/h

var _respawn_transform := Transform3D()
var _respawn_pending := false

static func steer_limit(speed: float) -> float:
	"""속도 감응 조향. 정지에서 최대각, 60 km/h 에서 그 30%.

	안 좁히면 고속에서 조금만 밀어도 스핀한다.
	"""
	return MAX_STEERING * lerpf(1.0, 0.3, clampf(speed / STEER_SPEED_FULL, 0.0, 1.0))

func _ready() -> void:
	mass = MASS
	# 질량 중심을 바닥 근처로 내려 급회전 전복을 막는다. 충돌 상자 중심은
	# y=2.0 이지만 무게는 아래에 몰려 있어야 한다.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.5, 0.0)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 3.0, 11.0)
	shape.shape = box
	# 차체 밑면이 지면에 닿으면 바퀴가 일을 못 한다. 상자를 띄운다.
	shape.position = Vector3(0.0, 2.0, 0.0)
	add_child(shape)

	var body_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.5, 3.0, 11.0)
	body_mesh.mesh = mesh
	body_mesh.position = Vector3(0.0, 2.0, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.45, 0.85)
	body_mesh.material_override = material
	add_child(body_mesh)

	# [z 위치, x 위치, 조향 여부]. 앞바퀴가 조향, 뒷바퀴가 구동이다.
	for spec in [[-3.6, -1.1, true], [-3.6, 1.1, true],
				 [3.0, -1.1, false], [3.0, 1.1, false]]:
		var wheel := VehicleWheel3D.new()
		wheel.position = Vector3(spec[1], 0.2, spec[0])
		wheel.use_as_steering = spec[2]
		wheel.use_as_traction = not spec[2]
		wheel.wheel_radius = 0.5
		wheel.suspension_travel = 0.35
		# 12 t 은 기본값(바퀴당 6 kN, 4륜 합 24 kN)으로 주저앉는다. 무게가
		# 117 kN 이다. 아래 값은 1번에서 실측으로 맞춘 것이다.
		wheel.suspension_stiffness = 150.0
		wheel.suspension_max_force = 80000.0
		wheel.damping_compression = 3.7
		wheel.damping_relaxation = 6.1
		wheel.wheel_friction_slip = 3.5
		add_child(wheel)

func apply_axes(steer_axis: float, throttle_axis: float, brake_axis: float,
		reverse: bool, delta: float) -> void:
	var speed := linear_velocity.length()
	var limit := steer_limit(speed)
	# engine_force 가 음수일 때 전방(-Z)으로 가고, 그 상태에서는 steering
	# 부호도 뒤집혀 있다. 오른쪽(steer_axis > 0)으로 돌려면 steering 이
	# 음수여야 한다. 1번에서 이걸 모르고 커브마다 도로를 이탈했다.
	var target := clampf(-steer_axis, -1.0, 1.0) * limit
	steering = move_toward(steering, target, STEER_RATE * delta)

	if reverse:
		# 후진 중에는 제동 축이 뒤로 미는 구동이 된다. 가속 축은 입력 계층이
		# 이미 전진 복귀에 썼으므로 여기선 보지 않는다.
		engine_force = ENGINE_FORCE * brake_axis if speed < REVERSE_SPEED_LIMIT else 0.0
		brake = 0.0
		return

	engine_force = -ENGINE_FORCE * throttle_axis if speed < MAX_SPEED else 0.0
	brake = BRAKE_FORCE * brake_axis

func respawn_to(point: Vector3, look_target: Vector3) -> void:
	"""끼거나 뒤집혔을 때 경로 위로 되돌린다. 벌점은 없다 — 5번이 정한다."""
	var origin := point + Vector3.UP * 1.5
	var target := look_target + Vector3.UP * 1.5
	if origin.distance_to(target) < 0.01:
		target = origin - global_transform.basis.z
	_respawn_transform = Transform3D().looking_at(target - origin, Vector3.UP)
	_respawn_transform.origin = origin
	_respawn_pending = true

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# 강체의 transform 을 밖에서 직접 대입하면 물리 서버와 어긋난다.
	# 순간이동은 _integrate_forces 안에서 state 를 통해 해야 한다.
	if not _respawn_pending:
		return
	_respawn_pending = false
	state.transform = _respawn_transform
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	steering = 0.0
	engine_force = 0.0
	brake = 0.0
```

- [ ] **Step 4: 테스트가 통과하는지 확인**

Run: `tests/game/run_game_tests.sh test_turn_radius`
Expected: `회전 반경 N.NN m` 출력 후 `TEST_OK`

회전 반경이 9–11 m 밖이면 `MAX_STEERING` 을 조정한다. 반경이 크면 값을 **올리고**, 작으면 **내린다**(`R = L / tan(δ)`). 한 번에 0.02 씩 움직이며 다시 잰다. 조정한 값과 실측 반경을 `MAX_STEERING` 주석에 남긴다.

- [ ] **Step 5: 커밋**

```bash
git add scripts/bus.gd tests/game/test_turn_radius.gd \
        tests/game/test_turn_radius.tscn tests/game/run_game_tests.sh
git commit -m "feat: 세미 리얼 버스 물리와 회전 반경 테스트"
```

---

### Task 5: 내비 라인과 추격 카메라

**Files:**
- Create: `scripts/nav_line.gd`
- Create: `scripts/chase_camera.gd`
- Create: `tests/game/test_nav_line.gd`, `tests/game/test_nav_line.tscn`
- Modify: `tests/game/run_game_tests.sh` (씬 목록에 `test_nav_line`)

**Interfaces:**
- Consumes: `RouteData.route: PackedVector3Array`
- Produces:
  - `NavLine` 은 `MeshInstance3D` 다. `build(route: PackedVector3Array) -> void`
  - `ChaseCamera` 는 `Node3D` 다. `target: Node3D` 를 설정하면 `_physics_process` 에서 따라간다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`tests/game/test_nav_line.gd`:

```gdscript
extends TestCase
# 내비 라인이 지면 위 올바른 높이에, 올바른 폭으로, 빠짐없이 깔리는지 본다.

const WIDTH := 1.5
const HEIGHT := 0.05

func _ready() -> void:
	var line := NavLine.new()
	add_child(line)

	# 동쪽으로 100 m, 그다음 남쪽으로 100 m 꺾이는 경로
	var route := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 100.0),
	])
	line.build(route)

	ok(line.mesh != null, "메쉬가 만들어지지 않았다")
	if line.mesh == null:
		finish()
		return

	var arrays := line.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 구간 2개 × 삼각형 2개 × 정점 3개
	ok(vertices.size() == 12, "정점이 %d 개다(12 기대)" % vertices.size())

	for vertex in vertices:
		equal_approx(vertex.y, HEIGHT, 0.0001,
			"정점 높이가 %.3f 다" % vertex.y)

	# 첫 구간은 동쪽으로 뻗으므로 폭이 z 축으로 벌어져야 한다.
	var min_z := INF
	var max_z := -INF
	for i in range(6):
		min_z = minf(min_z, vertices[i].z)
		max_z = maxf(max_z, vertices[i].z)
	equal_approx(max_z - min_z, WIDTH, 0.001,
		"리본 폭이 %.3f m 다" % (max_z - min_z))

	# 길이 0 구간이 섞여도 죽지 않아야 한다(같은 점이 연달아 나오는 경우).
	var degenerate := PackedVector3Array([
		Vector3.ZERO, Vector3.ZERO, Vector3(10.0, 0.0, 0.0),
	])
	var line2 := NavLine.new()
	add_child(line2)
	line2.build(degenerate)
	var arrays2 = line2.mesh.surface_get_arrays(0)
	ok(arrays2[Mesh.ARRAY_VERTEX].size() == 6,
		"길이 0 구간을 건너뛰지 못했다")

	finish()
```

`tests/game/test_nav_line.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_nav_line.gd" id="1"]

[node name="TestNavLine" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

`run_game_tests.sh` 씬 목록에 `test_nav_line` 을 더한다.

Run: `tests/game/run_game_tests.sh test_nav_line`
Expected: FAIL. `NavLine` 미정의.

- [ ] **Step 3: nav_line.gd 를 쓴다**

`scripts/nav_line.gd`:

```gdscript
extends MeshInstance3D
class_name NavLine
# 노선 폴리라인을 지면 위 반투명 띠로 깐다. 실제 서울 지도 위에서 길을 잃지
# 않게 하는 최소 안내다. 정류장 마커는 3번 서브프로젝트 것이라 넣지 않는다.

const WIDTH := 1.5
const HEIGHT := 0.05   # 도로면(y=0)과 z-fighting 을 피하는 높이

func build(route: PackedVector3Array) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := WIDTH * 0.5
	for i in range(route.size() - 1):
		var start := route[i]
		var end := route[i + 1]
		var direction := Vector3(end.x - start.x, 0.0, end.z - start.z)
		if direction.length() < 0.01:
			continue   # 같은 점이 연달아 있으면 건너뛴다
		# 진행 방향의 수직 벡터. (x, z) 평면에서 90도 돌린 것.
		var side := Vector3(-direction.z, 0.0, direction.x).normalized() * half
		var a := Vector3(start.x + side.x, HEIGHT, start.z + side.z)
		var b := Vector3(start.x - side.x, HEIGHT, start.z - side.z)
		var c := Vector3(end.x - side.x, HEIGHT, end.z - side.z)
		var d := Vector3(end.x + side.x, HEIGHT, end.z + side.z)
		for vertex in [a, b, c, a, c, d]:
			surface.add_vertex(vertex)
	mesh = surface.commit()

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.55, 1.0, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 양면 렌더. 런타임 생성 메쉬의 앞면 방향을 따지느니 컬링을 끄는 게 싸다.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
```

- [ ] **Step 4: chase_camera.gd 를 쓴다**

`scripts/chase_camera.gd`:

```gdscript
extends Node3D
class_name ChaseCamera
# 버스 뒤를 지연 추종한다. 위치는 즉시 따라가고 방향만 늦게 따라와서
# 커브에서 차체가 먼저 돌아간다.
#
# SpringArm3D 를 쓰는 이유는 건물 관통을 알아서 막아주기 때문이다.
# 직접 레이캐스트를 짤 이유가 없다.

const ARM_LENGTH := 13.0
const ARM_PITCH_DEG := -20.0
const PIVOT_HEIGHT := 1.5
const YAW_LAG := 4.0      # 클수록 빨리 따라붙는다

var target: Node3D

var _arm: SpringArm3D

func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = ARM_LENGTH
	_arm.margin = 0.2
	_arm.rotation_degrees = Vector3(ARM_PITCH_DEG, 0.0, 0.0)
	add_child(_arm)
	var camera := Camera3D.new()
	camera.far = 2000.0
	camera.current = true
	_arm.add_child(camera)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = target.global_position + Vector3.UP * PIVOT_HEIGHT
	# lerp_angle 은 -PI..PI 를 감아 도는 최단 경로로 보간한다. 단순 lerp 를
	# 쓰면 요가 PI 를 넘는 순간 카메라가 한 바퀴 돈다.
	rotation.y = lerp_angle(rotation.y, target.global_rotation.y,
		clampf(YAW_LAG * delta, 0.0, 1.0))
```

- [ ] **Step 5: 테스트가 통과하는지 확인**

Run: `tests/game/run_game_tests.sh`
Expected: 다섯 씬 모두 `TEST_OK`

카메라는 헤드리스로 단언할 게 없다. 6번 태스크에서 창을 띄워 눈으로 확인한다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/nav_line.gd scripts/chase_camera.gd tests/game/test_nav_line.gd \
        tests/game/test_nav_line.tscn tests/game/run_game_tests.sh
git commit -m "feat: 내비 라인과 추격 카메라"
```

---

### Task 6: 주행 씬

**Files:**
- Create: `scripts/drive.gd`, `scenes/drive.tscn`
- Create: `tests/game/drive_smoke.gd`, `tests/game/drive_smoke.tscn`
- Modify: `tests/game/run_game_tests.sh` (씬 목록에 `drive_smoke`)

**Interfaces:**
- Consumes: `RouteData`, `City.load_city()`, `Bus.apply_axes()`, `Bus.respawn_to()`, `BusInput.poll()`, `BusInput.take_respawn()`, `NavLine.build()`, `ChaseCamera.target`
- Produces:
  - `Drive` 는 `Node3D` 다. 필드 `data: RouteData`, `bus: Bus`, `city: City`
  - `route_id_from_args() -> String` — `--route=<id>` 가 있으면 그것, 없으면 `RouteData.selected_id`

- [ ] **Step 1: drive.gd 를 쓴다**

`scripts/drive.gd`:

```gdscript
extends Node3D
class_name Drive
# 주행 씬 조립. 도시를 올리고, 버스를 노선 첫 점에 놓고, 카메라와 내비 라인을
# 붙인 다음, 매 프레임 입력을 버스에 먹인다.
#
# 종점에 도착해도 아무 일도 일어나지 않는다 — 완주 판정·시간·점수는 5번
# 서브프로젝트다.

var data: RouteData
var bus: Bus
var city: City
var input: BusInput
var camera: ChaseCamera

func _ready() -> void:
	var route_id := route_id_from_args()
	data = RouteData.load_route(route_id)
	if data == null:
		push_error("노선 데이터를 읽지 못했다: %s" % route_id)
		return

	city = City.new()
	add_child(city)
	if not city.load_city(route_id):
		return

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var nav := NavLine.new()
	nav.build(data.route)
	add_child(nav)

	bus = Bus.new()
	add_child(bus)
	_place_at_start()

	input = BusInput.new()
	add_child(input)

	camera = ChaseCamera.new()
	camera.target = bus
	add_child(camera)

func route_id_from_args() -> String:
	"""--route=<id> 가 있으면 그것, 없으면 메뉴가 고른 노선."""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			return argument.trim_prefix("--route=")
	return RouteData.selected_id

func _place_at_start() -> void:
	# 노선 첫 점에서 진행 방향을 보고 선다.
	bus.global_position = data.route[0] + Vector3.UP * 1.5
	bus.look_at_from_position(bus.global_position,
		data.route[1] + Vector3.UP * 1.5, Vector3.UP)

func _physics_process(delta: float) -> void:
	if bus == null or input == null:
		return
	input.poll(bus.linear_velocity.length())
	bus.apply_axes(input.steer, input.throttle, input.brake, input.reverse, delta)
	if input.take_respawn():
		respawn()

func respawn() -> void:
	"""가장 가까운 경로점으로 노선 방향을 보게 되돌린다."""
	var index := data.nearest_index(bus.global_position)
	var look_index: int = mini(index + 1, data.route.size() - 1)
	if look_index == index:
		look_index = maxi(index - 1, 0)
	bus.respawn_to(data.route[index], data.route[look_index])
```

`scenes/drive.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/drive.gd" id="1"]

[node name="Drive" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 2: 스모크 테스트를 쓴다**

`tests/game/drive_smoke.gd`:

```gdscript
extends TestCase
# 주행 씬이 조립되고 버스가 실제로 굴러가는지 본다. 1번의 자율주행 조향을
# 축 입력으로 옮겨 먹인다. 완주는 요구하지 않는다 — 최대 조향각이 0.62 rad 로
# 줄어 하핀은 1번보다 더 못 돈다. 경로점 사이 도로 연속성은 1번의
# tests/bake/verify.gd 가 2 m 간격 샘플링으로 이미 훨씬 촘촘하게 본다.

const ROUTE_ID := "seoul-100"
const DRIVE_MIN_M := 100.0
const TARGET_SPEED := 8.0
const LOOKAHEAD := 15.0
const STUCK_LIMIT := 5.0
const MIN_Y := -5.0

var drive: Drive
var driven := 0.0
var guide_index := 0
var stuck := 0.0
var done := false

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/drive.tscn")
	drive = scene.instantiate()
	add_child(drive)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# drive.gd 는 매 프레임 입력을 읽어 버스에 먹인다. 헤드리스에서는 입력이
	# 전부 0 이라, 그대로 두면 이 테스트가 넣는 축을 매 프레임 덮어쓴다.
	drive.set_physics_process(false)

	ok(drive.data != null, "노선 데이터가 없다")
	ok(drive.city != null and drive.city.chunk_nodes.size() > 0, "도시가 비었다")
	ok(drive.bus != null, "버스가 없다")
	ok(drive.camera != null, "카메라가 없다")
	if drive.data == null or drive.bus == null:
		done = true
		finish()

func _physics_process(delta: float) -> void:
	if done or drive == null or drive.bus == null or drive.data == null:
		return
	var bus := drive.bus
	if bus.global_position.y < MIN_Y:
		ok(false, "버스가 지면 아래로 떨어졌다")
		_report()
		return

	_advance_guide()
	var target := _lookahead_point(LOOKAHEAD)
	var local := bus.to_local(target)
	# 목표가 뒤쪽일 때도 방향을 잃지 않도록 부호 있는 헤딩 오차를 쓴다.
	var heading_error := atan2(local.x, -local.z)
	var steer := clampf(heading_error / Bus.MAX_STEERING, -1.0, 1.0)
	var speed := bus.linear_velocity.length()
	var throttle := 1.0 if speed < TARGET_SPEED else 0.0
	bus.apply_axes(steer, throttle, 0.0, false, delta)

	stuck = stuck + delta if speed < 0.5 else 0.0
	if driven >= DRIVE_MIN_M or stuck > STUCK_LIMIT:
		_report()

func _advance_guide() -> void:
	var route := drive.data.route
	while guide_index < route.size() - 2 and _segment_t() > 1.0:
		driven += route[guide_index].distance_to(route[guide_index + 1])
		guide_index += 1

func _segment_t() -> float:
	var route := drive.data.route
	var start: Vector3 = route[guide_index]
	var segment: Vector3 = route[guide_index + 1] - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return 2.0
	return (drive.bus.global_position - start).dot(segment) / length_squared

func _lookahead_point(distance: float) -> Vector3:
	var route := drive.data.route
	var start: Vector3 = route[guide_index]
	var segment: Vector3 = route[mini(guide_index + 1, route.size() - 1)] - start
	var current: Vector3 = start + segment * clampf(_segment_t(), 0.0, 1.0)
	var remaining := distance
	var index := guide_index
	while index < route.size() - 1:
		var next_point: Vector3 = route[index + 1]
		var length := current.distance_to(next_point)
		if length >= remaining:
			return current.lerp(next_point, remaining / maxf(length, 0.001))
		remaining -= length
		current = next_point
		index += 1
	return route[route.size() - 1]

func _report() -> void:
	done = true
	print("주행 %.0fm, 경로점 %d/%d" % [driven, guide_index, drive.data.route.size() - 1])
	ok(driven >= DRIVE_MIN_M, "주행 거리 %.0fm < %.0fm" % [driven, DRIVE_MIN_M])
	finish()
```

`tests/game/drive_smoke.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/drive_smoke.gd" id="1"]

[node name="DriveSmoke" type="Node3D"]
script = ExtResource("1")
```

`drive_smoke` 는 `RouteData.selected_id` 의 기본값 `"seoul-100"` 을 그대로 쓴다.

- [ ] **Step 3: 테스트가 실패하는지 확인**

`run_game_tests.sh` 씬 목록에 `drive_smoke` 를 더한다.

Run: `tests/game/run_game_tests.sh drive_smoke`
Expected: FAIL. `scenes/drive.tscn` 이 없거나 `Drive` 미정의.

- [ ] **Step 4: 테스트가 통과하는지 확인**

Run: `tests/game/run_game_tests.sh`
Expected: 여섯 씬 모두 `TEST_OK`

- [ ] **Step 5: 창을 띄워 눈으로 확인한다**

Run: `/opt/homebrew/bin/godot res://scenes/drive.tscn -- --route=seoul-seodaemun03`

확인할 것:

1. 카메라가 버스 **뒤**를 비춘다. 앞이 보이면 `chase_camera.gd` 의 `_arm.rotation_degrees` 에 `y = 180.0` 을 더한다.
2. 내비 라인이 도로 위에 파란 띠로 보인다.
3. `W`/`A`/`S`/`D` 로 몰 수 있다. `A` 가 왼쪽으로 꺾는다 — 반대면 `bus.gd` 의 `apply_axes` 에서 `-steer_axis` 의 부호를 뒤집는다.
4. 도로 밖으로 나가도 떨어지지 않는다.
5. `R` 이 버스를 경로 위로 되돌린다.
6. 정지 상태에서 `S` 를 길게 누르면 후진한다.

고친 게 있으면 `run_game_tests.sh` 를 다시 돌려 회귀가 없는지 본다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/drive.gd scenes/drive.tscn tests/game/drive_smoke.gd \
        tests/game/drive_smoke.tscn tests/game/run_game_tests.sh
git commit -m "feat: 주행 씬 조립과 스모크 테스트"
```

---

### Task 7: 노선 선택 메뉴와 터치 UI

**Files:**
- Create: `scripts/menu.gd`, `scenes/menu.tscn`
- Create: `scripts/touch_controls.gd`
- Modify: `scripts/drive.gd` (터치 UI 붙이기)
- Modify: `project.godot` (`run/main_scene`)

**Interfaces:**
- Consumes: `RouteData.list_route_ids()`, `RouteData.load_route()`, `RouteData.selected_id`, `BusInput` 의 `touch_throttle` / `touch_brake` / `touch_reverse_toggle` / `take_respawn`
- Produces:
  - `TouchControls` 는 `CanvasLayer` 다. `input: BusInput` 를 설정하면 버튼이 그 필드를 민다.

- [ ] **Step 1: menu.gd 를 쓴다**

`scripts/menu.gd`:

```gdscript
extends Control
class_name Menu
# 노선 선택. 목록을 하드코딩하지 않고 assets/routes 를 훑어서 만든다 —
# 노선을 더 구우면 메뉴가 알아서 늘어난다.
# 꾸미는 일은 7번 서브프로젝트(배포) 것이다. 여기서는 고를 수만 있으면 된다.

func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
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
		var button := Button.new()
		button.text = "%s\n%s → %s" % [data.display_name, data.from_name, data.to_name]
		button.custom_minimum_size = Vector2(360, 72)
		button.pressed.connect(_on_route_chosen.bind(route_id))
		box.add_child(button)

func _on_route_chosen(route_id: String) -> void:
	RouteData.selected_id = route_id
	get_tree().change_scene_to_file("res://scenes/drive.tscn")
```

`scenes/menu.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/menu.gd" id="1"]

[node name="Menu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

- [ ] **Step 2: touch_controls.gd 를 쓴다**

`scripts/touch_controls.gd`:

```gdscript
extends CanvasLayer
class_name TouchControls
# 화면 오른쪽 버튼들. 조향은 왼쪽 절반 드래그가 맡으므로 여기 없다.
# 버튼은 BusInput 의 필드를 밀기만 한다 — 입력 해석은 전부 BusInput 안에 있다.

var input: BusInput
var respawn_requested := false

func _ready() -> void:
	_add_button("가속", Vector2(-260, -200), Vector2(140, 140), _on_throttle)
	_add_button("제동", Vector2(-120, -200), Vector2(100, 140), _on_brake)
	_add_button("후진", Vector2(-260, -60), Vector2(120, 48), _on_reverse)
	_add_button("복귀", Vector2(-130, -60), Vector2(120, 48), _on_respawn)

func _add_button(text: String, offset: Vector2, size: Vector2,
		handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	# 오른쪽 아래 기준으로 배치한다. 화면 크기가 달라도 버튼이 따라간다.
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = offset.x
	button.offset_top = offset.y
	button.offset_right = offset.x + size.x
	button.offset_bottom = offset.y + size.y
	button.button_down.connect(handler.bind(true))
	button.button_up.connect(handler.bind(false))
	add_child(button)

func _on_throttle(pressed: bool) -> void:
	if input != null:
		input.touch_throttle = pressed

func _on_brake(pressed: bool) -> void:
	if input != null:
		input.touch_brake = pressed

func _on_reverse(pressed: bool) -> void:
	# 토글은 누를 때 한 번만 반응한다. BusInput.poll 이 플래그를 소비한다.
	if pressed and input != null:
		input.touch_reverse_toggle = true

func _on_respawn(pressed: bool) -> void:
	if pressed:
		respawn_requested = true
```

- [ ] **Step 3: drive.gd 에 터치 UI 를 붙인다**

`scripts/drive.gd` 의 `_ready()` 끝, `camera` 를 붙인 뒤에 더한다:

```gdscript
	touch = TouchControls.new()
	touch.input = input
	add_child(touch)
```

필드 선언에 더한다:

```gdscript
var touch: TouchControls
```

`_physics_process` 의 리스폰 처리를 터치도 받도록 바꾼다:

```gdscript
	var respawn_asked := input.take_respawn()
	if touch != null and touch.respawn_requested:
		touch.respawn_requested = false
		respawn_asked = true
	if respawn_asked:
		respawn()
```

- [ ] **Step 4: 시작 씬을 바꾼다**

`project.godot` 의 `run/main_scene` 을 `"res://tests/bake/verify.tscn"` 에서 `"res://scenes/menu.tscn"` 으로 바꾼다.

1번의 검증 하네스는 씬 경로를 직접 주고 돌리므로(`tests/bake/run_verify.sh` 가 `--route=` 와 함께 `--headless` 로 띄운다) 영향이 없다 — 다만 그 스크립트는 `main_scene` 에 의존하므로, 같은 커밋에서 `tests/bake/run_verify.sh` 의 Godot 호출에 씬 경로 `res://tests/bake/verify.tscn` 를 인자로 더한다:

```bash
	if "$GODOT_BIN" --headless --fixed-fps 60 --quit-after 400000 \
			res://tests/bake/verify.tscn -- --route="$route"; then
```

- [ ] **Step 5: 확인한다**

Run: `tests/game/run_game_tests.sh`
Expected: 여섯 씬 모두 `TEST_OK`

Run: `tests/bake/run_verify.sh seoul-seodaemun03`
Expected: `VERIFY_OK`, `seoul-seodaemun03: OK` — 1번 검증이 깨지지 않았다

Run: `/opt/homebrew/bin/godot`
Expected: 노선 버튼 3개가 뜨고, 누르면 그 노선 주행 씬이 뜬다. 오른쪽 아래에 터치 버튼 4개가 보이고, 마우스로 눌러 가속·제동·후진·복귀가 동작한다(마우스→터치 에뮬레이션). 화면 왼쪽 절반을 마우스로 끌면 조향이 먹는다.

- [ ] **Step 6: 커밋**

```bash
git add scripts/menu.gd scenes/menu.tscn scripts/touch_controls.gd \
        scripts/drive.gd project.godot tests/bake/run_verify.sh
git commit -m "feat: 노선 선택 메뉴와 터치 컨트롤"
```

---

### Task 8: 성능 측정과 조작감 튜닝

**Files:**
- Create: `tests/game/measure_fps.gd`, `tests/game/measure_fps.tscn`
- Modify: `README.md` (실행·테스트 방법)
- Modify: `scripts/bus.gd` 또는 `scripts/chase_camera.gd` (튜닝 결과가 요구하면)

**Interfaces:**
- Consumes: `scenes/drive.tscn`, `Bus`, `Drive`
- Produces: 측정 결과. 기준 미달이면 `city.gd` 에 청크 거리 컬링을 넣는다.

- [ ] **Step 1: 측정 씬을 쓴다**

`tests/game/measure_fps.gd`:

```gdscript
extends Node3D
# 창 모드 전용 성능 측정. 헤드리스는 렌더링을 안 하므로 의미가 없다.
#   godot res://tests/game/measure_fps.tscn -- --route=seoul-100
# seoul-100 을 자율주행으로 달리며 프레임을 기록한다. 판정은 사람이 본다.

const WARMUP_SECONDS := 3.0      # 셰이더 컴파일과 첫 프레임 튐을 버린다
const MEASURE_SECONDS := 30.0
const TARGET_SPEED := 12.0
const LOOKAHEAD := 15.0

var drive: Drive
var elapsed := 0.0
var samples: Array[float] = []
var guide_index := 0
var done := false

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/drive.tscn")
	drive = scene.instantiate()
	add_child(drive)
	await get_tree().physics_frame
	# 자율주행으로 몰 것이므로 drive.gd 의 입력 처리를 끈다.
	drive.set_physics_process(false)

func _physics_process(delta: float) -> void:
	if done or drive == null or drive.bus == null or drive.data == null:
		return
	elapsed += delta

	var bus := drive.bus
	_advance_guide()
	var local := bus.to_local(_lookahead_point(LOOKAHEAD))
	var steer := clampf(atan2(local.x, -local.z) / Bus.MAX_STEERING, -1.0, 1.0)
	var throttle := 1.0 if bus.linear_velocity.length() < TARGET_SPEED else 0.0
	bus.apply_axes(steer, throttle, 0.0, false, delta)

	if elapsed > WARMUP_SECONDS:
		samples.append(float(Engine.get_frames_per_second()))
	if elapsed > WARMUP_SECONDS + MEASURE_SECONDS:
		_report()

func _advance_guide() -> void:
	var route := drive.data.route
	while guide_index < route.size() - 2 and _segment_t() > 1.0:
		guide_index += 1

func _segment_t() -> float:
	var route := drive.data.route
	var start: Vector3 = route[guide_index]
	var segment: Vector3 = route[guide_index + 1] - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return 2.0
	return (drive.bus.global_position - start).dot(segment) / length_squared

func _lookahead_point(distance: float) -> Vector3:
	var route := drive.data.route
	var start: Vector3 = route[guide_index]
	var segment: Vector3 = route[mini(guide_index + 1, route.size() - 1)] - start
	var current: Vector3 = start + segment * clampf(_segment_t(), 0.0, 1.0)
	var remaining := distance
	var index := guide_index
	while index < route.size() - 1:
		var next_point: Vector3 = route[index + 1]
		var length := current.distance_to(next_point)
		if length >= remaining:
			return current.lerp(next_point, remaining / maxf(length, 0.001))
		remaining -= length
		current = next_point
		index += 1
	return route[route.size() - 1]

func _report() -> void:
	done = true
	var total := 0.0
	var lowest := INF
	for sample in samples:
		total += sample
		lowest = minf(lowest, sample)
	var average := total / maxf(float(samples.size()), 1.0)
	print("fps 평균 %.1f, 최저 %.1f (표본 %d)" % [average, lowest, samples.size()])
	get_tree().quit(0)
```

`tests/game/measure_fps.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/measure_fps.gd" id="1"]

[node name="MeasureFps" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 2: 측정한다**

Run: `/opt/homebrew/bin/godot res://tests/game/measure_fps.tscn -- --route=seoul-100`

기준: **평균 60 fps 이상, 최저 55 이상**.

- 통과하면 청크 거리 컬링을 **구현하지 않는다**. 측정값을 `city.gd` 의 `chunk_nodes` 주석에 남긴다.
- 미달이면 `scripts/city.gd` 에 아래를 더하고 다시 잰다. `RouteData.chunks` 의 AABB 가 이미 JSON 에 들어 있으므로 거리 계산은 공짜다.

```gdscript
const CULL_DISTANCE := 600.0   # m. 이보다 먼 청크는 끈다

var _chunk_centers: PackedVector3Array = []

func set_chunk_bounds(chunks: Array) -> void:
	"""RouteData.chunks 의 AABB 중심을 받아 거리 컬링 준비를 한다."""
	_chunk_centers.resize(0)
	for node in chunk_nodes:
		var center := node.get_aabb().get_center()
		_chunk_centers.append(node.global_transform * center)

func cull_from(point: Vector3) -> void:
	for i in range(chunk_nodes.size()):
		chunk_nodes[i].visible = \
			_chunk_centers[i].distance_to(point) < CULL_DISTANCE
```

그리고 `drive.gd` 의 `_physics_process` 에서 `city.cull_from(bus.global_position)` 를 부른다. 매 프레임 643개를 도는 선형 스캔이라, 그래도 모자라면 프레임당 1/4 씩 나눠 돈다.

- [ ] **Step 3: 몰아보고 조작감을 조정한다**

Run: `/opt/homebrew/bin/godot`

메뉴에서 노선을 고르고 직접 몬다. 조작감은 자동으로 잴 방법이 없으므로 여기서만 판단한다. 조정 대상과 손잡이:

| 증상 | 손잡이 |
|---|---|
| 가속이 답답하다 / 너무 급하다 | `bus.gd` 의 `ENGINE_FORCE` |
| 잘 안 선다 | `bus.gd` 의 `BRAKE_FORCE` |
| 핸들이 굼뜨다 / 홱 돈다 | `bus.gd` 의 `STEER_RATE` |
| 고속에서 불안하다 | `bus.gd` 의 `STEER_SPEED_FULL` |
| 카메라가 멀미난다 / 너무 뻣뻣하다 | `chase_camera.gd` 의 `YAW_LAG` |
| 카메라가 너무 멀다 / 가깝다 | `chase_camera.gd` 의 `ARM_LENGTH` |

`MAX_STEERING` 은 건드리지 않는다 — 회전 반경 9–11 m 가 spec 의 요구고 `test_turn_radius` 가 지킨다.

조정했으면 `tests/game/run_game_tests.sh` 를 다시 돌린다.

- [ ] **Step 4: README 를 갱신한다**

`README.md` 에 아래 절을 더한다:

```markdown
## 게임 실행

    godot

노선을 고르면 주행 씬이 뜬다. 조작은 `W` 가속, `S` 제동(정지 상태에서 길게
누르면 후진), `A`/`D` 조향, `R` 리스폰이다.

## 게임 테스트

    tests/game/run_game_tests.sh

헤드리스로 노선 데이터·도시 로딩·입력 매핑·회전 반경·내비 라인·주행 스모크를
검사한다. 성능은 창이 필요해서 따로 잰다:

    godot res://tests/game/measure_fps.tscn -- --route=seoul-100
```

- [ ] **Step 5: 전체 검증**

Run: `run_tests.sh`
Expected: `OK` (1번의 파이썬 테스트 114개)

Run: `tests/game/run_game_tests.sh`
Expected: 여섯 씬 모두 `TEST_OK`

Run: `tests/bake/run_verify.sh seoul-seodaemun03`
Expected: `VERIFY_OK`

- [ ] **Step 6: 커밋**

```bash
git add tests/game/measure_fps.gd tests/game/measure_fps.tscn README.md \
        scripts/bus.gd scripts/chase_camera.gd scripts/city.gd
git commit -m "feat: 성능 측정 씬과 조작감 튜닝"
```

---

## 완료 확인

spec 의 완료 기준과 대응:

| 기준 | 어디서 지켜지나 |
|---|---|
| 1. 메뉴에서 노선 3개 선택 | Task 7, 눈으로 확인 |
| 2. 키보드로 몰 수 있다 | Task 6 Step 5, 눈으로 확인 |
| 3. 회전 반경 9–11 m | Task 4, `test_turn_radius` 자동 |
| 4. seoul-100 평균 60 / 최저 55 fps | Task 8 Step 2, 측정 |
| 5. 도로 밖에서 안 떨어진다, 리스폰 동작 | Task 2 `test_city` 자동 + Task 6 Step 5 눈으로 |
| 6. 터치 입력이 에뮬레이션에서 동작 | Task 3 `test_input` 자동 + Task 7 Step 5 눈으로 |
| 7. 헤드리스 테스트 전부 통과 | Task 8 Step 5 |
