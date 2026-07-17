#!/usr/bin/env python3
"""Validate SmartCart's dependency-free static website using the Python standard library."""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


REQUIRED_PAGES = {
    "index.html": "unreleased private-beta candidate",
    "privacy.html": "pre-publication legal draft",
    "terms.html": "pre-publication legal draft",
    "support.html": "verified support",
    "faq.html": "SmartCart private-beta FAQ",
    "about.html": "private proprietary software",
    "affiliate-disclosure.html": "does not represent affiliate compensation",
    "contact.html": "verified, monitored contact method",
    "developers/index.html": "Non-negotiable product truth",
    "developers/architecture.html": "Versioned persistence",
    "media-kit/index.html": "SmartCart media kit",
}

EMAIL_PATTERN = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
PLACEHOLDER_PAGES = {
    "privacy.html",
    "terms.html",
    "support.html",
    "contact.html",
    "affiliate-disclosure.html",
    "about.html",
    "media-kit/index.html",
}


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: list[str] = []
        self.links: list[str] = []
        self.assets: list[str] = []
        self.forms: list[str] = []
        self.title_parts: list[str] = []
        self.in_title = False
        self.lang = ""
        self.has_viewport = False
        self.main_count = 0
        self.h1_count = 0
        self.has_skip_link = False
        self.images_without_alt = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {name: value or "" for name, value in attrs}
        if values.get("id"):
            self.ids.append(values["id"])
        if tag == "html":
            self.lang = values.get("lang", "")
        elif tag == "meta" and values.get("name", "").lower() == "viewport":
            self.has_viewport = bool(values.get("content"))
        elif tag == "title":
            self.in_title = True
        elif tag == "main":
            self.main_count += 1
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "a":
            href = values.get("href", "")
            if href:
                self.links.append(href)
                if href == "#main" and "skip-link" in values.get("class", "").split():
                    self.has_skip_link = True
        elif tag == "link":
            href = values.get("href", "")
            if href:
                self.assets.append(href)
        elif tag == "script":
            src = values.get("src", "")
            if src:
                self.assets.append(src)
        elif tag == "img":
            src = values.get("src", "")
            if src:
                self.assets.append(src)
            if "alt" not in values:
                self.images_without_alt += 1
        elif tag == "form":
            self.forms.append(values.get("action", ""))

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title_parts.append(data)

    @property
    def title(self) -> str:
        return " ".join("".join(self.title_parts).split())


def _is_remote_or_special(reference: str) -> bool:
    parsed = urlsplit(reference)
    return bool(parsed.scheme or parsed.netloc or reference.startswith("//"))


def _target_path(root: Path, page: Path, reference: str) -> tuple[Path, str]:
    parsed = urlsplit(reference)
    relative = unquote(parsed.path)
    target = (page.parent / relative).resolve() if relative else page.resolve()
    if relative.endswith("/"):
        target = target / "index.html"
    return target, unquote(parsed.fragment)


def inspect_site(root: Path, required_pages: dict[str, str] | None = None) -> list[str]:
    root = root.resolve()
    errors: list[str] = []
    required = REQUIRED_PAGES if required_pages is None else required_pages

    for relative, phrase in required.items():
        path = root / relative
        if not path.is_file():
            errors.append(f"missing required page: {relative}")
            continue
        if phrase.casefold() not in path.read_text(encoding="utf-8").casefold():
            errors.append(f"{relative}: missing required content marker {phrase!r}")

    html_files = sorted(root.rglob("*.html"))
    if not html_files:
        errors.append("no HTML files found")
        return errors

    parsed_pages: dict[Path, PageParser] = {}
    page_titles: list[tuple[str, str]] = []

    for page in html_files:
        relative = page.relative_to(root).as_posix()
        source = page.read_text(encoding="utf-8")
        parser = PageParser()
        try:
            parser.feed(source)
        except Exception as exc:  # HTMLParser errors are rare, but report them cleanly.
            errors.append(f"{relative}: HTML parse error: {exc}")
            continue
        parsed_pages[page.resolve()] = parser
        page_titles.append((relative, parser.title))

        if parser.lang.lower() != "en":
            errors.append(f"{relative}: html lang must be 'en'")
        if not parser.has_viewport:
            errors.append(f"{relative}: missing viewport metadata")
        if not parser.title:
            errors.append(f"{relative}: missing document title")
        if parser.main_count != 1:
            errors.append(f"{relative}: expected exactly one main element, found {parser.main_count}")
        if parser.h1_count != 1:
            errors.append(f"{relative}: expected exactly one h1, found {parser.h1_count}")
        if not parser.has_skip_link:
            errors.append(f"{relative}: missing skip link to #main")
        if parser.images_without_alt:
            errors.append(f"{relative}: {parser.images_without_alt} image(s) missing alt text")

        duplicates = sorted(name for name, count in Counter(parser.ids).items() if count > 1)
        if duplicates:
            errors.append(f"{relative}: duplicate id(s): {', '.join(duplicates)}")

        emails = sorted(set(EMAIL_PATTERN.findall(source)))
        if emails:
            errors.append(f"{relative}: invented or unapproved email address(es): {', '.join(emails)}")
        if relative in PLACEHOLDER_PAGES and "[REPLACE BEFORE PUBLISHING" not in source:
            errors.append(f"{relative}: expected a marked pre-publication placeholder")

        for action in parser.forms:
            if action:
                errors.append(f"{relative}: form action must remain empty in the local package: {action}")

    title_counts = Counter(title for _, title in page_titles if title)
    for relative, title in page_titles:
        if title and title_counts[title] > 1:
            errors.append(f"{relative}: duplicate document title {title!r}")

    for page_path, parser in parsed_pages.items():
        relative = page_path.relative_to(root).as_posix()
        for reference in parser.assets + parser.links:
            if _is_remote_or_special(reference):
                errors.append(f"{relative}: remote or special reference is not allowed: {reference}")
                continue
            if reference.startswith("/"):
                errors.append(f"{relative}: root-absolute reference is not portable: {reference}")
                continue
            target, fragment = _target_path(root, page_path, reference)
            try:
                target.relative_to(root)
            except ValueError:
                errors.append(f"{relative}: reference escapes website root: {reference}")
                continue
            if not target.exists():
                errors.append(f"{relative}: broken local reference: {reference}")
                continue
            if fragment and target.suffix.lower() == ".html":
                target_parser = parsed_pages.get(target.resolve())
                if target_parser is None:
                    target_parser = PageParser()
                    target_parser.feed(target.read_text(encoding="utf-8"))
                if fragment not in target_parser.ids:
                    errors.append(f"{relative}: missing fragment target in {reference}")

    for relative in ("styles.css", "script.js", "README.md", "media-kit/press-notes.txt"):
        if not (root / relative).is_file():
            errors.append(f"missing required package file: {relative}")

    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    errors = inspect_site(args.root)
    if errors:
        print(f"SmartCart website validation failed ({len(errors)} issue(s)):")
        for error in errors:
            print(f"- {error}")
        return 1
    html_count = len(list(args.root.resolve().rglob("*.html")))
    print(f"SmartCart website validation passed: {html_count} HTML pages, local links, content markers, and accessibility basics checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
