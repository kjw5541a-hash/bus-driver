extends Control
class_name Menu
# 노선 선택. 목록을 하드코딩하지 않고 assets/routes 를 훑어서 만든다 —
# 노선을 더 구우면 메뉴가 알아서 늘어난다.
# 꾸미는 일은 7번 서브프로젝트(배포) 것이다. 여기서는 고를 수만 있으면 된다.

func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 16)
	add_child(box)

	var title := Label.new()
	title.text = "노선 선택"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	for route_id in RouteData.list_route_ids():
		var data := RouteData.load_route(route_id)
		if data == null:
			continue
		var button := Button.new()
		button.text = "%s\n%s → %s" % [data.display_name, data.from_name, data.to_name]
		button.custom_minimum_size = Vector2(360, 72)
		button.pressed.connect(_on_route_chosen.bind(route_id))
		box.add_child(button)

func _on_route_chosen(route_id: String) -> void:
	RouteData.selected_id = route_id
	get_tree().change_scene_to_file("res://scenes/drive.tscn")
