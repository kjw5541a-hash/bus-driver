extends CanvasLayer
class_name ViolationHud
# 위반 횟수와 게임 오버를 보여준다. 판정하지 않는다 — ViolationWatch 의 일이다.
#
# 2번에서 만든 터치 컨트롤이 화면 아래와 양옆을 쓰므로 좌상단만 쓴다.

const FLASH_S := 0.4

var violations := 0
var camera_violations := 0

var _label: Label
var _flash: ColorRect
var _flash_left := 0.0
var _over: Control

func _ready() -> void:
	layer = 10

	_flash = ColorRect.new()
	_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.85))
	_label.visible = false
	add_child(_label)

	_over = _make_game_over()
	add_child(_over)

func _make_game_over() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "단속 적발 — 주행 종료"
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "R: 다시 시작"
	hint.add_theme_font_size_override("font_size", 20)
	box.add_child(hint)
	panel.add_child(box)
	return panel

func on_violation(_index: int, by_camera: bool) -> void:
	violations += 1
	if by_camera:
		camera_violations += 1
	if camera_violations > 0:
		_label.text = "위반 %d회 (카메라 %d회)" % [violations, camera_violations]
	else:
		_label.text = "위반 %d회" % violations
	_label.visible = true
	_flash_left = FLASH_S

func on_busted() -> void:
	_over.visible = true

func _process(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left = maxf(_flash_left - delta, 0.0)
	_flash.color.a = 0.45 * (_flash_left / FLASH_S)
