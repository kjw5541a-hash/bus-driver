extends Node
class_name TestCase
# 헤드리스 테스트 공통 뼈대. 1번의 tests/bake/verify.gd 패턴을 따른다 —
# 실패를 모았다가 마지막에 TEST_OK / TEST_FAIL 을 찍고 종료 코드로 알린다.
# GUT 같은 프레임워크를 쓰지 않는 이유는 의존성을 늘리지 않기 위해서다.

var failures: Array[String] = []

func ok(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func equal_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (실제 %.4f, 기대 %.4f ± %.4f)" % [message, actual, expected, tolerance])

func finish() -> void:
	if failures.is_empty():
		print("TEST_OK")
		get_tree().quit(0)
		return
	for failure in failures:
		print("TEST_FAIL: %s" % failure)
	get_tree().quit(1)
