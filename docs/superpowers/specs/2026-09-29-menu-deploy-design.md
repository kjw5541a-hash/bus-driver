# 서브프로젝트 7: 메뉴와 배포 설계

## 목적

본인과 지인이 폰(Android)과 PC(Windows, macOS)에 게임을 설치해 플레이할 수 있게 한다.
태그를 push 하면 CI 가 세 플랫폼 빌드를 만들어 GitHub Release 에 올린다.
메뉴는 타이틀, 노선·구간 선택, 구간별 최고 기록을 갖춘다.

나중에 Google Play(B 단계)로 넘어갈 수 있어야 한다. 그래서 다음 두 가지는 지금 확정하고 바꾸지 않는다.

- 패키지 이름 `com.kjw5541.busdriver`. Play 는 이 이름으로 앱을 식별하며 출시 후 변경할 수 없다.
- release keystore. 이번에 만든 키를 Play 전환 때 앱 서명 키로 올리면, APK 로 설치한 사람도 Play 업데이트를 이어 받는다.

## 범위

포함:

- 타이틀 화면. 게임 이름, [시작] 버튼, 하단에 버전과 OSM 출처 표기.
- 노선·구간 선택 개선. 노선 정보, 선택 강조, 가로·세로 화면 대응.
- 구간별 최고 기록 저장과 표시.
- `export_presets.cfg`(Android APK, Windows, macOS)와 GitHub Actions 빌드·릴리스.

제외:

- 사운드. 8번 서브프로젝트로 따로 진행한다.
- Play 스토어 등록물(AAB, 스크린샷, 개인정보처리방침, 콘텐츠 등급).
- 출발 시각·날씨 선택 화면, 설정 화면.
- 모바일 성능 최적화. 폰에서 fps 를 잰 뒤 필요하면 별도로 한다.

## 메뉴

### 화면 흐름

타이틀 → [시작] → 노선·구간 선택 → 주행 → 결과 → [메뉴] → 노선·구간 선택.

`scenes/menu.tscn` 하나 안에서 두 단계(타이틀, 선택)를 전환한다. 새 씬은 만들지 않는다.
결과 화면에서 메뉴로 돌아오면 타이틀을 건너뛰고 선택 단계로 연다.
구분은 static 변수 `Menu.skip_title` 로 한다. `drive.gd` 가 메뉴로 돌아가기 직전에 `true` 로 세우고, 메뉴는 읽은 뒤 `false` 로 되돌린다.

### 타이틀 단계

- 게임 이름(`application/config/name`), [시작] 버튼.
- 하단 한 줄: `v<버전> · © OpenStreetMap contributors`.
- 버전은 `ProjectSettings.get_setting("application/config/version", "dev")` 로 읽는다. 로컬 실행은 `dev` 로 보인다.
- OSM 출처 표기는 ODbL 라이선스 요구사항이다. 반드시 보이는 곳에 둔다.

### 선택 단계

- 좌측 상단 [뒤로] 버튼은 타이틀로 돌아간다.
- 노선 버튼: 이름, 기점 → 종점, 정류장 수, 거리 km(`RouteData.length_m()` / 1000, 소수 한 자리).
- 선택한 노선 버튼은 `button_pressed` 토글로 강조한다(`ButtonGroup`).
- 구간 버튼: `구간 1 · A → B · 마감 12:30 · 최고 1840 ★★☆`. 기록이 없으면 `최고 —`.
- 전체를 `ScrollContainer` 로 감싼다. 구간이 많아도 화면을 넘치지 않는다.
- 화면이 세로(`size.y > size.x`)면 노선 열과 구간 열을 위아래로, 가로면 좌우로 놓는다. `resized` 신호마다 다시 판정한다.
  구현은 두 열을 담는 컨테이너의 `vertical` 속성(`BoxContainer.vertical`)을 바꾸는 것으로 한다.

## 기록

`scripts/records.gd`, `class_name Records`, static 함수만 쓴다.

- `static var path := "user://records.cfg"`. 테스트는 이 값을 임시 경로로 바꾼다.
- `static func best(route_id: String, section: int) -> Dictionary`: `{"score": int, "stars": int}`, 기록이 없으면 `{}`.
- `static func submit(route_id: String, section: int, score: int, stars: int) -> bool`: 기존 점수보다 높을 때만 저장하고 `true`. 같거나 낮으면 저장하지 않고 `false`.
- 저장 형식은 `ConfigFile`. 섹션은 route_id, 키는 `"s<section>"`, 값은 `{"score", "stars"}` Dictionary.
- 파일이 없거나 읽기에 실패하면 빈 기록으로 본다. 게임은 멈추지 않는다.

연결:

- `drive.gd` 의 `_on_finished` 에서 `Records.submit(data.id, data.section, card.total, card.stars)` 를 부른다.
- `ResultPanel.show_result` 에 네 번째 인자 `new_best := false` 를 더한다. `submit` 이 `true` 면 이 값을 `true` 로 넘기고, 패널은 총점 아래에 "최고 기록!" 한 줄을 추가한다.
- 적발(busted)로 끝나면 `_on_finished` 가 불리지 않으므로 기록하지 않는다. 지금 흐름 그대로다.

## 배포

### export_presets.cfg

커밋한다. 세 preset 모두 `exclude_filter` 에서 다음을 뺀다.

```
data/*, tools/*, tests/*, docs/*, *.py, .superpowers/*, build/*, android/*
```

`data/osm_cache`(97 MB)가 빠지지 않으면 APK 가 두 배가 된다.

- `Android`
  - APK(`gradle_build/export_format=0`), gradle 빌드, arm64-v8a 만.
  - min SDK 24, target SDK 36.
  - `package/unique_name="com.kjw5541.busdriver"`, `package/name="버스 운전"`.
  - `version/code`, `version/name` 은 CI 가 덮어쓴다. 커밋 값은 `1`, `"dev"`.
  - 인터넷 권한 없음.
  - keystore 칸 여섯 개는 빈 문자열로 커밋한다. 실제 값은 CI 가 러너 안에서만 채운다. 이 저장소는 public 이다.
- `Windows`: 기본값, 64비트. 산출물은 exe + pck.
- `macOS`: universal 바이너리, `codesign/codesign=1`(ad-hoc). 공증은 하지 않는다. Apple Silicon 은 서명이 전혀 없는 바이너리를 실행하지 않으므로 ad-hoc 서명이 최소 조건이다.

### 버전

- `project.godot` 에 `application/config/version="dev"` 를 커밋한다.
- CI 가 빌드 직전에 덮어쓴다.
  - 태그 `vX.Y.Z`: `config/version="X.Y.Z"`, Android `version/name="X.Y.Z"`, `version/code = X*10000 + Y*100 + Z`.
  - 그 밖(브랜치 push): `config/version="0.0.0-<sha7>"`, `version/code=1`.
- `version/code` 는 태그가 올라갈수록 커진다. Play 는 이 값이 줄어든 업로드를 거부한다. Y, Z 는 99 이하로 둔다.

### GitHub Actions: `.github/workflows/build.yml`

트리거:

- 모든 브랜치 push: `test`, `android` job 만. 산출물은 artifact 로 7일 보관.
- `v*` 태그 push: `test`, `android`, `windows`, `macos`, `release` 전부.
- `workflow_dispatch`.

job:

- `test`(ubuntu-latest)
  - Godot 4.7.2 설치, `godot --headless --import`.
  - 파이썬 테스트: `python -m unittest discover -s tests -t .` (requirements.txt 설치 후).
  - 게임 테스트: `tests/game/run_game_tests.sh`.
- `android`(ubuntu-latest, `needs: test`)
  - 3DBlockBreaker `android.yml` 에서 검증된 단계를 그대로 쓴다: JDK 17, 템플릿 캐시, Android 빌드 템플릿 풀기(`android/.build_version` 포함), keystore secret 주입.
  - `godot --headless --export-release "Android" build/bus-driver.apk`, `test -s` 로 확인.
- `windows`(ubuntu-latest, `needs: test`, 태그만): `--export-release "Windows"`, exe 와 pck 를 zip.
- `macos`(macos-latest, `needs: test`, 태그만): `--export-release "macOS" build/bus-driver-macos.zip`.
- `release`(ubuntu-latest, 태그만, `needs: [android, windows, macos]`, 이 job 에만 `permissions: contents: write`)
  - 산출물 이름: `bus-driver-X.Y.Z.apk`, `bus-driver-X.Y.Z-windows.zip`, `bus-driver-X.Y.Z-macos.zip`.
  - `gh release create vX.Y.Z` 로 세 파일을 첨부한다. 릴리스 노트는 `--generate-notes`.

secret(저장소 Settings → Secrets):

- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`.

### keystore

사용자가 한 번 직접 만든다. 비밀번호는 사용자가 정한다.

```
keytool -genkeypair -v -keystore ~/keys/bus-driver-release.jks \
  -alias busdriver -keyalg RSA -keysize 4096 -validity 36500
gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -i ~/keys/bus-driver-release.jks)
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS --body busdriver
```

- keystore 는 저장소 밖(`~/keys/`)에 둔다. 저장소에 절대 커밋하지 않는다.
- 잃어버리면 같은 앱으로 업데이트할 수 없다. 오프라인 백업을 따로 둔다.
- `.gitignore` 에 `*.jks`, `*.keystore`, `android/`, `build/` 를 추가한다.

### 릴리스 절차

```
git tag v1.0.0
git push origin v1.0.0
```

약 15분 뒤 Release 페이지에 파일 세 개가 올라온다.

## 테스트

자동(게임 테스트 씬, `run_game_tests.sh` 목록의 `drive_smoke` 앞에 추가):

- `test_records`
  - 빈 파일에서 `best` 는 `{}`.
  - 더 높은 점수 `submit` 은 `true` 이고 기록이 바뀐다. 같거나 낮은 점수는 `false` 이고 그대로다.
  - 깨진 cfg 파일은 빈 기록으로 본다.
  - 노선이 다르거나 구간이 다르면 기록이 섞이지 않는다.
  - `Records.path` 를 임시 경로로 바꿔 실제 기록을 건드리지 않는다.
- `test_menu`
  - 타이틀 단계로 시작한다. 하단 텍스트에 버전과 `OpenStreetMap` 이 있다.
  - [시작] 뒤 노선 버튼이 `RouteData.list_route_ids()` 개수만큼 있다.
  - 노선을 누르면 구간 버튼이 생기고, 기록이 있는 구간은 `최고` 점수가 보인다.
  - `Menu.skip_title` 이 `true` 면 선택 단계로 바로 열린다.
  - 세로 크기에서 두 열이 위아래(`vertical == true`)로, 가로에서 좌우로 놓인다.
- 완주 기록: 완주하면 `Records` 에 기록이 남는다(기존 완주 경로를 쓰는 테스트에 assert 추가 또는 `_on_finished` 직접 호출).

CI 확인:

- 브랜치 push 로 Android APK 가 실제로 만들어진다.
- 시험 태그 `v0.1.0` push 로 Release 에 파일 세 개가 올라간다.
- APK 크기를 기록한다. 150 MB 를 넘으면 exclude_filter 를 다시 본다(예상 40~60 MB).

사용자 확인(자동화 불가):

- 폰에 APK 설치: 실행, 메뉴 가로·세로, 버전 표시, 한 구간 완주 후 기록 저장, 백그라운드 전환 시 소리 정지, 대략적인 fps.
- Windows zip 실행(기기가 있으면).
- macOS zip: 우클릭 → 열기로 실행.
