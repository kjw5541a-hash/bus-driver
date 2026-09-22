"""베이크 진입점.

    python3 -m tools.osmbake.cli bake seoul-100

캐시가 있으면 네트워크를 타지 않는다. data/osm_cache/ 는 커밋하므로 같은 명령이
항상 같은 맵을 만든다.
"""
import argparse
import datetime
import sys
from pathlib import Path

from . import corridor as corridor_mod
from . import mesh as mesh_mod
from .emit import write_route_json
from .geo import Projector, haversine
from .glb import write_glb
from .graph import DRIVABLE_HIGHWAYS, build_graph
from .overpass import fetch
from .routes import ROUTES, RouteSpec
from .routing import astar, path_latlon, project_path, snap_stops

REPO_ROOT = Path(__file__).resolve().parents[2]
CACHE_DIR = REPO_ROOT / "data" / "osm_cache"
OUT_DIR = REPO_ROOT / "assets" / "routes"
HIGHWAY_FILTER = "|".join(sorted(DRIVABLE_HIGHWAYS))


def build_queries(spec: RouteSpec) -> tuple[str, str]:
    relation_query = (f"[out:json][timeout:180];rel({spec.relation});"
                      "way(r);out geom;")
    corridor_query = (
        "[out:json][timeout:180];\n"
        "(\n"
        f'  way["highway"~"^({HIGHWAY_FILTER})$"]({{bbox}});\n'
        f'  way["building"]({{bbox}});\n'
        f'  node["highway"="traffic_signals"]({{bbox}});\n'
        f'  node["highway"="bus_stop"]({{bbox}});\n'
        ");\nout geom;")
    return relation_query, corridor_query


def find_terminal_node(graph, stop_nodes: list[dict], name: str) -> int | None:
    """기점/종점 정류장 이름에 가장 가까운 도로 노드."""
    matches = [n for n in stop_nodes if n.get("tags", {}).get("name") == name]
    if not matches or not graph.adj:
        return None
    target = (matches[0]["lat"], matches[0]["lon"])
    # graph.coords 에는 나가는 엣지가 하나도 없는 노드도 들어 있다(일방통행의
    # 끝점 등). 기점/종점은 A* 의 출발·도착이라 그런 노드를 고르면 탐색이
    # 무조건 실패한다. 실제로 100번·654번이 여기서 막혔다. 엣지가 있는
    # 노드로만 후보를 좁힌다.
    return min(graph.adj,
               key=lambda node_id: haversine(graph.coords[node_id], target))


def _chunk_bounds(surfaces: dict) -> dict:
    """청크의 모든 서피스 정점에서 xz 경계 상자를 구한다."""
    xs = [p[0] for builder in surfaces.values() for p in builder.positions]
    zs = [p[2] for builder in surfaces.values() for p in builder.positions]
    return {"min": [round(min(xs), 2), round(min(zs), 2)],
            "max": [round(max(xs), 2), round(max(zs), 2)]}


def bake(route_id: str, *, cache_dir: Path = CACHE_DIR, out_dir: Path = OUT_DIR,
         radius_m: float = 250.0, baked_at: str | None = None) -> dict:
    spec = ROUTES[route_id]
    baked_at = baked_at or datetime.date.today().isoformat()
    cache_dir, out_dir = Path(cache_dir), Path(out_dir)
    relation_query, corridor_query = build_queries(spec)

    # 1. fetch — 노선 멤버 도로
    relation = fetch(relation_query, cache_dir / f"{route_id}_relation.json")
    member_elements = relation["elements"]
    member_way_ids = frozenset(e["id"] for e in member_elements
                               if e["type"] == "way")

    # 원점은 노선 멤버 기하의 중심
    lats = [g["lat"] for e in member_elements if "geometry" in e
            for g in e["geometry"]]
    lons = [g["lon"] for e in member_elements if "geometry" in e
            for g in e["geometry"]]
    origin = ((min(lats) + max(lats)) / 2, (min(lons) + max(lons)) / 2)
    projector = Projector(*origin)

    # 1b. fetch — 코리도. 멤버 기하 범위 + 여유
    box = corridor_mod.corridor_bbox(list(zip(lats, lons)), radius_m)
    corridor = fetch(corridor_query.format(bbox=",".join(f"{v:.6f}" for v in box)),
                     cache_dir / f"{route_id}_corridor.json")
    elements = corridor["elements"]

    # 2. graph
    graph = build_graph(elements)

    # 3. route
    stop_nodes = [e for e in elements if e.get("type") == "node"
                  and e.get("tags", {}).get("highway") == "bus_stop"]
    from_anchor, to_anchor = spec.anchors()
    start = find_terminal_node(graph, stop_nodes, from_anchor)
    goal = find_terminal_node(graph, stop_nodes, to_anchor)
    if start is None or goal is None:
        raise RuntimeError(
            f"{route_id}: 기점/종점 정류장을 찾지 못했다 "
            f"({from_anchor} → {to_anchor})")
    edges = astar(graph, start, goal, preferred_ways=member_way_ids)
    if not edges:
        raise RuntimeError(f"{route_id}: 기점에서 종점까지 경로가 없다")
    route_latlon = path_latlon(graph, edges)
    route_xz = project_path(route_latlon, projector)
    stops = snap_stops(route_xz, stop_nodes, projector)

    # 4. corridor
    near = corridor_mod.near_path(elements, route_xz, projector, radius_m)
    roads = [e for e in near if e.get("tags", {}).get("highway") in DRIVABLE_HIGHWAYS]
    buildings = [e for e in near if "building" in e.get("tags", {})]
    signal_nodes = [e for e in elements if e.get("type") == "node"
                    and e.get("tags", {}).get("highway") == "traffic_signals"]
    signals = corridor_mod.signal_candidates(graph, signal_nodes, projector,
                                             route_xz, radius_m)

    # 5. mesh
    road_chunks = mesh_mod.split_chunks(mesh_mod.build_roads(roads, projector))
    building_chunks = mesh_mod.split_chunks(
        mesh_mod.build_buildings(buildings, projector))
    chunks: dict[str, dict[str, mesh_mod.MeshBuilder]] = {}
    for name, builder in road_chunks.items():
        chunks.setdefault(name, {})["road"] = builder
    for name, builder in building_chunks.items():
        chunks.setdefault(name, {})["building"] = builder

    # 6. emit
    write_glb(out_dir / f"route_{route_id}.glb", chunks)
    payload = write_route_json(
        out_dir / f"route_{route_id}.json", spec,
        origin=origin, route_xz=route_xz, stops=stops, signals=signals,
        chunks=[{"name": name, **_chunk_bounds(surfaces)}
               for name, surfaces in chunks.items()],
        baked_at=baked_at)
    triangles = sum(b.triangle_count() for c in chunks.values()
                    for b in c.values())
    print(f"{route_id}: 경로 {len(route_xz)}점, 정류장 {len(stops)}개, "
          f"신호 후보 {len(signals)}개, 청크 {len(chunks)}개, 삼각형 {triangles}개")
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="OSM 노선 베이크")
    parser.add_argument("command", choices=["bake", "list"])
    parser.add_argument("route_id", nargs="?", default=None)
    args = parser.parse_args(argv)

    if args.command == "list":
        for route_id, spec in ROUTES.items():
            print(f"{route_id}\t{spec.name}\t{spec.from_stop} → {spec.to_stop}")
        return 0

    targets = [args.route_id] if args.route_id else list(ROUTES)
    for route_id in targets:
        bake(route_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
