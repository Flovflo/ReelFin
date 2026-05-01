#!/usr/bin/env python3
"""Static checks for the ReelFin GitHub Pages landing page."""

from html.parser import HTMLParser
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "Docs"
INDEX = DOCS / "index.html"
CSS = DOCS / "landing.css"
JS = DOCS / "landing.js"


class LandingParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.hrefs: list[str] = []
        self.images: list[str] = []
        self.h1_text: list[str] = []
        self._in_h1 = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = {name: value for name, value in attrs}
        if attr_map.get("id"):
            self.ids.add(attr_map["id"] or "")
        if tag == "a" and attr_map.get("href"):
            self.hrefs.append(attr_map["href"] or "")
        if tag == "img" and attr_map.get("src"):
            self.images.append(attr_map["src"] or "")
        if tag == "h1":
            self._in_h1 = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "h1":
            self._in_h1 = False

    def handle_data(self, data: str) -> None:
        if self._in_h1:
            self.h1_text.append(data)


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    html = INDEX.read_text(encoding="utf-8")
    css = CSS.read_text(encoding="utf-8")
    js = JS.read_text(encoding="utf-8")

    parser = LandingParser()
    parser.feed(html)

    h1 = " ".join("".join(parser.h1_text).split())
    assert_true(
        h1 == "Your Jellyfin library, made for iPhone and Apple TV.",
        f"Unexpected h1: {h1!r}",
    )

    required_ids = {"top", "overview", "screens", "tvos", "privacy", "support"}
    assert_true(required_ids.issubset(parser.ids), f"Missing ids: {required_ids - parser.ids}")

    required_assets = {
        "Media/reelfinlogo.png",
        "Media/Home-ios.PNG",
        "Media/Library_ios.PNG",
        "Media/Detail_ios.PNG",
        "Media/AppStoreReady/tvOS/screenshots/01-home.png",
    }
    assert_true(required_assets.issubset(set(parser.images)), "Missing required product screenshots")
    for image in parser.images:
        if image.startswith(("http://", "https://", "data:")):
            continue
        assert_true((DOCS / image).exists(), f"Missing image asset: {image}")

    assert_true("mailto:florian.taffin.pro@gmail.com?subject=ReelFin%20TestFlight%20Beta" in parser.hrefs, "Missing TestFlight mailto CTA")
    for href in ("support.html", "privacy-policy.html", "terms-of-service.html", "https://github.com/Flovflo/ReelFin"):
        assert_true(href in parser.hrefs, f"Missing link: {href}")

    for token in (
        "--color-pure-white",
        "--color-snow-gray",
        "--color-signal-blue",
        "--gradient-reelfin-prism",
        "--shadow-xl",
    ):
        assert_true(token in css, f"Missing CSS token: {token}")

    assert_true("color-scheme: light" in css, "Landing page must use the light design system")
    assert_true("Iowan Old Style" not in css, "Old editorial serif heading system should be removed")
    assert_true(".hero__eyebrow" not in css and "eyebrow" not in html.lower(), "Hero eyebrow labels are not part of the new design")
    assert_true("IntersectionObserver" in js, "Reveal script should remain lightweight and progressive")

    section_count = len(re.findall(r"<section\b", html))
    assert_true(section_count >= 6, f"Expected at least 6 sections, found {section_count}")

    print("ReelFin landing page static validation passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
