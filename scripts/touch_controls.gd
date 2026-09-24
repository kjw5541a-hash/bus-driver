extends CanvasLayer
class_name TouchControls
# 화면 오른쪽 버튼들. 조향은 왼쪽 절반 드래그가 맡으므로 여기 없다.
# 버튼은 BusInput 의 필드를 밀기만 한다 — 입력 해석은 전부 BusInput 안에 있다.

var input: BusInput
var respawn_requested := false
var view_toggle_requested := false

func _ready() -> void:
	_add_button("가속", Vector2(-260, -200), Vector2(140, 140), _on_throttle)
	_add_button("제동", Vector2(-120, -200), Vector2(100, 140), _on_brake)
	_add_button("후진", Vector2(-260, -60), Vector2(120, 48), _on_reverse)
	_add_button("복귀", Vector2(-130, -60), Vector2(120, 48), _on_respawn)
	_add_button("시점", Vector2(-130, -118), Vector2(120, 48), _on_view_toggle)

func _add_button(text: String, offset: Vector2, size: Vector2,
		handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	# 오른쪽 아래 기준으로 배치한다. 화면 크기가 달라도 버튼이 따라간다.
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = offset.x
	button.offset_top = offset.y
	button.offset_right = offset.x + size.x
	button.offset_bottom = offset.y + size.y
	button.button_down.connect(handler.bind(true))
	button.button_up.connect(handler.bind(false))
	add_child(button)

func _on_throttle(pressed: bool) -> void:
	if input != null:
		input.touch_throttle = pressed

func _on_brake(pressed: bool) -> void:
	if input != null:
		input.touch_brake = pressed

func _on_reverse(pressed: bool) -> void:
	# 토글은 누를 때 한 번만 반응한다. BusInput.poll 이 플래그를 소비한다.
	if pressed and input != null:
		input.touch_reverse_toggle = true

func _on_view_toggle(pressed: bool) -> void:
	if pressed:
		view_toggle_requested = true

func _on_respawn(pressed: bool) -> void:
	if pressed:
		respawn_requested = true
