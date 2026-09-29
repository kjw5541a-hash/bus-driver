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
