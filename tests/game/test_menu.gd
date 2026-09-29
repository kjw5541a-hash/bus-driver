extends TestCase
# 메뉴: 타이틀로 시작, 버전·OSM 출처 표기, 노선 → 구간, 최고 기록 표시,
# 세로 화면 배치, 결과 화면에서 돌아올 때 타이틀 건너뛰기.

const TEMP := "user://test_menu_records.cfg"

func _ready() -> void:
	Records.path = TEMP
	DirAccess.remove_absolute(TEMP)
	var ids := RouteData.list_route_ids()
	ok(ids.size() > 0, "노선이 없다")
	if ids.is_empty():
		finish()
		return
	Records.submit(ids[0], 0, 1840, 2)

	var menu := _open()
	ok(menu.title_box.visible and not menu.select_box.visible, "타이틀로 시작하지 않았다")
	ok(menu.footer.visible, "타이틀에 하단 표기가 안 보인다")
	ok(menu.footer.text.contains("OpenStreetMap"), "OSM 출처가 없다: %s" % menu.footer.text)
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	ok(menu.footer.text.contains("v" + version), "버전이 없다: %s" % menu.footer.text)

	menu.start_button.pressed.emit()
	ok(menu.select_box.visible and not menu.title_box.visible, "시작을 눌러도 선택 단계가 아니다")
	ok(menu.route_buttons.size() == ids.size(),
		"노선 버튼 %d 개, 노선 %d 개" % [menu.route_buttons.size(), ids.size()])
	var first: Button = menu.route_buttons[ids[0]]
	ok(first.text.contains("정류장") and first.text.contains("km"), "노선 정보가 없다: %s" % first.text)

	first.pressed.emit()
	ok(RouteData.selected_id == ids[0], "노선을 눌러도 선택이 안 바뀌었다")
	ok(menu.section_buttons.size() > 0, "구간 버튼이 없다")
	if menu.section_buttons.size() > 0:
		ok(menu.section_buttons[0].text.contains("최고 1840 ★★☆"),
			"기록이 안 보인다: %s" % menu.section_buttons[0].text)
	if menu.section_buttons.size() > 1:
		ok(menu.section_buttons[1].text.contains("최고 —"),
			"기록 없는 구간 표시: %s" % menu.section_buttons[1].text)

	menu.size = Vector2(720, 1280)
	ok(menu.columns.vertical, "세로 화면인데 두 열이 좌우로 놓였다")
	menu.size = Vector2(1280, 720)
	ok(not menu.columns.vertical, "가로 화면인데 두 열이 위아래로 놓였다")
	remove_child(menu)
	menu.free()

	# 결과 화면의 [메뉴]로 돌아온 경우.
	Menu.skip_title = true
	RouteData.selected_id = ids[0]
	var back := _open()
	ok(back.select_box.visible and not back.title_box.visible, "결과에서 돌아왔는데 타이틀이 떴다")
	ok(not Menu.skip_title, "skip_title 이 안 내려갔다")
	ok(back.section_buttons.size() > 0, "고르던 노선의 구간이 안 펼쳐졌다")
	ok((back.route_buttons[ids[0]] as Button).button_pressed, "고르던 노선이 강조되지 않았다")

	DirAccess.remove_absolute(TEMP)
	finish()

func _open() -> Menu:
	var menu: Menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	return menu
