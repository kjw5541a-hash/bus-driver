extends TestCase
# 시계. BoardingWatch 대신 on_stop_served 를 직접 부른다 — drive.gd 가
# boarding_finished 를 이 호출로 옮겨 준다.

var _finished_count := 0

func _ready() -> void:
	await _test_runs_and_finishes()
	await _test_busted_stops()
	_test_text()
	finish()

func _make() -> RunClock:
	_finished_count = 0
	var clock := RunClock.new()
	clock.start(600.0, 3)
	clock.finished.connect(func() -> void: _finished_count += 1)
	add_child(clock)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return clock

func _test_runs_and_finishes() -> void:
	var clock := await _make()
	ok(clock.elapsed_s > 0.0, "시계가 안 돈다")
	clock.on_stop_served(1, 4)
	ok(clock.is_running and not clock.is_finished, "끝 정류장이 아닌데 멈췄다")
	ok(clock.boarded_total == 4, "탑승 누적 %d" % clock.boarded_total)
	clock.on_stop_served(3, 2)
	ok(clock.is_finished and not clock.is_running, "끝 정류장에서 안 멈췄다")
	ok(clock.boarded_total == 6, "탑승 누적 %d" % clock.boarded_total)
	ok(_finished_count == 1, "finished 가 %d 번 났다" % _finished_count)
	var frozen := clock.elapsed_s
	await get_tree().physics_frame
	await get_tree().physics_frame
	equal_approx(clock.elapsed_s, frozen, 0.0001, "멈춘 뒤에도 시간이 흐른다")
	clock.on_stop_served(3, 0)
	ok(_finished_count == 1, "finished 가 두 번 났다")
	clock.queue_free()

func _test_busted_stops() -> void:
	var clock := await _make()
	clock.on_busted()
	ok(not clock.is_running and not clock.is_finished, "적발은 완주가 아니다")
	var frozen := clock.elapsed_s
	await get_tree().physics_frame
	equal_approx(clock.elapsed_s, frozen, 0.0001, "적발 뒤에도 시간이 흐른다")
	clock.queue_free()

func _test_text() -> void:
	ok(ClockHud.text_for(461.3) == "남은 시간 7:42", ClockHud.text_for(461.3))
	ok(ClockHud.text_for(0.0) == "남은 시간 0:00", ClockHud.text_for(0.0))
	ok(ClockHud.text_for(-35.7) == "초과 +0:35", ClockHud.text_for(-35.7))
