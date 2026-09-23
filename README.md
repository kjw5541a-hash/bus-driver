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

- `assets/routes/route_<id>.glb` — 도로와 건물 메쉬. 200 m 격자 청크로 나뉜다
- `assets/routes/route_<id>.json` — 경로 폴리라인, 정류장, 신호 후보, 청크 경계

## 게임 실행

```bash
godot
```

노선을 고르면 주행 씬이 뜬다. 조작은 `W` 가속, `S` 제동(정지 상태에서 길게 누르면
후진), `A`/`D` 조향, `R` 리스폰이다. 화면 왼쪽 절반을 끌면 터치 조향, 오른쪽 아래
버튼이 가속·제동·후진·복귀다. 시점은 마우스 우클릭 드래그로 돌리고 휠로
당기며, 휠 클릭으로 기본 시점에 돌아온다.

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
