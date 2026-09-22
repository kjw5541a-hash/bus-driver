#!/usr/bin/env bash
# 노선 하나를 굽고 Godot 헤드리스로 주행 검증까지 돌린다.
#   tests/bake/run_verify.sh seoul-100
# 노선 id 를 생략하면 정의된 노선 전부를 돈다.
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

# bash 3.2 (macOS 기본) 에는 mapfile 이 없다. while read 로 대체한다.
if [ $# -eq 0 ]; then
	routes=()
	while IFS= read -r line; do
		routes+=("$line")
	done < <(python3 -m tools.osmbake.cli list | cut -f1)
else
	routes=("$@")
fi

"$GODOT_BIN" --headless --import >/dev/null 2>&1 || true

failed=0
for route in "${routes[@]}"; do
	echo "=== $route ==="
	python3 -m tools.osmbake.cli bake "$route"
	"$GODOT_BIN" --headless --import >/dev/null 2>&1 || true
	# --quit-after 는 정상 종료(get_tree().quit())를 못 했을 때의 안전망 프레임 상한.
	# 20km 노선을 32km/h 로 달리면 약 135,000 프레임(60fps 기준)인데 교착/우회 여유를
	# 감안해 400,000 으로 잡는다.
	if "$GODOT_BIN" --headless --fixed-fps 60 --quit-after 400000 -- --route="$route"; then
		echo "$route: OK"
	else
		echo "$route: FAIL"
		failed=1
	fi
done
exit $failed
