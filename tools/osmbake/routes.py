"""구울 노선 정의.

후보 6개의 OSM 품질을 실측해서 셋을 골랐다(최대 연결 컴포넌트 비율 기준).
163 번은 24% 로 조각남이 심해 탈락, 동대문01 은 0.9 km 로 너무 짧아 탈락했다.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class RouteSpec:
    """노선 정의.

    게임이 읽는 메타데이터.
    """
    route_id: str
    relation: int
    name: str
    from_stop: str
    to_stop: str


ROUTES: dict[str, RouteSpec] = {
    # 마을버스. 좁은 길 위주, 4.9 km, 데이터 97% 연결. 입문용.
    "seoul-seodaemun03": RouteSpec(
        "seoul-seodaemun03", 7481016, "서울특별시 마을버스 서대문03",
        "홍은2동주민센터", "신촌전철역"),
    # 간선. 중앙버스전용차선 3.3 km 실재. 스파이크에서 주행 검증된 노선.
    "seoul-100": RouteSpec(
        "seoul-100", 2895724, "서울 버스 100", "하계동", "용산구청"),
    # 장거리. 데이터 97% 연결.
    "seoul-654": RouteSpec(
        "seoul-654", 2907286, "서울 버스 654",
        "노들역", "방화3동주민센터.국립국어원"),
}
