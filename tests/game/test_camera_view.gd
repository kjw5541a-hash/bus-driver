extends TestCase
# 시점 전환. 버스 대신 빈 Node3D 를 표적으로 놓고 카메라 전역 위치만 본다 —
# 물리를 끼울 이유가 없다.

func _ready() -> void:
	await _test_chase_is_behind()
	await _test_first_person_is_inside()
	await _test_toggle_returns()
	await _test_first_person_ignores_zoom()
	finish()

func _make() -> Array:
	var target := Node3D.new()
	add_child(target)
	# 북(-Z)을 보고 원점에 선다. 고도트의 정면은 -Z 다.
	target.global_position = Vector3.ZERO
	target.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	var camera := ChaseCamera.new()
	camera.target = target
	add_child(camera)
	# 갓 add_child 한 노드는 이번 physics_frame 신호가 뜬 뒤에야 첫
	# _physics_process 를 받는다. 두 번 기다려야 위치가 잡힌다.
	await get_tree().physics_frame
	await get_tree().physics_frame
	return [camera, target]

func _camera_position(camera: ChaseCamera) -> Vector3:
	return camera.view.global_position

func _test_chase_is_behind() -> void:
	var made := await _make()
	var camera: ChaseCamera = made[0]
	var here := _camera_position(camera)
	# 표적이 -Z 를 보므로 추격 카메라는 +Z 쪽 뒤에 있다.
	ok(here.z > 10.0, "추격 카메라가 뒤에 없다: %s" % str(here))
	made[0].queue_free()
	made[1].queue_free()

func _test_first_person_is_inside() -> void:
	var made := await _make()
	var camera: ChaseCamera = made[0]
	camera.set_first_person(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var here := _camera_position(camera)
	ok(here.length() < 5.0, "운전석 시점이 차 밖에 있다: %s" % str(here))
	ok(here.z < 0.0, "운전석 시점이 차 뒤쪽이다: %s" % str(here))
	ok(here.y > 1.5 and here.y < 3.0, "눈높이가 아니다: %.2f" % here.y)
	made[0].queue_free()
	made[1].queue_free()

func _test_toggle_returns() -> void:
	var made := await _make()
	var camera: ChaseCamera = made[0]
	camera.set_first_person(true)
	await get_tree().physics_frame
	camera.set_first_person(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var here := _camera_position(camera)
	ok(here.z > 10.0, "추격으로 돌아오지 않았다: %s" % str(here))
	made[0].queue_free()
	made[1].queue_free()

func _test_first_person_ignores_zoom() -> void:
	var made := await _make()
	var camera: ChaseCamera = made[0]
	camera.set_first_person(true)
	await get_tree().physics_frame
	var before := _camera_position(camera)
	camera.apply_orbit(0.0, 0.0, 20.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	ok(_camera_position(camera).distance_to(before) < 0.01,
		"운전석 시점에서 휠이 카메라를 움직였다")
	made[0].queue_free()
	made[1].queue_free()
