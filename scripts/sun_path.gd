extends RefCounted
class_name SunPath
# 서울에서 본 태양 고도·방위. 균시차는 무시한다(±16분) — 게임에서 해 지는
# 시각이 몇 분 틀려도 아무도 모른다.

const LATITUDE_DEG := 37.57
const LONGITUDE_DEG := 126.98
const ZONE_MERIDIAN_DEG := 135.0   # KST = UTC+9

static func angles(day_of_year: int, minutes_kst: float) -> Vector2:
	"""(고도, 방위) 도. 방위는 북 0°, 동 90°."""
	var declination := deg_to_rad(23.44 * sin(deg_to_rad(360.0 / 365.0 * (284 + day_of_year))))
	# 서울은 표준 자오선보다 서쪽이라 태양시가 KST 보다 약 32분 늦다.
	var solar_minutes := minutes_kst - (ZONE_MERIDIAN_DEG - LONGITUDE_DEG) * 4.0
	var hour_angle := deg_to_rad(15.0 * (solar_minutes / 60.0 - 12.0))
	var latitude := deg_to_rad(LATITUDE_DEG)
	var elevation := asin(sin(latitude) * sin(declination)
		+ cos(latitude) * cos(declination) * cos(hour_angle))
	# 남쪽 기준 서쪽으로 잰 방위에 180° 를 더해 북쪽 기준으로 바꾼다.
	var azimuth := atan2(sin(hour_angle),
		cos(hour_angle) * sin(latitude) - tan(declination) * cos(latitude)) + PI
	return Vector2(rad_to_deg(elevation), fposmod(rad_to_deg(azimuth), 360.0))

static func direction(elevation_deg: float, azimuth_deg: float) -> Vector3:
	"""태양 쪽 단위벡터. +X 동, -Z 북이다(bake 투영과 같다)."""
	var e := deg_to_rad(elevation_deg)
	var a := deg_to_rad(azimuth_deg)
	return Vector3(cos(e) * sin(a), sin(e), -cos(e) * cos(a))

static func today() -> int:
	var date := Time.get_date_dict_from_system()
	var start := Time.get_unix_time_from_datetime_dict(
		{"year": date["year"], "month": 1, "day": 1})
	var now := Time.get_unix_time_from_datetime_dict(
		{"year": date["year"], "month": date["month"], "day": date["day"]})
	return int((now - start) / 86400) + 1
