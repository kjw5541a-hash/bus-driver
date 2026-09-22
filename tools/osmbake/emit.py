"""route JSON 산출. 게임이 읽는 데이터 계약."""
import json
from pathlib import Path

from .routes import RouteSpec

ATTRIBUTION = "© OpenStreetMap contributors (ODbL)"


def write_route_json(path: Path, spec: RouteSpec, *, origin, route_xz, stops,
                     signals, chunks, baked_at: str) -> dict:
    """route JSON 파일을 쓴다.

    Args:
        path: 저장할 파일 경로
        spec: 노선 정의
        origin: (위도, 경도) 튜플
        route_xz: [(x, z), ...] 경로 좌표
        stops: [{"name", "x", "z", "progress_m", "osm_node"}, ...] 정류장
        signals: [{"x", "z", "source", "roads"}, ...] 신호기
        chunks: [{"name": str, "min": [x, z], "max": [x, z]}, ...] 청크 경계상자
        baked_at: ISO 8601 타임스탬프

    Returns:
        작성한 payload dict
    """
    payload = {
        "id": spec.route_id,
        "name": spec.name,
        "from": spec.from_stop,
        "to": spec.to_stop,
        "origin": [origin[0], origin[1]],
        "attribution": ATTRIBUTION,
        "osm_relation": spec.relation,
        "baked_at": baked_at,
        "route": [[round(x, 2), round(z, 2)] for x, z in route_xz],
        "stops": sorted(stops, key=lambda s: s["progress_m"]),
        "signals": signals,
        "chunks": sorted(chunks, key=lambda c: c["name"]),
    }
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=1),
                    encoding="utf-8")
    return payload
