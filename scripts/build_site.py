#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["jinja2", "markdown"]
# ///
"""Render the static Pages site into an output directory.

The site under site/ is a set of Jinja templates: shared chrome lives in
site/_layouts and site/_includes, and each page sets its metadata as {% set %}
values at the top. This renders every page template, copies the static assets
and imgs/, generates sitemap.xml from the pages' canonical paths, and drops in
the Sparkle feeds and changelog that the deploy job mirrors off gh-pages.

It also fills the download buttons from the current appcast and renders
/changelog/ from changelog.md. Both have fallbacks, so a checkout with no feed
(a local preview, say) still produces a working site.

Usage:
  build_site.py
  build_site.py --site site --feeds build/feeds --out build/site --imgs imgs
  build_site.py --self-test
"""

from __future__ import annotations

import argparse
import shutil
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import jinja2
import markdown

ROOT = Path(__file__).resolve().parent.parent
SITE_URL = "https://transmissionswift.jvacek.eu"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SITEMAP_NS = "http://www.sitemaps.org/schemas/sitemap/0.9"
REPO = "https://github.com/jvacek/TransmissionSwift"
RELEASES_LATEST = f"{REPO}/releases/latest"
RELEASES_PAGE = f"{REPO}/releases"


def newest_stable(feed: Path) -> tuple[str | None, str | None]:
    """Return (shortVersionString, enclosure url) for the newest stable item.

    Items are appended oldest-first and beta items carry a sparkle:channel
    child, so the newest stable one is the last item without it.
    """
    try:
        channel = ET.parse(feed).getroot().find("channel")
    except (OSError, ET.ParseError):
        return None, None
    if channel is None:
        return None, None
    stable = [
        it
        for it in channel.findall("item")
        if it.find(f"{{{SPARKLE_NS}}}channel") is None
    ]
    if not stable:
        return None, None
    item = stable[-1]
    enclosure = item.find("enclosure")
    url = enclosure.get("url") if enclosure is not None else None
    return item.findtext(f"{{{SPARKLE_NS}}}shortVersionString"), url


def download_context(feeds: Path) -> dict[str, str]:
    # version + asset URLs come from the newest stable appcast item, i.e. the
    # release Sparkle itself would offer. Both feeds carry the same version.
    version, universal_url = newest_stable(feeds / "appcast.xml")
    arm64_version, arm64_url = newest_stable(feeds / "appcast-arm64.xml")
    return {
        "version": version or arm64_version or "",
        "download_url_universal": universal_url or RELEASES_LATEST,
        "download_url_arm64": arm64_url or RELEASES_LATEST,
    }


def changelog_html(feeds: Path) -> str:
    # The deploy job mirrors the published changelog off gh-pages; fall back to
    # the repo copy so local previews show the real notes.
    for candidate in (feeds / "changelog.md", ROOT / "CHANGELOG.md"):
        if candidate.exists():
            return markdown.markdown(candidate.read_text(encoding="utf-8"))
    return f'<p>The changelog is on <a href="{RELEASES_PAGE}">GitHub releases</a>.</p>'


def sitemap_xml(env: jinja2.Environment, context: dict, pages: list) -> str:
    """Build sitemap.xml from the pages that declare a canonical path."""
    entries = []
    for _rel, name in pages:
        meta = env.get_template(name).make_module(context)
        path = getattr(meta, "path", None)
        if path is None:
            continue  # e.g. a redirect stub, which is not a canonical URL
        sitemap = getattr(meta, "sitemap", None) or {}
        entries.append(
            (
                float(sitemap.get("priority", 0.5)),
                sitemap.get("changefreq", "monthly"),
                SITE_URL + path,
            )
        )

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    root = ET.Element("urlset", xmlns=SITEMAP_NS)
    for priority, changefreq, loc in sorted(entries, key=lambda e: (-e[0], e[2])):
        url = ET.SubElement(root, "url")
        ET.SubElement(url, "loc").text = loc
        ET.SubElement(url, "lastmod").text = today
        ET.SubElement(url, "changefreq").text = changefreq
        ET.SubElement(url, "priority").text = f"{priority:.1f}"
    ET.indent(root, space="  ")
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        + ET.tostring(root, encoding="unicode")
        + "\n"
    )


def render(site: Path, feeds: Path, out: Path, imgs: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)

    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(site),
        autoescape=jinja2.select_autoescape(["html"]),
        undefined=jinja2.StrictUndefined,
        keep_trailing_newline=True,
    )
    context = {
        "site_url": SITE_URL,
        "changelog": changelog_html(feeds),
        **download_context(feeds),
    }

    pages = []
    for template in sorted(site.rglob("*.html")):
        rel = template.relative_to(site)
        if rel.parts[0].startswith("_"):
            continue  # _layouts and _includes are partials, not pages
        name = rel.as_posix()
        pages.append((rel, name))
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(env.get_template(name).render(**context), encoding="utf-8")

    (out / "sitemap.xml").write_text(sitemap_xml(env, context, pages), encoding="utf-8")

    for asset in site.rglob("*"):
        rel = asset.relative_to(site)
        if (
            asset.is_file()
            and asset.suffix != ".html"
            and not rel.parts[0].startswith("_")
        ):
            dest = out / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(asset, dest)

    if imgs.is_dir():
        shutil.copytree(imgs, out / "imgs", dirs_exist_ok=True)

    # The Sparkle feeds and release notes must sit at the published root.
    if feeds.is_dir():
        for feed in feeds.iterdir():
            if feed.is_file():
                shutil.copy2(feed, out / feed.name)


def _feed(version: str, url: str, beta: bool) -> str:
    channel = "<sparkle:channel>beta</sparkle:channel>" if beta else ""
    return (
        '<?xml version="1.0"?>'
        f'<rss xmlns:sparkle="{SPARKLE_NS}" version="2.0"><channel>'
        f"<item><title>x</title>"
        f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>"
        f'<enclosure url="{url}" length="1" type="application/octet-stream"/>'
        f"{channel}</item></channel></rss>"
    )


def self_test() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        site, feeds, out, imgs = tmp / "site", tmp / "feeds", tmp / "out", tmp / "imgs"
        (site / "_layouts").mkdir(parents=True)
        (site / "_includes").mkdir()
        (site / "download").mkdir()
        (site / "moved").mkdir()
        feeds.mkdir()
        imgs.mkdir()

        (site / "_layouts" / "base.html").write_text(
            "<title>{{ title }}</title>"
            "{% include '_includes/nav.html' %}"
            "{% block content %}{% endblock %}"
        )
        (site / "_includes" / "nav.html").write_text(
            '<a href="/">{% if page == "home" %}home{% endif %}</a>'
        )
        (site / "index.html").write_text(
            '{% extends "_layouts/base.html" %}{% set title = "Hi" %}{% set page = "home" %}'
            '{% set path = "/" %}{% set sitemap = {"changefreq": "weekly", "priority": "1.0"} %}'
            "{% block content %}BODY{% endblock %}"
        )
        (site / "download" / "index.html").write_text(
            '{% extends "_layouts/base.html" %}{% set title = "DL" %}{% set page = "download" %}'
            '{% set path = "/download/" %}'
            '{% block content %}<a href="{{ download_url_universal }}">{{ version }}</a>'
            "{{ changelog | safe }}{% endblock %}"
        )
        (site / "moved" / "index.html").write_text("<html><body>moved</body></html>")
        (site / "style.css").write_text("body{}")
        (feeds / "appcast.xml").write_text(
            _feed("0.7.0", "https://e/u.zip", beta=False)
        )
        (feeds / "appcast-arm64.xml").write_text(
            _feed("0.7.0", "https://e/a.zip", beta=False)
        )
        (feeds / "changelog.md").write_text("# Changelog\n\n- a change\n")
        (imgs / "icon.png").write_text("png")

        render(site, feeds, out, imgs)

        index = (out / "index.html").read_text()
        assert "<title>Hi</title>" in index and "home" in index
        download = (out / "download" / "index.html").read_text()
        assert "https://e/u.zip" in download
        assert ">0.7.0<" in download
        assert "<h1>Changelog</h1>" in download and "<li>a change</li>" in download
        assert (out / "style.css").read_text() == "body{}"
        assert (out / "imgs" / "icon.png").read_text() == "png"
        assert (out / "appcast.xml").exists() and (out / "changelog.md").exists()
        assert not (out / "_layouts").exists() and not (out / "_includes").exists()

        sitemap = (out / "sitemap.xml").read_text()
        assert f"<loc>{SITE_URL}/</loc>" in sitemap
        assert f"<loc>{SITE_URL}/download/</loc>" in sitemap
        assert (
            "<priority>1.0</priority>" in sitemap
            and "<changefreq>weekly</changefreq>" in sitemap
        )
        assert "/moved/" not in sitemap  # no canonical path -> not indexable

        # A feed holding only a beta item must fall back rather than offer it.
        (feeds / "appcast.xml").write_text(
            _feed("0.8.0-beta", "https://e/beta.zip", beta=True)
        )
        (feeds / "appcast-arm64.xml").unlink()
        render(site, feeds, out, imgs)
        download = (out / "download" / "index.html").read_text()
        assert "beta.zip" not in download and RELEASES_LATEST in download
        assert ">0.7.0<" not in download

    print("self-test ok")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, default=ROOT / "site")
    parser.add_argument("--feeds", type=Path, default=ROOT / "build" / "feeds")
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "site")
    parser.add_argument("--imgs", type=Path, default=ROOT / "imgs")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
    else:
        render(args.site, args.feeds, args.out, args.imgs)


if __name__ == "__main__":
    main()
