extends Node3D
class_name Drive
# 주행 씬 조립. 도시를 올리고, 버스를 노선 첫 점에 놓고, 카메라와 내비 라인을
# 붙인 다음, 매 프레임 입력을 버스에 먹인다.
#
# 노선은 구간 하나로 잘라 싣는다. 끝 정류장 승하차가 끝나면 RunClock 이
# 멈추고 결과 화면이 뜬다.

var data: RouteData
var bus: Bus
var city: City
var input: BusInput
var camera: ChaseCamera
var touch: TouchControls
var signal_field: SignalField
var traffic: Traffic
var watch: ViolationWatch
var hud: ViolationHud
var stop_field: StopField
var boarding: BoardingWatch
var boarding_hud: BoardingHud
var clock: RunClock
var clock_hud: ClockHud
var result: ResultPanel

func _ready() -> void:
	var route_id := route_id_from_args()
	data = RouteData.load_route(route_id)
	if data == null:
		push_error("노선 데이터를 읽지 못했다: %s" % route_id)
		return
	data = data.slice(section_from_args())

	city = City.new()
	add_child(city)
	if not city.load_city(route_id):
		return

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	var nav := NavLine.new()
	nav.build(data.route)
	add_child(nav)

	bus = Bus.new()
	add_child(bus)
	_place_at_start()

	input = BusInput.new()
	add_child(input)

	camera = ChaseCamera.new()
	camera.target = bus
	add_child(camera)

	touch = TouchControls.new()
	touch.input = input
	add_child(touch)

	signal_field = SignalField.new()
	signal_field.build(data.signals)
	signal_field.target = bus
	add_child(signal_field)

	traffic = Traffic.new()
	traffic.build(data, bus)
	add_child(traffic)

	watch = ViolationWatch.new()
	watch.build(data.signals)
	watch.bus = bus
	watch.traffic = traffic
	add_child(watch)

	hud = ViolationHud.new()
	add_child(hud)
	watch.violation.connect(hud.on_violation)
	watch.busted.connect(hud.on_busted)

	boarding = BoardingWatch.new()
	boarding.build(data.stop_targets)
	boarding.bus = bus
	add_child(boarding)

	stop_field = StopField.new()
	stop_field.build(data.stops, boarding.plan)
	stop_field.target = bus
	add_child(stop_field)

	boarding_hud = BoardingHud.new()
	add_child(boarding_hud)
	boarding_hud.set_route(data.stops)
	boarding.boarding_started.connect(boarding_hud.on_boarding_started)
	boarding.bell_rung.connect(boarding_hud.on_bell_rung)
	# 마지막 한 명은 정차가 끝나는 프레임에 탄다. 그때는 is_boarding 이 이미
	# 꺼져 _update_boarding_hud 가 못 치운다. 신호 안에서는 boarding_index 가
	# 아직 살아 있다.
	boarding.boarding_finished.connect(func(boarded: int, _alighted: int) -> void:
		stop_field.set_boarded(boarding.boarding_index, boarded))
	boarding.boarding_finished.connect(boarding_hud.on_boarding_finished)
	boarding.stop_missed.connect(boarding_hud.on_stop_missed)

	clock = RunClock.new()
	clock.start(Timetable.deadline_for(data), data.stops.size() - 1)
	add_child(clock)
	# boarding_index 는 boarding_finished 신호 안에서 아직 살아 있다.
	boarding.boarding_finished.connect(func(boarded: int, _alighted: int) -> void:
		clock.on_stop_served(boarding.boarding_index, boarded))
	watch.busted.connect(clock.on_busted)
	clock.finished.connect(_on_finished)

	clock_hud = ClockHud.new()
	add_child(clock_hud)

	result = ResultPanel.new()
	add_child(result)
	result.next_requested.connect(func() -> void:
		RouteData.selected_id = data.id
		RouteData.selected_section = data.section + 1
		get_tree().reload_current_scene())
	result.retry_requested.connect(func() -> void: get_tree().reload_current_scene())
	result.menu_requested.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))

func route_id_from_args() -> String:
	"""--route=<id> 가 있으면 그것, 없으면 메뉴가 고른 노선."""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			return argument.trim_prefix("--route=")
	return RouteData.selected_id

func section_from_args() -> int:
	"""--section=<n> 이 있으면 그것, 없으면 메뉴가 고른 구간. 범위 밖은 slice 가 0 으로."""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--section="):
			return int(argument.trim_prefix("--section="))
	return RouteData.selected_section

func _on_finished() -> void:
	var card := ScoreCard.tally(clock.elapsed_s, clock.deadline_s,
		clock.boarded_total, watch.violations, watch.camera_violations,
		boarding.missed, boarding.left_behind, clock.respawns)
	var title := "%s · 구간 %d/%d" % [data.display_name, data.section + 1, data.section_count]
	result.show_result(card, title, data.section < data.section_count - 1)

func _place_at_start() -> void:
	# 노선 첫 점에서 진행 방향을 보고 선다.
	bus.global_position = data.route[0] + Vector3.UP * 1.5
	bus.look_at_from_position(bus.global_position,
		data.route[1] + Vector3.UP * 1.5, Vector3.UP)

func _physics_process(delta: float) -> void:
	if bus == null or input == null:
		return
	if clock_hud != null:
		clock_hud.update_clock(clock)
	if clock != null and clock.is_finished:
		# 완주. 결과 화면이 떠 있는 동안 버스를 붙잡는다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		return
	if watch != null and watch.is_busted:
		# 적발되면 조향과 가속을 끊고 브레이크만 건다. 버스가 서서히 선다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	if boarding != null and boarding.is_boarding:
		# 문이 열려 있다. 브레이크만 걸어 버스를 붙잡는다. 승하차 시간을
		# 주행으로 건너뛸 수 없어야 시간 압박이 성립한다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		_update_boarding_hud()
		return
	input.poll(bus.linear_velocity.length())
	bus.apply_axes(input.steer, input.throttle, input.brake, input.reverse, delta)

	var view_asked := input.take_view_toggle()
	if touch != null and touch.view_toggle_requested:
		touch.view_toggle_requested = false
		view_asked = true
	if view_asked and camera != null:
		camera.toggle_view()

	_update_boarding_hud()

	var respawn_asked := input.take_respawn()
	if touch != null and touch.respawn_requested:
		touch.respawn_requested = false
		respawn_asked = true
	if respawn_asked:
		respawn()

func _update_boarding_hud() -> void:
	if boarding == null or boarding_hud == null:
		return
	boarding_hud.update_status(boarding)
	if boarding.is_boarding and stop_field != null:
		stop_field.set_boarded(boarding.boarding_index, boarding.boarded_so_far)

func respawn() -> void:
	"""가장 가까운 경로점으로 노선 방향을 보게 되돌린다."""
	if boarding != null and boarding.is_boarding:
		# 리스폰으로 승하차 시간을 건너뛸 수 없다.
		return
	var index := data.nearest_index(bus.global_position)
	var look_index: int = mini(index + 1, data.route.size() - 1)
	if look_index == index:
		look_index = maxi(index - 1, 0)
	bus.respawn_to(data.route[index], data.route[look_index])
	if clock != null:
		clock.respawns += 1
