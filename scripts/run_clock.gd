extends Node
class_name RunClock
# 구간 시계. 첫 프레임부터 돌고, 끝 정류장 승하차가 끝나면 멈춘다. 승하차
# 시간도 시계에 들어간다 — 그 편차가 "이번 판은 빠듯한가"를 만든다.

signal finished

var deadline_s := 0.0
var elapsed_s := 0.0
var boarded_total := 0
var respawns := 0      # drive.respawn() 이 실제로 되돌렸을 때만 올린다
var is_running := true
var is_finished := false

var _last_stop_index := -1

func start(deadline: float, last_stop_index: int) -> void:
	deadline_s = deadline
	_last_stop_index = last_stop_index

func _physics_process(delta: float) -> void:
	if is_running:
		elapsed_s += delta

func on_stop_served(stop_index: int, boarded: int) -> void:
	if is_finished:
		return
	boarded_total += boarded
	if stop_index == _last_stop_index:
		is_running = false
		is_finished = true
		finished.emit()

func on_busted() -> void:
	is_running = false
