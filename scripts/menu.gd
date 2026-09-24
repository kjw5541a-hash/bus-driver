extends Control
class_name Menu
# 노선 선택. 목록을 하드코딩하지 않고 assets/routes 를 훑어서 만든다 —
# 노선을 더 구우면 메뉴가 알아서 늘어난다. 노선을 누르면 구간 목록이 펼쳐진다.
# 꾸미는 일은 7번 서브프로젝트(배포) 것이다. 여기서는 고를 수만 있으면 된다.

var _routes := {}               # route_id -> RouteData
var _sections_box: VBoxContainer

func _ready() -> void:
	# 노선은 왼쪽, 구간은 오른쪽 열. 한 열에 쌓으면 구간 8 개가 화면 위로 넘친다.
	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_CENTER)
	columns.grow_horizontal = Control.GROW_DIRECTION_BOTH
	columns.grow_vertical = Control.GROW_DIRECTION_BOTH
	columns.add_theme_constant_override("separation", 24)
	add_child(columns)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	columns.add_child(box)

	var title := Label.new()
	title.text = "노선 선택"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	for route_id in RouteData.list_route_ids():
		var data := RouteData.load_route(route_id)
		if data == null:
			continue
		_routes[route_id] = data
		var button := Button.new()
		button.text = "%s\n%s → %s" % [data.display_name, data.from_name, data.to_name]
		button.custom_minimum_size = Vector2(360, 72)
		button.pressed.connect(_on_route_chosen.bind(route_id))
		box.add_child(button)

	_sections_box = VBoxContainer.new()
	_sections_box.add_theme_constant_override("separation", 8)
	columns.add_child(_sections_box)

func _on_route_chosen(route_id: String) -> void:
	RouteData.selected_id = route_id
	for child in _sections_box.get_children():
		child.queue_free()
	var data: RouteData = _routes[route_id]
	for index in maxi(1, data.sections().size()):
		var part := data.slice(index)
		var button := Button.new()
		button.text = "구간 %d · %s → %s · 마감 %s" % [index + 1,
			_stop_name(part, 0), _stop_name(part, part.stops.size() - 1),
			Timetable.format_mmss(int(Timetable.deadline_for(part)))]
		button.custom_minimum_size = Vector2(360, 48)
		button.pressed.connect(_on_section_chosen.bind(index))
		_sections_box.add_child(button)

func _stop_name(data: RouteData, index: int) -> String:
	if index < 0 or index >= data.stops.size():
		return ""
	return str(data.stops[index].get("name", ""))

func _on_section_chosen(index: int) -> void:
	RouteData.selected_section = index
	get_tree().change_scene_to_file("res://scenes/drive.tscn")
