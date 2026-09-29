extends TestCase
# 구간별 최고 기록. 실제 기록 파일을 건드리지 않게 임시 경로를 쓴다.

const TEMP := "user://test_records.cfg"

func _ready() -> void:
	Records.path = TEMP
	DirAccess.remove_absolute(TEMP)

	ok(Records.best("seoul-100", 0).is_empty(), "파일이 없는데 기록이 있다")

	ok(Records.submit("seoul-100", 0, 1500, 2), "첫 기록인데 새 기록이 아니다")
	var best := Records.best("seoul-100", 0)
	ok(best.get("score") == 1500 and best.get("stars") == 2, "기록이 %s" % best)

	ok(Records.submit("seoul-100", 0, 1800, 3), "더 높은 점수가 새 기록이 아니다")
	ok(Records.best("seoul-100", 0).get("score") == 1800, "더 높은 점수로 안 바뀌었다")
	ok(not Records.submit("seoul-100", 0, 1800, 3), "같은 점수가 새 기록이다")
	ok(not Records.submit("seoul-100", 0, 900, 1), "낮은 점수가 새 기록이다")
	ok(Records.best("seoul-100", 0).get("score") == 1800, "낮은 점수가 덮어썼다")

	# 노선과 구간이 섞이지 않는다.
	ok(Records.best("seoul-100", 1).is_empty(), "구간 1 에 구간 0 기록이 보인다")
	ok(Records.best("seoul-654", 0).is_empty(), "다른 노선에 기록이 보인다")
	Records.submit("seoul-654", 0, 700, 1)
	ok(Records.best("seoul-100", 0).get("score") == 1800, "다른 노선 저장이 기존 기록을 지웠다")

	# 깨진 파일은 빈 기록. 저장은 다시 된다.
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string("[[[ 깨진 파일 = = =")
	file.close()
	ok(Records.best("seoul-100", 0).is_empty(), "깨진 파일에서 기록이 나왔다")
	ok(Records.submit("seoul-100", 0, 100, 1), "깨진 파일 뒤 첫 기록이 안 됐다")
	ok(Records.best("seoul-100", 0).get("score") == 100, "깨진 파일 뒤 저장이 안 됐다")

	DirAccess.remove_absolute(TEMP)
	finish()
