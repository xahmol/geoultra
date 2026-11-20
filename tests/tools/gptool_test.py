#!/usr/bin/env python3
"""tools/gptool.py (docs/manuals/TOOLS_MANUAL.md): the geoPaint compression both
ways (random strips, and runs of bytes and of cards, decompressed back
the same; within the format's limits); a picture with shapes in black
and white imported into a D64 as a geoPaint document, listed, exported
again: the same pixels; in colour: each card's two colours chosen from
the picture (a red square on blue comes back red on blue); --crop.
With GEOS_PAINT_IMAGE (a disk image with geoPaint documents, the user's
own) also: each of its documents' strips decompressed and compressed
again by gptool gives the same pixels. No VICE.
Usage: tests/tools/gptool_test.py
"""
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gptool  # noqa: E402
from mkappsdnp import Image  # noqa: E402
from PIL import Image as PImage, ImageDraw  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "tools", "paint")
TOOL = [sys.executable, os.path.join(ROOT, "tools", "gptool.py")]
REAL = localcfg.disk("GEOS_PAINT_IMAGE", "mp3-64.d81")


def main():
    os.makedirs(OUT, exist_ok=True)
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    rnd = random.Random(7)
    samples = [bytes(rnd.randrange(256) for _ in range(gptool.REC_BYTES)),
               bytes(gptool.REC_BYTES),
               (bytes([0x55, 0xAA] * 4) * 181)[:gptool.REC_BYTES],
               bytes(rnd.choice((0, 0xFF, 7)) for _ in range(gptool.REC_BYTES))]
    good = all(gptool.decompress(gptool.compress(x)) == x for x in samples)
    packets = all(len(gptool.compress(x)) < len(x) for x in samples[1:3])
    check("compression: back the same (random, blank, cards, runs)", good)
    check("compression: blank and patterned strips shrink", packets)
    check("every stream ends with geoPaint's end byte 0 (without it geoPaint reads on)",
          all(gptool.compress(x).endswith(b"\0") for x in samples))
    pic = os.path.join(OUT, "shapes.png")
    im = PImage.new("RGB", (320, 200), "white")
    d = ImageDraw.Draw(im)
    d.rectangle((10, 10, 150, 90), outline="black", width=3)
    d.ellipse((170, 20, 300, 180), fill="black")
    d.line((0, 199, 319, 0), fill="black", width=2)
    im.save(pic)
    img = os.path.join(OUT, "paint.d64")
    for f in (img,):
        if os.path.exists(f):
            os.remove(f)
    r = subprocess.run(TOOL + ["import", pic, img, "Shapes", "--no-dither"], capture_output=True, text=True)
    check("import (black and white) into a D64", r.returncode == 0, r.stderr)
    listed = subprocess.run(TOOL + ["list", img], capture_output=True, text=True).stdout
    check("list: the document, Paint Image V1.1, 45 strips", "Shapes" in listed and "V1.1" in listed
          and "45 of 45" in listed, listed)
    back = os.path.join(OUT, "back.png")
    subprocess.run(TOOL + ["export", img, "Shapes", back, "--mono"], capture_output=True, check=True)
    a = PImage.open(pic).convert("L").point(lambda v: 0 if v < 128 else 255)
    b = PImage.open(back).convert("L").crop((0, 0, 320, 200))
    check("exported again: the same pixels", list(a.getdata()) == list(b.getdata()))
    en = Image(img).find("Shapes")
    idx = Image(img).block(en[1], en[2])
    pairs = [(idx[2 + 2 * k], idx[3 + 2 * k]) for k in range(127)]
    check("all 127 index entries exist (45 strips, the rest empty)", (0, 0) not in pairs
          and sum(1 for p in pairs if p[0]) == 45)
    cpic = os.path.join(OUT, "colour.png")
    im = PImage.new("RGB", (64, 64), gptool.PALETTE[6])
    ImageDraw.Draw(im).rectangle((16, 16, 47, 47), fill=gptool.PALETTE[2])
    im.save(cpic)
    cimg = os.path.join(OUT, "colour.d64")
    if os.path.exists(cimg):
        os.remove(cimg)
    subprocess.run(TOOL + ["import", cpic, cimg, "Colour", "--colour"], capture_output=True, check=True)
    full = os.path.join(OUT, "colour-full.png")
    subprocess.run(TOOL + ["export", cimg, "Colour", full], capture_output=True, check=True)
    px = PImage.open(full).convert("RGB")
    check("colour: the square red, around it blue (exported again)",
          px.getpixel((30, 30)) == gptool.PALETTE[2] and px.getpixel((4, 4)) == gptool.PALETTE[6]
          and px.getpixel((60, 30)) == gptool.PALETTE[6], (px.getpixel((30, 30)), px.getpixel((4, 4))))
    cb = os.path.join(OUT, "colour-back.png")
    subprocess.run(TOOL + ["export", cimg, "Colour", cb, "--crop"], capture_output=True, check=True)
    check("colour exported, cropped to the drawing: the square (its blue background fills the page",
          PImage.open(cb).size == (32, 32), PImage.open(cb).size)  # since the import keeps it as paper)
    if os.path.exists(REAL):
        real = Image(REAL)
        names = [l.split()[0] for l in subprocess.run(TOOL + ["list", REAL], capture_output=True,
                                                      text=True).stdout.splitlines() if l.strip()]
        same = True
        for n in names:
            gf = gptool.find(real, n)
            for rec in gf.records[:gptool.RECORDS]:
                if rec in (None, "end"):
                    continue
                raw = gptool.decompress(rec)
                same = same and gptool.decompress(gptool.compress(raw)) == raw
        check("%d real documents: every strip recompressed the same" % len(names), same and names, names)
    print("gptool_test: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
