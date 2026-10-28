"""Adds a release to Carbon's Sparkle appcast, keeping every previous item.

    appcast.py --previous appcast.xml --version 0.1.0 --build 7 --url URL \
        --length BYTES --signature EDDSA --notes-file notes.txt > new-appcast.xml

`--previous` may name a missing file: the first release starts the appcast.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from email.utils import formatdate
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
FEED_URL = "https://carbon.alexandrejoly.me/appcast.xml"
MINIMUM_SYSTEM_VERSION = "26.0"

ET.register_namespace("sparkle", SPARKLE)


def sparkle(name: str) -> str:
    return f"{{{SPARKLE}}}{name}"


@dataclass(frozen=True)
class Release:
    version: str
    build: int
    url: str
    length: int
    signature: str
    notes: str
    published: str


def empty_channel() -> ET.Element:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Carbon"
    ET.SubElement(channel, "link").text = FEED_URL
    ET.SubElement(channel, "description").text = "Carbon updates"
    ET.SubElement(channel, "language").text = "en"
    return rss


def item(release: Release) -> ET.Element:
    element = ET.Element("item")
    ET.SubElement(element, "title").text = release.version
    ET.SubElement(element, "pubDate").text = release.published
    ET.SubElement(element, sparkle("version")).text = str(release.build)
    ET.SubElement(element, sparkle("shortVersionString")).text = release.version
    ET.SubElement(element, sparkle("minimumSystemVersion")).text = MINIMUM_SYSTEM_VERSION
    notes = ET.SubElement(element, "description", {sparkle("format"): "plain-text"})
    notes.text = release.notes
    ET.SubElement(
        element,
        "enclosure",
        {
            "url": release.url,
            "length": str(release.length),
            "type": "application/x-apple-diskimage",
            sparkle("edSignature"): release.signature,
        },
    )
    return element


def add_release(previous: str | None, release: Release) -> str:
    rss = ET.fromstring(previous) if previous else empty_channel()
    channel = rss.find("channel")
    for existing in channel.findall("item"):
        if existing.findtext(sparkle("version")) == str(release.build):
            channel.remove(existing)
    items = channel.findall("item")
    position = list(channel).index(items[0]) if items else len(channel)
    channel.insert(position, item(release))
    ET.indent(rss)
    return ET.tostring(rss, encoding="unicode", xml_declaration=True) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--previous", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", type=int, required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--notes-file", type=Path, required=True)
    arguments = parser.parse_args()

    previous = arguments.previous.read_text() if arguments.previous.exists() else None
    release = Release(
        version=arguments.version,
        build=arguments.build,
        url=arguments.url,
        length=arguments.length,
        signature=arguments.signature,
        notes=arguments.notes_file.read_text().strip(),
        published=formatdate(usegmt=False),
    )
    sys.stdout.write(add_release(previous, release))


if __name__ == "__main__":
    main()
