extends TestCase
# 태양 위치 공식. 서울 기준 교과서 값과 비교한다.

func _ready() -> void:
	# 하지(172일) 태양 남중은 KST 12:32 쯤, 고도 90 - 37.57 + 23.44 = 75.9°.
	equal_approx(SunPath.angles(172, 752.0).x, 75.9, 1.0, "하지 남중 고도")
	# 동지(355일) 남중 고도 90 - 37.57 - 23.44 = 29.0°.
	equal_approx(SunPath.angles(355, 752.0).x, 29.0, 1.0, "동지 남중 고도")
	# 춘분(80일) 일몰은 KST 18:30 전후.
	ok(SunPath.angles(80, 18 * 60 + 15).x > 0.0, "춘분 18:15 에 해가 졌다")
	ok(SunPath.angles(80, 18 * 60 + 45).x < 0.0, "춘분 18:45 에 해가 떠 있다")
	# 오전은 동쪽(방위 < 180), 오후는 서쪽.
	ok(SunPath.angles(172, 9 * 60).y < 180.0, "오전 방위가 서쪽이다")
	ok(SunPath.angles(172, 16 * 60).y > 180.0, "오후 방위가 동쪽이다")
	# 방위 90°(동)는 +X, 고도 0 이면 y 0.
	var east := SunPath.direction(0.0, 90.0)
	ok(east.distance_to(Vector3(1, 0, 0)) < 0.001, "동쪽 벡터가 %s" % east)
	var north := SunPath.direction(0.0, 0.0)
	ok(north.distance_to(Vector3(0, 0, -1)) < 0.001, "북쪽 벡터가 %s" % north)
	ok(SunPath.today() >= 1 and SunPath.today() <= 366, "오늘 날짜 %d" % SunPath.today())
	finish()
