#!/usr/bin/env python3
"""A font on drive E, the system drive, in geoWrite on GeoUltra in VICE.

A test copy of the system drive gets a font from the user's own disks
(SYSFONT_DISK, a D64 or D81, default ~/geos-dev/u64-usb/GEOS64.D81, font
SYSFONT_NAME, default LW_Cal; never committed) next to
GeoUltra's own files, is relocated (tools/sysreloc.py) and patched into a
copy of the cartridge. geoWrite runs from GEOS_APPS_DISK (default the
user's neos-mouse-driver-for-geos.d64, five fonts, so the menu has room),
the font menu is opened, and the font chosen and typed with. Screens in
build/harness/sysfont-*.png; the font menu is checked for the font's
name by comparing with a run of the plain cartridge.
Usage: tests/drives/sysfont.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness")
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")
FONT_DISK = os.environ.get("SYSFONT_DISK", os.path.expanduser("~/geos-dev/u64-usb/GEOS64.D81"))
FONT_NAME = os.environ.get("SYSFONT_NAME", "LW_Cal")
APPS_DISK = os.environ.get("GEOS_APPS_DISK", os.path.expanduser(
    "~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))


class Image:
    """A D64 or D81 image: blocks by track/sector."""

    def __init__(self, path):
        self.data = bytearray(open(path, "rb").read())
        self.d81 = len(self.data) == 819200
        self.dir = (40, 3) if self.d81 else (18, 1)

    def sectors(self, track):
        if self.d81:
            return 40
        return 21 if track <= 17 else 19 if track <= 24 else 18 if track <= 30 else 17

    def at(self, track, sector):
        return (sum(self.sectors(t) for t in range(1, track)) + sector) * 256

    def block(self, track, sector):
        return self.data[self.at(track, sector):self.at(track, sector) + 256]

    def put(self, track, sector, block):
        self.data[self.at(track, sector):self.at(track, sector) + 256] = block

    def entries(self):
        track, sector = self.dir
        while track:
            block = self.block(track, sector)
            for e in range(8):
                yield track, sector, 2 + 32 * e, block[2 + 32 * e:2 + 32 * e + 30]
            track, sector = block[0], block[1]

    def chain(self, track, sector):
        while track:
            block = self.block(track, sector)
            yield block
            track, sector = block[0], block[1]


def copy_font(source, target):
    """FONT_NAME (a VLIR file) from the image `source` onto the D64 `target`:
    header, index block and records into free blocks, the BAM updated."""
    src, dst = Image(source), Image(target)
    entry = next((e for _, _, _, e in src.entries() if e[0] & 7
                  and e[3:19].split(b"\xa0")[0].decode("latin1") == FONT_NAME), None)
    if entry is None or entry[0x15] != 1:
        sys.exit("sysfont.py: no VLIR file %s on %s" % (FONT_NAME, source))
    bam = dst.at(18, 0)
    free = [(t, s) for t in range(1, 36) if t != 18 for s in range(dst.sectors(t))
            if dst.data[bam + 4 * t + 1 + s // 8] & (1 << (s % 8))]

    def take():
        t, s = free.pop(0)
        dst.data[bam + 4 * t] -= 1
        dst.data[bam + 4 * t + 1 + s // 8] &= ~(1 << (s % 8)) & 0xFF
        return t, s

    def write_chain(blocks):
        where = [take() for _ in blocks]
        for i, block in enumerate(blocks):
            block = bytearray(block)
            if i + 1 < len(blocks):
                block[0], block[1] = where[i + 1]
            dst.put(*where[i], block)
        return where[0]

    header = take()
    dst.put(*header, src.block(entry[0x13], entry[0x14]))
    index = bytearray(src.block(entry[1], entry[2]))
    count = 2
    for r in range(2, 256, 2):
        if index[r]:
            blocks = list(src.chain(index[r], index[r + 1]))
            index[r], index[r + 1] = write_chain(blocks)
            count += len(blocks)
    where = take()
    dst.put(*where, index)
    new = bytearray(entry)
    new[1], new[2] = where
    new[0x13], new[0x14] = header
    new[0x1C], new[0x1D] = count & 0xFF, count >> 8
    for t, s, off, e in dst.entries():
        if not e[0]:
            block = dst.block(t, s)
            block[off:off + 30] = new
            dst.put(t, s, block)
            break
    else:
        sys.exit("sysfont.py: no free directory entry")
    open(target, "wb").write(dst.data)


def build():
    """The test system drive, relocated, in a copy of the cartridge."""
    plain = os.path.join(OUT, "sysfont-plain.d64")
    image = os.path.join(OUT, "sysfont.d64")
    if os.path.exists(plain):
        os.remove(plain)
    subprocess.run([C1541, "-format", "geoultra system,gu", "d64", plain,
                    "-geoswrite", os.path.join(ROOT, "build", "tools", "geofolder.cvt")],
                   capture_output=True, check=True)
    copy_font(FONT_DISK, plain)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sysreloc.py"), plain, image],
                   check=True, stdout=subprocess.DEVNULL)
    crt = bytearray(open(os.path.join(ROOT, "build", "geoultra64.crt"), "rb").read())
    packets, at = [], int.from_bytes(crt[0x10:0x14], "big")
    while at < len(crt):
        size = int.from_bytes(crt[at + 4:at + 8], "big")
        packets.append((at + 16, size - 16))
        at += size
    rom = bytearray(b"".join(crt[p:p + n] for p, n in packets))
    old = open(os.path.join(ROOT, "build", "sysdrive.d64"), "rb").read()
    new = open(image, "rb").read()
    head = 357 * 256                            # block 18/0 of a D64
    start = rom.find(old[head:head + 256]) - head
    if start < 0 or rom[start:start + len(old)] != old:
        sys.exit("sysfont.py: the system drive is not in the cartridge")
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
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
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
