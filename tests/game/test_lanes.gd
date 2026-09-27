extends TestCase
# 차선 중앙과 방향별 차선 수.

func _ready() -> void:
	equal_approx(Lanes.side_of(0, 4, 15.0, false), 1.875, 0.001, "왕복 4차선 안쪽")
	equal_approx(Lanes.side_of(1, 4, 15.0, false), 5.625, 0.001, "왕복 4차선 바깥")
	equal_approx(Lanes.side_of(0, 3, 9.6, true), -3.2, 0.001, "일방통행 왼쪽")
	equal_approx(Lanes.side_of(1, 3, 9.6, true), 0.0, 0.001, "일방통행 가운데")
	equal_approx(Lanes.side_of(2, 3, 9.6, true), 3.2, 0.001, "일방통행 오른쪽")
	ok(Lanes.count_for(4, false, true) == 2, "왕복 4차선 정방향")
	ok(Lanes.count_for(4, false, false) == 2, "왕복 4차선 역방향")
	ok(Lanes.count_for(3, true, true) == 3, "일방통행 정방향")
	ok(Lanes.count_for(3, true, false) == 0, "일방통행 마주 오는 방향")
	ok(Lanes.count_for(1, false, true) == 1, "왕복인데 차선 1")
	ok(Lanes.even_count(15.0) == 4, "15 m 는 4차선")
	ok(Lanes.even_count(20.0) == 6, "20 m 는 6차선")
	ok(Lanes.even_count(4.5) == 2, "좁아도 2차선")
	equal_approx(Lanes.outer_offset(15.0, 4), 5.625, 0.001, "바깥 차선 중앙")
	finish()
