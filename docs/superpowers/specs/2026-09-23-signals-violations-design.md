# 신호·위반 설계

작성일: 2026-09-23
서브프로젝트: 4 / 7 (교차로 신호등, 신호위반 판정, 단속)

## 배경

1번(OSM 베이크)과 2번(버스 물리·입력)이 끝나 `main` 에 병합돼 있다. 서울 3개
노선이 구워져 있고, 사람이 버스를 몰아 노선을 달릴 수 있다. 도로에는 차선 도색과
인도·연석까지 들어갔다.

지금 도시에는 신호가 없다. 교차로를 아무 때나 통과할 수 있어서, 이 게임의 핵심
저울질인 "정시성 대 안전운전"이 성립하지 않는다. 이 문서는 교차로에 신호를
세우고, 신호위반을 판정하고, 단속 카메라와 순찰 경찰차로 위반에 결과를 붙이는
일을 다룬다.

전체 분해에서 이 문서의 자리:

1. OSM 베이크 파이프라인 — 완료
2. 버스 물리 + 입력 — 완료
3. 정류장·승객 시스템 — 미착수
4. **신호·위반 시스템** ← 이 문서
5. 시간표·점수·종착 판정
6. 교통 AI / 단속
7. 노선 선택 메뉴, 3개 노선 굽기, 배포

3번보다 4번을 먼저 하는 이유는 6번(교통 AI)이 신호 데이터 위에 얹히기 때문이다.
일반 차량이 신호를 지키려면 신호가 먼저 있어야 한다.

## 목표와 비목표

**목표**

- 실제 서울 간선도로와 비슷한 밀도로 교차로에 신호등을 세운다.
- 신호 상태를 시간의 순수 함수로 만들어 저장 상태 없이 결정적으로 재현한다.
- 적색에 정지선을 넘으면 위반으로 판정한다.
- 단속 카메라 교차로를 **미리 보이게** 표시한다. 알고 거는 도박이라야 저울질이
  된다.
- 순찰 경찰차 앞에서의 위반은 즉시 게임 오버.
- 위반 횟수를 화면에 표시하고, 5번 서브프로젝트가 읽어갈 인터페이스를 낸다.

**비목표**

- 시간 페널티·벌점·점수 계산(5번). 기준 시간이 아직 없어 지금 숫자를 정하면
  5번에서 다시 정하게 된다.
- 일반 교통 차량, 충돌 회피, 차량 간 상호작용(6번). 경찰차는 경로 추종
  키네마틱 2대까지만이고 이 문서의 범위다.
- 과속 단속. OSM 에 남아 있는 것은 과속 카메라뿐이지만 제한속도 체계가 없다.
- 꼬리물기(교차로 내 정지) 판정. 6번에서 막히는 상황이 생긴 뒤에 얹는다.
- 보행자, 우회전 전용 신호, 비보호 좌회전, 좌회전 화살표 신호.

## 조사 결과: OSM 태그는 쓸 수 없다

1번 스파이크에서 이미 확인한 대로 `highway=traffic_signals` 노드는 밀집 도심
3 km 구간에 6개뿐이다. 이번에 단속 데이터도 같은 방식으로 확인했다.

서울 북부 전역(위도 37.51677~37.64920, 경도 126.96139~127.07536)을 Overpass 로
조회한 결과:

```
node["highway"="speed_camera"]  + node["enforcement"] + relation[type=enforcement]
→ 총 13개
```

13개 전부 `maxspeed` 가 붙은 **과속** 카메라이고, 신호위반 단속 카메라는 0개다.
따라서 신호와 마찬가지로 단속 카메라도 **합성해야 한다.**

이 조사는 재현 가능하지만 산출물에 남지 않는다. 베이크는 OSM 단속 데이터를
조회하지 않는다.

## 신호 밀도 결정

`corridor.signal_candidates` 는 현재 OSM 태그 노드와 "주요도로 3갈래 이상"
교차점을 모두 낸다. 노선 15 m 이내 후보를 갈래 수로 분해하면(seoul-100, 24.1 km):

| 필터 | 개수 | 평균 간격 |
|---|---|---|
| OSM 태그(`roads: 0`)만 | 37 | 652 m |
| OSM 태그 + 4갈래 이상 | 93 | 259 m |
| 전부 (3갈래 포함) | 140 | 172 m |

실제 서울 간선도로의 신호 간격은 300~500 m 다. 3갈래까지 모두 신호로 만들면
172 m 마다 멈추게 되어 주행이 답답해지고, OSM 태그만 쓰면 652 m 로 너무 뻥
뚫린다.

**결정: OSM 태그 + 4갈래 이상.** 3갈래(T자) 교차점은 무신호로 통과한다.

## 데이터 계약 변경

`route_<id>.json` 의 `signals` 배열 항목에 필드를 추가한다. 기존 필드
(`x`, `z`, `source`, `roads`)는 그대로 둔다.

```json
{
  "x": -1857.29,
  "z": 789.43,
  "source": "synthesized",
  "roads": 4,
  "axis_deg": [12.4, 103.8],
  "half_width": 10.0,
  "camera": true
}
```

- `axis_deg`: 교차로의 두 축 방위각(도, 북쪽 0, 동쪽 90 — OSM 관례와 같다).
  갈래들의 방위각을 180° 로 모듈로 한 뒤 두 군집으로 나눈 대표각이다. 버스가
  어느 축에 있는지 판정하는 데 쓴다. `axis_deg[0]` 이 최빈 방위, `axis_deg[1]`
  은 그것에 가장 수직인 갈래의 방위다. 갈래가 한 축뿐이면(있을 수 없지만 방어)
  `axis_deg[1] = axis_deg[0] + 90` 으로 채운다.
- `half_width`: 이 교차로에서 가장 넓은 갈래 도로 폭의 절반(m). 정지선 위치를
  잡는 데 쓴다. `mesh.road_width(tags)` 가 이미 계산하는 값이다.
- `camera`: 신호위반 단속 카메라 설치 여부.

`source: "osm"` 항목도 같은 필드를 채운다. OSM 신호 노드가 그래프 노드와
일치하면 그 노드의 갈래에서 축을 뽑고, 일치하지 않으면 가장 가까운 그래프
노드의 갈래를 쓴다.

## 아키텍처

```
베이크 (Python, 오프라인)
  corridor.signal_candidates
    ├ 필터: OSM 태그 + 4갈래 이상
    ├ axis_deg  ← 갈래 방위각 2군집
    ├ half_width ← mesh.road_width 최대값
    └ camera    ← 좌표 해시 상위 30%
                                  │
                        route_<id>.json  "signals"
                                  │
런타임 (Godot)                     ▼
  RouteData.signals  (route_data.gd 가 파싱)
        │
        ├── TrafficSignal   (traffic_signal.gd)  신호 위상 순수 함수
        ├── SignalField     (signal_field.gd)    기둥·등 생성, 근거리만 갱신
        ├── ViolationWatch  (violation_watch.gd) 정지선 통과 판정
        ├── PatrolCars      (patrol_cars.gd)     경로 순회 경찰차 2대
        └── ViolationHud    (violation_hud.gd)   횟수·플래시·게임 오버
                    ▲
                    └─ Drive (drive.gd) 가 조립하고 배선한다
```

단위별 책임:

- `traffic_signal.gd` — 상태 없음. 좌표와 시각에서 위상을 계산하는 static 함수
  모음. 다른 어떤 노드에도 의존하지 않는다.
- `signal_field.gd` — 보이는 것만 담당한다. 판정은 하지 않는다.
- `violation_watch.gd` — 판정만 담당한다. 화면에 아무것도 그리지 않는다.
  `violation(index: int, by_camera: bool)` 시그널을 낸다.
- `patrol_cars.gd` — 경찰차 위치만 담당한다. `sees(point: Vector3) -> bool` 를
  낸다.
- `violation_hud.gd` — 표시만 담당한다. 시그널을 받아 그린다.

## 신호 위상

`scripts/traffic_signal.gd`:

```gdscript
extends RefCounted
class_name TrafficSignal

enum Phase { GREEN, YELLOW, RED }

const GREEN_S := 30.0
const YELLOW_S := 3.0
const CYCLE_S := 66.0        # (GREEN + YELLOW) * 2

static func offset_for(x: float, z: float) -> float
static func phase_at(offset_s: float, axis_index: int, t: float) -> Phase
static func axis_for(heading_deg: float, axis_deg: Array) -> int
```

- 축 0 의 위상 기준 시각은 `t + offset_s`, 축 1 은 거기에 `CYCLE_S / 2` 를
  더한다. 따라서 한 축이 녹/황일 때 다른 축은 반드시 적색이다.
- `GREEN 30s → YELLOW 3s → RED 33s` 가 한 주기다. 두 축 합이 정확히 `CYCLE_S`
  가 되어야 겹침이 생기지 않는다.
- `offset_for` 는 좌표를 정수로 양자화해 해시한 뒤 `CYCLE_S` 로 나눈 나머지다.
  교차로마다 위상이 흩어져 전 도시가 동시에 바뀌는 일이 없고, 같은 노선을 다시
  달리면 같은 신호를 만난다.
- `axis_for` 는 버스 진행 방위를 180° 모듈로한 뒤 두 축 중 가까운 쪽의 인덱스를
  낸다. 180° 모듈로이므로 역주행해도 같은 축으로 판정된다.

상태를 노드에 들지 않으므로 신호 93개가 있어도 갱신 비용이 색칠뿐이다. 테스트도
시각을 넣고 위상을 받는 것으로 끝난다.

## 신호등 외형

한 교차로에는 진입 방향이 네 개다(축 2개 × 각 축의 양방향). 진입 방향마다
기둥을 하나씩 세우므로 신호당 기둥 4개, seoul-100 기준 93 × 4 = 372개다.

- 위치: 진입 방향 단위벡터를 `d` 라 할 때, 교차로 중심에서 `-d` 로
  `half_width + 2.0` m (정지선 자리), 그 지점에서 `d` 를 기준으로 오른쪽
  `half_width - 1.0` m. 높이 5.5 m. 기둥이 바라보는 방향은 `-d` — 진입하는
  차를 마주본다.
- 구성: 기둥(`CylinderMesh`) + 등판(`BoxMesh`) + 등 3개(`SphereMesh`, 반지름
  0.25 m).
- 머티리얼은 6개(적/황/녹 × 켜짐/꺼짐)를 미리 만들어 모든 등이 공유한다. 등마다
  새 `StandardMaterial3D` 를 만들면 372 × 3 = 1116개가 된다. 색을 바꾸는 것은
  `set_surface_override_material` 로 공유 머티리얼을 바꿔 끼우는 것뿐이다.
- 충돌면을 붙이지 않는다. 기둥이 인도 위에 서므로 물리적으로 부딪힐 일이 거의
  없고, 붙이면 StaticBody3D 가 372개 늘어난다.
- 같은 축의 두 기둥은 항상 같은 위상을 보인다. 위상은 축 인덱스로만 정해지고
  진입 방향과는 무관하다.

**단속 카메라 표시.** `camera: true` 인 교차로는 기둥 위에 흰 박스
(`BoxMesh`, 0.5 × 0.3 × 0.8 m)를 얹고, 그 아래에 붉은 표지판
(`QuadMesh` 1.2 × 0.6 m)을 단다. 실제 한국 도로에도 "신호위반 단속중" 표지가
있어서 운전자가 미리 안다. 이게 게임적으로 중요하다 — 모르고 걸리는 것이 아니라
알고 거는 도박이라야 저울질이 성립한다.

**갱신 범위.** `_physics_process` 에서 버스 반경 200 m 안의 신호만 색을 갱신한다.
반경 밖 신호는 어차피 보이지 않는다. 공간 색인은 정류장·신호가 정적이므로
64 m 격자 사전 하나로 충분하다 (`mesh._road_index` 와 같은 패턴).

## 위반 판정

`scripts/violation_watch.gd` 가 매 물리 프레임에 다음을 한다.

1. 버스 반경 60 m 안의 신호만 본다(같은 격자 색인 재사용).
2. 각 후보에 대해 버스 진행 방위로 `TrafficSignal.axis_for` 를 불러 축을 고른다.
3. **정지선까지의 부호 거리**를 구한다. 정지선은 교차로 중심에서 버스 쪽으로
   `half_width + 2.0` m 떨어진, 축에 수직인 직선이다. 부호 거리는 버스에서
   교차로 중심으로 가는 방향을 양으로 잡는다.
4. 직전 프레임의 부호 거리가 양수이고 이번 프레임이 0 이하이면 **진입**이다.
5. 진입 순간 `phase_at` 가 `RED` 면 위반 1회.

황색 진입은 위반이 아니다. 황색 3초에 안전하게 정지할 수 있는 거리가 아니면
억울하고, 실제 단속도 이렇게 하지 않는다.

교차로마다 직전 프레임 부호 거리를 들고 있어야 하므로 `Dictionary[int, float]`
하나를 유지한다. 반경 60 m 를 벗어나면 항목을 지운다.

판정 결과:

```gdscript
signal violation(index: int, by_camera: bool)
var violations := 0
var camera_violations := 0
```

`by_camera` 는 그 교차로의 `camera` 필드다. 5번 서브프로젝트가 이 둘을 읽어
점수를 계산한다.

## 단속

**단속 카메라.** 위반이 카메라 교차로에서 일어나면 `camera_violations` 가
올라가고 주행은 계속된다. 현실에서 카메라는 과태료이지 현장 제지가 아니다.
과태료의 구체적 대가는 5번이 정한다.

**순찰 경찰차.** `scripts/patrol_cars.gd` 가 노선 경로를 순회하는 차량 2대를
만든다.

- 물리 없음. `Node3D` 에 차체 박스 메쉬와 경광등만 붙이고, 매 프레임 경로
  위 누적거리를 `PATROL_SPEED_MPS := 11.0` (약 40 km/h)만큼 전진시킨다.
- 2대는 경로의 1/4 지점과 3/4 지점에서 서로 반대 방향으로 출발한다. 끝에
  닿으면 방향을 뒤집는다.
- `sees(point: Vector3) -> bool`: 경찰차에서 `point` 까지 거리가
  `PATROL_SIGHT_M := 80.0` 이하이고, 경찰차 전방 반구 안(내적 > 0)이면 참.

위반 순간 어느 경찰차든 버스를 보고 있으면 **게임 오버**다. 입력을 끊고
오버레이를 띄우고 `R` 로 재시작한다.

경찰차는 충돌하지 않으므로 버스가 통과해 지나간다. 6번에서 실제 차량이
들어오면 그때 물리를 붙인다. 지금 붙이면 버스가 경찰차를 들이받아 게임이
멈추는 쪽이 더 나쁘다.

## HUD

`scripts/violation_hud.gd` (`CanvasLayer`):

- 좌상단 `Label`: `위반 3회 (카메라 1회)`. 위반이 0이면 표시하지 않는다.
- 위반 순간 화면 가장자리에 붉은 `ColorRect` 를 0.4초 동안 페이드아웃한다.
- 게임 오버 시 화면 중앙에 반투명 패널: `단속 적발 — 주행 종료` 와
  `R: 다시 시작`.

2번에서 만든 터치 컨트롤과 겹치지 않도록 좌상단만 쓴다.

## 배선

`drive.gd` 의 `_ready` 마지막에 붙인다.

```gdscript
var signal_field := SignalField.new()
signal_field.build(data.signals)
signal_field.target = bus
add_child(signal_field)

var patrol := PatrolCars.new()
patrol.build(data.route)
add_child(patrol)

var watch := ViolationWatch.new()
watch.build(data.signals)
watch.bus = bus
watch.patrol = patrol
add_child(watch)

var hud := ViolationHud.new()
watch.violation.connect(hud.on_violation)
watch.busted.connect(hud.on_busted)
add_child(hud)
```

`route_data.gd` 에 `var signals: Array = []` 를 추가하고
`data.signals = parsed.get("signals", [])` 로 채운다. 키 이름을 아는 유일한
지점이라는 기존 규칙을 유지한다.

게임 오버 시 `drive.gd` 의 `_physics_process` 가 입력을 버스에 먹이지 않도록
`watch.busted` 를 보고 있다가 조향·가속을 0으로 넘긴다. 브레이크는 계속 걸어
버스를 세운다.

## 오류 처리

- `signals` 가 비었거나 키가 없으면 모든 노드가 조용히 아무것도 하지 않는다.
  구 버전 `route_<id>.json` 으로도 주행은 된다.
- `axis_deg` 가 없는 항목은 건너뛴다. 재베이크 전 산출물로 게임이 죽지 않아야
  한다.
- 경로점이 2개 미만이면 경찰차를 만들지 않는다.

## 테스트

**Python (`tests/osmbake/`)**

`test_corridor.py` 에 추가:

- 4갈래 미만 교차점이 후보에서 빠진다.
- OSM 태그 노드는 갈래 수와 무관하게 남는다.
- 십자 교차로에서 `axis_deg` 두 값의 차이가 90° ± 15° 안에 든다.
- 비스듬한 교차로(갈래 4개, 30°/120°)에서 두 군집이 올바르게 갈린다.
- `camera` 가 좌표만으로 결정된다 — 같은 입력에 같은 결과.
- `camera` 비율이 후보 100개 표본에서 20~40% 안에 든다.
- `half_width` 가 가장 넓은 갈래의 `road_width / 2` 와 같다.

**Godot (`tests/game/`)**

새 `test_traffic_signal.tscn`:

- `phase_at` 경계: `t = 0` 녹, `t = 29.9` 녹, `t = 30.1` 황, `t = 33.1` 적,
  `t = 65.9` 적, `t = 66.1` 녹.
- 같은 시각에 축 0 이 녹/황이면 축 1 은 반드시 적.
- `axis_for`: 방위 10°, 190° 가 모두 축 `[12, 102]` 의 0번.
- `offset_for` 가 `[0, CYCLE_S)` 안이고 결정적이다.

새 `test_violation.tscn`:

- 합성 신호 하나를 놓고 버스를 적색에 통과시키면 `violations == 1`.
- 같은 위치를 녹색에 통과시키면 `violations == 0`.
- 황색 통과는 `violations == 0`.
- 한 번 통과에 위반이 두 번 세어지지 않는다(프레임 중복 방지).
- `camera: true` 교차로 위반이면 `camera_violations == 1`.
- 경찰차를 위반 지점 50 m 앞에 두면 `busted == true`, 200 m 밖이면 거짓.
- 경찰차 뒤쪽 50 m 에서의 위반은 `busted == false`.

기존 `drive_smoke.gd` 에 추가:

- 신호 기둥 노드가 신호 개수 × 4 만큼 생성됐다.
- 버스 근처에서 `SignalField` 가 갱신한 기둥 수가 전체 기둥 수보다 작다
  (근거리 컬링이 실제로 동작한다).

**회귀**

- 3개 노선 전부 `VERIFY_OK` (신호 기둥이 주행을 막지 않는다).
- seoul-100 fps 평균 60 / 최저 55 이상. 현재 평균 119.7 이라 여유가 크지만,
  신호 기둥 93 × 2 × 5 메쉬가 붙으므로 다시 잰다.

## 구현 순서

1. 베이크: 필터 좁히기 + `axis_deg` + `half_width` + `camera`, Python 테스트.
2. 3개 노선 재베이크, 산출물 커밋.
3. `traffic_signal.gd` 순수 함수 + Godot 테스트.
4. `route_data.gd` 에 `signals` 파싱.
5. `signal_field.gd` 기둥·등 생성과 근거리 갱신.
6. `violation_watch.gd` 판정 + 테스트.
7. `patrol_cars.gd` 순찰 + 시야 판정.
8. `violation_hud.gd` 표시와 게임 오버, `drive.gd` 배선.
9. 회귀: 3개 노선 검증, fps 재측정.

## 열린 문제

- 신호 주기 30/3/33 은 추정치다. 실제로 몰아 보고 "기다리기 답답한가"로
  조정한다. 상수 하나라 바꾸기 싸다.
- 카메라 비율 30% 도 추정치다. 서울 신호교차로 수 대비 무인단속장비 수에서
  잡았다.
- 신호 기둥 372개 × 5 메쉬 = 1860 메쉬가 늘어난다. 현재 fps 여유가 커서 그대로
  간다고 보지만, 측정에서 기준을 못 넘으면 등판과 등을 하나의 메쉬로 합치거나
  `MultiMeshInstance3D` 로 바꾼다.
- 경찰차 2대가 24 km 노선에서는 거의 안 마주친다. 마주침 빈도가 너무 낮으면
  대수를 늘리거나 버스 주변에서 생성하는 방식으로 바꾼다. 6번에서 일반 차량이
  들어올 때 같이 손본다.
