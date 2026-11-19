#!/usr/bin/env python3
"""GeoLudo on GeoUltra on the U64: started from drive C (the private apps
DNP, its test copy in /USB0/GEOULTRA/test: /c/Games/GeoLudo) in a new
task, as the desktop's "open in new task" does (FE_TASK), then the
same steps as tests/apps/geoludo.py through memory (the pointer and its
button at $3A-$3C, mouseData, pressFlag; keys into the kernal's queue):
a game with four AI players, File > Save, six throws, File > Load, Open:
the board as saved. Screens from the VIC stream (GeoUTools'
tests/e2e/shot.py). Afterwards a reboot and the save deleted again
(FE_DELETE; if that fails, drive C's image is put back as it was);
the user's HIBERNAT.BIN is set aside first and put back.
Usage: tests/apps/geoludou64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

OUT = os.path.join(ROOT, "build", "e2e", "ludo")
SHOT = localcfg.GEOUTOOLS_SHOT
APP = "/c/Games/GeoLudo"
SAVE_NAME = "gutest"
SAVE_FILE = SAVE_NAME.ljust(16)                # (GeoLudo pads with spaces)
HOME = "/USB0/GEOULTRA/"
C_IMAGE = HOME + "test/geoultra-apps.dnp"   # (MOUNTS.INI C=, a test copy)
FE_TASK, FE_DELETE = 32, 7
KEY_DELETE, CR = 29, 13


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    os.makedirs(OUT, exist_ok=True)
    u = U64()
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    def shot(name):
        u.write(0x3A, bytes([0x30, 0x01, 196]))      # (the pointer, a sprite, parked
        time.sleep(0.5)                             # at the same place each time)
        path = os.path.join(OUT, name + ".png")
        subprocess.run([sys.executable, SHOT, "--device", u.ip, path], check=True,
                       capture_output=True, timeout=60)
        return Image.open(path).convert("RGB")

    def press(x, y, t=1.0):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        for data in (0x00, 0x80):                   # pressed, released
            u.write(0x8505, bytes([data]))
            u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
            time.sleep(0.4)
        time.sleep(t)

    def key(c, t=0.6):
        head = u.read(kern["qHead"], 1)[0]
        u.write(kern["keyQueue"] + head, bytes([c]))
        u.write(kern["qHead"], bytes([(head + 1) & 15]))
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x80]))
        time.sleep(t)

    def text(s):
        for ch in s:
            key(ord(ch), t=0.5)

    f = ftplib.FTP(u.ip, timeout=60)
    f.login()
    hib = io.BytesIO()
    try:
        f.retrbinary("RETR " + HOME + "HIBERNAT.BIN", hib.write)
        f.delete(HOME + "HIBERNAT.BIN")
        hib = hib.getvalue()
    except ftplib.error_perm:
        hib = None
    image = io.BytesIO()                            # drive C's test copy, kept
    f.retrbinary("RETR " + C_IMAGE, image.write)
    image = image.getvalue()
    f.quit()
    deleted = False
    try:
        u.boot(crt)
        time.sleep(20)
        x, a, regs = u.fe(FE_TASK, y=2, s0=APP)     # "open in new task": the
        check("FE_TASK: a new task opens it", x, 0)    # desktop's own Open
        time.sleep(25)
        check("GeoLudo running (its name as the task's)",
              u.read(kern["taskName"], 7), b"GeoLudo")
        shot("title")
        press(44, 6, 2)                             # Game > (Re)Start
        press(20, 17, 3)
        key(KEY_DELETE)
        key(ord("4"))
        key(CR, 3)
        for _ in range(4):                          # default names
            key(CR, 2)
        time.sleep(13)
        press(300, 190, 2)                          # (menus closed)
        start = shot("start")
        press(68, 6, 2)                             # File > Save
        press(40, 17, 3)
        text(SAVE_NAME)
        shot("name")
        key(CR, 10)
        press(300, 190, 2)
        for _ in range(6):                          # six throws
            press(223, 157, 6)
        played = shot("played")
        press(68, 6, 2)                             # File > Load, Open
        press(12, 17, 5)
        shot("list")
        press(100, 58, 2)                           # the save (".." is first)
        press(222, 63, 12)
        loaded = shot("loaded")
        w, h = start.size
        board = (0, 60, w, h)                       # below the menu bar
        check("six throws: the screen changed", ImageChops.difference(
            start.crop(board), played.crop(board)).getbbox() is not None, True)
        check("loaded: the screen as saved", ImageChops.difference(
            start.crop(board), loaded.crop(board)).getbbox(), None)
        u.boot()                                    # (the desktop again)
        time.sleep(20)
        x, a, regs = u.fe(FE_DELETE, s0="/c/Games/" + SAVE_FILE)
        check("the save deleted again", x, 0)
        deleted = x == 0
    finally:
        if not deleted:                             # (the image as it was, mounted
            f = ftplib.FTP(u.ip, timeout=60)        # anew by a reboot)
            f.login()
            f.storbinary("STOR " + C_IMAGE, io.BytesIO(image))
            f.quit()
            u.boot()
            print("drive C's image put back as it was")
        if hib is not None:
            f = ftplib.FTP(u.ip, timeout=60)
            f.login()
            f.storbinary("STOR " + HOME + "HIBERNAT.BIN", io.BytesIO(hib))
            f.quit()
    print("geoludou64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
