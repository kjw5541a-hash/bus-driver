# 교차로 면 연산과 차량 모델 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 교차로 도로 면 틈을 없애고, 인도가 차도와 겹치지 않고 모서리를 곡선으로 돌게 하며, 교통 차량을 받은 glb 모델로 바꾼다.

**Architecture:** bake 단계에서 모든 차도를 shapely 로 한 다각형으로 합치고, 교차점 둘레만 닫힘 연산으로 모서리를 메운 뒤, 인도는 띠에서 도로를 빼서 만든다. 청크 칸마다 잘라 제약 들로네 삼각분할한다. 게임은 `_make_car` 가 박스 대신 glb 를 인스턴스한다.

**Tech Stack:** Python 3.14 + shapely 2.1(`.venv`), Godot 4.7.2 GDScript.

**Spec:** `docs/superpowers/specs/2026-09-27-junction-corners-design.md`

## Global Constraints

- 파이썬은 저장소 `.venv/bin/python` 으로 돈다(Homebrew Python 은 전역 pip 금지). `venv` 가 만든 `.venv/.gitignore` 가 있어 `.gitignore` 는 안 건드린다.
- 산출물 표면 이름 `road`, `sidewalk` 는 그대로다.
- `CURB_SLOPE_M`, `SIDEWALK_WIDTH`, `CURB_HEIGHT`, `SIDEWALK_MIN_ROAD_WIDTH`, `_road_index`, `_on_roadway` 는 다른 모듈이 쓰므로 남긴다.
- 충돌 박스 `BODY_SIZE` (1.8, 1.4, 4.6) 는 그대로다.
- godot 실행 뒤에는 `git checkout -q project.godot`. 새 `.gd` 는 `godot --headless --import` 후 `.uid` 도 커밋.
- 임시 캡처 `tests/game/_cap.*` 는 커밋하지 않는다.
- 파일은 이름으로만 `git add` 한다.

---

### Task 1: 면 연산 모듈

**Files:**
- Create: `requirements.txt`, `tools/osmbake/surface.py`, `tests/osmbake/test_surface.py`

**Interfaces:**
- Produces: `surface.build_surfaces(ways, projector, chunk_size=CHUNK_SIZE_M) -> tuple[MeshBuilder, MeshBuilder]` (도로, 인도), `surface.road_and_sidewalk(ways, projector) -> (road, top, slope)` shapely 다각형.

- [ ] **Step 1: 환경** — `python3 -m venv .venv && .venv/bin/pip install 'shapely>=2.1'`. `requirements.txt` 내용은 한 줄 `shapely>=2.1`.
- [ ] **Step 2: 테스트** — `tests/osmbake/test_surface.py`:

```python
"""면 연산으로 만든 도로와 인도."""
import math
import unittest

from shapely.geometry import LineString, Point

from tools.osmbake.geo import METERS_PER_DEG_LAT, Projector
from tools.osmbake.mesh import CURB_HEIGHT, road_width
from tools.osmbake.surface import build_surfaces

PROJECTOR = Projector(37.500, 127.000)
M_PER_LON = METERS_PER_DEG_LAT * math.cos(math.radians(37.500))


def way(way_id, nodes, points, highway="primary"):
    """xz 좌표(m)로 way 를 만든다. x 동쪽, z 남쪽."""
    return {"type": "way", "id": way_id, "nodes": nodes,
            "geometry": [{"lat": 37.500 - z / METERS_PER_DEG_LAT,
                          "lon": 127.000 + x / M_PER_LON} for x, z in points],
            "tags": {"highway": highway}}


def triangles(builder):
    """[(정점 셋)] 목록."""
    return [[builder.positions[i] for i in builder.indices[k:k + 3]]
            for k in range(0, len(builder.indices), 3)]


def covers(builder, x, z):
    """(x, z) 가 어떤 삼각형 안(경계 포함)에 드는가."""
    for a, b, c in triangles(builder):
        d1 = (b[0] - a[0]) * (z - a[2]) - (b[2] - a[2]) * (x - a[0])
        d2 = (c[0] - b[0]) * (z - b[2]) - (c[2] - b[2]) * (x - b[0])
        d3 = (a[0] - c[0]) * (z - c[2]) - (a[2] - c[2]) * (x - c[0])
        if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
            return True
    return False


def cross():
    """(0, 0) 에서 만나는 primary 네 갈래(폭 20 m)."""
    return [way(1, [1, 0], [(-60.0, 0.0), (0.0, 0.0)]),
            way(2, [0, 2], [(0.0, 0.0), (60.0, 0.0)]),
            way(3, [3, 0], [(0.0, -60.0), (0.0, 0.0)]),
            way(4, [0, 4], [(0.0, 0.0), (0.0, 60.0)])]


def oblique_t():
    """남북 primary 에 30° 로 비스듬히 붙는 secondary."""
    angle = math.radians(30.0)
    return [way(1, [1, 0, 2], [(0.0, -80.0), (0.0, 0.0), (0.0, 80.0)]),
            way(2, [0, 3], [(0.0, 0.0),
                            (80.0 * math.sin(angle), 80.0 * math.cos(angle))],
                highway="secondary")]


def crossing_without_node():
    """노드를 공유하지 않고 겹치는 두 도로(고가 아래 같은 경우)."""
    return [way(1, [1, 2], [(-60.0, 0.0), (60.0, 0.0)]),
            way(2, [3, 4], [(0.0, -60.0), (0.0, 60.0)])]


SCENES = {"교차": cross, "비스듬한_T": oblique_t, "노드_없는_교차": crossing_without_node}


class TestSurfaces(unittest.TestCase):
    def test_인도는_어떤_차도에도_올라가지_않는다(self):
        for name, scene in SCENES.items():
            ways = scene()
            _, sidewalk = build_surfaces(ways, PROJECTOR)
            lanes = [LineString([PROJECTOR.to_xz(g["lat"], g["lon"])
                                 for g in w["geometry"]])
                     .buffer(road_width(w["tags"]) / 2.0 - 0.01, cap_style="flat")
                     for w in ways]
            self.assertGreater(sidewalk.triangle_count(), 0, name)
            for tri in triangles(sidewalk):
                centre = Point(sum(p[0] for p in tri) / 3, sum(p[2] for p in tri) / 3)
                for lane in lanes:
                    self.assertFalse(lane.contains(centre), f"{name}: {centre}")

    def test_높이와_위쪽_감기(self):
        for name, scene in SCENES.items():
            road, sidewalk = build_surfaces(scene(), PROJECTOR)
            self.assertEqual({p[1] for p in road.positions}, {0.0}, name)
            self.assertEqual({round(p[1], 4) for p in sidewalk.positions},
                             {0.0, CURB_HEIGHT}, name)
            for builder in (road, sidewalk):
                for a, b, c in triangles(builder):
                    # 위에서 내려다볼 때 반시계(Godot 앞면)면 y 성분이 양수다.
                    cross_y = ((b[2] - a[2]) * (c[0] - a[0])
                               - (b[0] - a[0]) * (c[2] - a[2]))
                    self.assertGreater(cross_y, 0, name)

    def test_교차로_모서리가_메워진다(self):
        road, sidewalk = build_surfaces(cross(), PROJECTOR)
        # 두 차도 모서리는 (10, 10). 메움 원호는 중심 (16, 16) 반경 6 m 라
        # 대각선 위 모서리에서 2.49 m 까지 도로다. (13, 13) 은 원호에서
        # 1.76 m 바깥이라 인도 윗면이다.
        self.assertTrue(covers(road, 9.6, 9.6))
        self.assertTrue(covers(road, 10.0 + 1.0, 10.0 + 1.0))
        self.assertFalse(covers(sidewalk, 10.0 + 1.0, 10.0 + 1.0))
        # 모서리 바깥 원호 뒤에는 인도가 곡선으로 돈다.
        self.assertTrue(covers(sidewalk, 10.0 + 3.0, 10.0 + 3.0))

    def test_일자로_이어진_way_사이_인도가_끊기지_않는다(self):
        ways = [way(1, [1, 0], [(0.0, -60.0), (0.0, 0.0)]),
                way(2, [0, 2], [(0.0, 0.0), (0.0, 60.0)])]
        _, sidewalk = build_surfaces(ways, PROJECTOR)
        self.assertTrue(covers(sidewalk, 11.5, 0.0))
        self.assertTrue(covers(sidewalk, -11.5, 0.0))

    def test_30m_떨어진_평행_도로는_합쳐지지_않는다(self):
        ways = [way(1, [1, 2], [(-60.0, 0.0), (60.0, 0.0)]),
                way(2, [3, 4], [(-60.0, 30.0), (60.0, 30.0)])]
        road, sidewalk = build_surfaces(ways, PROJECTOR)
        self.assertFalse(covers(road, 0.0, 15.0))
        self.assertTrue(covers(sidewalk, 0.0, 11.5))
        self.assertTrue(covers(sidewalk, 0.0, 18.5))

    def test_골목에는_인도가_없다(self):
        ways = [way(1, [1, 2], [(-60.0, 0.0), (60.0, 0.0)], highway="service")]
        road, sidewalk = build_surfaces(ways, PROJECTOR)
        self.assertGreater(road.triangle_count(), 0)
        self.assertEqual(sidewalk.triangle_count(), 0)

    def test_삼각형은_청크_경계를_넘지_않는다(self):
        # 경계 x = 0 을 가로지르는 도로를 50 m 칸으로 나눈다.
        road, sidewalk = build_surfaces(cross(), PROJECTOR, chunk_size=50.0)
        for builder in (road, sidewalk):
            for tri in triangles(builder):
                cells = {(math.floor(sum(p[0] for p in tri) / 3 / 50.0),
                          math.floor(sum(p[2] for p in tri) / 3 / 50.0))}
                for p in tri:
                    cx, cz = next(iter(cells))
                    self.assertTrue(cx * 50.0 - 1e-6 <= p[0] <= (cx + 1) * 50.0 + 1e-6)
                    self.assertTrue(cz * 50.0 - 1e-6 <= p[2] <= (cz + 1) * 50.0 + 1e-6)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: 실패 확인** — `.venv/bin/python -m unittest tests.osmbake.test_surface` → `ModuleNotFoundError: tools.osmbake.surface`.
- [ ] **Step 4: 구현** — `tools/osmbake/surface.py`:

```python
"""도로 면과 인도를 면 연산으로 만든다.

way 마다 따로 리본과 인도를 깔던 방식은 교차로에서 틈이 남고, 비스듬한
합류에서 인도가 이웃 차도로 튀어나왔다. 여기서는 모든 차도를 한 면으로
합치고, 인도는 그 면을 빼서 만든다. 그래서 인도는 어떤 차도와도 겹칠 수
없다.
"""

import math

import shapely
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union

from .geo import Projector
from .mesh import (CHUNK_SIZE_M, CURB_HEIGHT, CURB_SLOPE_M, SIDEWALK_MIN_ROAD_WIDTH,
                   SIDEWALK_WIDTH, MeshBuilder, road_width)

CORNER_RADIUS_M = 6.0
SIMPLIFY_M = 0.05   # 원호 정점을 이만큼 솎는다. 삼각형 수가 절반 가까이 준다.


def _way_polygons(ways: list[dict], projector: Projector):
    """(차도 다각형, 인도를 둘 넓은 도로 다각형, 공유 노드 둘레 원) 목록."""
    usage: dict[int, int] = {}
    for w in ways:
        for node_id in set(w.get("nodes", [])):
            usage[node_id] = usage.get(node_id, 0) + 1

    roads, wide = [], []
    node_half: dict[int, tuple[tuple[float, float], float]] = {}
    for w in ways:
        tags = w.get("tags", {})
        if "highway" not in tags or "geometry" not in w:
            continue
        points = [projector.to_xz(g["lat"], g["lon"]) for g in w["geometry"]]
        if len(points) < 2:
            continue
        width = road_width(tags)
        polygon = LineString(points).buffer(width / 2.0, cap_style="flat",
                                            join_style="round")
        roads.append(polygon)
        if width >= SIDEWALK_MIN_ROAD_WIDTH:
            wide.append(polygon)
        for node_id, point in zip(w.get("nodes", []), points):
            if usage.get(node_id, 0) > 1:
                _, half = node_half.get(node_id, (point, 0.0))
                node_half[node_id] = (point, max(half, width / 2.0))
    discs = [Point(point).buffer(half + 2.0 * CORNER_RADIUS_M)
             for point, half in node_half.values()]
    return roads, wide, discs


def road_and_sidewalk(ways: list[dict], projector: Projector):
    """(도로 면, 인도 윗면, 연석 경사면) shapely 다각형."""
    roads, wide, discs = _way_polygons(ways, projector)
    carriageway = unary_union(roads)
    # 닫힘 연산은 오목한 모서리를 반경 R 원호로 메운다. 교차점 둘레만 쓴다 —
    # 전체에 쓰면 12 m 안으로 붙은 평행 도로가 한 덩어리가 된다.
    closed = carriageway.buffer(CORNER_RADIUS_M).buffer(-CORNER_RADIUS_M)
    fillets = closed.intersection(unary_union(discs))
    road = unary_union([carriageway, fillets]).simplify(SIMPLIFY_M)
    # 인도 띠도 메운 모서리를 따라 돈다. 안 그러면 모서리 원호가 띠를 먹는다.
    band = unary_union(wide + [fillets]).buffer(
        CURB_SLOPE_M + SIDEWALK_WIDTH).simplify(SIMPLIFY_M)
    curb_edge = road.buffer(CURB_SLOPE_M).simplify(SIMPLIFY_M)
    top = band.difference(curb_edge)
    slope = band.intersection(curb_edge).difference(road)
    return road, top, slope


def _triangles(geometry, chunk_size: float):
    """청크 칸마다 잘라 삼각분할한 삼각형 좌표 배열 목록."""
    if geometry.is_empty:
        return []
    min_x, min_z, max_x, max_z = geometry.bounds
    out = []
    for cx in range(math.floor(min_x / chunk_size), math.floor(max_x / chunk_size) + 1):
        for cz in range(math.floor(min_z / chunk_size),
                        math.floor(max_z / chunk_size) + 1):
            cell = box(cx * chunk_size, cz * chunk_size,
                       (cx + 1) * chunk_size, (cz + 1) * chunk_size)
            part = geometry.intersection(cell)
            if part.is_empty:
                continue
            triangles = shapely.get_parts(shapely.constrained_delaunay_triangles(part))
            # 삼각형 하나는 닫힌 고리라 좌표가 4 개다.
            out += shapely.get_coordinates(triangles).reshape(-1, 4, 2)[:, :3].tolist()
    return out


def _add(builder: MeshBuilder, corners, heights) -> None:
    """삼각형 하나를 위를 향하게 넣는다. 법선은 면 법선이다."""
    points = [(x, y, z) for (x, z), y in zip(corners, heights)]
    a, b, c = points
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if ny < 0:
        points = [a, c, b]
        nx, ny, nz = -nx, -ny, -nz
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 1e-9:
        return
    builder.add_triangles(points, [(0, 1, 2)], (nx / length, ny / length, nz / length))


def build_surfaces(ways: list[dict], projector: Projector,
                   chunk_size: float = CHUNK_SIZE_M) -> tuple[MeshBuilder, MeshBuilder]:
    """(도로, 인도) 메쉬. 삼각형은 청크 칸을 넘지 않는다."""
    road, top, slope = road_and_sidewalk(ways, projector)
    road_builder = MeshBuilder()
    for corners in _triangles(road, chunk_size):
        _add(road_builder, corners, [0.0] * 3)
    sidewalk = MeshBuilder()
    for corners in _triangles(top, chunk_size):
        _add(sidewalk, corners, [CURB_HEIGHT] * 3)
    # 경사면 정점은 모두 차도 경계(높이 0)나 인도 윗면 경계(0.15) 위에 있다.
    # 차도에 닿는지만 보면 된다. 큰 다각형과의 거리 계산보다 훨씬 빠르다.
    road_edge = road.buffer(0.01)
    shapely.prepare(road_edge)
    for corners in _triangles(slope, chunk_size):
        on_road = shapely.intersects(road_edge, shapely.points(corners))
        _add(sidewalk, corners, [0.0 if hit else CURB_HEIGHT for hit in on_road])
    return road_builder, sidewalk

```

- [ ] **Step 5: 통과 확인** — 같은 명령 7 개 OK. 실데이터 속도: seoul-100 20 초 안.
- [ ] **Step 6: 커밋** — `git add requirements.txt tools/osmbake/surface.py tests/osmbake/test_surface.py` 후 `feat: 차도를 면 연산으로 합치고 인도를 그 바깥에 만든다`.

### Task 2: bake 연결, 옛 빌더 제거

**Files:**
- Modify: `tools/osmbake/cli.py` (5. mesh 부분), `tools/osmbake/mesh.py` (`build_roads`, `build_sidewalks` 와 전용 도우미·상수), `tests/osmbake/test_mesh.py` (`TestBuildRoads`, `TestBuildSidewalks`, `TestSidewalkOverlap` 와 import), `tests/bake/run_verify.sh`, `README.md`

**Interfaces:**
- Consumes: `surface.build_surfaces` (Task 1)

- [ ] **Step 1: cli** — `from . import surface as surface_mod` 를 넣고 5. mesh 를 바꾼다:

```python
    road_builder, sidewalk_builder = surface_mod.build_surfaces(roads, projector)
    road_chunks = mesh_mod.split_chunks(road_builder)
    ...
    extra = dict(mesh_mod.build_markings(roads, projector))
    extra["sidewalk"] = sidewalk_builder
```

- [ ] **Step 2: 제거** — `mesh.py` 에서 `build_roads`, `build_sidewalks`, `_allowed_spans`, `_sidewalk_side`, `_clear_runs`, `INTERSECTION_CLEAR_M`, `MIN_SIDEWALK_SPAN`, `SIDEWALK_SAMPLE_M` 와 이것들만 쓰던 도우미(`grep -n` 으로 다른 호출처가 없는지 확인)를 지운다. `test_mesh.py` 의 세 테스트 클래스와 import 를 지운다.
- [ ] **Step 3: 스크립트** — `run_verify.sh` 의 `python3` 를 `.venv/bin/python` 으로, README 의 bake·테스트 명령도 `.venv/bin/python` 으로 바꾸고 설치 한 줄(`python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`)을 적는다.
- [ ] **Step 4: 확인** — `.venv/bin/python -m unittest discover -s tests -t .` 전부 OK.
- [ ] **Step 5: 커밋** — `refactor: bake 가 면 연산 도로·인도를 쓰고 옛 리본 빌더를 지운다`.

### Task 3: 차량 glb

**Files:**
- Create: `assets/models/car.glb` (+ `car.glb.import`, 텍스처 import 산출물)
- Modify: `scripts/traffic.gd` (`_make_car`), `tests/game/test_traffic.gd`

- [ ] **Step 1: 복사·import** — `cp ~/Downloads/angular-apocalypse-abandoned-compact-car-intact-parked.glb assets/models/car.glb`, `godot --headless --import`.
- [ ] **Step 2: 테스트** — `test_traffic.gd` 에서 차 하나를 만든 뒤 `car.body` 자식 중 `CAR_MODEL_NAME` 이름의 노드가 있고 그 아래 `MeshInstance3D` 가 있으며 `material_override` 가 있다고 단언. 경찰차 색 머티리얼이 일반 차와 다르다고 단언.
- [ ] **Step 3: 구현** — `BoxMesh` 를 아래로 바꾼다:

```gdscript
const CAR_SCENE := preload("res://assets/models/car.glb")
const CAR_MODEL_NAME := "Model"
# 모델 크기(길이 X 1.6, 높이 0.776, 폭 0.904 m). 축마다 BODY_SIZE 에 맞춘다.
const CAR_MODEL_SCALE := Vector3(4.6 / 1.6, 1.4 / 0.776, 1.8 / 0.9037)
var _car_materials := {}   # 색 -> 복제 머티리얼

	var model: Node3D = CAR_SCENE.instantiate()
	model.name = CAR_MODEL_NAME
	# 보닛(앞)이 -X 다. 차의 앞은 -Z 라 Y 축으로 -90° 돌린다.
	model.transform = Transform3D(
		Basis(Vector3.UP, -PI / 2.0) * Basis.from_scale(CAR_MODEL_SCALE), Vector3.ZERO)
	var color: Color = POLICE_COLOR if is_police \
		else BODY_COLORS[color_index % BODY_COLORS.size()]
	var mesh := model.find_children("*", "MeshInstance3D")[0] as MeshInstance3D
	mesh.material_override = _car_material(mesh, color)
	body.add_child(model)
```

배율은 모델 축 기준이라 회전 오른쪽에 곱한다. `_car_material` 은 `_car_materials` 에 없으면 `mesh.get_active_material(0).duplicate()` 의 `albedo_color` 를 색으로 두고 저장한다.
- [ ] **Step 4: 확인** — `tests/game/run_game_tests.sh` 전부 TEST_OK. 추격 시점 캡처로 앞뒤 확인(뒤집혔으면 +90°).
- [ ] **Step 5: 커밋** — `feat: 교통 차량을 받은 차 모델로 그린다`.

### Task 4: 재굽기, 검증, 캡처

- [ ] **Step 1:** 세 노선 `.venv/bin/python -m tools.osmbake.cli bake <id>`.
- [ ] **Step 2:** `tests/bake/run_verify.sh` VERIFY_OK. 지면 커버리지 100번 99.8%·654번 99.9%·서대문03 99.9% 이상, 정류장 인도 비율 0.65 이상. 교착 거리 기록(기존 1024 / 528 / 220 m).
- [ ] **Step 3:** 전체 파이썬·게임 테스트. `measure_fps` 평균 60 이상.
- [ ] **Step 4:** 캡처 — 교차로 6곳 위, 비스듬한 합류 한 곳, 추격 시점 1장. 사용자 스크린샷과 비교.
- [ ] **Step 5:** README 에 면 연산 설명 한 단락. 커밋 `chore: 면 연산 도로·인도로 세 노선을 다시 굽는다`.
