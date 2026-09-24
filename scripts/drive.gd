extends Node3D
class_name Drive
# 주행 씬 조립. 도시를 올리고, 버스를 노선 첫 점에 놓고, 카메라와 내비 라인을
# 붙인 다음, 매 프레임 입력을 버스에 먹인다.
#
# 종점에 도착해도 아무 일도 일어나지 않는다 — 완주 판정·시간·점수는 5번
# 서브프로젝트다.

var data: RouteData
var bus: Bus
var city: City
var input: BusInput
var camera: ChaseCamera
var touch: TouchControls
var signal_field: SignalField
var patrol: PatrolCars
var watch: ViolationWatch
var hud: ViolationHud

func _ready() -> void:
	var route_id := route_id_from_args()
	data = RouteData.load_route(route_id)
	if data == null:
		push_error("노선 데이터를 읽지 못했다: %s" % route_id)
		return

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

	patrol = PatrolCars.new()
	patrol.build(data.route)
	add_child(patrol)

	watch = ViolationWatch.new()
	watch.build(data.signals)
	watch.bus = bus
	watch.patrol = patrol
	add_child(watch)

	hud = ViolationHud.new()
	add_child(hud)
	watch.violation.connect(hud.on_violation)
	watch.busted.connect(hud.on_busted)

func route_id_from_args() -> String:
	"""--route=<id> 가 있으면 그것, 없으면 메뉴가 고른 노선."""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			return argument.trim_prefix("--route=")
	return RouteData.selected_id

func _place_at_start() -> void:
	# 노선 첫 점에서 진행 방향을 보고 선다.
	bus.global_position = data.route[0] + Vector3.UP * 1.5
	bus.look_at_from_position(bus.global_position,
		data.route[1] + Vector3.UP * 1.5, Vector3.UP)

func _physics_process(delta: float) -> void:
	if bus == null or input == null:
		return
	if watch != null and watch.is_busted:
		# 적발되면 조향과 가속을 끊고 브레이크만 건다. 버스가 서서히 선다.
		bus.apply_axes(0.0, 0.0, 1.0, false, delta)
		if Input.is_key_pressed(KEY_R):
			get_tree().reload_current_scene()
		return
	input.poll(bus.linear_velocity.length())
	bus.apply_axes(input.steer, input.throttle, input.brake, input.reverse, delta)

	var view_asked := input.take_view_toggle()
	if touch != null and touch.view_toggle_requested:
		touch.view_toggle_requested = false
		view_asked = true
	if view_asked and camera != null:
		camera.toggle_view()

	var respawn_asked := input.take_respawn()
	if touch != null and touch.respawn_requested:
		touch.respawn_requested = false
		respawn_asked = true
	if respawn_asked:
		respawn()

func respawn() -> void:
	"""가장 가까운 경로점으로 노선 방향을 보게 되돌린다."""
	var index := data.nearest_index(bus.global_position)
	var look_index: int = mini(index + 1, data.route.size() - 1)
	if look_index == index:
		look_index = maxi(index - 1, 0)
	bus.respawn_to(data.route[index], data.route[look_index])
