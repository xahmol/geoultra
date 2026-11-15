#!/usr/bin/env python3
"""geoWrite on GeoUltra in VICE: a document created, typed, saved (file >
close), opened again (its text as typed), edited at its start, saved and
opened once more (the edit kept), then file > quit and the document on
the disk (FindFile). Through tools/harness/apprun.py with a copy of an
applications disk (GEOS_APPS_DISK, the user's own, default the
neos-mouse-driver disk with geoWrite 1.1; never committed). Screens:
build/harness/gw/*.png.
Usage: tests/apps/geowrite.py
"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "gw")
APPS_DISK = os.environ.get("GEOS_APPS_DISK", os.path.expanduser(
    "~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))
DOC = "GU test"
TEXT = (0, 56, 640, 110)                # the first two lines (2x pixels)


def events():
    """geoWrite's dialogs and menus, as apprun events (1x coordinates)."""
    shot = lambda n: "s:" + os.path.join(OUT, n + ".png")
    menu = lambda y: ["30,6,p", "w:2", "45,%d,p" % y, "w:1", "45,%d,r" % y, "w:8"]
    close, quit_ = menu(21), menu(105)
    open_ = ["102,87,p", "w:1", "102,87,r", "w:6",          # Open existing
             "100,57,p", "w:1", "100,57,r", "w:1",          # its second row
             "222,62,p", "w:1", "222,62,r", "w:10"]         # Open
    return (["102,63,p", "102,63,r", "w:3", "k:" + DOC, "k:#13", "w:8",   # Create
             "k:Hello GeoUltra.", "k:#13", "k:Second line of text.", "w:3", shot("typed")]
            + close + open_ + [shot("reopened"), "k:Edited: ", "w:3", shot("edited")]
            + close + open_ + [shot("reopened2")] + quit_)


def main():
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "apps.d64")
    shutil.copyfile(APPS_DISK, disk)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "12", "--find", DOC, "--out", os.path.join(OUT, "end.png"),
                        "GEOWRITE"] + events(), env=dict(os.environ, GEOS_APPS_DISK=disk),
                       capture_output=True, text=True, timeout=590)
    print(r.stdout.strip())
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    im = {n: Image.open(os.path.join(OUT, n + ".png")).convert("RGB").crop(TEXT)
          for n in ("typed", "reopened", "edited", "reopened2")}
    diff = lambda a, b: ImageChops.difference(im[a], im[b]).getbbox()
    check("typed text on the screen", im["typed"].getextrema()[0][0] < 100, True)
    check("saved and opened again: the same text", diff("typed", "reopened"), None)
    check("edited: the text changed", diff("typed", "edited") is not None, True)
    check("saved and opened again: the edit kept", diff("edited", "reopened2"), None)
    check("quit: the document on the disk", "FindFile '%s' on drive B: X = $00" % DOC in r.stdout, True)
    print("geowrite: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
