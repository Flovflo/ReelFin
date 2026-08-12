"""Behavioral tests for App Store screenshot release validation."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PREFLIGHT = ROOT / "scripts" / "preflight_testflight_release.sh"
ASSET_ROOT = ROOT / "Docs" / "Media" / "AppStoreReady"
MANIFEST = ASSET_ROOT / "screenshots.sha256"


class StorefrontAssetPreflightTests(unittest.TestCase):
    def run_gate(
        self,
        asset_root: Path | None = None,
        manifest: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        if asset_root is not None:
            environment["REELFIN_STOREFRONT_ASSET_ROOT"] = str(asset_root)
        if manifest is not None:
            environment["REELFIN_STOREFRONT_MANIFEST"] = str(manifest)
        return subprocess.run(
            [str(PREFLIGHT), "--storefront-assets-readiness"],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    def copy_fixture(self, destination: Path) -> Path:
        for family in ("6.9-inch", "13-inch", "tvOS"):
            target = destination / family / "screenshots"
            target.mkdir(parents=True)
            for source in (ASSET_ROOT / family / "screenshots").glob("*.png"):
                os.link(source, target / source.name)
        return destination

    def write_manifest(self, asset_root: Path, manifest: Path) -> None:
        lines = []
        for screenshot in sorted(asset_root.glob("*/screenshots/*.png")):
            digest = hashlib.sha256(screenshot.read_bytes()).hexdigest()
            relative = screenshot.relative_to(asset_root)
            lines.append(f"{digest}  {relative.as_posix()}\n")
        manifest.write_text("".join(lines), encoding="utf-8")

    def test_canonical_assets_match_the_committed_release_manifest(self) -> None:
        completed = self.run_gate()

        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("12 storefront screenshots match the release manifest", completed.stdout)

    def test_extra_screenshot_is_rejected_even_when_its_hash_is_manifested(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            asset_root = self.copy_fixture(Path(temporary) / "assets")
            extra = asset_root / "6.9-inch" / "screenshots" / "05-extra.png"
            os.link(asset_root / "6.9-inch" / "screenshots" / "01-home.png", extra)
            manifest = Path(temporary) / "screenshots.sha256"
            self.write_manifest(asset_root, manifest)

            completed = self.run_gate(asset_root, manifest)

        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertIn("exactly 4 PNG files", completed.stdout)

    def test_alpha_channel_is_rejected_even_when_dimensions_and_hash_match(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            asset_root = self.copy_fixture(Path(temporary) / "assets")
            target = asset_root / "6.9-inch" / "screenshots" / "01-home.png"
            target.unlink()
            source = ROOT / "ReelFinApp" / "Resources" / "Onboarding" / "TV" / "reelfin-tv-onboarding-home-live.png"
            subprocess.run(
                ["/usr/bin/sips", "-z", "2868", "1320", str(source), "--out", str(target)],
                check=True,
                text=True,
                capture_output=True,
            )
            manifest = Path(temporary) / "screenshots.sha256"
            self.write_manifest(asset_root, manifest)

            completed = self.run_gate(asset_root, manifest)

        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertIn("has no alpha channel", completed.stdout)

    def test_hash_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            asset_root = self.copy_fixture(Path(temporary) / "assets")
            manifest = Path(temporary) / "screenshots.sha256"
            self.write_manifest(asset_root, manifest)
            contents = manifest.read_text(encoding="utf-8")
            manifest.write_text("0" * 64 + contents[64:], encoding="utf-8")

            completed = self.run_gate(asset_root, manifest)

        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertIn("SHA-256 manifest matches", completed.stdout)


if __name__ == "__main__":
    unittest.main()
