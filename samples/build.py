#!/usr/bin/env python3
"""GeoUltra's sample documents (make samples): the brochure, the quick
start guide and a short letter as geoWrite 2.1 documents (tools/gwgen.py
from samples/*.toml), the GeoUltra logo as a geoPaint picture
(tools/gptool.py, from the start picture), on one D81 image, and the
brochure and the guide as PDFs (gwgen's PostScript, ps2pdf):

    build/samples/geoultra-samples.d81
    build/samples/brochure.pdf, build/samples/quickstart.pdf

The screenshots the documents show are in samples/shots (made by
samples/shots.py in VICE, committed). Needs c1541 (VICE) and ps2pdf
(ghostscript).
Usage: samples/build.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build", "samples")
CVT = os.path.join(BUILD, "cvt")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import localcfg  # noqa: E402
C1541 = localcfg.C1541
DOCS = (("letter", "Letter"), ("brochure", "Brochure"), ("quickstart", "Quick start"))


def splash():
    """build/samples/splash.png (the start picture, tools/dev/splash/mksplash.py)
    and logo.png (its upper part: the logo, the name, the line under it)."""
    os.makedirs(BUILD, exist_ok=True)
    tmp = os.path.join(BUILD, "splash")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "splash", "mksplash.py"),
                    tmp + ".bin", tmp + "_col.bin", tmp + ".png", "Graphical desktop for the Ultimate"],
                   env=dict(os.environ, GU_KERNAL=os.path.join(ROOT, "build", "kernal64.bin")), check=True)
    from PIL import Image
    im = Image.open(tmp + ".png")
    im.crop((0, 0, im.width, im.height * 500 // 600)).save(os.path.join(BUILD, "logo.png"))


def gwgen(stem, ps=None):
    cmd = [sys.executable, os.path.join(ROOT, "tools", "gwgen.py"),
           os.path.join(ROOT, "samples", stem + ".toml"), CVT]
    subprocess.run(cmd + (["--ps=" + ps] if ps else []), check=True)


def logo_picture():
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gptool.py"), "import",
                    os.path.join(BUILD, "logo.png"), CVT, "GeoUltra logo", "--colour"],
                   check=True)          # (its shapes as set pixels in their
                                        # colours: right with and without colour)


def disk(path, names):
    """A D81 named "GeoUltra samples" with the CVTs NAMES (from CVT)."""
    if os.path.exists(path):
        os.remove(path)
    cmd = [C1541, "-format", "GeoUltra samples,gu", "d81", path]
    for n in names:
        cmd += ["-geoswrite", os.path.join(CVT, n + ".cvt")]
    subprocess.run(cmd, capture_output=True, check=True)
    return path


def main():
    if os.path.exists(CVT):
        shutil.rmtree(CVT)
    splash()
    logo_picture()
    for stem, _ in DOCS:
        ps = os.path.join(BUILD, stem + ".ps") if stem != "letter" else None
        gwgen(stem, ps)
        if ps:
            subprocess.run(["ps2pdf", ps, ps[:-3] + ".pdf"], check=True)
    out = disk(os.path.join(BUILD, "geoultra-samples.d81"), [n for _, n in DOCS] + ["GeoUltra logo"])
    print(out)


if __name__ == "__main__":
    main()
