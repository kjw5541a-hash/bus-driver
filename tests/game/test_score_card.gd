extends TestCase
# 점수표. 순수 계산이라 트리가 필요 없다.

func _ready() -> void:
	var card := ScoreCard.tally(600.0, 600.0, 0, 0, 0, 0, 0, 0)
	ok(card.total == 1000, "정각 완주 %d" % card.total)
	ok(card.stars == 3, "정각 완주 별 %d" % card.stars)
	ok(card.lines.size() == 1, "0 인 항목도 줄에 들어갔다: %s" % str(card.lines))

	ok(ScoreCard.tally(590.7, 600.0, 0, 0, 0, 0, 0, 0).total == 1018, "일찍 9 초")
	card = ScoreCard.tally(610.9, 600.0, 0, 0, 0, 0, 0, 0)
	ok(card.total == 950, "초과 10 초 %d" % card.total)
	ok(card.stars == 1 and not card.on_time, "초과면 별 1")

	ok(ScoreCard.tally(600.0, 600.0, 5, 0, 0, 0, 0, 0).total == 1100, "승객 5 명")
	# 위반 3 중 1 이 카메라: 2 x -50 + 1 x -150.
	ok(ScoreCard.tally(600.0, 600.0, 0, 3, 1, 0, 0, 0).total == 750, "위반")
	ok(ScoreCard.tally(600.0, 600.0, 0, 0, 0, 1, 0, 0).total == 900, "놓친 정류장")
	ok(ScoreCard.tally(600.0, 600.0, 0, 0, 0, 0, 2, 0).total == 980, "못 태운 승객")
	ok(ScoreCard.tally(600.0, 600.0, 0, 0, 0, 0, 0, 2).total == 940, "리스폰")

	# 별 경계. 감점은 10 단위로만 움직인다.
	ok(ScoreCard.tally(600.0, 600.0, 0, 3, 0, 0, 0, 0).stars == 3, "감점 150 이면 별 3")
	ok(ScoreCard.tally(600.0, 600.0, 0, 3, 0, 0, 1, 0).stars == 2, "감점 160 이면 별 2")
	# 일찍 도착 가산은 감점 한도 계산에 안 들어간다.
	ok(ScoreCard.tally(500.0, 600.0, 0, 3, 0, 0, 1, 0).stars == 2, "시간 가산이 감점을 덮었다")
	finish()
