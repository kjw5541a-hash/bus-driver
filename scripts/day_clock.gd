extends Node
class_name DayClock
# 게임 속 시각(분). 남은 시간(RunClock)과는 별개로 흐른다 — 마감에는
# 영향이 없고 해·하늘·가로등만 움직인다.
#
# 새벽에는 버스가 다니지 않으니 24:00 이 되면 첫차 05:00 으로 넘긴다.

signal rolled_over

const FIRST_BUS := 300.0   # 05:00
const LAST := 1440.0       # 24:00
const SPEED := 0.5         # 게임 분 / 실제 초. 게임 1시간이 실제 2분이다

var minutes := FIRST_BUS

func start(start_minutes: float) -> void:
	"""음수면 [05:00, 24:00) 에서 무작위로 고른다."""
	minutes = start_minutes if start_minutes >= 0.0 else randf_range(FIRST_BUS, LAST)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta_s: float) -> void:
	minutes += SPEED * delta_s
	if minutes >= LAST:
		# 한 번에 여러 날을 넘는 큰 delta 도 첫차 이후 하루 운행 시간 안에 접는다.
		minutes = FIRST_BUS + fposmod(minutes - LAST, LAST - FIRST_BUS)
		rolled_over.emit()

static func minutes_from_args(args: PackedStringArray) -> float:
	"""--time=HH:MM. 없거나 운행 시간(05:00~23:59) 밖이면 -1."""
	for argument in args:
		if not argument.begins_with("--time="):
			continue
		var parts := argument.trim_prefix("--time=").split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return -1.0
		var value := int(parts[0]) * 60.0 + int(parts[1])
		if int(parts[1]) > 59 or value < FIRST_BUS or value >= LAST:
			return -1.0
		return value
	return -1.0

static func hhmm(value: float) -> String:
	var whole := int(value)
	return "%02d:%02d" % [whole / 60, whole % 60]
