import unittest

from appcast import Release, add_release

FIRST = Release(
    version="0.1.0",
    build=7,
    url="https://carbon.alexandrejoly.me/releases/Carbon-0.1.0.dmg",
    length=1234,
    signature="c2lnbmF0dXJlLTE=",
    notes="First release.\nMeetings to Markdown & more.",
    published="Tue, 27 Oct 2026 09:00:00 +0000",
)

SECOND = Release(
    version="0.2.0",
    build=9,
    url="https://carbon.alexandrejoly.me/releases/Carbon-0.2.0.dmg",
    length=5678,
    signature="c2lnbmF0dXJlLTI=",
    notes="Speakers.",
    published="Wed, 28 Oct 2026 10:30:00 +0000",
)

FIRST_ITEM = """\
    <item>
      <title>0.1.0</title>
      <pubDate>Tue, 27 Oct 2026 09:00:00 +0000</pubDate>
      <sparkle:version>7</sparkle:version>
      <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description sparkle:format="plain-text">First release.
Meetings to Markdown &amp; more.</description>
      <enclosure url="https://carbon.alexandrejoly.me/releases/Carbon-0.1.0.dmg" length="1234" type="application/x-apple-diskimage" sparkle:edSignature="c2lnbmF0dXJlLTE=" />
    </item>
"""

SECOND_ITEM = """\
    <item>
      <title>0.2.0</title>
      <pubDate>Wed, 28 Oct 2026 10:30:00 +0000</pubDate>
      <sparkle:version>9</sparkle:version>
      <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description sparkle:format="plain-text">Speakers.</description>
      <enclosure url="https://carbon.alexandrejoly.me/releases/Carbon-0.2.0.dmg" length="5678" type="application/x-apple-diskimage" sparkle:edSignature="c2lnbmF0dXJlLTI=" />
    </item>
"""


def appcast(*items: str) -> str:
    return (
        "<?xml version='1.0' encoding='utf-8'?>\n"
        '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
        "  <channel>\n"
        "    <title>Carbon</title>\n"
        "    <link>https://carbon.alexandrejoly.me/appcast.xml</link>\n"
        "    <description>Carbon updates</description>\n"
        "    <language>en</language>\n"
        + "".join(items)
        + "  </channel>\n"
        "</rss>\n"
    )


class AddReleaseTests(unittest.TestCase):
    def test_first_release_starts_the_appcast(self):
        self.assertEqual(add_release(None, FIRST), appcast(FIRST_ITEM))

    def test_a_new_release_goes_on_top_of_the_previous_ones(self):
        self.assertEqual(
            add_release(appcast(FIRST_ITEM), SECOND),
            appcast(SECOND_ITEM, FIRST_ITEM),
        )

    def test_rerunning_a_release_replaces_its_item(self):
        self.assertEqual(
            add_release(appcast(SECOND_ITEM, FIRST_ITEM), SECOND),
            appcast(SECOND_ITEM, FIRST_ITEM),
        )


if __name__ == "__main__":
    unittest.main()
