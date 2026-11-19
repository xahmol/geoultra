#!/usr/bin/env python3
"""A font on drive E, the system drive, in geoWrite on GeoUltra in VICE.

A test copy of the system drive gets a font from the user's own disks
(SYSFONT_DISK, a D64 or D81, default GEOS64.D81 in GEOS_DEV, font
SYSFONT_NAME, default LW_Cal; never committed) in its root next to
GeoUltra's own files (src/sysdrive.toml, tools/mkappsdnp.py), is
relocated (tools/dev/sysreloc.py) and patched into a copy of the cartridge. geoWrite runs from GEOS_APPS_DISK (default the
user's neos-mouse-driver-for-geos.d64, five fonts, so the menu has room),
the font menu is opened, and the font chosen and typed with. Screens in
build/harness/sysfont-*.png; the font menu is checked for the font's
name by comparing with a run of the plain cartridge.
Usage: tests/drives/sysfont.py
"""
import os
import re
import subprocess
import sys
import tomllib
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness")
FONT_DISK = localcfg.disk("SYSFONT_DISK", "GEOS64.D81")
FONT_NAME = os.environ.get("SYSFONT_NAME", "LW_Cal")
APPS_DISK = localcfg.disk("GEOS_APPS_DISK", "neos-mouse-driver-for-geos.d64")


def build():
    """The test system drive (src/sysdrive.toml's files and the font in its
    root), relocated as the Makefile does, in a copy of the cartridge."""
    manifest = os.path.join(OUT, "sysfont.toml")
    plain = os.path.join(OUT, "sysfont-plain.dnp")
    image = os.path.join(OUT, "sysfont.dnp")
    sysdrive = tomllib.load(open(os.path.join(ROOT, "src", "sysdrive.toml"), "rb"))
    lines = ["[dnp]", 'out = "%s"' % plain, 'name = "GeoUltra System"', 'id = "GU"',
             "tracks = %d" % sysdrive["dnp"]["tracks"], "strict = true", "", "[sources]"]
    for key, path in sysdrive["sources"].items():
        lines.append('%s = "%s"' % (key, os.path.normpath(os.path.join(ROOT, "src", path))))
    lines.append('font = "%s"' % FONT_DISK)
    for folder in sysdrive["folder"]:
        files = list(folder["files"]) + (["font:" + FONT_NAME] if not folder["path"] else [])
        lines += ["", "[[folder]]", 'path = "%s"' % folder["path"],
                  "files = [%s]" % ", ".join('"%s"' % f for f in files)]
    open(manifest, "w").write("\n".join(lines) + "\n")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), manifest],
                   check=True, stdout=subprocess.DEVNULL)
    inc = open(os.path.join(ROOT, "src", "inc", "sysdrive.inc")).read()
    shift = re.search(r"^SYSDRV_TRACK\s*=\s*(\d+)", inc, re.M).group(1)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "sysreloc.py"), plain, image, shift],
                   check=True, stdout=subprocess.DEVNULL)
    crt = bytearray(open(os.path.join(ROOT, "build", "geoultra64.crt"), "rb").read())
    packets, at = [], int.from_bytes(crt[0x10:0x14], "big")
    while at < len(crt):
        size = int.from_bytes(crt[at + 4:at + 8], "big")
        packets.append((at + 16, size - 16))
        at += size
    rom = bytearray(b"".join(crt[p:p + n] for p, n in packets))
    old = open(os.path.join(ROOT, "build", "sysdrive.dnp"), "rb").read()
    new = open(image, "rb").read()
    head = 256                                  # block 1/1 of a DNP
    start = rom.find(old[head:head + 256]) - head
    if start < 0 or rom[start:start + len(old)] != old:
        sys.exit("sysfont.py: the system drive is not in the cartridge")
    if len(new) != len(old):
        sys.exit("sysfont.py: the test drive has %d tracks stored, the cartridge's %d"
                 % (len(new) // 65536, len(old) // 65536))
    rom[start:start + len(new)] = new
    at = 0
    for p, n in packets:
        crt[p:p + n] = rom[at:at + n]
        at += n
    path = os.path.join(OUT, "sysfont.crt")
    open(path, "wb").write(crt)
    return path


def run(cartridge, out, *events):
    env = dict(os.environ, GEOS_APPS_DISK=APPS_DISK, GEOULTRA_CRT=cartridge)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "harness", "apprun.py"),
                    "--wait", "12", "--out", out, "GEOWRITE",
                    "102,63,p", "102,63,r", "w:3", "k:Font test", "k:#13", "w:8"] + list(events),
                   env=env, check=True, stdout=subprocess.DEVNULL)


def main():
    os.makedirs(OUT, exist_ok=True)
    cartridge = build()
    menu = os.path.join(OUT, "sysfont-menu.png")
    plain = os.path.join(OUT, "sysfont-menu-plain.png")
    run(cartridge, menu, "122,6,p", "w:3")
    run(os.path.join(ROOT, "build", "geoultra64.crt"), plain, "122,6,p", "w:3")
    print("font menu with drive E's font: %s (without: %s)" % (menu, plain))


if __name__ == "__main__":
    main()
