import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from diagnostic_redaction import redact_snapshot


class RedactionTests(unittest.TestCase):
    def test_allowed_fields_only(self):
        result = redact_snapshot({"model": "MacPro6,1", "macos_version": "15.7",
                                  "daemon_status": "running", "username": "private",
                                  "serial": "private", "logs": "token=private",
                                  "fans": [{"current_rpm": 1200, "path": "/Users/private"}]})
        self.assertEqual(result, {"model": "MacPro6,1", "macos_version": "15.7",
                                  "daemon_status": "running", "fans": [{"current_rpm": 1200}]})

    def test_sensitive_content_in_allowed_fields_is_dropped(self):
        self.assertEqual(redact_snapshot({"model": "/Users/private", "macos_version": "15.7 token=secret",
                                         "daemon_status": "private", "fans": [None, {"current_rpm": "secret", "min_rpm": True}]}), {"fans": []})

    def test_rpm_bounds_and_cap(self):
        self.assertEqual(redact_snapshot({"fans": [{"min_rpm": -1, "max_rpm": 100001}]}), {"fans": []})
        self.assertEqual(len(redact_snapshot({"fans": [{"current_rpm": 1}] * 100})["fans"]), 32)

    def test_does_not_modify_input(self):
        raw = {"fans": [{"current_rpm": 1, "serial": "secret"}]}
        redact_snapshot(raw)
        self.assertEqual(raw["fans"][0]["serial"], "secret")


if __name__ == "__main__":
    unittest.main()
