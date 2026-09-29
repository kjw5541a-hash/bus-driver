extends Control
class_name Menu
# 타이틀과 노선·구간 선택. 한 씬 안에서 두 단계를 전환한다.
# 노선 목록은 하드코딩하지 않고 assets/routes 를 훑어서 만든다 —
# 노선을 더 구우면 메뉴가 알아서 늘어난다.

# 결과 화면의 [메뉴]로 돌아올 때 타이틀을 건너뛴다. drive.gd 가 세우고
# 메뉴가 읽은 뒤 내린다. RouteData.selected_id 와 같은 이유로 static 이다.
static var skip_title := false

var title_box: VBoxContainer
var select_box: VBoxContainer
var footer: Label
var start_button: Button
var columns: BoxContainer
var route_buttons := {}                 # route_id -> Button
var section_buttons: Array[Button] = []

var _routes := {}                       # route_id -> RouteData
var _sections_box: VBoxContainer
var _group := ButtonGroup.new()

func _ready() -> void:
	_build_title()
	_build_select()
	resized.connect(_update_layout)
	_update_layout()
	var returning := skip_title
	skip_title = false
	show_select(returning)
	if returning and _routes.has(RouteData.selected_id):
		route_buttons[RouteData.selected_id].button_pressed = true
		_on_route_chosen(RouteData.selected_id)

static func footer_text() -> String:
	return "v%s · © OpenStreetMap contributors" % str(
		ProjectSettings.get_setting("application/config/version", "dev"))

func show_select(on: bool) -> void:
	title_box.visible = not on
	footer.visible = not on
	select_box.visible = on

func _build_title() -> void:
	title_box = VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 32)
	add_child(title_box)

	var name_label := Label.new()
	name_label.text = str(ProjectSettings.get_setting("application/config/name"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 56)
	title_box.add_child(name_label)

	start_button = Button.new()
	start_button.text = "시작"
	start_button.custom_minimum_size = Vector2(240, 72)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(show_select.bind(true))
	title_box.add_child(start_button)

	# OSM 출처 표기는 ODbL 라이선스 요구사항이다. 빼지 말 것.
	footer = Label.new()
	footer.text = footer_text()
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_top = -40
	footer.offset_bottom = -12
	add_child(footer)

func _build_select() -> void:
	select_box = VBoxContainer.new()
	select_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	select_box.add_theme_constant_override("separation", 12)
	add_child(select_box)

	var back := Button.new()
	back.text = "← 뒤로"
	back.custom_minimum_size = Vector2(120, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(show_select.bind(false))
	select_box.add_child(back)

	# 구간이 많거나 세로 화면이면 넘친다. 스크롤로 받는다.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	select_box.add_child(scroll)

	columns = BoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)

	var routes_box := VBoxContainer.new()
	routes_box.add_theme_constant_override("separation", 16)
	columns.add_child(routes_box)

	var heading := Label.new()
	heading.text = "노선 선택"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	routes_box.add_child(heading)

	for route_id in RouteData.list_route_ids():
		var data := RouteData.load_route(route_id)
		if data == null:
			continue
		_routes[route_id] = data
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _group
		button.text = route_text(data)
		button.custom_minimum_size = Vector2(360, 72)
		button.pressed.connect(_on_route_chosen.bind(route_id))
		routes_box.add_child(button)
		route_buttons[route_id] = button

	_sections_box = VBoxContainer.new()
	_sections_box.add_theme_constant_override("separation", 8)
	columns.add_child(_sections_box)

func _update_layout() -> void:
	# 폰 세로 화면에서는 노선 열 아래에 구간 열을 쌓는다.
	columns.vertical = size.y > size.x

static func route_text(data: RouteData) -> String:
	return "%s\n%s → %s · 정류장 %d · %.1f km" % [data.display_name,
		data.from_name, data.to_name, data.stops.size(), data.length_m() / 1000.0]

static func section_text(route_id: String, part: RouteData, index: int) -> String:
	var best := Records.best(route_id, index)
	var record := "최고 —"
	if not best.is_empty():
		record = "최고 %d %s" % [best["score"],
			"★".repeat(best["stars"]) + "☆".repeat(3 - best["stars"])]
	return "구간 %d · %s → %s · 마감 %s · %s" % [index + 1,
		_stop_name(part, 0), _stop_name(part, part.stops.size() - 1),
		Timetable.format_mmss(int(Timetable.deadline_for(part))), record]

func _on_route_chosen(route_id: String) -> void:
	RouteData.selected_id = route_id
	for child in _sections_box.get_children():
		child.queue_free()
	section_buttons.clear()
	var data: RouteData = _routes[route_id]
	for index in maxi(1, data.sections().size()):
		var button := Button.new()
		button.text = section_text(route_id, data.slice(index), index)
		button.custom_minimum_size = Vector2(360, 48)
		button.pressed.connect(_on_section_chosen.bind(index))
		_sections_box.add_child(button)
		section_buttons.append(button)

static func _stop_name(data: RouteData, index: int) -> String:
	if index < 0 or index >= data.stops.size():
		return ""
	return str(data.stops[index].get("name", ""))

func _on_section_chosen(index: int) -> void:
	RouteData.selected_section = index
	get_tree().change_scene_to_file("res://scenes/drive.tscn")
