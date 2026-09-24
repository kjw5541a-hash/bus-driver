extends CanvasLayer
class_name ResultPanel
# 구간 완주 결과. 점수 계산은 ScoreCard 가, 다음 동작은 drive.gd 가 한다.
# 적발은 ViolationHud 의 종료 화면이 맡는다.

signal next_requested
signal retry_requested
signal menu_requested

var line_count := 0

var _box: VBoxContainer
var _next: Button
var _has_next := false

func _ready() -> void:
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	_box = VBoxContainer.new()
	outer.add_child(_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	outer.add_child(buttons)
	_next = _button(buttons, "다음 구간 (Enter)", next_requested)
	_button(buttons, "다시 하기 (R)", retry_requested)
	_button(buttons, "메뉴", menu_requested)

func _button(parent: Control, text: String, emitted: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 56)
	button.pressed.connect(func() -> void: emitted.emit())
	parent.add_child(button)
	return button

func show_result(card: ScoreCard, title: String, has_next: bool) -> void:
	for child in _box.get_children():
		child.queue_free()
	_label(title, 28)
	line_count = 0
	for line in card.lines:
		_label("%s  x%d   %+d" % [line["label"], line["count"], line["points"]], 20)
		line_count += 1
	_label("총점 %d" % card.total, 30)
	_label("★".repeat(card.stars) + "☆".repeat(3 - card.stars), 40)
	_has_next = has_next
	_next.visible = has_next
	visible = true

func _label(text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	_box.add_child(label)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and _has_next:
		next_requested.emit()
	elif event.keycode == KEY_R:
		retry_requested.emit()
