"""Tests of appcast.py (review TS12): a new feed, the new version first, a version given again replaced.

    python3 -I scripts/test-appcast.py

Run by scripts/check.sh. Depends only on Python.
"""

import importlib.util
import pathlib
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

# Loaded from its path (`-I` leaves the script's folder out of the import path), leaving no `__pycache__` there.
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("appcast", pathlib.Path(__file__).with_name("appcast.py"))
appcast = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(appcast)


def arguments(feed, version, short_version):
    return [
        str(feed), "--version", version, "--short-version", short_version,
        "--url", f"https://example.test/Matcha-{short_version}.dmg", "--signature", f"signature-{version}",
        "--length", "12345678", "--minimum-system", "15.4",
    ]


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.feed = pathlib.Path(self.folder.name) / "appcast.xml"

    def tearDown(self):
        self.folder.cleanup()

    def items(self):
        return ET.parse(self.feed).getroot().find("channel").findall("item")

    def test_a_missing_feed_is_created_with_the_version(self):
        appcast.main(arguments(self.feed, "412", "1.2.0"))
        [item] = self.items()
        self.assertEqual(item.findtext("title"), "Matcha 1.2.0")
        self.assertEqual(item.findtext(appcast.sparkle("version")), "412")
        self.assertEqual(item.findtext(appcast.sparkle("shortVersionString")), "1.2.0")
        self.assertEqual(item.findtext(appcast.sparkle("minimumSystemVersion")), "15.4")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"), "https://example.test/Matcha-1.2.0.dmg")
        self.assertEqual(enclosure.get("length"), "12345678")
        self.assertEqual(enclosure.get(appcast.sparkle("edSignature")), "signature-412")
        self.assertTrue(self.feed.read_text(encoding="utf-8").startswith("<?xml"))

    def test_the_new_version_comes_first(self):
        appcast.main(arguments(self.feed, "412", "1.2.0"))
        appcast.main(arguments(self.feed, "420", "1.3.0"))
        self.assertEqual([item.findtext(appcast.sparkle("version")) for item in self.items()], ["420", "412"])

    def test_a_version_given_again_is_replaced(self):
        appcast.main(arguments(self.feed, "412", "1.2.0"))
        appcast.main(arguments(self.feed, "420", "1.3.0"))
        appcast.main(arguments(self.feed, "412", "1.2.1"))
        items = self.items()
        self.assertEqual([item.findtext(appcast.sparkle("version")) for item in items], ["412", "420"])
        self.assertEqual(items[0].findtext(appcast.sparkle("shortVersionString")), "1.2.1")


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0], "-q"], exit=False).result
    sys.exit(0 if result.wasSuccessful() else 1)
