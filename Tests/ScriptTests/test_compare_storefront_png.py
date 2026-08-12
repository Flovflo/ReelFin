"""Behavioral tests for the fail-closed storefront screenshot comparator."""

from __future__ import annotations

import binascii
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
COMPARATOR = ROOT / "scripts" / "compare_storefront_png.swift"
CAPTURE_SCRIPT = ROOT / "scripts" / "capture_app_store_screenshots.sh"


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_rgb_png(path: Path, width: int, height: int, pixels: bytearray) -> None:
    rows = b"".join(
        b"\0" + bytes(pixels[row * width * 3 : (row + 1) * width * 3])
        for row in range(height)
    )
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(rows))
        + png_chunk(b"IEND", b"")
    )


class StorefrontPNGComparatorTests(unittest.TestCase):
    def compare(self, first: Path, second: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/usr/bin/xcrun", "swift", str(COMPARATOR), str(first), str(second)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def fixture(self, directory: Path, width: int = 300, height: int = 300) -> tuple[Path, Path, bytearray, bytearray]:
        first = directory / "first.png"
        second = directory / "second.png"
        baseline = bytearray([96, 96, 96] * width * height)
        candidate = bytearray(baseline)
        return first, second, baseline, candidate

    def test_accepts_sparse_single_lsb_rasterization_noise(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            first, second, baseline, candidate = self.fixture(Path(temporary))
            for x, y in ((12, 17), (147, 83), (281, 264)):
                candidate[(y * 300 + x) * 3] += 1
            write_rgb_png(first, 300, 300, baseline)
            write_rgb_png(second, 300, 300, candidate)

            completed = self.compare(first, second)

        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("changed_pixels=3", completed.stdout)
        self.assertIn("max_channel_delta=1", completed.stdout)

    def test_rejects_dimension_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            first = directory / "first.png"
            second = directory / "second.png"
            write_rgb_png(first, 300, 300, bytearray([96, 96, 96] * 300 * 300))
            write_rgb_png(second, 301, 300, bytearray([96, 96, 96] * 301 * 300))

            completed = self.compare(first, second)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("dimensions", completed.stdout + completed.stderr)

    def test_rejects_visible_color_change_even_when_it_is_one_pixel(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            first, second, baseline, candidate = self.fixture(Path(temporary))
            candidate[(150 * 300 + 150) * 3] += 8
            write_rgb_png(first, 300, 300, baseline)
            write_rgb_png(second, 300, 300, candidate)

            completed = self.compare(first, second)

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("max channel delta", completed.stdout + completed.stderr)

    def test_rejects_one_pixel_displacement_of_a_low_contrast_shape(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            first, second, baseline, candidate = self.fixture(Path(temporary))
            for y in range(100, 130):
                for x in range(100, 130):
                    baseline[(y * 300 + x) * 3] = 97
                    candidate[(y * 300 + x + 1) * 3] = 97
            write_rgb_png(first, 300, 300, baseline)
            write_rgb_png(second, 300, 300, candidate)

            completed = self.compare(first, second)

        self.assertNotEqual(completed.returncode, 0)
        self.assertRegex(completed.stdout + completed.stderr, r"changed fraction|component")

    def test_capture_matrix_uses_fail_closed_comparison_for_every_png(self) -> None:
        source = CAPTURE_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("compare_storefront_png.swift", source)
        self.assertNotIn("diff -rq", source)


if __name__ == "__main__":
    unittest.main()
