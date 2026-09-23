extends MeshInstance3D
class_name NavLine
# 노선 폴리라인을 지면 위 반투명 띠로 깐다. 실제 서울 지도 위에서 길을 잃지
# 않게 하는 최소 안내다. 정류장 마커는 3번 서브프로젝트 것이라 넣지 않는다.

const WIDTH := 1.5
const HEIGHT := 0.05   # 도로면(y=0)과 z-fighting 을 피하는 높이

func build(route: PackedVector3Array) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := WIDTH * 0.5
	for i in range(route.size() - 1):
		var start := route[i]
		var end := route[i + 1]
		var direction := Vector3(end.x - start.x, 0.0, end.z - start.z)
		if direction.length() < 0.01:
			continue   # 같은 점이 연달아 있으면 건너뛴다
		# 진행 방향의 수직 벡터. (x, z) 평면에서 90도 돌린 것.
		var side := Vector3(-direction.z, 0.0, direction.x).normalized() * half
		var a := Vector3(start.x + side.x, HEIGHT, start.z + side.z)
		var b := Vector3(start.x - side.x, HEIGHT, start.z - side.z)
		var c := Vector3(end.x - side.x, HEIGHT, end.z - side.z)
		var d := Vector3(end.x + side.x, HEIGHT, end.z + side.z)
		for vertex in [a, b, c, a, c, d]:
			surface.add_vertex(vertex)
	mesh = surface.commit()

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.55, 1.0, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 양면 렌더. 런타임 생성 메쉬의 앞면 방향을 따지느니 컬링을 끄는 게 싸다.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material
