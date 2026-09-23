#!/usr/bin/env bash
# 파이썬 단위 테스트 전체 실행. Godot 주행 검증은 tests/bake/run_verify.sh 가 따로 돈다.
set -euo pipefail
cd "$(dirname "$0")"
python3 -m unittest discover -s tests -t . -v
