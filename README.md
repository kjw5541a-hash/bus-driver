# 버스 운전 게임

실제 서울 버스 노선 위를 달리는 버스 운전 게임. 정류장마다 승객을 태우고 정해진
시간 안에 종착역까지 가야 한다. 신호와 승하차로 소요 시간이 계속 바뀌고, 신호를
어겨 시간을 벌 수도 있다.

맵은 OpenStreetMap 데이터를 빌드 타임에 구워서 만든다. 게임은 런타임에 OSM 을
읽지 않는다 — 구워둔 `.glb` 와 `.json` 만 읽는다.

## 지도 데이터

© OpenStreetMap contributors. 지도 데이터는 ODbL 라이선스를 따른다.

## 노선 굽기

```bash
python3 -m tools.osmbake.cli list          # 정의된 노선 보기
python3 -m tools.osmbake.cli bake seoul-100
```

`data/osm_cache/` 에 캐시가 있으면 네트워크를 타지 않는다. 최신 OSM 데이터로 다시
구우려면 해당 캐시 파일을 지운다.

산출물은 노선마다 두 개다.

- `assets/routes/route_<id>.glb` — 도로·건물·차선 도색·인도 메쉬. 200 m 격자
  청크로 나뉜다. 도로 폭은 `lanes` 태그가 있으면 차선 수로, 없으면 등급별
  추정 테이블로 정한다(서울 실제 기준). 인도는 교차로 둘레와 다른 도로 위를
  비운다
- `assets/routes/route_<id>.json` — 경로 폴리라인, 정류장, 신호 후보, 청크 경계

`signals` 는 교차로마다 위치(`x`, `z`), 두 축의 방위각(`axis_deg`), 교차로 반폭
(`half_width`), 무인단속 카메라 유무(`camera`)를 담는다. OSM 의 `traffic_signals`
태그를 쓰되 진입 방향마다 찍힌 노드를 40 m 반경으로 병합하고, 태그가 없는 큰
교차로는 갈래 수를 보고 합성한다. 노선당 평균 간격은 230~320 m 다.

## 게임 실행

```bash
godot
```

노선을 고르면 주행 씬이 뜬다. 조작은 `W` 가속, `S` 제동(정지 상태에서 길게 누르면
후진), `A`/`D` 조향, `R` 리스폰, `C` 시점 전환이다. 화면 왼쪽 절반을 끌면 터치 조향,
오른쪽 아래 버튼이 가속·제동·후진·복귀·시점이다. 시점은 마우스 우클릭 드래그로
돌리고 휠로 당기며, 휠 클릭으로 기본 시점에 돌아온다. `C` 를 누르면 운전석
1인칭으로 바뀐다 — 여기서는 둘러보기만 되고 휠 거리 조절은 안 된다.

교차로에는 신호등이 서 있고 두 축이 반주기씩 번갈아 녹색이 된다. 적색에 정지선을
넘으면 위반이 세어져 좌상단에 표시된다. 카메라가 달린 교차로는 따로 세고, 노선을
왕복하는 순찰 경찰차 시야 안에서 위반하면 적발되어 주행이 끝난다. 이때 `R` 로 다시
시작한다.

정류장에는 대기 승객이 서 있다. 정류장 앞 15 m 안에서 멈추면 승하차가 시작되고
그동안 버스는 움직이지 않는다. 걸리는 시간은 타는 사람과 내리는 사람 수, 그리고
정류장에서 얼마나 떨어져 섰는지로 달라진다. 탈 사람도 내릴 사람도 없는 정류장은
그냥 지나가면 된다. 대기 인원은 매 플레이 새로 정해진다.

## 테스트

```bash
./run_tests.sh                      # 파이썬 단위 테스트
tests/bake/run_verify.sh            # 노선을 굽고 Godot 헤드리스 검증
tests/game/run_game_tests.sh        # 게임 쪽 헤드리스 테스트
```

`run_game_tests.sh` 는 노선 데이터·도시 로딩·입력 매핑·회전 반경·내비 라인·주행
스모크를 검사한다. 성능은 창이 필요해서 따로 잰다.

```bash
godot res://tests/game/measure_fps.tscn -- --route=seoul-100
```

두 러너 모두 `godot` 을 PATH 에서 찾는다. 다른 곳에 있으면 `GODOT` 환경변수로
경로를 준다.

## 문서

- 설계: `docs/superpowers/specs/2026-09-22-osm-bake-pipeline-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-22-osm-bake-pipeline.md`
- 설계: `docs/superpowers/specs/2026-09-23-bus-physics-input-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-23-bus-physics-input.md`
- 설계: `docs/superpowers/specs/2026-09-23-signals-violations-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-23-signals-violations.md`
- 설계: `docs/superpowers/specs/2026-09-24-stops-passengers-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-24-stops-passengers.md`
