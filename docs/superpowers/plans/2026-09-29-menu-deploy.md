# 메뉴와 배포 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 타이틀·노선 선택·최고 기록을 갖춘 메뉴와, 태그 push 로 Android APK·Windows·macOS 빌드를 GitHub Release 에 올리는 파이프라인을 만든다.

**Architecture:** 메뉴는 `scenes/menu.tscn` 한 씬 안에서 타이틀/선택 두 단계를 전환한다. 기록은 static 함수만 가진 `Records` 가 `user://records.cfg`(ConfigFile)에 둔다. 배포는 커밋된 `export_presets.cfg` 와 `.github/workflows/build.yml` 하나이고, 버전은 CI 가 `tools/set_version.py` 로 태그에서 계산해 빌드 직전에 써 넣는다.

**Tech Stack:** Godot 4.7.2(GDScript), Python 3(unittest), GitHub Actions(ubuntu-latest, macos-latest), JDK 17, Android gradle 빌드.

**Spec:** `docs/superpowers/specs/2026-09-29-menu-deploy-design.md`

## Global Constraints

- 패키지 이름 `com.kjw5541.busdriver`. 영구 고정. Android `package/unique_name`, macOS `application/bundle_identifier` 둘 다.
- 커밋되는 `project.godot` 의 `application/config/version="dev"`. Android `version/code=1`, `version/name="dev"`.
- 태그 `vX.Y.Z` 의 `version/code = X*10000 + Y*100 + Z`, Y·Z 는 99 이하. 태그가 아니면 `0.0.0-<sha7>`, code 1.
- 타이틀 하단 문구: `v<버전> · © OpenStreetMap contributors`.
- 구간 버튼 문구: `구간 N · A → B · 마감 MM:SS · 최고 <점수> <별>`, 기록 없으면 `최고 —`.
- keystore 는 저장소에 절대 커밋하지 않는다. `export_presets.cfg` 의 keystore 칸 여섯 개는 빈 문자열로 커밋한다. 저장소는 public 이다.
- 모든 preset 의 `exclude_filter="data/*, tools/*, tests/*, docs/*, *.py, .superpowers/*, build/*, android/*"`.
- `git add -A` / `git add .` 금지. 파일 이름을 명시해서 추가한다. 새 스크립트의 `.uid` 도 같이 커밋한다.
- Godot 실행 뒤에는 항상 `git checkout -q project.godot` 로 Godot 이 고쳐 쓴 것을 되돌린다. 단, 이 계획에서 `project.godot` 을 의도적으로 고친 커밋 뒤에는 그 커밋 상태로 되돌리는 것이다.
- 게임 테스트: `tests/game/run_game_tests.sh [씬 이름...]`. 새 씬은 스크립트의 목록에서 `drive_smoke` 앞에 넣는다. 통과하면 `TEST_OK` 를 찍는다.
- 파이썬 테스트: `.venv/bin/python -m unittest discover -s tests -t .`
- 코드 주석·커밋 메시지는 한국어. 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **내보낸 빌드에 노선 JSON 이 빠지는 것.** `route_*.json` 은 Godot 리소스가 아니라 `export_filter="all_resources"` 만으로는 안 들어간다. 빠지면 메뉴에 노선이 0 개다. 모든 preset 에 `include_filter="assets/routes/*.json"` 을 넣고, Task 5 의 로컬 pck 검사와 Task 6 의 CI 검사(APK·pck 안의 파일 목록)로 고정한다.
2. **`data/osm_cache`(97 MB)가 빌드에 딸려 들어가는 것.** 같은 검사에서 `osm_cache` 가 없음을 확인한다.
3. **깨진 기록 파일.** 사용자가 파일을 건드렸거나 저장 중 앱이 죽어 cfg 가 깨져도 메뉴와 완주가 멈추면 안 된다. Task 1 `test_records` 가 깨진 파일을 직접 써서 확인한다.
4. **결과 화면에서 메뉴로 돌아왔을 때 타이틀이 다시 뜨는 것, 고르던 노선이 풀리는 것.** Task 3 `test_menu` 가 `skip_title` 과 노선 자동 펼침을 확인한다.
5. **폰에서 한글이 네모(□)로 나오는 것.** 폰트를 번들하지 않고 시스템 폰트 폴백에 기댄다. 자동 테스트로는 못 잡는다. 사용자 확인 목록(Task 7)의 첫 항목이며, 깨지면 한글 폰트 번들을 별도로 진행한다.

---

## 파일 구조

- Create `scripts/records.gd`: 구간별 최고 기록 읽기·쓰기. 유일한 기록 접근 지점.
- Create `tests/game/test_records.gd`, `tests/game/test_records.tscn`
- Modify `scripts/result_panel.gd`: `show_result` 에 `new_best` 인자.
- Modify `scripts/drive.gd`: 완주 시 `Records.submit`, 메뉴 복귀 시 `Menu.skip_title = true`.
- Modify `tests/game/drive_smoke.gd`: 완주 기록 확인.
- Rewrite `scripts/menu.gd`: 타이틀/선택 두 단계, 반응형 배치.
- Create `tests/game/test_menu.gd`, `tests/game/test_menu.tscn`
- Modify `project.godot`: `config/version="dev"`, 폰 화면 회전 허용.
- Modify `tests/game/run_game_tests.sh`: 새 테스트 두 개 등록.
- Create `tools/set_version.py`, `tests/test_set_version.py`: 태그에서 버전 계산·주입.
- Create `export_presets.cfg`: Android, Windows, macOS preset.
- Modify `.gitignore`: 빌드 산출물·keystore·작업 디렉토리.
- Create `.github/workflows/build.yml`

---

### Task 1: 기록 저장소 `Records`

**Files:**
- Create: `scripts/records.gd`
- Test: `tests/game/test_records.gd`, `tests/game/test_records.tscn`
- Modify: `tests/game/run_game_tests.sh` (목록)

**Interfaces:**
- Produces:
  - `class_name Records` (extends RefCounted)
  - `static var path: String` (기본 `"user://records.cfg"`)
  - `static func best(route_id: String, section: int) -> Dictionary` — `{"score": int, "stars": int}` 또는 `{}`
  - `static func submit(route_id: String, section: int, score: int, stars: int) -> bool` — 새 최고 기록이면 저장하고 `true`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/game/test_records.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_records.gd" id="1"]

[node name="TestRecords" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_records.gd`:

```gdscript
extends TestCase
# 구간별 최고 기록. 실제 기록 파일을 건드리지 않게 임시 경로를 쓴다.

const TEMP := "user://test_records.cfg"

func _ready() -> void:
	Records.path = TEMP
	DirAccess.remove_absolute(TEMP)

	ok(Records.best("seoul-100", 0).is_empty(), "파일이 없는데 기록이 있다")

	ok(Records.submit("seoul-100", 0, 1500, 2), "첫 기록인데 새 기록이 아니다")
	var best := Records.best("seoul-100", 0)
	ok(best.get("score") == 1500 and best.get("stars") == 2, "기록이 %s" % best)

	ok(Records.submit("seoul-100", 0, 1800, 3), "더 높은 점수가 새 기록이 아니다")
	ok(Records.best("seoul-100", 0).get("score") == 1800, "더 높은 점수로 안 바뀌었다")
	ok(not Records.submit("seoul-100", 0, 1800, 3), "같은 점수가 새 기록이다")
	ok(not Records.submit("seoul-100", 0, 900, 1), "낮은 점수가 새 기록이다")
	ok(Records.best("seoul-100", 0).get("score") == 1800, "낮은 점수가 덮어썼다")

	# 노선과 구간이 섞이지 않는다.
	ok(Records.best("seoul-100", 1).is_empty(), "구간 1 에 구간 0 기록이 보인다")
	ok(Records.best("seoul-654", 0).is_empty(), "다른 노선에 기록이 보인다")
	Records.submit("seoul-654", 0, 700, 1)
	ok(Records.best("seoul-100", 0).get("score") == 1800, "다른 노선 저장이 기존 기록을 지웠다")

	# 깨진 파일은 빈 기록. 저장은 다시 된다.
	var file := FileAccess.open(TEMP, FileAccess.WRITE)
	file.store_string("[[[ 깨진 파일 = = =")
	file.close()
	ok(Records.best("seoul-100", 0).is_empty(), "깨진 파일에서 기록이 나왔다")
	ok(Records.submit("seoul-100", 0, 100, 1), "깨진 파일 뒤 첫 기록이 안 됐다")
	ok(Records.best("seoul-100", 0).get("score") == 100, "깨진 파일 뒤 저장이 안 됐다")

	DirAccess.remove_absolute(TEMP)
	finish()
```

`tests/game/run_game_tests.sh` 의 `scenes=(...)` 목록에서 `drive_smoke` 앞에 `test_records` 를 넣는다.

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `tests/game/run_game_tests.sh test_records; git checkout -q project.godot`
Expected: `test_records: FAIL`. 출력에 `Records` 식별자를 찾지 못한다는 파싱 에러.

- [ ] **Step 3: 구현**

`scripts/records.gd`:

```gdscript
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
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `tests/game/run_game_tests.sh test_records; git checkout -q project.godot`
Expected: `TEST_OK`, `test_records: OK`.

- [ ] **Step 5: 커밋**

```bash
git add scripts/records.gd scripts/records.gd.uid tests/game/test_records.gd tests/game/test_records.gd.uid tests/game/test_records.tscn tests/game/run_game_tests.sh
git commit -m "feat: 구간별 최고 기록 저장(Records)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`.uid` 파일이 아직 없으면 Godot 이 Step 4 실행 때 만든다. `ls scripts/records.gd.uid tests/game/test_records.gd.uid` 로 확인하고 추가한다.

---

### Task 2: 완주 기록과 결과 화면 표시

**Files:**
- Modify: `scripts/result_panel.gd:48-60` (`show_result`)
- Modify: `scripts/drive.gd:156-157` (menu_requested), `scripts/drive.gd:173-178` (`_on_finished`)
- Test: `tests/game/drive_smoke.gd` (`_report` 끝)

**Interfaces:**
- Consumes: `Records.submit`, `Records.best`, `Records.path` (Task 1)
- Produces:
  - `ResultPanel.show_result(card: ScoreCard, title: String, has_next: bool, new_best := false) -> void`
  - `drive.gd` 가 메뉴로 돌아가기 직전 `Menu.skip_title = true` 를 세운다. `Menu.skip_title` 은 Task 3 에서 생긴다. 이 Task 에서는 아직 없으므로 **메뉴 쪽 한 줄은 Task 3 Step 3 에서 넣는다.**

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/game/drive_smoke.gd` 의 `_report()` 에서 결과 화면 줄 수를 확인하는 블록(`ok(drive.result.visible and drive.result.line_count == 4, ...)`) 바로 뒤, `finish()` 앞에 넣는다:

```gdscript
	# 완주하면 구간 최고 기록이 남고 결과 화면에 "최고 기록!" 이 뜬다.
	# 실제 기록 파일을 건드리지 않게 임시 경로를 쓴다.
	Records.path = "user://test_drive_records.cfg"
	DirAccess.remove_absolute(Records.path)
	drive._on_finished()
	ok(not Records.best(drive.data.id, drive.data.section).is_empty(),
		"완주했는데 기록이 안 남았다")
	ok(_result_has("최고 기록!"), "새 기록인데 결과 화면에 표시가 없다")
	DirAccess.remove_absolute(Records.path)
```

같은 파일 끝에 헬퍼를 넣는다:

```gdscript
func _result_has(text: String) -> bool:
	# show_result 는 이전 줄을 queue_free 로 지워서 같은 프레임에는 옛 줄도
	# 남아 있다. 찾는 문구가 있는지만 본다.
	for label in drive.result.find_children("*", "Label", true, false):
		if (label as Label).text == text and not label.is_queued_for_deletion():
			return true
	return false
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `tests/game/run_game_tests.sh drive_smoke; git checkout -q project.godot`
Expected: `drive_smoke: FAIL`, `TEST_FAIL: 완주했는데 기록이 안 남았다` 와 `TEST_FAIL: 새 기록인데 결과 화면에 표시가 없다`.

- [ ] **Step 3: 구현**

`scripts/result_panel.gd` 의 `show_result` 를 바꾼다:

```gdscript
func show_result(card: ScoreCard, title: String, has_next: bool, new_best := false) -> void:
	for child in _box.get_children():
		child.queue_free()
	_label(title, 28)
	line_count = 0
	for line in card.lines:
		_label("%s  x%d   %+d" % [line["label"], line["count"], line["points"]], 20)
		line_count += 1
	_label("총점 %d" % card.total, 30)
	if new_best:
		_label("최고 기록!", 24)
	_label("★".repeat(card.stars) + "☆".repeat(3 - card.stars), 40)
	_has_next = has_next
	_next.visible = has_next
	visible = true
```

`scripts/drive.gd` 의 `_on_finished` 를 바꾼다:

```gdscript
func _on_finished() -> void:
	var card := ScoreCard.tally(clock.elapsed_s, clock.deadline_s,
		clock.boarded_total, watch.violations, watch.camera_violations,
		boarding.missed, boarding.left_behind, clock.respawns, crash.crashes)
	var title := "%s · 구간 %d/%d" % [data.display_name, data.section + 1, data.section_count]
	# 적발로 끝나면 이 함수가 불리지 않는다. 완주만 기록한다.
	var new_best := Records.submit(data.id, data.section, card.total, card.stars)
	result.show_result(card, title, data.section < data.section_count - 1, new_best)
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `tests/game/run_game_tests.sh drive_smoke; git checkout -q project.godot`
Expected: `TEST_OK`, `drive_smoke: OK`.

- [ ] **Step 5: 커밋**

```bash
git add scripts/result_panel.gd scripts/drive.gd tests/game/drive_smoke.gd
git commit -m "feat: 구간 완주 시 최고 기록 저장과 결과 화면 표시

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 타이틀과 노선·구간 선택 메뉴

**Files:**
- Rewrite: `scripts/menu.gd`
- Modify: `scripts/drive.gd:156-157` (menu_requested 에 `Menu.skip_title = true`)
- Modify: `project.godot` (`[application]` 에 `config/version="dev"`, `[display]` 에 회전 허용)
- Test: `tests/game/test_menu.gd`, `tests/game/test_menu.tscn`
- Modify: `tests/game/run_game_tests.sh` (목록)

**Interfaces:**
- Consumes: `Records.best`, `Records.submit`, `Records.path` (Task 1). 기존 `RouteData.list_route_ids()`, `RouteData.load_route(id)`, `RouteData.selected_id`, `RouteData.selected_section`, `RouteData.slice(i)`, `RouteData.sections()`, `RouteData.length_m()`, `Timetable.deadline_for(part)`, `Timetable.format_mmss(int)`.
- Produces:
  - `Menu.skip_title: bool` (static var)
  - `Menu.footer_text() -> String` (static)
  - 테스트가 읽는 멤버: `title_box: Control`, `select_box: Control`, `footer: Label`, `start_button: Button`, `columns: BoxContainer`, `route_buttons: Dictionary` (route_id → Button), `section_buttons: Array[Button]`

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/game/test_menu.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/game/test_menu.gd" id="1"]

[node name="TestMenu" type="Node3D"]
script = ExtResource("1")
```

`tests/game/test_menu.gd`:

```gdscript
extends TestCase
# 메뉴: 타이틀로 시작, 버전·OSM 출처 표기, 노선 → 구간, 최고 기록 표시,
# 세로 화면 배치, 결과 화면에서 돌아올 때 타이틀 건너뛰기.

const TEMP := "user://test_menu_records.cfg"

func _ready() -> void:
	Records.path = TEMP
	DirAccess.remove_absolute(TEMP)
	var ids := RouteData.list_route_ids()
	ok(ids.size() > 0, "노선이 없다")
	if ids.is_empty():
		finish()
		return
	Records.submit(ids[0], 0, 1840, 2)

	var menu := _open()
	ok(menu.title_box.visible and not menu.select_box.visible, "타이틀로 시작하지 않았다")
	ok(menu.footer.visible, "타이틀에 하단 표기가 안 보인다")
	ok(menu.footer.text.contains("OpenStreetMap"), "OSM 출처가 없다: %s" % menu.footer.text)
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	ok(menu.footer.text.contains("v" + version), "버전이 없다: %s" % menu.footer.text)

	menu.start_button.pressed.emit()
	ok(menu.select_box.visible and not menu.title_box.visible, "시작을 눌러도 선택 단계가 아니다")
	ok(menu.route_buttons.size() == ids.size(),
		"노선 버튼 %d 개, 노선 %d 개" % [menu.route_buttons.size(), ids.size()])
	var first: Button = menu.route_buttons[ids[0]]
	ok(first.text.contains("정류장") and first.text.contains("km"), "노선 정보가 없다: %s" % first.text)

	first.pressed.emit()
	ok(RouteData.selected_id == ids[0], "노선을 눌러도 선택이 안 바뀌었다")
	ok(menu.section_buttons.size() > 0, "구간 버튼이 없다")
	if menu.section_buttons.size() > 0:
		ok(menu.section_buttons[0].text.contains("최고 1840 ★★☆"),
			"기록이 안 보인다: %s" % menu.section_buttons[0].text)
	if menu.section_buttons.size() > 1:
		ok(menu.section_buttons[1].text.contains("최고 —"),
			"기록 없는 구간 표시: %s" % menu.section_buttons[1].text)

	menu.size = Vector2(720, 1280)
	ok(menu.columns.vertical, "세로 화면인데 두 열이 좌우로 놓였다")
	menu.size = Vector2(1280, 720)
	ok(not menu.columns.vertical, "가로 화면인데 두 열이 위아래로 놓였다")
	remove_child(menu)
	menu.free()

	# 결과 화면의 [메뉴]로 돌아온 경우.
	Menu.skip_title = true
	RouteData.selected_id = ids[0]
	var back := _open()
	ok(back.select_box.visible and not back.title_box.visible, "결과에서 돌아왔는데 타이틀이 떴다")
	ok(not Menu.skip_title, "skip_title 이 안 내려갔다")
	ok(back.section_buttons.size() > 0, "고르던 노선의 구간이 안 펼쳐졌다")
	ok((back.route_buttons[ids[0]] as Button).button_pressed, "고르던 노선이 강조되지 않았다")

	DirAccess.remove_absolute(TEMP)
	finish()

func _open() -> Menu:
	var menu: Menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	return menu
```

`tests/game/run_game_tests.sh` 목록에서 `drive_smoke` 앞에 `test_menu` 를 넣는다.

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `tests/game/run_game_tests.sh test_menu; git checkout -q project.godot`
Expected: `test_menu: FAIL`. `title_box` 등 없는 멤버 때문에 파싱 에러.

- [ ] **Step 3: 구현**

`scripts/menu.gd` 전체를 바꾼다:

```gdscript
extends Control
class_name Menu
# 타이틀과 노선·구간 선택. 한 씬 안에서 두 단계를 전환한다.
# 노선 목록은 하드코딩하지 않고 assets/routes 를 훑어서 만든다 —
# 노선을 더 구우면 메뉴가 알아서 늘어난다.

# 결과 화면의 [메뉴]로 돌아올 때 타이틀을 건너뛴다. drive.gd 가 세우고
# 메뉴가 읽은 뒤 내린다. RouteData.selected_id 와 같은 이유로 static 이다.
static var skip_title := false

var title_box: VBoxContainer
var select_box: VBoxContainer
var footer: Label
var start_button: Button
var columns: BoxContainer
var route_buttons := {}                 # route_id -> Button
var section_buttons: Array[Button] = []

var _routes := {}                       # route_id -> RouteData
var _sections_box: VBoxContainer
var _group := ButtonGroup.new()

func _ready() -> void:
	_build_title()
	_build_select()
	resized.connect(_update_layout)
	_update_layout()
	var returning := skip_title
	skip_title = false
	show_select(returning)
	if returning and _routes.has(RouteData.selected_id):
		route_buttons[RouteData.selected_id].button_pressed = true
		_on_route_chosen(RouteData.selected_id)

static func footer_text() -> String:
	return "v%s · © OpenStreetMap contributors" % str(
		ProjectSettings.get_setting("application/config/version", "dev"))

func show_select(on: bool) -> void:
	title_box.visible = not on
	footer.visible = not on
	select_box.visible = on

func _build_title() -> void:
	title_box = VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 32)
	add_child(title_box)

	var name_label := Label.new()
	name_label.text = str(ProjectSettings.get_setting("application/config/name"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 56)
	title_box.add_child(name_label)

	start_button = Button.new()
	start_button.text = "시작"
	start_button.custom_minimum_size = Vector2(240, 72)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.pressed.connect(show_select.bind(true))
	title_box.add_child(start_button)

	# OSM 출처 표기는 ODbL 라이선스 요구사항이다. 빼지 말 것.
	footer = Label.new()
	footer.text = footer_text()
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_top = -40
	footer.offset_bottom = -12
	add_child(footer)

func _build_select() -> void:
	select_box = VBoxContainer.new()
	select_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	select_box.add_theme_constant_override("separation", 12)
	add_child(select_box)

	var back := Button.new()
	back.text = "← 뒤로"
	back.custom_minimum_size = Vector2(120, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(show_select.bind(false))
	select_box.add_child(back)

	# 구간이 많거나 세로 화면이면 넘친다. 스크롤로 받는다.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	select_box.add_child(scroll)

	columns = BoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)

	var routes_box := VBoxContainer.new()
	routes_box.add_theme_constant_override("separation", 16)
	columns.add_child(routes_box)

	var heading := Label.new()
	heading.text = "노선 선택"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	routes_box.add_child(heading)

	for route_id in RouteData.list_route_ids():
		var data := RouteData.load_route(route_id)
		if data == null:
			continue
		_routes[route_id] = data
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _group
		button.text = route_text(data)
		button.custom_minimum_size = Vector2(360, 72)
		button.pressed.connect(_on_route_chosen.bind(route_id))
		routes_box.add_child(button)
		route_buttons[route_id] = button

	_sections_box = VBoxContainer.new()
	_sections_box.add_theme_constant_override("separation", 8)
	columns.add_child(_sections_box)

func _update_layout() -> void:
	# 폰 세로 화면에서는 노선 열 아래에 구간 열을 쌓는다.
	columns.vertical = size.y > size.x

static func route_text(data: RouteData) -> String:
	return "%s\n%s → %s · 정류장 %d · %.1f km" % [data.display_name,
		data.from_name, data.to_name, data.stops.size(), data.length_m() / 1000.0]

static func section_text(route_id: String, part: RouteData, index: int) -> String:
	var best := Records.best(route_id, index)
	var record := "최고 —"
	if not best.is_empty():
		record = "최고 %d %s" % [best["score"],
			"★".repeat(best["stars"]) + "☆".repeat(3 - best["stars"])]
	return "구간 %d · %s → %s · 마감 %s · %s" % [index + 1,
		_stop_name(part, 0), _stop_name(part, part.stops.size() - 1),
		Timetable.format_mmss(int(Timetable.deadline_for(part))), record]

func _on_route_chosen(route_id: String) -> void:
	RouteData.selected_id = route_id
	for child in _sections_box.get_children():
		child.queue_free()
	section_buttons.clear()
	var data: RouteData = _routes[route_id]
	for index in maxi(1, data.sections().size()):
		var button := Button.new()
		button.text = section_text(route_id, data.slice(index), index)
		button.custom_minimum_size = Vector2(360, 48)
		button.pressed.connect(_on_section_chosen.bind(index))
		_sections_box.add_child(button)
		section_buttons.append(button)

static func _stop_name(data: RouteData, index: int) -> String:
	if index < 0 or index >= data.stops.size():
		return ""
	return str(data.stops[index].get("name", ""))

func _on_section_chosen(index: int) -> void:
	RouteData.selected_section = index
	get_tree().change_scene_to_file("res://scenes/drive.tscn")
```

`scripts/drive.gd` 의 menu_requested 연결을 바꾼다:

```gdscript
	result.menu_requested.connect(func() -> void:
		Menu.skip_title = true
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
```

`project.godot` 의 `[application]` 섹션에 `config/icon=...` 줄 다음으로 넣는다:

```
config/version="dev"
```

`project.godot` 에 `[display]` 섹션이 없으므로 `[input_devices]` 앞에 새로 넣는다. 6 은 센서 방향(가로·세로 모두)이다:

```
[display]

window/handheld/orientation=6
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `tests/game/run_game_tests.sh test_menu drive_smoke; git diff --stat project.godot`
Expected: 두 테스트 모두 `OK`. `project.godot` 의 차이는 이번에 넣은 두 부분뿐. Godot 이 다른 줄을 고쳤으면 `git diff project.godot` 로 보고 그 줄만 되돌린다.

- [ ] **Step 5: 전체 게임 테스트**

Run: `tests/game/run_game_tests.sh > /tmp/claude-game.log 2>&1; echo $?; grep -c ": OK$" /tmp/claude-game.log; grep ": FAIL$" /tmp/claude-game.log`
Expected: 종료 코드 0, OK 29 개, FAIL 없음.

- [ ] **Step 6: 커밋**

```bash
git add scripts/menu.gd scripts/drive.gd project.godot tests/game/test_menu.gd tests/game/test_menu.gd.uid tests/game/test_menu.tscn tests/game/run_game_tests.sh
git commit -m "feat: 타이틀·노선 선택 메뉴, 버전과 OSM 출처 표기, 세로 화면 대응

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: 눈으로 확인 (창 모드, 샌드박스 밖)**

Run: `/opt/homebrew/bin/godot --path . res://scenes/menu.tscn` (dangerouslyDisableSandbox). 창에서 타이틀 → 시작 → 노선 → 구간이 보이는지, 창을 세로로 길게 늘리면 두 열이 위아래로 쌓이는지 캡처하거나 사용자에게 보여 준다. 끝나면 `git checkout -q project.godot`.

---

### Task 4: 태그에서 버전 계산 `tools/set_version.py`

**Files:**
- Create: `tools/set_version.py`
- Test: `tests/test_set_version.py`

**Interfaces:**
- Produces:
  - `version_for(ref_name: str, sha: str) -> tuple[str, int]`
  - `apply(project_text: str, presets_text: str, name: str, code: int) -> tuple[str, str]` — 바꿀 줄이 없으면 `ValueError`
  - CLI: `python tools/set_version.py <ref_name> <sha>` 가 저장소 루트의 `project.godot`, `export_presets.cfg` 를 고쳐 쓰고 `<name> <code>` 를 출력.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/test_set_version.py`:

```python
"""태그에서 버전을 정하고 project.godot, export_presets.cfg 에 써 넣는다."""
import unittest

from tools.set_version import apply, version_for

PROJECT = '[application]\nconfig/name="버스 운전"\nconfig/version="dev"\n'
PRESETS = (
    '[preset.0.options]\nversion/code=1\nversion/name="dev"\n'
    'package/unique_name="com.kjw5541.busdriver"\n'
)


class VersionForTest(unittest.TestCase):
    def test_tag(self):
        self.assertEqual(version_for("v1.2.3", "abcdef1234"), ("1.2.3", 10203))

    def test_code_grows_with_tags(self):
        codes = [version_for(t, "x")[1] for t in ["v0.1.0", "v0.1.9", "v0.2.0", "v1.0.0"]]
        self.assertEqual(codes, sorted(codes))
        self.assertEqual(len(set(codes)), len(codes))

    def test_branch_is_dev_build(self):
        self.assertEqual(version_for("menu-deploy", "abcdef1234"), ("0.0.0-abcdef1", 1))

    def test_malformed_tag_is_dev_build(self):
        self.assertEqual(version_for("v1.2", "abcdef1234"), ("0.0.0-abcdef1", 1))

    def test_minor_over_99_rejected(self):
        with self.assertRaises(ValueError):
            version_for("v1.100.0", "x")


class ApplyTest(unittest.TestCase):
    def test_writes_all_three(self):
        project, presets = apply(PROJECT, PRESETS, "1.2.3", 10203)
        self.assertIn('config/version="1.2.3"', project)
        self.assertIn("version/code=10203", presets)
        self.assertIn('version/name="1.2.3"', presets)
        self.assertIn('package/unique_name="com.kjw5541.busdriver"', presets)

    def test_missing_line_raises(self):
        with self.assertRaises(ValueError):
            apply('[application]\nconfig/name="x"\n', PRESETS, "1.0.0", 10000)
        with self.assertRaises(ValueError):
            apply(PROJECT, "[preset.0.options]\n", "1.0.0", 10000)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `.venv/bin/python -m unittest tests.test_set_version -v`
Expected: `ModuleNotFoundError: No module named 'tools.set_version'`.

- [ ] **Step 3: 구현**

`tools/set_version.py`:

```python
"""태그에서 버전을 정해 project.godot 과 export_presets.cfg 에 써 넣는다. CI 전용.

    python tools/set_version.py <ref_name> <sha>

태그 vX.Y.Z 면 버전 X.Y.Z, 안드로이드 version/code 는 X*10000 + Y*100 + Z.
Play 는 version/code 가 줄어든 업로드를 거부하므로 Y, Z 는 99 를 넘지 않게 한다.
태그가 아니면(브랜치 빌드) 0.0.0-<sha7>, code 1.
"""
import re
import sys
from pathlib import Path

TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def version_for(ref_name, sha):
    match = TAG.match(ref_name)
    if not match:
        return "0.0.0-%s" % sha[:7], 1
    major, minor, patch = (int(part) for part in match.groups())
    if minor > 99 or patch > 99:
        raise ValueError("Y, Z 는 99 이하여야 한다: %s" % ref_name)
    return "%d.%d.%d" % (major, minor, patch), major * 10000 + minor * 100 + patch


def _replace(text, pattern, line):
    # 줄이 없으면 조용히 넘어가지 않는다. 버전이 안 들어간 빌드가 나가면 안 된다.
    result, count = re.subn(pattern, line, text, flags=re.M)
    if count == 0:
        raise ValueError("바꿀 줄이 없다: %s" % pattern)
    return result


def apply(project_text, presets_text, name, code):
    project = _replace(project_text, r'^config/version=".*"$', 'config/version="%s"' % name)
    presets = _replace(presets_text, r"^version/code=\d+$", "version/code=%d" % code)
    presets = _replace(presets, r'^version/name=".*"$', 'version/name="%s"' % name)
    return project, presets


def main(argv):
    name, code = version_for(argv[1], argv[2])
    project = Path("project.godot")
    presets = Path("export_presets.cfg")
    new_project, new_presets = apply(
        project.read_text(encoding="utf-8"), presets.read_text(encoding="utf-8"), name, code)
    project.write_text(new_project, encoding="utf-8")
    presets.write_text(new_presets, encoding="utf-8")
    print(name, code)


if __name__ == "__main__":
    main(sys.argv)
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `.venv/bin/python -m unittest tests.test_set_version -v`
Expected: 7 개 모두 `ok`.

Run: `.venv/bin/python -m unittest discover -s tests -t . 2>&1 | tail -3`
Expected: `Ran 176 tests`, `OK`.

- [ ] **Step 5: 커밋**

```bash
git add tools/set_version.py tests/test_set_version.py
git commit -m "feat: 태그에서 빌드 버전을 계산해 써 넣는 스크립트

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: export preset 과 .gitignore

**Files:**
- Create: `export_presets.cfg`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `tools/set_version.py` 가 찾는 `version/code=1`, `version/name="dev"` 줄 (Task 4)
- Produces: preset 이름 `Android`, `Windows`, `macOS` (Task 6 의 `--export-release` 인자). 적지 않은 옵션은 Godot 이 기본값으로 채운다.

- [ ] **Step 1: `.gitignore` 에 추가**

```
# 빌드 산출물과 CI 가 푸는 안드로이드 빌드 템플릿
build/
android/
# 서명 키는 저장소에 절대 넣지 않는다
*.jks
*.keystore
# superpowers 작업 기록
.superpowers/
```

- [ ] **Step 2: `export_presets.cfg` 작성**

```
[preset.0]

name="Android"
platform="Android"
runnable=true
export_filter="all_resources"
; 노선 JSON 은 Godot 리소스가 아니라 all_resources 에 안 잡힌다. 빠지면 메뉴가 빈다.
include_filter="assets/routes/*.json"
exclude_filter="data/*, tools/*, tests/*, docs/*, *.py, .superpowers/*, build/*, android/*"
export_path="build/bus-driver.apk"

[preset.0.options]

gradle_build/use_gradle_build=true
; 0 = APK. Play 로 넘어갈 때 1(AAB) 인 preset 을 따로 둔다.
gradle_build/export_format=0
gradle_build/min_sdk="24"
gradle_build/target_sdk="36"
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
; version 두 줄은 CI 가 tools/set_version.py 로 덮어쓴다.
version/code=1
version/name="dev"
; 패키지 이름은 영구 고정. Play 가 이 이름으로 앱을 식별한다.
package/unique_name="com.kjw5541.busdriver"
package/name="버스 운전"
package/signed=true
screen/immersive_mode=true
permissions/internet=false
; 아래 keystore 값은 CI 가 빌드 직전에만 비밀값으로 채워 넣는다 — 커밋에는
; 절대 실제 값이 들어가면 안 된다. 이 저장소는 public 이다.
keystore/debug=""
keystore/debug_user=""
keystore/debug_password=""
keystore/release=""
keystore/release_user=""
keystore/release_password=""

[preset.1]

name="Windows"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="assets/routes/*.json"
exclude_filter="data/*, tools/*, tests/*, docs/*, *.py, .superpowers/*, build/*, android/*"
export_path="build/windows/bus-driver.exe"

[preset.1.options]

binary_format/architecture="x86_64"
; 리눅스 러너에서 exe 리소스를 고치려면 rcedit+wine 이 필요하다. 끈다.
application/modify_resources=false

[preset.2]

name="macOS"
platform="macOS"
runnable=true
export_filter="all_resources"
include_filter="assets/routes/*.json"
exclude_filter="data/*, tools/*, tests/*, docs/*, *.py, .superpowers/*, build/*, android/*"
export_path="build/bus-driver-macos.zip"

[preset.2.options]

binary_format/architecture="universal"
application/bundle_identifier="com.kjw5541.busdriver"
; 1 = 내장 ad-hoc 서명. Apple Silicon 은 서명이 전혀 없는 바이너리를 실행하지 않는다.
; 공증은 하지 않으므로 처음 한 번은 우클릭 → 열기가 필요하다.
codesign/codesign=1
notarization/notarization=0
```

- [ ] **Step 3: preset 이 읽히고 pck 에 노선 JSON 이 들어가는지 로컬 확인**

pck 만 만드는 `--export-pack` 은 export 템플릿이 없어도 된다.

Run:
```bash
mkdir -p build && /opt/homebrew/bin/godot --headless --export-pack "Windows" build/check.pck > build/check.log 2>&1; echo "exit $?"; ls -la build/check.pck; grep -ac "assets/routes/route_seoul-100.json" build/check.pck; grep -ac "osm_cache" build/check.pck; grep -ac "tests/game" build/check.pck; git checkout -q project.godot
```
Expected: `exit 0`, pck 크기 수십 MB, `route_seoul-100.json` 개수 1 이상, `osm_cache` 0, `tests/game` 0.
0 이 아니거나 export 가 실패하면 `build/check.log` 의 에러를 보고 preset 을 고친다. `--export-pack` 이 템플릿을 요구해서 실패하면 이 검사를 Task 6 CI 로 넘기고 ledger 에 Ruling 을 남긴다.

Run: `.venv/bin/python -c "from tools.set_version import apply; from pathlib import Path; apply(Path('project.godot').read_text(), Path('export_presets.cfg').read_text(), '9.9.9', 90909); print('ok')"`
Expected: `ok` (실제 파일에서 바꿀 줄을 모두 찾는다).

- [ ] **Step 4: 커밋**

```bash
rm -rf build
git status --short
git add export_presets.cfg .gitignore
git commit -m "build: Android·Windows·macOS export preset

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`git status --short` 에 `.jks`, `.keystore`, `build/`, `android/` 가 보이면 멈추고 사용자에게 알린다.

---

### Task 6: GitHub Actions 빌드·릴리스

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: preset `Android`/`Windows`/`macOS` (Task 5), `tools/set_version.py <ref_name> <sha>` (Task 4), `tests/game/run_game_tests.sh` (`GODOT` 환경변수).
- Produces: artifact `apk`, `windows`, `macos`. 태그면 Release 에 `bus-driver-X.Y.Z.apk`, `bus-driver-X.Y.Z-windows.zip`, `bus-driver-X.Y.Z-macos.zip`.

- [ ] **Step 1: 사용자에게 keystore 생성과 secret 등록 요청 (사용자가 직접)**

에이전트가 비밀번호를 정하거나 키를 만들지 않는다. 사용자에게 다음을 `!` 로 실행해 달라고 요청하고, 끝났다는 답을 기다린다:

```
mkdir -p ~/keys
keytool -genkeypair -v -keystore ~/keys/bus-driver-release.jks -alias busdriver -keyalg RSA -keysize 4096 -validity 36500
gh secret set ANDROID_KEYSTORE_BASE64 -R kjw5541a-hash/bus-driver < <(base64 -i ~/keys/bus-driver-release.jks)
gh secret set ANDROID_KEYSTORE_PASSWORD -R kjw5541a-hash/bus-driver
gh secret set ANDROID_KEY_ALIAS -R kjw5541a-hash/bus-driver --body busdriver
```

그리고 알린다: keystore 를 잃어버리면 같은 앱으로 업데이트할 수 없다. `~/keys/bus-driver-release.jks` 와 비밀번호를 오프라인에 따로 백업할 것.

Run: `gh secret list -R kjw5541a-hash/bus-driver`
Expected: 세 이름이 모두 보인다.

- [ ] **Step 2: 워크플로 작성**

`.github/workflows/build.yml`:

```yaml
name: Build

# 브랜치 push: 테스트 + 안드로이드 빌드(로컬에 SDK 가 없어 이것이 유일한 검증).
# v* 태그 push: 세 플랫폼 빌드 후 GitHub Release 에 올린다.
on:
  push:
    branches: ['**']
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: read

env:
  GODOT_VERSION: 4.7.2

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.13'
      - name: Install Godot
        run: |
          set -euo pipefail
          base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
          curl -fsSL -o godot.zip "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          unzip -q godot.zip
          install -m 755 "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot
      - name: Python tests
        run: |
          pip install -r requirements.txt
          python -m unittest discover -s tests -t .
      - name: Game tests
        run: tests/game/run_game_tests.sh
        env:
          GODOT: /usr/local/bin/godot

  android:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # Godot 의 그레이들 빌드가 JDK 17 을 요구한다.
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: '17'
      - name: Cache export templates
        id: templates
        uses: actions/cache@v4
        with:
          path: ~/.local/share/godot/export_templates
          key: godot-android-templates-${{ env.GODOT_VERSION }}
      - name: Install Godot
        run: |
          set -euo pipefail
          base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
          curl -fsSL -o godot.zip "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          unzip -q godot.zip
          install -m 755 "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot
      - name: Install export templates
        if: steps.templates.outputs.cache-hit != 'true'
        run: |
          set -euo pipefail
          base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
          curl -fsSL -o templates.tpz "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
          dest="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
          mkdir -p "$dest"
          unzip -q -o -j templates.tpz 'templates/android_*' 'templates/version.txt' -d "$dest"
      # 에디터의 "Install Android Build Template" 메뉴가 하는 일을 흉내 낸다
      # (3DBlockBreaker 에서 검증). .build_version 이 없으면 export 가 막힌다.
      - name: Install Android build template
        run: |
          set -euo pipefail
          dest="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
          mkdir -p android/build
          printf '%s.stable\n' "$GODOT_VERSION" > android/.build_version
          echo "" > android/build/.gdignore
          unzip -q -o "$dest/android_source.zip" -d android/build
      - name: Set version
        run: python3 tools/set_version.py "$GITHUB_REF_NAME" "$GITHUB_SHA"
      # 키스토어는 비밀값으로만 존재한다. 파일로 풀고 preset 에 써 넣는 일은
      # 이 러너 안에서만 벌어진다 — 커밋되지 않는다.
      - name: Write keystore
        run: |
          set -euo pipefail
          echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > /tmp/release.jks
          python3 - <<'PY'
          import os
          p = 'export_presets.cfg'
          s = open(p, encoding='utf-8').read()
          s = s.replace('keystore/release=""', 'keystore/release="/tmp/release.jks"')
          s = s.replace('keystore/release_user=""',
              'keystore/release_user="%s"' % os.environ['ANDROID_KEY_ALIAS'])
          s = s.replace('keystore/release_password=""',
              'keystore/release_password="%s"' % os.environ['ANDROID_KEYSTORE_PASSWORD'])
          open(p, 'w', encoding='utf-8').write(s)
          PY
        env:
          ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
      - name: Export APK
        run: |
          set -euo pipefail
          mkdir -p build
          godot --headless --import >/dev/null 2>&1 || true
          godot --headless --export-release "Android" build/bus-driver.apk
          test -s build/bus-driver.apk
      # 노선 JSON 이 들어가고 원본 OSM 캐시가 빠졌는지 본다.
      - name: Check APK contents
        run: |
          set -euo pipefail
          unzip -l build/bus-driver.apk > build/apk.txt
          grep -q 'route_seoul-100.json' build/apk.txt
          ! grep -q 'osm_cache' build/apk.txt
          ls -la build/bus-driver.apk
      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: build/bus-driver.apk
          retention-days: 7

  windows:
    if: startsWith(github.ref, 'refs/tags/v')
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Cache export templates
        id: templates
        uses: actions/cache@v4
        with:
          path: ~/.local/share/godot/export_templates
          key: godot-windows-templates-${{ env.GODOT_VERSION }}
      - name: Install Godot
        run: |
          set -euo pipefail
          base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
          curl -fsSL -o godot.zip "$base/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          unzip -q godot.zip
          install -m 755 "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot
      - name: Install export templates
        if: steps.templates.outputs.cache-hit != 'true'
        run: |
          set -euo pipefail
          base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
          curl -fsSL -o templates.tpz "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
          dest="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
          mkdir -p "$dest"
          unzip -q -o -j templates.tpz 'templates/windows_*' 'templates/version.txt' -d "$dest"
      - name: Set version
        run: python3 tools/set_version.py "$GITHUB_REF_NAME" "$GITHUB_SHA"
      - name: Export Windows
        run: |
          set -euo pipefail
          mkdir -p build/windows
          godot --headless --import >/dev/null 2>&1 || true
          godot --headless --export-release "Windows" build/windows/bus-driver.exe
          test -s build/windows/bus-driver.exe
          grep -aq 'route_seoul-100.json' build/windows/bus-driver.pck
          ! grep -aq 'osm_cache' build/windows/bus-driver.pck
          cd build/windows && zip -q ../bus-driver-windows.zip ./*
      - uses: actions/upload-artifact@v4
        with:
          name: windows
          path: build/bus-driver-windows.zip
          retention-days: 7

  macos:
    if: startsWith(github.ref, 'refs/tags/v')
    needs: test
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Cache export templates
        id: templates
        uses: actions/cache@v4
        with:
          path: ~/Library/Application Support/Godot/export_templates
          key: godot-macos-templates-${{ env.GODOT_VERSION }}
      - name: Install Godot
        run: |
          set -euo pipefail
          base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
          curl -fsSL -o godot.zip "$base/Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
          unzip -q godot.zip
          echo "GODOT_BIN=$PWD/Godot.app/Contents/MacOS/Godot" >> "$GITHUB_ENV"
      - name: Install export templates
        if: steps.templates.outputs.cache-hit != 'true'
        run: |
          set -euo pipefail
          base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
          curl -fsSL -o templates.tpz "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
          dest="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
          mkdir -p "$dest"
          unzip -q -o -j templates.tpz 'templates/macos.zip' 'templates/version.txt' -d "$dest"
      - name: Set version
        run: python3 tools/set_version.py "$GITHUB_REF_NAME" "$GITHUB_SHA"
      - name: Export macOS
        run: |
          set -euo pipefail
          mkdir -p build
          "$GODOT_BIN" --headless --import >/dev/null 2>&1 || true
          "$GODOT_BIN" --headless --export-release "macOS" build/bus-driver-macos.zip
          test -s build/bus-driver-macos.zip
      # ad-hoc 서명이 붙었는지 본다. 없으면 Apple Silicon 에서 아예 안 열린다.
      - name: Check signature
        run: |
          set -euo pipefail
          mkdir -p build/check && cd build/check && unzip -q ../bus-driver-macos.zip
          codesign -dv ./*.app 2>&1 | tee sig.txt
          grep -q 'Signature=adhoc' sig.txt
      - uses: actions/upload-artifact@v4
        with:
          name: macos
          path: build/bus-driver-macos.zip
          retention-days: 7

  release:
    if: startsWith(github.ref, 'refs/tags/v')
    needs: [android, windows, macos]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: dist
      - name: Create release
        run: |
          set -euo pipefail
          version="${GITHUB_REF_NAME#v}"
          mv dist/apk/bus-driver.apk "bus-driver-${version}.apk"
          mv dist/windows/bus-driver-windows.zip "bus-driver-${version}-windows.zip"
          mv dist/macos/bus-driver-macos.zip "bus-driver-${version}-macos.zip"
          gh release create "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" --generate-notes \
            "bus-driver-${version}.apk" "bus-driver-${version}-windows.zip" "bus-driver-${version}-macos.zip"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 3: 문법 확인**

Run: `.venv/bin/python -c "import yaml" 2>/dev/null && .venv/bin/python -c "import yaml; d=yaml.safe_load(open('.github/workflows/build.yml')); print(sorted(d['jobs']))" || ruby -ryaml -e "puts YAML.load_file('.github/workflows/build.yml')['jobs'].keys.sort.inspect"`
Expected: `['android', 'macos', 'release', 'test', 'windows']`.

- [ ] **Step 4: 커밋과 브랜치 push (사용자 확인 후)**

```bash
git add .github/workflows/build.yml
git commit -m "ci: 테스트·안드로이드 빌드, 태그 시 세 플랫폼 릴리스

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

push 는 외부에 보이는 동작이다. 사용자에게 `menu-deploy` 브랜치 push 확인을 받은 뒤:

```bash
git push -u origin menu-deploy
```

- [ ] **Step 5: CI 결과 확인**

Run: `gh run list -R kjw5541a-hash/bus-driver --branch menu-deploy --limit 1` 로 run id 를 얻고 `gh run watch <id> -R kjw5541a-hash/bus-driver --exit-status`
Expected: `test`, `android` 성공. `windows`, `macos`, `release` 는 skipped.
실패하면 `gh run view <id> --log-failed` 로 원인을 보고 고친 뒤 다시 push 한다. 3DBlockBreaker `android.yml` 과 달라진 부분부터 의심한다.

Run: `gh run download <id> -R kjw5541a-hash/bus-driver -n apk -D build/ci && ls -la build/ci`
Expected: `bus-driver.apk`, 150 MB 이하(예상 40~60 MB). 크기를 ledger 에 적는다. 확인 뒤 `rm -rf build`.

---

### Task 7: 시험 릴리스와 사용자 확인 (main 병합 뒤, 사용자 확인 후)

**Files:** 없음

- [ ] **Step 1: main 병합 뒤 시험 태그 (사용자 확인 후)**

병합 절차(PR, 로컬 `--no-ff` 병합, 테스트, main push, 브랜치 삭제)는 finishing-a-development-branch 에서 사용자가 고른 대로 한다. 병합이 끝나고 사용자가 허락하면:

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 2: 릴리스 확인**

Run: `gh run watch <태그 run id> -R kjw5541a-hash/bus-driver --exit-status && gh release view v0.1.0 -R kjw5541a-hash/bus-driver`
Expected: 모든 job 성공. Release 에 `bus-driver-0.1.0.apk`, `bus-driver-0.1.0-windows.zip`, `bus-driver-0.1.0-macos.zip` 세 파일.

- [ ] **Step 3: 사용자 확인 목록 전달**

사용자에게 다음 확인을 요청한다(자동화 불가):

1. 폰에서 한글이 네모(□)로 나오지 않는지. 나오면 한글 폰트 번들을 별도로 진행한다.
2. 폰에 APK 설치 후 실행되는지, 타이틀 하단에 `v0.1.0` 과 OSM 출처가 보이는지.
3. 메뉴를 가로·세로로 돌려 배치가 괜찮은지. 주행 화면을 세로로 돌렸을 때 조작이 가능한지(불편하면 주행 중 가로 고정을 별도로 진행).
4. 한 구간 완주 뒤 메뉴에 `최고` 점수가 보이는지.
5. 앱을 백그라운드로 보냈을 때 소리가 멈추는지.
6. 대략적인 fps.
7. macOS zip 을 풀고 우클릭 → 열기로 실행되는지. Windows 기기가 있으면 zip 실행.
