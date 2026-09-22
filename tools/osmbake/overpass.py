"""Overpass API 조회.

공개 인스턴스는 504 를 자주 낸다. 미러를 순회하고 재시도하며, 성공한 응답은
반드시 캐시에 남긴다. OSM 데이터는 계속 바뀌므로 캐시가 없으면 같은 명령이
다른 맵을 만든다.
"""
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
USER_AGENT = "bus-driver-osmbake/0.1"
TIMEOUT_S = 180


def fetch(query: str, cache_path: Path, *, opener=None,
          attempts: int = 3, sleep=time.sleep) -> dict:
    """쿼리 결과를 반환한다. 캐시가 있으면 그것을 쓴다."""
    cache_path = Path(cache_path)
    if cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    opener = opener or urllib.request.urlopen
    body = urllib.parse.urlencode({"data": query}).encode()
    last_error = None
    for attempt in range(attempts):
        for url in MIRRORS:
            request = urllib.request.Request(url, body, {"User-Agent": USER_AGENT})
            try:
                with opener(request, timeout=TIMEOUT_S) as response:
                    payload = json.loads(response.read())
            except Exception as error:  # 미러별 장애는 전부 다음 미러로 넘긴다
                last_error = f"{url}: {error}"
                continue
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_text(json.dumps(payload, ensure_ascii=False),
                                  encoding="utf-8")
            return payload
        sleep(5 * (attempt + 1))
    raise RuntimeError(f"Overpass 미러가 전부 실패했다: {last_error}")
