extends TestCase
# 축 계산은 순수 계산이라 헤드리스로 단언할 수 있다. 실제 입력 이벤트가 아니라
# 계산 함수를 직접 부른다 — 이벤트 주입은 플랫폼에 의존해 헤드리스에서 불안정하다.

const SCREEN := 1000.0   # 화면 폭. 15% = 150 px 가 최대 조향

func _ready() -> void:
	# 중립
	equal_approx(BusInput.steer_from_touch(500.0, 500.0, SCREEN), 0.0, 0.001,
		"터치 변위 0 이 중립이 아니다")
	# 절반(7.5%)
	equal_approx(BusInput.steer_from_touch(500.0, 575.0, SCREEN), 0.5, 0.001,
		"변위 7.5% 가 0.5 가 아니다")
	# 최대(15%)
	equal_approx(BusInput.steer_from_touch(500.0, 650.0, SCREEN), 1.0, 0.001,
		"변위 15% 가 1.0 이 아니다")
	# 최대를 넘겨도 1.0 을 넘지 않는다
	equal_approx(BusInput.steer_from_touch(500.0, 800.0, SCREEN), 1.0, 0.001,
		"변위 30% 가 1.0 을 넘었다")
	# 왼쪽은 음수
	equal_approx(BusInput.steer_from_touch(500.0, 425.0, SCREEN), -0.5, 0.001,
		"왼쪽 변위가 음수가 아니다")

	# 후진 전환: 정지 상태에서 제동을 누르면 켜진다
	ok(BusInput.next_reverse(false, 0.1, true, false),
		"정지 상태 제동이 후진으로 전환되지 않았다")
	# 주행 중 제동은 후진이 아니다
	ok(not BusInput.next_reverse(false, 8.0, true, false),
		"주행 중 제동이 후진으로 전환됐다")
	# 아무것도 안 누르면 그대로
	ok(not BusInput.next_reverse(false, 0.0, false, false),
		"입력 없이 후진이 켜졌다")
	# 후진 중 가속을 누르면 전진으로 복귀
	ok(not BusInput.next_reverse(true, 3.0, false, true),
		"후진 중 가속이 전진으로 복귀시키지 못했다")
	# 후진 중 제동만 누르면 후진 유지
	ok(BusInput.next_reverse(true, 3.0, true, false),
		"후진 중 제동이 후진을 풀었다")

	# 터치를 떼면 중립으로 돌아간다
	var input := BusInput.new()
	add_child(input)
	input._begin_touch(0, 500.0, SCREEN)
	input._move_touch(0, 650.0)
	input.poll(0.0)
	equal_approx(input.steer, 1.0, 0.001, "터치 조향이 축에 반영되지 않았다")
	input._end_touch(0)
	input.poll(0.0)
	equal_approx(input.steer, 0.0, 0.001, "터치를 뗐는데 중립으로 안 돌아갔다")

	# 키보드 축. 헤드리스에도 Input.action_press 로 눌린 상태를 만들 수 있다.
	Input.action_press("bus_steer_right")
	input.poll(0.0)
	equal_approx(input.steer, 1.0, 0.001, "D 가 steer +1 을 내지 않는다")
	Input.action_release("bus_steer_right")

	Input.action_press("bus_steer_left")
	input.poll(0.0)
	equal_approx(input.steer, -1.0, 0.001, "A 가 steer -1 을 내지 않는다")
	Input.action_release("bus_steer_left")

	Input.action_press("bus_throttle")
	input.poll(0.0)
	equal_approx(input.throttle, 1.0, 0.001, "W 가 throttle 1 을 내지 않는다")
	Input.action_release("bus_throttle")

	finish()
