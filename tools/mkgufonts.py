#!/usr/bin/env python3
"""mkgufonts.py - build GeoUltra's own GEOS fonts (docs/DESIGN.md "Fonts").

    mkgufonts.py OUTDIR

Each family through tools/mkgeosfont.py from the copies in
tools/fonts/src: TeX Gyre outlines (GUST Font Licence) and, at 10-14
points, the shapes of the X11 75-dpi Adobe bitmaps (permissive licence,
src/adobe75/COPYRIGHT.txt); hand fixes from tools/fonts/<file>_fix.py
where one exists. The font IDs are the LW fonts' (27-36, the user's
decision 2026-11-15), so LW documents open with them when the user has
none; the names are GeoUltra's own ("GU" and a word: no trademarked
names), the info text says what each follows.

Written 2026 by Xander Mol for GeoUltra (own code).
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "fonts", "src")
SIZES = "9,10,12,14,18,24"

# name, ID, TeX Gyre file (None: bitmaps only), Adobe prefix (None: no
# bitmaps), the sizes the bitmaps are used for, fix file stem, what it
# follows (info text)
FAMILIES = [
    ("GU Serif", 27, "texgyretermes-regular", "timR", "10,12,14", "guserif",
     "Times (TeX Gyre Termes, Adobe 75-dpi bitmaps)"),
    ("GU Sans", 28, "texgyreheros-regular", "helvR", "10,12,14", "gusans",
     "Helvetica (TeX Gyre Heros, Adobe 75-dpi bitmaps)"),
    ("GU Symbol", 29, None, "symb", "8,10,12,14,18,24", "gusymbol",
     "Symbol (Adobe 75-dpi bitmaps)"),
    ("GU Mono", 30, "texgyrecursor-regular", "courR", "10,12,14", "gumono",
     "Courier (TeX Gyre Cursor, Adobe 75-dpi bitmaps)"),
    ("GU Geometric", 31, "texgyreadventor-regular", None, None, "gugeometric",
     "Avant Garde (TeX Gyre Adventor)"),
    ("GU Book", 32, "texgyrebonum-regular", None, None, "gubook",
     "Bookman (TeX Gyre Bonum)"),
    ("GU Narrow", 33, "texgyreheroscn-regular", None, None, "gunarrow",
     "Helvetica Narrow (TeX Gyre Heros Condensed)"),
    ("GU School", 34, "texgyreschola-regular", "ncenR", "10,12,14", "guschool",
     "New Century Schoolbook (TeX Gyre Schola, Adobe 75-dpi)"),
    ("GU Classic", 35, "texgyrepagella-regular", None, None, "guclassic",
     "Palatino (TeX Gyre Pagella)"),
    ("GU Script", 36, "texgyrechorus-mediumitalic", None, None, "guscript",
     "Zapf Chancery (TeX Gyre Chorus)"),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().split("\n")[2].strip())
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, fid, otf, pcf, pcf_sizes, fix, follows in FAMILIES:
        sizes = SIZES if otf else pcf_sizes
        target = os.path.join(out, name.lower().replace(" ", "") + ".cvt")
        info = "GeoUltra's font after %s; widths as %s. Licences: README." % (follows, follows.split(" (")[0])
        args = [sys.executable, os.path.join(ROOT, "tools", "mkgeosfont.py"),
                os.path.join(SRC, "texgyre", otf + ".otf") if otf else "-",
                str(fid), name, sizes, target, "--info", info[:95]]
        if pcf:
            args += ["--pcf", os.path.join(SRC, "adobe75", pcf + "%02d.pcf.gz"), "--pcf-sizes", pcf_sizes]
        fixfile = os.path.join(ROOT, "tools", "fonts", fix + "_fix.py")
        if os.path.exists(fixfile):
            args += ["--fix", fixfile]
        subprocess.run(args, check=True)


if __name__ == "__main__":
    main()
