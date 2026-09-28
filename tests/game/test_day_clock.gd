extends TestCase
# 게임 시각. _process 대신 advance 를 직접 불러 프레임과 무관하게 본다.

var _rolls := 0

func _ready() -> void:
	var clock := DayClock.new()
	clock.rolled_over.connect(func() -> void: _rolls += 1)
	clock.start(23 * 60 + 59)
	clock.advance(2.0)   # 1 게임분 = 2 실제 초. 24:00 을 넘는다
	equal_approx(clock.minutes, DayClock.FIRST_BUS, 0.01, "자정에 05:00 으로 안 넘어갔다")
	ok(_rolls == 1, "rolled_over 가 %d 번" % _rolls)
	clock.advance(120.0)
	equal_approx(clock.minutes, DayClock.FIRST_BUS + 60.0, 0.01, "1시간이 120초가 아니다")
	# 프레임이 크게 튀어도 범위 안.
	clock.start(1430.0)
	clock.advance(10000.0)
	ok(clock.minutes >= DayClock.FIRST_BUS and clock.minutes < DayClock.LAST,
		"시각이 범위 밖 %.1f" % clock.minutes)
	# 인자 해석.
	equal_approx(DayClock.minutes_from_args(PackedStringArray(["--time=17:42"])), 1062.0, 0.01, "17:42")
	for bad in ["--time=25:00", "--time=abc", "--time=04:00", "--time=24:00"]:
		ok(DayClock.minutes_from_args(PackedStringArray([bad])) < 0.0, "%s 를 받아들였다" % bad)
	ok(DayClock.minutes_from_args(PackedStringArray()) < 0.0, "인자 없는데 값이 나왔다")
	# start 에 음수를 주면 범위 안 무작위.
	for i in 20:
		clock.start(-1.0)
		ok(clock.minutes >= DayClock.FIRST_BUS and clock.minutes < DayClock.LAST,
			"무작위 시작 %.1f" % clock.minutes)
	ok(DayClock.hhmm(1062.0) == "17:42", "hhmm %s" % DayClock.hhmm(1062.0))
	ok(DayClock.hhmm(300.0) == "05:00", "hhmm %s" % DayClock.hhmm(300.0))
	var hud := ClockHud.new()
	add_child(hud)
	hud.update_time(1062.0)
	ok(hud.time_text == "17:42", "HUD 시각 %s" % hud.time_text)
	hud.show_first_bus()
	hud.update_time(300.0, 1.0)
	ok(hud.time_text == "첫차 05:00", "첫차 표시 %s" % hud.time_text)
	hud.update_time(301.0, 3.0)
	ok(hud.time_text == "05:01", "첫차 표시가 안 사라졌다 %s" % hud.time_text)
	hud.queue_free()
	clock.free()
	finish()
