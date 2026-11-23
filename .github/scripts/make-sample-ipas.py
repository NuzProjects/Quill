#!/usr/bin/env python3
"""Writes a few tiny placeholder .ipa files so the UI screenshot run has apps in the Library."""
import io, plistlib, struct, sys, zipfile, zlib
from pathlib import Path

APPS = [
    ("Tempo", "1.4.2", (91, 133, 240), (52, 84, 200)),
    ("Pixel Cam", "3.0", (240, 96, 120), (190, 50, 90)),
    ("Orbit", "2.1.1", (64, 196, 160), (30, 140, 120)),
    ("Lumen", "0.9.8", (250, 190, 70), (230, 130, 40)),
    ("Pocket Chess", "5.2", (120, 110, 230), (70, 60, 170)),
    ("Field Notes", "1.0", (90, 90, 100), (40, 40, 50)),
]


def png(size, top, bottom):
    rows = bytearray()
    for y in range(size):
        t = y / (size - 1)
        colour = bytes(round(a + (b - a) * t) for a, b in zip(top, bottom))
        rows += b"\x00" + colour * size

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b""))


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    for name, version, top, bottom in APPS:
        slug = name.replace(" ", "")
        info = {
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": f"dev.madebynuz.sample.{slug.lower()}",
            "CFBundleExecutable": slug,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "1",
            "CFBundlePackageType": "APPL",
            "MinimumOSVersion": "16.0",
            "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60"]}},
        }
        with zipfile.ZipFile(out / f"{slug}.ipa", "w", zipfile.ZIP_DEFLATED) as z:
            root = f"Payload/{slug}.app/"
            z.writestr(root + "Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            z.writestr(root + slug, b"")
            z.writestr(root + "AppIcon60x60@2x.png", png(120, top, bottom))
            z.writestr(root + "AppIcon60x60@3x.png", png(180, top, bottom))
        print(slug)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
