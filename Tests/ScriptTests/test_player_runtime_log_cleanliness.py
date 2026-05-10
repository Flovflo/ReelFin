#!/usr/bin/env python3
"""Unit tests for ReelFin runtime log cleanliness checks."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"


def load_script_module(name: str):
    sys.path.insert(0, str(SCRIPTS_DIR))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS_DIR / f"{name}.py")
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


runtime_clean = load_script_module("assert_player_runtime_log_clean")


class PlayerRuntimeLogCleanlinessTests(unittest.TestCase):
    def test_detects_password_accessibility_value_leak(self) -> None:
        line = (
            "First responder: <UITextField: 0x123; text = 's...t' "
            "(length = 12); placeholder = Password; layer = <CALayer>>"
        )

        matches = [
            label
            for label, pattern in runtime_clean.FORBIDDEN_REGEXES
            if pattern.search(line)
        ]

        self.assertIn("RAW_PASSWORD_ACCESSIBILITY_VALUE", matches)

    def test_redacts_password_accessibility_value_in_findings(self) -> None:
        line = (
            "First responder: <UITextField: 0x123; text = 's...t' "
            "(length = 12); placeholder = Password; layer = <CALayer>>"
        )

        redacted = runtime_clean.redact_sensitive(line)

        self.assertIn("text = '<redacted>'", redacted)
        self.assertNotIn("s...t", redacted)
        self.assertNotIn("length = 12", redacted)


if __name__ == "__main__":
    unittest.main()
