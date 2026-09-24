extends Node
class_name BusInput
# 플랫폼 입력을 축 세 개와 플래그 둘로 번역한다. bus.gd 는 PC 냐 터치냐를
# 모른다. 이 경계 덕분에 축 계산을 헤드리스로 테스트할 수 있고, 5번
# 서브프로젝트의 HUD 도 같은 통로로 계기판을 그린다.

# 화면 폭의 이만큼을 끌면 최대 조향. 고정 위치 스틱이 아니라 손가락을 댄
# 지점을 중립으로 잡는다 — 화면을 안 보고 엄지를 내리면 고정 스틱은 빗나간다.
const TOUCH_FULL_LOCK_RATIO := 0.15
# 이보다 느릴 때만 후진으로 전환한다. 달리는 중에 제동을 밟았다고 후진이
# 걸리면 안 된다.
const REVERSE_SPEED_MAX := 0.5

var steer := 0.0
var throttle := 0.0
var brake := 0.0
var reverse := false

# 터치 버튼이 눌러주는 값. TouchControls 가 직접 쓴다.
var touch_throttle := false
var touch_brake := false
var touch_reverse_toggle := false

var _respawn_pressed := false
var _view_pressed := false
# 조향을 맡은 손가락. -1 이면 아무도 안 잡고 있다.
var _steer_touch := -1
var _touch_origin_x := 0.0
var _touch_steer := 0.0
var _screen_width := 1152.0

static func steer_from_touch(origin_x: float, current_x: float,
		screen_width: float) -> float:
	"""손가락 가로 변위를 -1..1 조향축으로. 화면 폭의 15% 가 최대 조향."""
	var full := maxf(screen_width * TOUCH_FULL_LOCK_RATIO, 1.0)
	return clampf((current_x - origin_x) / full, -1.0, 1.0)

static func next_reverse(current: bool, speed: float, brake_held: bool,
		throttle_held: bool) -> bool:
	"""후진 상태 전이. 정지 상태 제동으로 켜지고, 가속으로 꺼진다."""
	if current:
		return not throttle_held
	return brake_held and speed < REVERSE_SPEED_MAX

func poll(speed: float) -> void:
	"""매 물리 프레임 호출. 축과 플래그를 갱신한다."""
	var keyboard_steer := Input.get_axis("bus_steer_left", "bus_steer_right")
	# 터치가 잡고 있으면 터치가 이긴다. 둘 다 없으면 0 으로 돌아간다.
	steer = _touch_steer if _steer_touch != -1 else keyboard_steer

	var throttle_held := Input.is_action_pressed("bus_throttle") or touch_throttle
	var brake_held := Input.is_action_pressed("bus_brake") or touch_brake

	if touch_reverse_toggle:
		# 터치는 전용 토글 버튼이다. 한 번 누르면 한 번 뒤집는다.
		touch_reverse_toggle = false
		reverse = not reverse
	else:
		reverse = next_reverse(reverse, speed, brake_held, throttle_held)

	throttle = 1.0 if throttle_held else 0.0
	brake = 1.0 if brake_held else 0.0

	if Input.is_action_just_pressed("bus_respawn"):
		_respawn_pressed = true
	if Input.is_action_just_pressed("bus_view_toggle"):
		_view_pressed = true

func take_view_toggle() -> bool:
	"""시점 전환 요청을 꺼내간다. 한 번 꺼내면 지워진다."""
	var pressed := _view_pressed
	_view_pressed = false
	return pressed

func take_respawn() -> bool:
	"""리스폰 요청을 꺼내간다. 한 번 꺼내면 지워진다."""
	var pressed := _respawn_pressed
	_respawn_pressed = false
	return pressed

func _unhandled_input(event: InputEvent) -> void:
	# 화면 왼쪽 절반만 조향을 받는다. 오른쪽은 버튼 영역이다.
	if event is InputEventScreenTouch:
		var width := float(get_viewport().get_visible_rect().size.x)
		if event.pressed:
			if event.position.x < width * 0.5 and _steer_touch == -1:
				_begin_touch(event.index, event.position.x, width)
		elif event.index == _steer_touch:
			_end_touch(event.index)
	elif event is InputEventScreenDrag and event.index == _steer_touch:
		_move_touch(event.index, event.position.x)

func _begin_touch(index: int, x: float, screen_width: float) -> void:
	_steer_touch = index
	_touch_origin_x = x
	_screen_width = screen_width
	_touch_steer = 0.0

func _move_touch(index: int, x: float) -> void:
	if index != _steer_touch:
		return
	_touch_steer = steer_from_touch(_touch_origin_x, x, _screen_width)

func _end_touch(index: int) -> void:
	if index != _steer_touch:
		return
	_steer_touch = -1
	_touch_steer = 0.0
