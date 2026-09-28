extends TestCase
# 빗물 쌓임과 와이퍼. 셰이더 모양은 창 모드 캡처로 본다.

func _ready() -> void:
	var screen := RainScreen.new()
	add_child(screen)
	ok(not screen.is_shown(), "맑은데 빗물이 보인다")
	screen.set_rain(1.0)
	screen.step(2.0)
	equal_approx(screen.wetness, 2.0 * RainScreen.WET_RATE, 0.01, "빗물이 안 쌓인다")
	ok(screen.is_shown(), "비 오는데 빗물이 안 보인다")
	# 3초가 되면 와이퍼가 좌→우로 쓴다.
	screen.step(1.0 + RainScreen.WIPE_S / 2.0)
	ok(screen.wipe_x > 0.3 and screen.wipe_x < 0.7, "와이퍼가 중간에 없다 %.2f" % screen.wipe_x)
	screen.step(RainScreen.WIPE_S)
	ok(screen.wetness < 0.05, "닦은 뒤에도 젖어 있다 %.2f" % screen.wetness)
	equal_approx(screen.wipe_x, 0.0, 0.001, "닦은 뒤 와이퍼 위치")
	# 비가 그치면 마르고 오버레이가 꺼진다. 와이퍼도 안 돈다.
	screen.step(2.0)
	screen.set_rain(0.0)
	for i in 100:
		screen.step(0.5)
	ok(screen.wetness == 0.0, "비가 그쳤는데 안 마른다 %.2f" % screen.wetness)
	ok(not screen.is_shown(), "마른 뒤에도 오버레이가 켜져 있다")
	ok(screen.wipe_x == 0.0, "맑은데 와이퍼가 돈다")
	finish()
