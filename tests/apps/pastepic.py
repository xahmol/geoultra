#!/usr/bin/env python3
"""geoWrite pastes a photo scrap (C= W) into a document on another drive
(the user's hand test 2026-11-21: "Error I:00 copying photoScrap into data
file"). geoWrite copies the scrap block by block (geoWrite-3.s
copyPhotoScrapData): its own drive current to read a block, SetNextFree
for the next block of the document's disk meanwhile; GEOS 2.0 allocates
in the BAM in memory (the document's), GeoUltra's driver allocated on the
current drive's (reudrv.s SnfOwner). Drive A the user's GEOS64.D81
(GEOS_ORACLE81, a copy) with "ReadMe 1581", drive B a native image with
geoWrite and a "Photo Scrap" in "Writing": a picture 80 x 40 made here (a
frame and a diagonal; docxgw.picture_record, geoWrite's own layout) in
the CVT shell of a Photo Scrap V1.1 (gptool has no scrap export). Check:
the picture at the top of the page (its frame's top line; an error box
would cover it).
Screens: build/harness/apps/pastepic-*.png.
Usage: tests/apps/pastepic.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import docxgw  # noqa: E402
import localcfg  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "apps")
WC, H = 10, 40


def scrap_cvt(path):
    """A sequential CVT "Photo Scrap" (class Photo Scrap V1.1, SYSTEM) with
    the test picture."""
    rows = bytearray()
    for y in range(H):
        for c in range(WC):
            b = 0xFF if y in (0, H - 1) else 0
            if c == 0:
                b |= 0x80
            if c == WC - 1:
                b |= 0x01
            if (y * 2) // 8 == c:
                b |= 0x80 >> ((y * 2) % 8)
            rows.append(b)
    data = docxgw.picture_record(WC, H, bytes(rows))
    sig = bytearray(254)                             # directory entry, signature
    sig[0:3] = bytes([0x81, 0, 0])                   # (SEQ; the link is set on add)
    sig[3:19] = b"Photo Scrap".ljust(16, b"\xa0")
    sig[19:21] = b"\0\0"                             # (the header's place)
    sig[21] = 0                                      # sequential
    sig[22] = 15                                     # SYSTEM
    sig[30 - 2:30] = (1 + (len(data) + 253) // 254).to_bytes(2, "little")
    sig[30:30 + 24] = b"PRG formatted GEOS file "
    sig[54:58] = b"V1.0"
    hdr = bytearray(254)                             # the file header (no link)
    hdr[0:3] = bytes([3, 21, 63 | 0x80])             # icon: 3 x 21, uncompacted
    hdr[66:69] = bytes([0x81, 15, 0])                # Commodore type, GEOS type, structure
    hdr[75:75 + 20] = b"Photo Scrap V1.1".ljust(20, b"\0")
    open(path, "wb").write(bytes(sig) + bytes(hdr) + data)


def main():
    os.makedirs(OUT, exist_ok=True)
    d81 = os.path.join(OUT, "pastepic.d81")
    shutil.copyfile(localcfg.disk("GEOS_ORACLE81", "GEOS64.D81"), d81)
    src = os.path.join(OUT, "pastepic-src.d64")
    if os.path.exists(src):
        os.remove(src)
    gd = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]
    subprocess.run(gd + ["new", src], check=True, capture_output=True)
    cvt = os.path.join(OUT, "Photo Scrap.cvt")
    scrap_cvt(cvt)
    subprocess.run(gd + ["add", src, cvt], check=True, capture_output=True)
    toml = os.path.join(OUT, "pastepic.toml")
    open(toml, "w").write('[dnp]\nout = "pastepic.dnp"\nname = "Apps test"\nid = "AT"\ntracks = 8\n'
                          'strict = true\n\n[sources]\ng = "%s"\ns = "%s"\n\n[[folder]]\npath = "Writing"\n'
                          'files = ["g:GEOWRITE", "s:Photo Scrap"]\n' % (d81, src))
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml], cwd=OUT,
                   check=True, capture_output=True)
    shots = {n: os.path.join(OUT, "pastepic-%s.png" % n) for n in ("doc", "pasted")}
    env = dict(os.environ, APPRUN_DRIVE_A=d81, GEOS_APPS_DISK=os.path.join(OUT, "pastepic.dnp"),
               PYTHONPATH=os.path.join(ROOT, "tools", "dev", "harness"))
    clicks = ["103,86,p", "w:1", "103,86,r", "w:4",          # Open
              "223,98,p", "w:1", "223,98,r", "w:4",          # Drive: A
              "223,63,p", "w:1", "223,63,r", "w:20",         # Open "ReadMe 1581"
              "s:" + shots["doc"],
              "k:#215", "w:20", "s:" + shots["pasted"]]      # C= W: paste picture
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "harness", "apprun.py"), "--wait", "15",
                    "--select", "/b/Writing/GEOWRITE", "--out", os.path.join(OUT, "pastepic.png"), "GEOWRITE"]
                   + clicks, env=env, capture_output=True, text=True, timeout=900)
    from PIL import Image
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    im = Image.open(shots["pasted"]).convert("L")             # (doubled pixels)
    dark = lambda x, y: im.getpixel((x, y)) < 120
    y = 72                                                     # the frame's top line
    check("pasted, no error box: the picture's frame at the top, 80 dots", (
        not dark(238, y), all(dark(x, y) for x in range(240, 400, 2)), not dark(400, y)), (True, True, True))
    print("pastepic: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
