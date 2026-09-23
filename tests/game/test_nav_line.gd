extends TestCase
# 내비 라인이 지면 위 올바른 높이에, 올바른 폭으로, 빠짐없이 깔리는지 본다.

const WIDTH := 1.5
const HEIGHT := 0.05

func _ready() -> void:
	var line := NavLine.new()
	add_child(line)

	# 동쪽으로 100 m, 그다음 남쪽으로 100 m 꺾이는 경로
	var route := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 100.0),
	])
	line.build(route)

	ok(line.mesh != null, "메쉬가 만들어지지 않았다")
	if line.mesh == null:
		finish()
		return

	var arrays := line.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 구간 2개 × 삼각형 2개 × 정점 3개
	ok(vertices.size() == 12, "정점이 %d 개다(12 기대)" % vertices.size())

	for vertex in vertices:
		equal_approx(vertex.y, HEIGHT, 0.0001,
			"정점 높이가 %.3f 다" % vertex.y)

	# 첫 구간은 동쪽으로 뻗으므로 폭이 z 축으로 벌어져야 한다.
	var min_z := INF
	var max_z := -INF
	for i in range(6):
		min_z = minf(min_z, vertices[i].z)
		max_z = maxf(max_z, vertices[i].z)
	equal_approx(max_z - min_z, WIDTH, 0.001,
		"리본 폭이 %.3f m 다" % (max_z - min_z))

	# 길이 0 구간이 섞여도 죽지 않아야 한다(같은 점이 연달아 나오는 경우).
	var degenerate := PackedVector3Array([
		Vector3.ZERO, Vector3.ZERO, Vector3(10.0, 0.0, 0.0),
	])
	var line2 := NavLine.new()
	add_child(line2)
	line2.build(degenerate)
	var arrays2 = line2.mesh.surface_get_arrays(0)
	ok(arrays2[Mesh.ARRAY_VERTEX].size() == 6,
		"길이 0 구간을 건너뛰지 못했다")

	finish()
