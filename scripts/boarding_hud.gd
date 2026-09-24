extends CanvasLayer
class_name BoardingHud
# 다음 정류장, 탑승 인원, 승하차 진행을 보여준다. 판정하지 않는다 —
# BoardingWatch 의 일이다.
#
# 좌상단은 ViolationHud 가, 아래와 양옆은 터치 컨트롤이 쓴다. 상단 중앙만
# 쓴다. 적발 패널이 위에 오도록 layer 는 ViolationHud(10) 보다 낮게 둔다.

const MISS_FLASH_S := 1.5
const CHIME_RATE := 22050

var bell_count := 0          # 테스트가 차임이 울렸는지 본다

var _stops: Array = []
var _next_label: Label
var _onboard_label: Label
var _progress: ProgressBar
var _miss_label: Label
var _miss_left := 0.0
var _crash_label: Label
var _crash_left := 0.0
var _bell_label: Label
var _chime: AudioStreamPlayer

func _ready() -> void:
	layer = 9

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -200.0
	box.offset_right = 200.0
	box.offset_top = 12.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_crash_label = Label.new()
	_crash_label.text = "사고 — %d초 정차" % int(CrashWatch.CRASH_STOP_S)
	_crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash_label.add_theme_font_size_override("font_size", 22)
	_crash_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_crash_label.visible = false
	box.add_child(_crash_label)

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

	# 실제 버스의 "정차합니다" 표시등처럼 붉게 켜 둔다.
	_bell_label = Label.new()
	_bell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bell_label.add_theme_font_size_override("font_size", 20)
	_bell_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_bell_label.text = "● 하차벨 · 다음 정류장에서 내립니다"
	_bell_label.visible = false
	box.add_child(_bell_label)

	_chime = AudioStreamPlayer.new()
	_chime.stream = _make_chime()
	add_child(_chime)

	_miss_label = Label.new()
	_miss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_miss_label.add_theme_font_size_override("font_size", 18)
	_miss_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_miss_label.visible = false
	box.add_child(_miss_label)

func set_route(stops: Array) -> void:
	_stops = stops

func update_status(watch: BoardingWatch) -> void:
	_bell_label.visible = watch.bell_on
	if watch.is_boarding and watch.boarding_total > 0.0:
		# 몇 명 중 몇 명째인지 보여야 인원에 따라 시간이 다른 게 읽힌다.
		_next_label.text = "%s 승하차 중" % _name_of(watch.boarding_index)
		_onboard_label.text = "탑승 %d/%d · 하차 %d/%d" % [
			watch.boarded_so_far, watch.board_count,
			watch.alighted_so_far, watch.alight_count]
		_progress.visible = true
		_progress.value = 100.0 * (1.0 - watch.boarding_left / watch.boarding_total)
		return
	_progress.visible = false
	var distance_m := watch.distance_to_next()
	if distance_m < 0.0:
		_next_label.text = "종점"
	else:
		_next_label.text = "다음 %s · %d m" % [_name_of(watch.next_index), int(distance_m)]
	_onboard_label.text = "탑승 %d명" % watch.onboard

func on_boarding_started(stop_index: int) -> void:
	_next_label.text = "%s 승하차 중" % _name_of(stop_index)

func on_bell_rung(_stop_index: int) -> void:
	bell_count += 1
	_chime.play()

func _make_chime() -> AudioStreamWAV:
	"""띵동 두 음을 코드로 합성한다. 음원 파일을 들이지 않는다."""
	var data := PackedByteArray()
	for note in [[880.0, 0.18], [660.0, 0.35]]:
		var frequency: float = note[0]
		var count := int(float(note[1]) * CHIME_RATE)
		for i in count:
			var t := float(i) / CHIME_RATE
			var sample := sin(TAU * frequency * t) * exp(-t * 6.0) * 0.4
			var value := int(sample * 32767.0)
			data.append(value & 0xFF)
			data.append((value >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = CHIME_RATE
	stream.stereo = false
	stream.data = data
	return stream

func on_boarding_finished(boarded: int, alighted: int) -> void:
	_progress.visible = false
	_onboard_label.text = "탄 사람 %d · 내린 사람 %d" % [boarded, alighted]

func on_crashed() -> void:
	_crash_label.visible = true
	_crash_left = CrashWatch.CRASH_STOP_S

func on_stop_missed(stop_index: int) -> void:
	_miss_label.text = "%s 통과" % _name_of(stop_index)
	_miss_label.visible = true
	_miss_left = MISS_FLASH_S

func _name_of(stop_index: int) -> String:
	if stop_index < 0 or stop_index >= _stops.size():
		return ""
	return str(_stops[stop_index].get("name", ""))

func _process(delta: float) -> void:
	if _crash_left > 0.0:
		_crash_left = maxf(_crash_left - delta, 0.0)
		_crash_label.visible = _crash_left > 0.0
	if _miss_left <= 0.0:
		return
	_miss_left = maxf(_miss_left - delta, 0.0)
	if _miss_left == 0.0:
		_miss_label.visible = false
