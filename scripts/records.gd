extends RefCounted
class_name Records
# 구간별 최고 기록. user:// 의 ConfigFile 한 개에 둔다. 섹션은 노선 id,
# 키는 "s<구간>". 파일이 없거나 깨졌으면 빈 기록으로 본다 — 기록 때문에
# 메뉴나 결과 화면이 멈추면 안 된다.

# 테스트가 실제 기록을 건드리지 않게 바꿀 수 있도록 static var 로 둔다.
static var path := "user://records.cfg"

static func best(route_id: String, section: int) -> Dictionary:
	var config := _load()
	var value = config.get_value(route_id, _key(section), {})
	if not (value is Dictionary) or not value.has("score") or not value.has("stars"):
		return {}
	return {"score": int(value["score"]), "stars": int(value["stars"])}

static func submit(route_id: String, section: int, score: int, stars: int) -> bool:
	var old := best(route_id, section)
	if not old.is_empty() and score <= old["score"]:
		return false
	var config := _load()
	config.set_value(route_id, _key(section), {"score": score, "stars": stars})
	config.save(path)
	return true

static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		# 깨진 파일은 일부만 읽혔을 수 있다. 통째로 버린다.
		config.clear()
	return config

static func _key(section: int) -> String:
	return "s%d" % section
