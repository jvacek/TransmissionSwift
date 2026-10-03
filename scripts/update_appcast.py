#!/usr/bin/env python3
"""
Update a Sparkle appcast feed with a new release entry.

Each feed is architecture-specific (universal or arm64), so an entry has
exactly one enclosure. The app picks its feed via SPUUpdaterDelegate's
feedURLStringForUpdater:.

Usage:
  update_appcast.py \
    --appcast-path path/to/appcast.xml \
    --download-url "https://github.com/.../release/download/v1.0.0/app.zip" \
    --title "Version 1.0.0" \
    --short-version "1.0.0" \
    --build-version "20260711" \
    --signature "abc123..." \
    --length "1234567" \
    --release-notes-url "https://.../release-notes.md" \
    [--full-release-notes-url "https://.../changelog.md"] \
    [--channel "beta"] \
    [--hardware-requirements "arm64"]

If the appcast does not exist, a new one is created.
The file is modified in-place.
"""

import argparse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"
# ElementTree exposes parsed xml:lang attributes under the XML namespace, not
# the literal "xml:lang" key; using the qualified name keeps set/check in sync.
XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)


def _sparkle(tag):
    return "{%s}%s" % (SPARKLE_NS, tag)


def _dc(tag):
    return "{%s}%s" % (DC_NS, tag)


def ensure_appcast(path):
    try:
        tree = ET.parse(path)
        root = tree.getroot()
        channel = root.find("channel")
        if channel is None:
            channel = ET.SubElement(root, "channel")
            ET.SubElement(channel, "title").text = "TransmissionSwift"
    except (FileNotFoundError, ET.ParseError):
        root = ET.Element(
            "rss",
            attrib={
                "version": "2.0",
                "{%s}%s" % (ET.QName("xmlns"), "sparkle"): SPARKLE_NS,
                "{%s}%s" % (ET.QName("xmlns"), "dc"): DC_NS,
            },
        )
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "TransmissionSwift"
        tree = ET.ElementTree(root)
    return tree, root, channel


def add_item(
    channel,
    title,
    short_version,
    build_version,
    download_url,
    signature,
    length,
    release_notes_url,
    full_release_notes_url=None,
    channel_name=None,
    minimum_system_version="26.0",
    hardware_requirements=None,
):
    item = ET.SubElement(channel, "item")

    ET.SubElement(item, "title").text = title
    ET.SubElement(item, _sparkle("version")).text = build_version
    ET.SubElement(item, _sparkle("shortVersionString")).text = short_version

    # One enclosure per item; the feed is architecture-specific. xml:lang is
    # set so a feed with legacy multi-enclosure items parses without errors.
    ET.SubElement(
        item,
        "enclosure",
        attrib={
            "url": download_url,
            "length": str(length),
            "type": "application/octet-stream",
            XML_LANG: "en",
            _sparkle("edSignature"): signature,
        },
    )

    ET.SubElement(item, _sparkle("minimumSystemVersion")).text = minimum_system_version

    # Guardrail on the arm64 feed: Sparkle refuses the item on Intel Macs.
    if hardware_requirements:
        ET.SubElement(
            item, _sparkle("hardwareRequirements")
        ).text = hardware_requirements

    if release_notes_url:
        ET.SubElement(item, _sparkle("releaseNotesLink")).text = release_notes_url

    if full_release_notes_url:
        ET.SubElement(
            item, _sparkle("fullReleaseNotesLink")
        ).text = full_release_notes_url

    if channel_name:
        ET.SubElement(item, _sparkle("channel")).text = channel_name

    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")
    ET.SubElement(item, "pubDate").text = pub_date


def backfill_enclosure_languages(channel):
    # Items published before xml:lang was emitted still parse (Sparkle assumes
    # "en") but log an error per enclosure on every check. Normalize the whole
    # feed so only new-item code needs to set the attribute.
    for item in channel.findall("item"):
        for enclosure in item.findall("enclosure"):
            if XML_LANG not in enclosure.attrib:
                enclosure.set(XML_LANG, "en")


def main():
    parser = argparse.ArgumentParser(
        description="Update Sparkle appcast with a new release entry"
    )
    parser.add_argument("--appcast-path", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--short-version", required=True)
    parser.add_argument("--build-version", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--length", type=int, required=True)
    parser.add_argument("--release-notes-url", default="")
    parser.add_argument("--full-release-notes-url", default="")
    parser.add_argument("--channel", default="")
    parser.add_argument("--hardware-requirements", default="")
    args = parser.parse_args()

    tree, root, channel = ensure_appcast(args.appcast_path)

    add_item(
        channel,
        title=args.title,
        short_version=args.short_version,
        build_version=args.build_version,
        download_url=args.download_url,
        signature=args.signature,
        length=args.length,
        release_notes_url=args.release_notes_url,
        full_release_notes_url=args.full_release_notes_url or None,
        channel_name=args.channel or None,
        hardware_requirements=args.hardware_requirements or None,
    )

    backfill_enclosure_languages(channel)

    tree.write(args.appcast_path, xml_declaration=True, encoding="utf-8")


if __name__ == "__main__":
    main()
