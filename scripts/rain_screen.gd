extends CanvasLayer
class_name RainScreen
# 앞유리(추격 시점에서는 렌즈)에 맺힌 빗물. 비 세기만큼 쌓이고, 와이퍼가
# WIPE_INTERVAL_S 마다 좌→우로 쓸어 0 으로 돌린다. 닦기 직전이 가장 흐리다.
# 비가 그치면 천천히 마르고, 다 마르면 오버레이를 꺼서 화면 복사 비용을 없앤다.

const WET_RATE := 0.25       # 비 1 에서 초당 쌓이는 양. 4초면 가득
const DRY_RATE := 0.1
const WIPE_INTERVAL_S := 3.0
const WIPE_S := 0.4
const SHADER := preload("res://shaders/rain_screen.gdshader")

var wetness := 0.0
var wipe_x := 0.0

var _rain := 0.0
var _since_wipe := 0.0
var _rect: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
	layer = -1   # 3D 바로 위, 모든 UI(터치 버튼 1, HUD 10) 아래. 글자는 안 가려진다
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)

func set_rain(amount: float) -> void:
	_rain = clampf(amount, 0.0, 1.0)

func is_shown() -> bool:
	return wetness > 0.001

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	if _rain > 0.01:
		wetness = minf(1.0, wetness + _rain * WET_RATE * delta)
		_since_wipe += delta
		if _since_wipe >= WIPE_INTERVAL_S:
			wipe_x = clampf((_since_wipe - WIPE_INTERVAL_S) / WIPE_S, 0.0, 1.0)
			if _since_wipe >= WIPE_INTERVAL_S + WIPE_S:
				wetness = 0.0
				wipe_x = 0.0
				_since_wipe = 0.0
				if _material != null:
					_material.set_shader_parameter("seed", randf() * 100.0)
	else:
		wetness = maxf(0.0, wetness - DRY_RATE * delta)
		wipe_x = 0.0
		_since_wipe = 0.0
	if _rect != null:
		_rect.visible = is_shown()
		_material.set_shader_parameter("wetness", wetness)
		_material.set_shader_parameter("wipe_x", wipe_x)
