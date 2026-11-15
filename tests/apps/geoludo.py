#!/usr/bin/env python3
"""GeoLudo (the user's own GEOS game, github.com/xahmol/ludo, GEOS/) on
GeoUltra in VICE, through tools/harness/apprun.py: Game > (Re)Start with
four AI players and their default names, the board drawn (player 1,
green); File > Save as SAVE_NAME; six throws (the turn and the die change the
screen); File > Load lists the save, Open restores it: the screen below
the menu bar is the one before the save, pixel for pixel. Twice: from
the root of a copy of GeoLudo's own D81 (LUDO_DISK), and from a folder
of a native (DNP) image made from it with tools/mkappsdnp.py, as drive
C on the U64 has it (there the Load list starts with ".."; GeoLudo's
build of 2023-02-28 failed this one: it does not reopen its VLIR file
after a save). Nothing is written back to the disks.
Screens: build/harness/ludo/*.png.
Usage: tests/apps/geoludo.py
"""
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "ludo")
LUDO_DISK = os.environ.get("LUDO_DISK", os.path.expanduser("~/git/ludo/GEOS/GeoLudo.d81"))
SAVE_NAME = "gutest"           # (GeoLudo pads it with spaces to 16)
GREEN = (85, 160, 73)
BOARD = (0, 26, 640, 400)               # below the menu bar (2x pixels)
COLOUR_BOX = (575, 55)                   # the current player's colour
LIST_ROW = (200, 87)                     # the Load dialog's first entry


def events(save=None, row=0, tag=""):
    """GeoLudo's menus and dialogs, as apprun events (1x coordinates);
    row: the save's row in the Load list; tag: the screens' names."""
    save = save or SAVE_NAME
    throw = ["223,157,p", "w:1", "223,157,r", "w:7"]
    off = ["300,190,p", "w:1", "300,190,r", "w:3"]     # a click outside: menus closed
    shot = lambda n: "s:" + os.path.join(OUT, n + tag + ".png")
    pick = ["100,%d,p" % (44 + 14 * row), "w:1", "100,%d,r" % (44 + 14 * row), "w:2"]
    return (["44,6,p", "w:2", "20,17,p", "w:3",         # Game > (Re)Start
             "k:#29", "k:4", "k:#13", "w:3"]             # 4 AI players
            + ["k:#13", "w:2"] * 4 + ["w:13"]           # default names
            + off + [shot("start")]
            + ["68,6,p", "w:3", "40,17,p", "w:1", "40,17,r", "w:3",   # File > Save
               "k:" + save, "k:#13", "w:10"]
            + off + throw * 6 + [shot("played")]
            + ["68,6,p", "w:3", "12,17,p", "w:1", "12,17,r", "w:6",   # File > Load
               shot("list")] + pick + ["222,63,p", "w:1", "222,63,r", "w:12"])  # Open


def run(disk, select, row, tag, check):
    """One run: GeoLudo from DISK (SELECT: its path in a folder)."""
    env = dict(os.environ, GEOS_APPS_DISK=disk)
    cmd = [sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "14",
           "--out", os.path.join(OUT, "loaded%s.png" % tag)]
    if select:
        cmd += ["--select", select]
    r = subprocess.run(cmd + ["GeoLudo"] + events(row=row, tag=tag), env=env,
                       capture_output=True, text=True, timeout=590)
    print(r.stdout.strip().splitlines()[0] if r.stdout.strip() else r.stderr[-300:])
    im = {n: Image.open(os.path.join(OUT, n + tag + ".png")).convert("RGB")
          for n in ("start", "played", "list", "loaded")}
    where = "folder" if select else "root"
    check("%s: started, player 1 (green)" % where, im["start"].getpixel(COLOUR_BOX), GREEN)
    check("%s: six throws changed the screen" % where, ImageChops.difference(
        im["start"].crop(BOARD), im["played"].crop(BOARD)).getbbox() is not None, True)
    check("%s: File > Load lists files (the first row selected)" % where,
          im["list"].getpixel(LIST_ROW), (0, 0, 0))
    check("%s: loaded, the board as saved, pixel for pixel" % where, ImageChops.difference(
        im["start"].crop(BOARD), im["loaded"].crop(BOARD)).getbbox(), None)


def main():
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "geoludo.d81")
    shutil.copyfile(LUDO_DISK, disk)
    toml = os.path.join(OUT, "ludo-folder.toml")
    open(toml, "w").write('[dnp]\nout = "ludo-folder.dnp"\nname = "Ludo folder"\nid = "LF"\n'
                          'tracks = 4\nstrict = true\n\n[sources]\nludo = "%s"\n\n'
                          '[[folder]]\npath = "Games"\nfiles = ["ludo:GeoLudo"]\n' % disk)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml],
                   check=True, capture_output=True)
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    run(disk, None, 0, "", check)
    run(os.path.join(OUT, "ludo-folder.dnp"), "/b/Games/GeoLudo", 1, "-f", check)
    print("geoludo: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
