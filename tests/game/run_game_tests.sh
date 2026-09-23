#!/usr/bin/env bash
# 게임 쪽 헤드리스 테스트 전체 실행.
#   tests/game/run_game_tests.sh
# 씬 이름을 인자로 주면 그것만 돈다:
#   tests/game/run_game_tests.sh test_input
set -euo pipefail
cd "$(dirname "$0")/../.."

# Godot 실행 파일: 환경변수로 덮어쓸 수 있게 하고, PATH 에 없으면
# 이 기계에 설치된 경로로 폴백한다. 둘 다 없으면 바로 에러로 종료.
GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="godot"
	elif [ -x /opt/homebrew/bin/godot ]; then
		GODOT_BIN="/opt/homebrew/bin/godot"
	else
		echo "godot 실행 파일을 찾을 수 없다. GODOT 환경변수로 경로를 지정하라." >&2
		exit 1
	fi
fi

if [ $# -gt 0 ]; then
	scenes=("$@")
else
	scenes=(test_route_data test_city test_input test_turn_radius test_nav_line)
fi

"$GODOT_BIN" --headless --import >/dev/null 2>&1 || true

failed=0
for scene in "${scenes[@]}"; do
	echo "=== $scene ==="
	# --quit-after 는 씬이 스스로 종료하지 못했을 때의 안전망 프레임 상한.
	# 스크립트 파싱에 실패해도 Godot 은 0 으로 종료한다. 종료 코드만 믿으면
	# 안 돌아간 테스트가 통과로 보이므로 TEST_OK 출력도 같이 확인한다.
	output=$("$GODOT_BIN" --headless --fixed-fps 60 --quit-after 200000 \
		"res://tests/game/${scene}.tscn" 2>&1) && status=0 || status=$?
	echo "$output"
	if [ "$status" -eq 0 ] && echo "$output" | grep -q "^TEST_OK$"; then
		echo "$scene: OK"
	else
		echo "$scene: FAIL"
		failed=1
	fi
done
exit $failed
