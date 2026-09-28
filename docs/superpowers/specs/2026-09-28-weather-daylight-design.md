# 시간 흐름, 날씨, 가로등 설계

작성일: 2026-09-28
범위: 낮·노을·밤이 주행 중에 흐르고, 비가 오다 그치며, 밤에는 가로등이 켜진다.
`weather` 브랜치에서 한다.

## 배경

지금은 고정 태양(`drive.gd` 의 DirectionalLight3D, 그림자 켜짐) 하나뿐이고
하늘 설정이 없다. 사용자 요청:

- 시간대에 따라 태양 위치를 정하고 건물 그림자가 그 방향으로 진다.
- 일몰 때 노을이 진다.
- 새벽에는 버스가 다니지 않으니 밤 12시에 첫차 시각으로 넘어간다.
- 비는 보이는 것, 노면 마찰, 교통 속도 모두에 영향을 준다. 마감은 그대로다.
- 비가 오면 화면에 빗물이 묻어 잘 안 보이고, 와이퍼가 자동으로 닦는다.
- 밤에는 가로등이 있다.

## 목표와 비목표

**목표**

- 구간 시작 시각은 05:00~24:00 사이 무작위. 게임 1시간 = 실제 120초.
- 24:00 이 되면 주행은 그대로 두고 시각만 05:00 으로 넘기며 "첫차 05:00" 을 띄운다.
- 태양 고도·방위는 서울(37.57°N, 126.98°E, KST)과 시스템 날짜·게임 시각으로 계산한다.
- 하늘·햇빛·주변광 색이 태양 고도를 따라 바뀌고, 고도 −6°~+10° 에서 노을이 진다.
- 비는 무작위로 오고 그친다. 세기 0~1 을 30초에 걸쳐 오르내린다.
- 비 세기에 비례해 버스 바퀴 마찰과 교통 순항 속도가 준다.
- 비가 오면 화면 전체에 빗물이 쌓이고, 3초마다 와이퍼가 닦는다. 두 시점 모두.
- 가로등은 인도를 따라 약 30 m 간격으로 bake 하고, 밤에만 켜진다.
- 캡처와 테스트를 위해 `--time=HH:MM`, `--rain=0|1` 인자로 시작 상태를 고정할 수 있다.

**비목표**

- 달·별, 번개, 물웅덩이, 안개 속 전조등. 교통 차량 전조등도 넣지 않는다.
- 비 오는 동안 마감 보정. 사용자 결정으로 비는 그냥 불리하다.
- 계절 선택. 날짜는 시스템 날짜를 쓴다.

## 설계

### 1. 게임 시각 — `scripts/day_clock.gd` (`DayClock`, Node)

- `minutes: float` (0~1440). `SPEED := 0.5` 게임 분 / 실제 초 (1시간 = 120초).
- `FIRST_BUS := 300.0`(05:00), `LAST := 1440.0`.
- `_process` 에서 `minutes += SPEED * delta`. `minutes >= LAST` 이면 `FIRST_BUS` 로
  돌리고 `rolled_over` 신호를 낸다.
- 시작 시각: 인자 `--time` 이 있으면 그 값, 없으면 `randf_range(FIRST_BUS, LAST)`.
- RunClock(남은 시간, 실제 초 기준)과는 별개다. 게임 시각은 마감에 영향이 없다.

### 2. 태양 위치 — `scripts/sun_path.gd` (`SunPath`, static)

- `static func angles(day_of_year: int, minutes_kst: float) -> Vector2` — (고도, 방위) 도.
  - 적위 δ = 23.44·sin(360/365·(284 + n)).
  - 균시차 무시. 태양시 = KST − (135 − 126.98)·4 분 ≈ KST − 32분.
  - 시간각 H = 15·(태양시/60 − 12). 고도·방위는 표준 구면 공식. 방위는 북 0°, 동 90°.
- `static func direction(elevation, azimuth) -> Vector3` — 태양을 향하는 단위 벡터.
  월드 축은 bake 투영과 같다: +X 동, −Z 북.

### 3. 하늘과 조명 — `scripts/atmosphere.gd` (`Atmosphere`, Node3D)

- 자식: DirectionalLight3D(해, 그림자 켬), WorldEnvironment(ProceduralSkyMaterial).
  `drive.gd` 의 고정 태양을 이것으로 바꾼다.
- `apply(elevation, azimuth, rain)` 이 매 프레임 해 방향과 색을 정한다.
  - 해 방향 = `-SunPath.direction(...)` 로 비추게 `look_at`. 고도 < 0 이면 해 대신
    약한 푸른 달빛(에너지 0.08, 고정 방향 높이 50°)으로 바꾼다. 그림자는 유지.
  - 색 키프레임(고도 기준, 선형 보간): 밤(≤ −12°), 박명(−6°), 노을(0°·+5°),
    골든아워(+10°), 낮(≥ +20°). 키마다 하늘 위·지평선 색, 햇빛 색·에너지,
    주변광 에너지를 둔다. 노을 키는 지평선 주황~적색, 햇빛 주황.
  - 비 세기만큼 하늘을 회색으로 섞고, 햇빛을 40% 까지 줄이고, 안개를 켠다.
- 색 보간은 `static func palette(elevation, rain) -> Dictionary` 로 떼어 테스트한다.

### 4. 비 — `scripts/weather.gd` (`Weather`, Node3D)

- `rain: float` 현재 세기, `_target` 0 또는 1. `RAMP_S := 30.0` 초에 걸쳐 따라간다.
- 일정: 맑음 구간 실제 120~360초, 비 구간 60~240초를 번갈아 무작위로 뽑는다.
  시작 시 30% 확률로 비 구간에서 시작. `--rain` 이 있으면 그 상태로 시작하고
  바뀌지 않는다.
- 적용(매 프레임, 세기 비례):
  - 버스: `wheel_friction_slip` 3.5 → 2.2. `Bus.set_grip(ratio)` 를 새로 둔다.
  - 교통: 순항 속도 40 → 30 km/h. `CarFollow.next_speed` 가 쓰는 순항 속도를
    `Traffic.cruise_scale` 로 곱한다.
  - 노면: 도로 청크 재질의 roughness 를 0.9 → 0.25 로 낮춰 반사를 낸다.
    `City` 가 도로 재질 목록을 내놓는다.
  - 빗줄기: 카메라를 따라다니는 GPUParticles3D, 40×25×40 m 상자, 세로로 늘인
    쿼드, 최대 4000개. `amount_ratio` 를 세기로.

### 5. 화면 빗물 — `scripts/rain_screen.gd` + `shaders/rain_screen.gdshader`

- CanvasLayer(HUD 아래 층)의 전체 화면 ColorRect. `hint_screen_texture` 를 읽어
  빗방울 자리(셀 노이즈)만 굴절·흐림을 준다.
- `wetness` 0~1: 비 세기 × 0.25 / 초로 쌓인다. 3초마다 와이퍼가 0.4초 동안
  화면을 좌→우로 쓸고, 쓸고 지나간 쪽은 0 이 된다(`wipe_x` 유니폼).
- 비가 그치면 wetness 가 천천히 마른다.

### 6. 가로등

**bake** — `tools/osmbake/routing.py` 에 `place_streetlights(path_xz, sidewalk)`.

- 노선을 따라 30 m 마다, 오른쪽은 지금의 `_to_sidewalk` 로, 왼쪽은 뒤집은 경로로
  인도 위 자리를 찾는다. 없으면 건너뛴다.
- 결과: `[[x, z, yaw], ...]`, yaw 는 전등 머리가 도로(노선)를 향하는 각.
- 서로 10 m 안에 붙은 자리는 하나만 남긴다(급커브·교차로에서 겹침).
- JSON 키 `streetlights`. seoul-100 약 1,300개 예상.

**게임** — `scripts/street_lights.gd` (`StreetLights`, Node3D).

- 기둥(8 m, 회색)과 전등 머리를 MultiMeshInstance3D 두 개로 그린다.
- 전등 머리 재질 emission 에너지 = 밤 정도(태양 고도 +2° 에서 0, −4° 에서 1).
- OmniLight3D 8개를 풀로 두고(모바일 렌더러의 메쉬당 옴니 라이트 한도), 0.5초마다 버스에서 가장 가까운 8곳으로 옮긴다.
  범위 18 m, 그림자 없음. 밤 정도가 0 이면 모두 끈다.

### 7. HUD

- `ClockHud` 에 게임 시각 라벨("17:42")을 남은 시간 아래에 더한다.
- `rolled_over` 시 3초간 "첫차 05:00" 을 띄운다.

### 8. 배선 — `drive.gd`

DayClock → SunPath → Atmosphere·StreetLights, Weather → Atmosphere·Bus·Traffic·
City·RainScreen. `drive.gd` 가 `_process` 에서 값을 넘긴다. 서로 직접 참조하지 않는다.

## 테스트

**파이썬**

- `place_streetlights`: 직선 노선 양쪽 인도 띠에 30 m 간격으로 양쪽 모두 놓인다.
  인도가 없는 쪽은 비고, 10 m 안 중복은 하나로 준다.

**게임** (`tests/game/`)

- `test_sun_path`: 하지 12:32 고도 ≈ 76°, 동지 ≈ 29°. 춘분 일몰 ≈ 18:40 전후에
  고도 0 을 지난다. 오전 방위 < 180, 오후 > 180.
- `test_day_clock`: 23:59 에서 2초 지나면 05:00 대이고 `rolled_over` 가 한 번 뜬다.
- `test_atmosphere`: 고도 0° 지평선 색의 빨강 > 파랑(노을), 고도 −15° 햇빛 에너지가
  낮보다 훨씬 작다. 비 1 이면 햇빛 에너지가 비 0 보다 작다.
- `test_weather`: 비 1 에서 버스 바퀴 마찰 2.2, `Traffic.cruise_scale` 0.75.
  비 0 에서 원래 값. 전환은 30초에 걸친다.
- `test_street_lights`: 밤에는 켜진 OmniLight 가 버스에서 가장 가까운 자리에 있고,
  낮에는 전부 꺼진다.

**창 모드 확인**

- `--time` 과 `--rain` 으로 낮·노을·밤·비 오는 밤을 캡처해 본다.
- `measure_fps` 를 낮과 비 오는 밤에 돌린다. 기준 평균 60 / 최저 55.

## 위험

- 그림자: 해가 낮으면 그림자가 매우 길어져 DirectionalLight 의 그림자 거리
  (기본 100 m) 안에서 계단 현상이 커질 수 있다. 캡처로 보고 `shadow_max_distance`
  와 분할 수를 조정한다.
- 화면 셰이더와 입자 4000개가 안드로이드에서 무거울 수 있다. PC 기준으로 먼저
  맞추고, 모바일은 입자 수와 셰이더 표본 수를 줄이는 상수로 둔다.
