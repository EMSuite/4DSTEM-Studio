"""Writes the Sparkle update feed for one download (#122, #374). Called by appcast.sh; testable on its own.

    python3 -I feed.py <CHANGELOG.md> <version> <macOS floor> <sign_update attributes> <out.xml> [notes file]

The feed's <description> is short, user-facing text (#374): the notes file (docs/app-store/whats-new.txt, the store's
What's New text written and approved for the release) when it names this version; otherwise this version's CHANGELOG
section with commit hashes, "closes #N" and issue links stripped. The full list stays behind
sparkle:fullReleaseNotesLink, the GitHub release.
"""
import re
import sys
from email.utils import formatdate
from xml.sax.saxutils import escape


def notes_from_file(path, version):
    """The notes file's text, or None when it is missing, empty or written for another version."""
    try:
        text = open(path, encoding="utf-8").read().strip()
    except OSError:
        return None
    if not text or version not in text:
        return None
    return text


def notes_from_changelog(path, version):
    """This version's CHANGELOG section as plain bullets, without hashes, issue refs or links."""
    lines, commits, inside = [], set(), False
    for line in open(path, encoding="utf-8"):
        if line.startswith("## "):
            if inside:
                break
            inside = re.match(r"## \[?" + re.escape(version) + r"\]?[ (]", line + " ") is not None
            continue
        if not inside or not line.strip() or line.startswith("#"):
            continue
        commit = re.search(r"\(\[([0-9a-f]{7,40})\]\(", line)
        if commit:  # one commit listed twice (release-please reads a squash body's lines as entries) is one note
            if commit.group(1) in commits:
                continue
            commits.add(commit.group(1))
        line = re.sub(r",? closes \[#\d+\]\([^)]+\)(, \[#\d+\]\([^)]+\))*", "", line)
        line = re.sub(r" \(\[[0-9a-f]{7,40}\]\([^)]+\)\)", "", line)  # (345776b)
        line = re.sub(r"\[#\d+\]\([^)]+\)", "", line)                 # #327 anywhere
        line = re.sub(r"\(,\s*|,\s*\)", lambda m: "(" if m.group(0).startswith("(") else ")", line)
        line = re.sub(r"\s*\(\s*\)", "", line)
        line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
        line = line.replace("**", "").rstrip()
        line = re.sub(r"^\* ", "• ", line)
        if line not in lines:
            lines.append(line)
    return "\n".join(lines).strip() or None


def main(argv):
    changelog, version, floor, attributes, feed = argv[:5]
    notes_file = argv[5] if len(argv) > 5 else None
    notes = notes_from_file(notes_file, version) if notes_file else None
    if notes is None:
        if notes_file:
            print(f"{notes_file} does not name {version}; the feed takes the CHANGELOG section", file=sys.stderr)
        notes = notes_from_changelog(changelog, version)
    if not notes:
        sys.exit(f"No release notes for {version}: neither a notes file naming it nor a CHANGELOG section")
    tag = f"v{version}"
    item = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>mac4DSTEM</title>
    <link>https://mac4dstem.com/</link>
    <item>
      <title>mac4DSTEM {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{floor}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/EMSuite/4DSTEM-Studio/releases/tag/{tag}</sparkle:fullReleaseNotesLink>
      <description sparkle:format="plain-text">{escape(notes)}</description>
      <enclosure url="https://github.com/EMSuite/4DSTEM-Studio/releases/download/{tag}/mac4DSTEM-{version}.dmg" type="application/octet-stream" {attributes}/>
    </item>
  </channel>
</rss>
"""
    open(feed, "w", encoding="utf-8").write(item)


if __name__ == "__main__":
    main(sys.argv[1:])
