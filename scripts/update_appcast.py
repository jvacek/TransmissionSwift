#!/usr/bin/env python3
"""
Update the Sparkle appcast.xml with a new release entry.

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
    [--channel "beta"]

If appcast.xml does not exist, a new one is created.
The file is modified in-place.
"""

import argparse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"

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
    channel_name=None,
    minimum_system_version="26.0",
    download_url_arm64=None,
    signature_arm64=None,
    length_arm64=None,
):
    item = ET.SubElement(channel, "item")

    ET.SubElement(item, "title").text = title
    ET.SubElement(item, _sparkle("version")).text = build_version
    ET.SubElement(item, _sparkle("shortVersionString")).text = short_version

    # Universal / x86_64 enclosure
    enclosure_attrs = {
        "url": download_url,
        "length": str(length),
        "type": "application/octet-stream",
        _sparkle("edSignature"): signature,
    }
    if download_url_arm64:
        enclosure_attrs[_sparkle("arch")] = "x86_64"
    ET.SubElement(item, "enclosure", attrib=enclosure_attrs)

    # Arm64-only enclosure (optional)
    if download_url_arm64 and signature_arm64 and length_arm64 is not None:
        ET.SubElement(
            item,
            "enclosure",
            attrib={
                "url": download_url_arm64,
                "length": str(length_arm64),
                "type": "application/octet-stream",
                _sparkle("edSignature"): signature_arm64,
                _sparkle("arch"): "arm64",
            },
        )

    ET.SubElement(item, _sparkle("minimumSystemVersion")).text = minimum_system_version

    if release_notes_url:
        ET.SubElement(item, _sparkle("releaseNotesLink")).text = release_notes_url

    if channel_name:
        ET.SubElement(item, _sparkle("channel")).text = channel_name

    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")
    ET.SubElement(item, "pubDate").text = pub_date


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
    parser.add_argument("--channel", default="")
    parser.add_argument("--download-url-arm64", default="")
    parser.add_argument("--signature-arm64", default="")
    parser.add_argument("--length-arm64", type=int, default=0)
    args = parser.parse_args()

    tree, root, channel = ensure_appcast(args.appcast_path)

    has_arm64 = bool(args.download_url_arm64)
    if has_arm64 and not (args.signature_arm64 and args.length_arm64):
        parser.error("--signature-arm64 and --length-arm64 are required with --download-url-arm64")

    add_item(
        channel,
        title=args.title,
        short_version=args.short_version,
        build_version=args.build_version,
        download_url=args.download_url,
        signature=args.signature,
        length=args.length,
        release_notes_url=args.release_notes_url,
        channel_name=args.channel or None,
        download_url_arm64=args.download_url_arm64 or None,
        signature_arm64=args.signature_arm64 or None,
        length_arm64=args.length_arm64 or None,
    )

    tree.write(args.appcast_path, xml_declaration=True, encoding="utf-8")


if __name__ == "__main__":
    main()
