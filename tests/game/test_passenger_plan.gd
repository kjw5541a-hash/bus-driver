extends TestCase
# PassengerPlan 순수 로직. 노드가 아니라 트리도 대기도 필요 없다.

func _ready() -> void:
	_test_waiting_range()
	_test_destinations_are_ahead()
	_test_capacity_leaves_people()
	_test_terminus_empties_bus()
	_test_needs_stop()
	_test_dwell_formula()
	finish()

func _test_waiting_range() -> void:
	var plan := PassengerPlan.new()
	plan.build(200)
	var zero_count := 0
	for index in 200:
		var waiting := plan.waiting_at(index)
		ok(waiting >= 0 and waiting <= 8,
			"%d 번 정류장 대기 인원이 %d 명이다" % [index, waiting])
		if waiting == 0:
			zero_count += 1
	# maxi(0, randi_range(-3, 8)) 이라 0 명이 4/12 다. 200 표본이면
	# 40~95 사이에 들어온다 — 균등 분포(22 명)와 확실히 갈린다.
	ok(zero_count > 40 and zero_count < 95,
		"200 곳 중 빈 정류장이 %d 곳이다" % zero_count)

func _test_destinations_are_ahead() -> void:
	var plan := PassengerPlan.new()
	plan.build(10)
	plan.force_waiting(0, 6)
	# 0 번에서 태운 사람은 1~9 번 어딘가에서 내린다. 끝까지 훑으며 하차
	# 인원을 합하면 태운 만큼이어야 한다.
	var boarded := int(plan.serve(0, 0.0)["boarded"])
	ok(boarded == 6, "6 명이 기다렸는데 %d 명만 탔다" % boarded)
	var alighted_total := 0
	for index in range(1, 10):
		alighted_total += int(plan.serve(index, 0.0)["alighted"])
	ok(alighted_total >= boarded,
		"0 번에서 %d 명 태웠는데 뒤에서 %d 명만 내렸다"
		% [boarded, alighted_total])
	ok(plan.onboard == 0, "종점까지 훑었는데 %d 명이 남았다" % plan.onboard)

func _test_capacity_leaves_people() -> void:
	var plan := PassengerPlan.new()
	plan.build(40)
	# 앞쪽 30 곳에 8 명씩 세운다. 목적지가 뒤쪽이라 앞에서는 거의 내리지
	# 않아 정원 60 명이 반드시 찬다.
	for index in 30:
		plan.force_waiting(index, 8)
	for index in 30:
		plan.serve(index, 0.0)
	ok(plan.onboard <= PassengerPlan.CAPACITY,
		"탑승 인원이 정원을 넘었다: %d" % plan.onboard)
	ok(plan.left_behind > 0,
		"정원이 찼는데 못 탄 사람이 %d 명이다" % plan.left_behind)

func _test_terminus_empties_bus() -> void:
	var plan := PassengerPlan.new()
	plan.build(5)
	for index in 4:
		plan.force_waiting(index, 3)
		plan.serve(index, 0.0)
	var remaining := plan.onboard
	var last := plan.serve(4, 0.0)
	ok(plan.onboard == 0, "종점 하차 뒤에 %d 명이 남았다" % plan.onboard)
	ok(int(last["alighted"]) == remaining,
		"종점에서 %d 명이 남아 있었는데 %d 명만 내렸다"
		% [remaining, int(last["alighted"])])
	ok(int(last["boarded"]) == 0, "종점에서 사람이 탔다")

func _test_needs_stop() -> void:
	var plan := PassengerPlan.new()
	plan.build(4)
	for index in 4:
		plan.force_waiting(index, 0)
	ok(not plan.needs_stop(1), "아무도 없는 정류장에 서야 한다고 한다")
	ok(plan.needs_stop(3), "종점에 안 서도 된다고 한다")
	plan.force_waiting(1, 2)
	ok(plan.needs_stop(1), "대기 인원이 있는데 안 서도 된다고 한다")
	# 1 번에서 태우면 목적지는 2 나 3 이다. 둘 중 하나는 서야 한다.
	plan.serve(1, 0.0)
	ok(plan.needs_stop(2) or plan.needs_stop(3),
		"태운 사람이 내릴 정류장이 없다")

func _test_dwell_formula() -> void:
	var plan := PassengerPlan.new()
	# 아무도 없으면 문 개폐뿐이다.
	equal_approx(plan.dwell_for(0, 0, 0.0, 0), PassengerPlan.DOOR_S, 0.001,
		"빈 정류장 정차 시간")
	# 탑승과 하차는 동시다. 합이 아니라 max 다.
	equal_approx(plan.dwell_for(5, 5, 0.0, 5),
		PassengerPlan.DOOR_S + 5.0 * PassengerPlan.BOARD_S, 0.001,
		"탑승·하차 동시 진행")
	# 걸어오는 시간은 대기 인원이 있을 때만 붙는다.
	equal_approx(plan.dwell_for(0, 3, 12.0, 0),
		PassengerPlan.DOOR_S + 3.0 * PassengerPlan.ALIGHT_S, 0.001,
		"대기 0 명인데 걸어오는 시간이 붙었다")
	equal_approx(plan.dwell_for(3, 0, 12.0, 3),
		PassengerPlan.DOOR_S + 12.0 / PassengerPlan.WALK_SPEED_MPS
		+ 3.0 * PassengerPlan.BOARD_S, 0.001,
		"걸어오는 시간")
