extends CanvasLayer
class_name ClockHud
# 남은 시간. 오른쪽 위 — 위반 HUD 가 왼쪽 위, 승하차 HUD 가 가운데 위다.

var label_text: String:
	get: return _label.text if _label != null else ""

var _label: Label

func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.position = Vector2(-236.0, 16.0)
	_label.size = Vector2(220.0, 32.0)
	_label.add_theme_font_size_override("font_size", 24)
	add_child(_label)

func update_clock(clock: RunClock) -> void:
	if _label == null or clock == null:
		return
	var left := clock.deadline_s - clock.elapsed_s
	_label.text = text_for(left)
	_label.add_theme_color_override("font_color",
		Color.WHITE if left >= 0.0 else Color(1.0, 0.35, 0.3))

static func text_for(left_s: float) -> String:
	if left_s >= 0.0:
		return "남은 시간 " + Timetable.format_mmss(ceili(left_s))
	return "초과 +" + Timetable.format_mmss(floori(-left_s))
