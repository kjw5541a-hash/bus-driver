extends Node3D
class_name City
# 구운 .glb 를 올리고 충돌면을 만든다. 청크 노드 목록을 쥔 유일한 곳이라,
# 거리 컬링이 필요해지면 들어갈 자리도 여기다.
#
# 아직 필요 없다. seoul-100(삼각형 133k, 청크 643개)을 M4 Pro 에서 재니
# 평균 119.7 fps / 최저 119.0 으로 vsync 상한에 붙었다. 기준은 평균 60 /
# 최저 55 다. Godot 이 MeshInstance3D 단위로 절두체 컬링을 공짜로 해준다.
var chunk_nodes: Array[Node3D] = []

func load_city(route_id: String) -> bool:
	var scene: PackedScene = load("res://assets/routes/route_%s.glb" % route_id)
	if scene == null:
		push_error("glb 를 읽지 못했다: %s" % route_id)
		return false
	var instance := scene.instantiate()
	add_child(instance)
	for node in instance.find_children("*", "MeshInstance3D", true):
		# 구운 메쉬에는 충돌체가 없다. 삼각형 메쉬 충돌을 붙여야 바퀴가 닿는다.
		node.create_trimesh_collision()
		chunk_nodes.append(node)
	_add_ground()
	return true

func _add_ground() -> void:
	# 1번 산출물의 충돌면은 도로 리본과 건물뿐이라 도로 밖은 허공이다.
	# 무한 평면 하나를 y=0 에 깔아 도로를 벗어나도 맨땅을 달리게 한다.
	# WorldBoundaryShape3D 의 기본 평면이 y=0, 법선 +Y 다. 도로 리본도
	# y=0 이라 턱이 생기지 않는다.
	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)
