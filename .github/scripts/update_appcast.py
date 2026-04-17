#!/usr/bin/env python3
"""Prepend a new <item> to appcast.xml for a Sparkle release.

Usage:
    python3 update_appcast.py \\
        --appcast appcast.xml \\
        --title "PiGuard 3.4" \\
        --version 702 \\
        --short-version 3.4 \\
        --pub-date 2026-04-17T12:00:00Z \\
        --dmg-url https://github.com/.../PiGuard-3.4-702-macOS.dmg \\
        --dmg-length 12345678 \\
        --signature "base64sig==" \\
        --release-notes-file release_body.txt
"""

import argparse
from email.utils import formatdate
from datetime import datetime


def markdown_to_html(md_text: str) -> str:
    try:
        import markdown
        return markdown.markdown(md_text)
    except ImportError:
        escaped = md_text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        return f"<pre>{escaped}</pre>"


def build_item(
    title: str,
    version: str,
    short_version: str,
    pub_date_rfc: str,
    dmg_url: str,
    dmg_length: str,
    signature: str,
    min_os: str,
    release_notes_html: str,
) -> str:
    return (
        f"    <item>\n"
        f"        <title>{title}</title>\n"
        f"        <pubDate>{pub_date_rfc}</pubDate>\n"
        f"        <sparkle:version>{version}</sparkle:version>\n"
        f"        <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>\n"
        f"        <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>\n"
        f"        <enclosure\n"
        f"            url=\"{dmg_url}\"\n"
        f"            length=\"{dmg_length}\"\n"
        f"            type=\"application/octet-stream\"\n"
        f"            sparkle:edSignature=\"{signature}\" />\n"
        f"        <description><![CDATA[{release_notes_html}]]></description>\n"
        f"    </item>"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--version", required=True, help="CFBundleVersion (build number)")
    parser.add_argument("--short-version", required=True, help="CFBundleShortVersionString (marketing version)")
    parser.add_argument("--pub-date", required=True, help="ISO 8601 date from GitHub API")
    parser.add_argument("--dmg-url", required=True)
    parser.add_argument("--dmg-length", required=True)
    parser.add_argument("--signature", required=True, help="EdDSA signature from sign_update -p")
    parser.add_argument("--min-os", default="11.0")
    parser.add_argument("--release-notes-file", required=True, help="Path to file containing Markdown release notes")
    args = parser.parse_args()

    dt = datetime.fromisoformat(args.pub_date.replace("Z", "+00:00"))
    pub_date_rfc = formatdate(dt.timestamp(), usegmt=True)

    with open(args.release_notes_file, encoding="utf-8") as f:
        notes_html = markdown_to_html(f.read())

    item_xml = build_item(
        title=args.title,
        version=args.version,
        short_version=args.short_version,
        pub_date_rfc=pub_date_rfc,
        dmg_url=args.dmg_url,
        dmg_length=args.dmg_length,
        signature=args.signature,
        min_os=args.min_os,
        release_notes_html=notes_html,
    )

    with open(args.appcast, encoding="utf-8") as f:
        content = f.read()

    if "<item>" in content:
        new_content = content.replace("<item>", item_xml + "\n    <item>", 1)
    else:
        new_content = content.replace("</channel>", item_xml + "\n    </channel>")

    with open(args.appcast, "w", encoding="utf-8") as f:
        f.write(new_content)

    print(f"Prepended item for {args.short_version} (build {args.version}) to {args.appcast}")


if __name__ == "__main__":
    main()
