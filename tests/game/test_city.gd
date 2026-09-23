extends TestCase
# 구운 .glb 가 충돌 가능한 도시로 올라오는지, 도로 밖이 허공이 아닌지 본다.

func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var world := City.new()
	root.add_child(world)

	var data := RouteData.load_route("seoul-seodaemun03")
	ok(data != null, "노선 데이터를 읽지 못했다")
	if data == null:
		finish()
		return

	ok(world.load_city("seoul-seodaemun03"), "도시를 올리지 못했다")
	ok(world.chunk_nodes.size() > 0, "청크 노드가 없다")

	# 물리 서버가 새로 붙은 충돌체를 인식할 때까지 한 틱 기다린다.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := world.get_world_3d().direct_space_state

	# 경로 첫 점 아래에는 도로가 있어야 한다.
	ok(_ray_hit_y(space, data.route[0]) > -0.5,
		"경로 첫 점 아래에 지면이 없다")

	# 도로에서 한참 떨어진 곳도 바닥 평면이 받아야 한다. 이게 없으면
	# 플레이어가 도로를 벗어나는 순간 허공으로 떨어진다.
	var far_point: Vector3 = data.route[0] + Vector3(3000.0, 0.0, 3000.0)
	ok(_ray_hit_y(space, far_point) > -0.5,
		"도로 밖에 바닥이 없다 — 벗어나면 추락한다")

	finish()

func _ray_hit_y(space: PhysicsDirectSpaceState3D, point: Vector3) -> float:
	"""point 위 30 m 에서 아래로 쏜 레이가 맞은 높이. 안 맞으면 -999."""
	var origin := Vector3(point.x, 30.0, point.z)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 60.0)
	var hit := space.intersect_ray(query)
	return -999.0 if hit.is_empty() else float(hit["position"].y)
