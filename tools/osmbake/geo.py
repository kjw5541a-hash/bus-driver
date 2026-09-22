"""로컬 평면 좌표 투영과 거리 계산.

게임 맵은 한 노선 범위(최대 20 km)만 다루므로 정식 투영법 대신 원점 위도에서
고정한 미터 환산을 쓴다. 이 범위에서 오차는 미터 단위 이하다.
"""
import math

EARTH_RADIUS_M = 6371000.0
METERS_PER_DEG_LAT = 111320.0


def haversine(a: tuple[float, float], b: tuple[float, float]) -> float:
    """두 (위도, 경도) 사이 대권 거리(미터)."""
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat = lat2 - lat1
    dlon = math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


class Projector:
    """위경도를 로컬 평면 미터로 옮긴다. x 는 동쪽, z 는 남쪽."""

    def __init__(self, lat0: float, lon0: float) -> None:
        self.lat0 = lat0
        self.lon0 = lon0
        self._m_per_lon = METERS_PER_DEG_LAT * math.cos(math.radians(lat0))

    def to_xz(self, lat: float, lon: float) -> tuple[float, float]:
        return ((lon - self.lon0) * self._m_per_lon,
                -(lat - self.lat0) * METERS_PER_DEG_LAT)
