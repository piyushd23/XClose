#!/usr/bin/env python3
"""Inserts dist/appcast-item.xml at the top of site/appcast.xml (newest first).

Usage: python3 scripts/update-appcast.py [item.xml] [appcast.xml]
"""
import pathlib
import re
import sys

item_path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "dist/appcast-item.xml")
appcast_path = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "site/appcast.xml")
marker = "<!-- items: newest first -->"

item = item_path.read_text().rstrip("\n")
appcast = appcast_path.read_text()
version = re.search(r"<sparkle:shortVersionString>([^<]+)<", item).group(1)
if f"<sparkle:shortVersionString>{version}<" in appcast:
    sys.exit(f"{appcast_path} already lists {version}")
if marker not in appcast:
    sys.exit(f"{appcast_path} is missing the marker {marker!r}")
appcast_path.write_text(appcast.replace(marker, marker + "\n" + item, 1))
print(f"Added {version} to {appcast_path}")
