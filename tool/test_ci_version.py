import importlib.util
import unittest
from pathlib import Path

_MODULE_PATH = Path(__file__).with_name("ci_version.py")
_SPEC = importlib.util.spec_from_file_location(
    "ci_version_for_tests",
    str(_MODULE_PATH),
)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError(f"Could not load {_MODULE_PATH}.")
ci_version = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(ci_version)

_SHA = "b6ddc8ddde61b64a84af7f82ce1f6eab26607efa"


class VersionCodeTests(unittest.TestCase):
    def test_new_runs_increase_the_version_code(self):
        codes = [ci_version.version_code_for(1, run, 1) for run in (1, 2, 3)]

        self.assertEqual(codes, [2, 102, 202])
        self.assertTrue(all(left < right for left, right in zip(codes, codes[1:])))

    def test_a_rerun_attempt_increases_the_version_code(self):
        first = ci_version.version_code_for(1, 7, 1)
        second = ci_version.version_code_for(1, 7, 2)

        self.assertGreater(second, first)

    def test_attempt_width_is_reserved(self):
        self.assertEqual(ci_version.version_code_for(1, 1, 99), 100)
        for attempt in (0, 100):
            with self.assertRaises(ci_version.VersionError):
                ci_version.version_code_for(1, 1, attempt)

    def test_version_code_stays_inside_the_android_range(self):
        self.assertEqual(
            ci_version.version_code_for(1, 21_000_000, 1),
            2_099_999_902,
        )
        with self.assertRaises(ci_version.VersionError):
            ci_version.version_code_for(1, 21_000_001, 1)

    def test_android_preview_rejects_a_rerun(self):
        with self.assertRaisesRegex(
            ci_version.VersionError,
            "dispatch a new Android build",
        ):
            ci_version.resolve_version("0.1.0", 1, 7, 2, _SHA, True)

    def test_short_commit_sha_is_rejected(self):
        with self.assertRaises(ci_version.VersionError):
            ci_version.make_version_id("0.1.0", 2, 1, 1, "b6ddc8d")

    def test_validation_and_web_reruns_remain_supported(self):
        code, identifier = ci_version.resolve_version(
            "0.1.0",
            1,
            7,
            2,
            _SHA,
            False,
        )

        self.assertEqual(code, 603)
        self.assertEqual(identifier, f"0.1.0+603.r7a2.{_SHA}")


class PubspecTests(unittest.TestCase):
    def test_valid_pubspec_keeps_the_semantic_base(self):
        self.assertEqual(
            ci_version.parse_pubspec("version: 0.1.0+1\n"),
            ("0.1.0", 1),
        )

    def test_missing_version_is_rejected(self):
        with self.assertRaises(ci_version.VersionError):
            ci_version.parse_pubspec("name: companion_focus\n")

    def test_malformed_version_is_rejected(self):
        with self.assertRaises(ci_version.VersionError):
            ci_version.parse_pubspec("version: 0.1\n")


if __name__ == "__main__":
    unittest.main()
