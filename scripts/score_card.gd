extends RefCounted
class_name ScoreCard
# 구간 점수. 숫자만 받아 숫자를 낸다 — 판정은 각 Watch 가 이미 했다.
#
# 저울질: 카메라 없는 위반 한 번(-50)은 25 초를 번 것(+2 x 25)과 같다. 적색
# 대기는 평균 16.5 초, 최대 36 초라 해볼 만한 도박이다. 카메라 교차로는 대부분
# 손해다. 조정은 아래 숫자만 바꾼다.

const FINISH_POINTS := 1000
const PER_PASSENGER := 20
const EARLY_PER_S := 2
const LATE_PER_S := -5
const VIOLATION := -50
const CAMERA_VIOLATION := -150
const MISSED_STOP := -100
const LEFT_BEHIND := -10
const RESPAWN := -30
const THREE_STAR_PENALTY := 150   # 시간 항목을 뺀 감점 합이 이 이하면 별 3

var lines: Array = []
var total := 0
var stars := 1
var on_time := true

static func tally(elapsed_s: float, deadline_s: float, boarded: int,
		violations: int, camera_violations: int, missed: int,
		left_behind: int, respawns: int) -> ScoreCard:
	var card := ScoreCard.new()
	card._add("완주", 1, FINISH_POINTS)
	card._add("태운 승객", boarded, PER_PASSENGER)
	card.on_time = elapsed_s <= deadline_s
	if card.on_time:
		card._add("일찍 도착 (초)", floori(deadline_s - elapsed_s), EARLY_PER_S)
	else:
		card._add("마감 초과 (초)", floori(elapsed_s - deadline_s), LATE_PER_S)
	var penalty := 0
	penalty += card._add("신호 위반", violations - camera_violations, VIOLATION)
	penalty += card._add("카메라 단속", camera_violations, CAMERA_VIOLATION)
	penalty += card._add("놓친 정류장", missed, MISSED_STOP)
	penalty += card._add("못 태운 승객", left_behind, LEFT_BEHIND)
	penalty += card._add("리스폰", respawns, RESPAWN)
	if not card.on_time:
		card.stars = 1
	elif -penalty <= THREE_STAR_PENALTY:
		card.stars = 3
	else:
		card.stars = 2
	return card

func _add(label: String, count: int, per: int) -> int:
	"""count 가 0 이면 줄을 만들지 않는다. 더한 점수를 돌려준다."""
	if count <= 0:
		return 0
	var points := count * per
	lines.append({"label": label, "count": count, "points": points})
	total += points
	return points
