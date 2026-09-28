extends TestCase
# 가로등 풀. 밤에만, 대상에서 가장 가까운 자리만 실제 빛을 낸다.

func _ready() -> void:
	equal_approx(StreetLights.night_amount(20.0), 0.0, 0.001, "한낮이 밤이다")
	equal_approx(StreetLights.night_amount(-10.0), 1.0, 0.001, "한밤이 밤이 아니다")

	var empty := StreetLights.new()
	add_child(empty)
	empty.build([])
	empty.set_night(1.0)
	empty.update_pool(Vector3.ZERO)
	ok(empty.lit_positions().is_empty(), "가로등이 없는데 불이 켜졌다")

	# 모바일 렌더러는 메쉬 하나에 옴니 라이트를 8개까지만 적용한다.
	ok(StreetLights.POOL <= 8, "풀이 모바일 한도를 넘는다 %d" % StreetLights.POOL)
	var lights := StreetLights.new()
	add_child(lights)
	var entries := []
	for i in 30:
		entries.append([i * 30.0, 13.0, 0.0])
	lights.build(entries)
	lights.set_night(1.0)
	lights.update_pool(Vector3(300.0, 0.0, 0.0))
	var lit := lights.lit_positions()
	# 기둥 1,400 개가 매 프레임 그려지니 기둥 하나는 삼각형 수십 개 안이어야 한다.
	for instance in lights.find_children("*", "MultiMeshInstance3D", false, false):
		var faces: int = instance.multimesh.mesh.get_faces().size() / 3
		ok(faces <= 64, "가로등 메쉬 삼각형 %d 개" % faces)
	ok(lit.size() == StreetLights.POOL, "켜진 불이 %d 개" % lit.size())
	var nearest := INF
	for spot in lit:
		nearest = minf(nearest, Vector2(spot.x - 300.0, spot.z).length())
	ok(nearest < 15.0, "가장 가까운 가로등이 안 켜졌다 %.1f" % nearest)
	for spot in lit:
		ok(absf(spot.x - 300.0) <= 4 * 30.0 + 1.0, "먼 가로등이 켜졌다 %s" % spot)
	lights.set_night(0.0)
	ok(lights.lit_positions().is_empty(), "낮인데 불이 켜져 있다")
	finish()
