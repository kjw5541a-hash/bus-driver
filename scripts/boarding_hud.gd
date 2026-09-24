extends CanvasLayer
class_name BoardingHud
# 다음 정류장, 탑승 인원, 승하차 진행을 보여준다. 판정하지 않는다 —
# BoardingWatch 의 일이다.
#
# 좌상단은 ViolationHud 가, 아래와 양옆은 터치 컨트롤이 쓴다. 상단 중앙만
# 쓴다. 적발 패널이 위에 오도록 layer 는 ViolationHud(10) 보다 낮게 둔다.

const MISS_FLASH_S := 1.5

var _stops: Array = []
var _next_label: Label
var _onboard_label: Label
var _progress: ProgressBar
var _miss_label: Label
var _miss_left := 0.0

func _ready() -> void:
	layer = 9

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -200.0
	box.offset_right = 200.0
	box.offset_top = 12.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_next_label = Label.new()
	_next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_next_label)

	_onboard_label = Label.new()
	_onboard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_onboard_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_onboard_label)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(320.0, 18.0)
	_progress.show_percentage = false
	_progress.visible = false
	box.add_child(_progress)

	_miss_label = Label.new()
	_miss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_miss_label.add_theme_font_size_override("font_size", 18)
	_miss_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_miss_label.visible = false
	box.add_child(_miss_label)

func set_route(stops: Array) -> void:
	_stops = stops

func update_status(next_name: String, distance_m: float, onboard: int,
		boarding_left: float, boarding_total: float) -> void:
	if distance_m < 0.0:
		_next_label.text = "종점"
	else:
		_next_label.text = "다음 %s · %d m" % [next_name, int(distance_m)]
	_onboard_label.text = "탑승 %d명" % onboard
	if boarding_left > 0.0 and boarding_total > 0.0:
		_progress.visible = true
		_progress.value = 100.0 * (1.0 - boarding_left / boarding_total)
	else:
		_progress.visible = false

func on_boarding_started(stop_index: int) -> void:
	_next_label.text = "%s 승하차 중" % _name_of(stop_index)

func on_boarding_finished(boarded: int, alighted: int) -> void:
	_progress.visible = false
	_onboard_label.text = "탄 사람 %d · 내린 사람 %d" % [boarded, alighted]

func on_stop_missed(stop_index: int) -> void:
	_miss_label.text = "%s 통과" % _name_of(stop_index)
	_miss_label.visible = true
	_miss_left = MISS_FLASH_S

func _name_of(stop_index: int) -> String:
	if stop_index < 0 or stop_index >= _stops.size():
		return ""
	return str(_stops[stop_index].get("name", ""))

func _process(delta: float) -> void:
	if _miss_left <= 0.0:
		return
	_miss_left = maxf(_miss_left - delta, 0.0)
	if _miss_left == 0.0:
		_miss_label.visible = false
