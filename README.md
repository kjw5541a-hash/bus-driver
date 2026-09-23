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

## 테스트

```bash
./run_tests.sh                      # 파이썬 단위 테스트
tests/bake/run_verify.sh            # 노선을 굽고 Godot 헤드리스 검증
```

`run_verify.sh` 는 `godot` 을 PATH 에서 찾는다. 다른 곳에 있으면 `GODOT` 환경변수로
경로를 준다.

## 문서

- 설계: `docs/superpowers/specs/2026-09-22-osm-bake-pipeline-design.md`
- 구현 계획: `docs/superpowers/plans/2026-09-22-osm-bake-pipeline.md`
