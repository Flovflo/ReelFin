"""Behavioral tests for the App Review credential release boundary."""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PREFLIGHT = ROOT / "scripts" / "preflight_testflight_release.sh"
REVIEW_KEYS = (
    "REELFIN_REVIEW_SERVER_URL",
    "REELFIN_REVIEW_USERNAME",
    "REELFIN_REVIEW_PASSWORD",
)


class ReleasePreflightCredentialTests(unittest.TestCase):
    def run_credentials_gate(
        self,
        values: dict[str, str],
        mode: str = "--review-credentials-readiness",
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        for key in REVIEW_KEYS:
            environment.pop(key, None)
        environment.update(values)
        return subprocess.run(
            [str(PREFLIGHT), mode],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_missing_ephemeral_credentials_block_readiness_without_requesting_values_in_repo(self) -> None:
        completed = self.run_credentials_gate({})

        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        output = completed.stdout + completed.stderr
        for key in REVIEW_KEYS:
            self.assertIn(key, output)
        self.assertNotIn("Docs/AppReview-Notes.md", output)

    def test_ephemeral_credentials_pass_without_echoing_any_value(self) -> None:
        values = {
            "REELFIN_REVIEW_SERVER_URL": "https://review-canary.invalid/private",
            "REELFIN_REVIEW_USERNAME": "review-user-canary",
            "REELFIN_REVIEW_PASSWORD": "Review /Pass+Canary?%2F",
        }

        completed = self.run_credentials_gate(values)

        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        output = completed.stdout + completed.stderr
        for value in values.values():
            self.assertNotIn(value, output)
        self.assertIn("App Review credentials are available from ephemeral environment input", output)

    def test_distribution_readiness_stops_before_standard_checks_when_credentials_are_missing(self) -> None:
        completed = self.run_credentials_gate({}, mode="--distribution-readiness")

        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        output = completed.stdout + completed.stderr
        for key in REVIEW_KEYS:
            self.assertIn(key, output)
        self.assertNotIn("Running ReelFin TestFlight preflight", output)


if __name__ == "__main__":
    unittest.main()
