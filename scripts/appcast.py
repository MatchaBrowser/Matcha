"""Ajoute une version à appcast.xml, le flux de mises à jour de Sparkle (tâche 8.5), créé s'il n'existe pas.

    python3 -I scripts/appcast.py appcast.xml --version 412 --short-version 1.2.0 \
        --url https://…/Matcha-1.2.0.dmg --signature … --length 12345678 --minimum-system 15.4

La nouvelle version passe en tête ; une version de même numéro est remplacée. Ne dépend que de Python.
"""

import argparse
import email.utils
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def sparkle(name):
    return f"{{{SPARKLE}}}{name}"


def empty_feed():
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Matcha"
    ET.SubElement(channel, "link").text = "https://github.com/MatchaBrowser/Matcha"
    ET.SubElement(channel, "description").text = "Mises à jour de Matcha"
    ET.SubElement(channel, "language").text = "fr"
    return ET.ElementTree(rss)


def add_version(tree, args, date=None):
    channel = tree.getroot().find("channel")
    for item in channel.findall("item"):
        if item.findtext(sparkle("version")) == args.version:
            channel.remove(item)
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Matcha {args.short_version}"
    ET.SubElement(item, "pubDate").text = date or email.utils.formatdate(usegmt=True)
    ET.SubElement(item, sparkle("version")).text = args.version
    ET.SubElement(item, sparkle("shortVersionString")).text = args.short_version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = args.minimum_system
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": args.length,
        "type": "application/octet-stream",
        sparkle("edSignature"): args.signature,
    })
    first = next((index for index, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(first, item)


def main(argv):
    parser = argparse.ArgumentParser(description="Ajoute une version à appcast.xml")
    parser.add_argument("feed")
    parser.add_argument("--version", required=True, help="numéro de build (CFBundleVersion)")
    parser.add_argument("--short-version", required=True, help="version affichée (CFBundleShortVersionString)")
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature", required=True, help="sparkle:edSignature")
    parser.add_argument("--length", required=True)
    parser.add_argument("--minimum-system", required=True)
    args = parser.parse_args(argv)
    try:
        tree = ET.parse(args.feed)
    except FileNotFoundError:
        tree = empty_feed()
    add_version(tree, args)
    ET.indent(tree, space="  ")
    tree.write(args.feed, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main(sys.argv[1:])
