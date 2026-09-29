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
