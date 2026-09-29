extends TestCase
# 웹 빌드에는 시스템 폰트가 없다. 화면에 나올 수 있는 글자(스크립트·씬의 문자열,
# 노선 JSON 의 정류장·도로 이름)가 전부 프로젝트 폰트에 들어 있어야 한다.
# 빠진 글자는 네모로 나온다. 데스크톱은 OS 폰트로 대체돼 드러나지 않는다.

func _ready() -> void:
	var path: String = ProjectSettings.get_setting("gui/theme/custom_font", "")
	ok(path != "", "gui/theme/custom_font 가 비어 있다")
	if path == "":
		finish()
		return
	var font: Font = load(path)
	var chars := {}
	for dir in ["res://scripts", "res://scenes", "res://assets/routes"]:
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() in ["gd", "tscn", "json"]:
				_collect(FileAccess.get_file_as_string(dir + "/" + f), chars)
	var missing := []
	for c in chars:
		if not font.has_char(c):
			missing.append(String.chr(c))
	ok(missing.is_empty(), "폰트에 없는 글자: %s" % "".join(missing))
	finish()

# 주석 줄은 화면에 나오지 않으니 건너뛰고, 따옴표 안 문자열만 모은다.
func _collect(text: String, chars: Dictionary) -> void:
	var lit := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#") or s.begins_with(";"):
			continue
		for m in lit.search_all(line):
			var t := m.get_string(1)
			for i in t.length():
				var c := t.unicode_at(i)
				if c >= 0x20:
					chars[c] = true
