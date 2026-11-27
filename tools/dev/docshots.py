#!/usr/bin/env python3
"""Screenshots for the README and the user manual, taken on the U64.

    tools/dev/docshots.py [NAME ...]

Boots build/geoultra64.crt on the Ultimate in .env (ULTIP1) with a demo
state on the stick: GEOULTRA/demo holds the samples D81 (drive A), a demo
DNP with folders (drive B) and an empty D64 to mount; SETTINGS.INI,
RECENT.INI and MOUNTS.INI are the demo's. The user's own files
(MOUNTS.INI, SETTINGS.INI, RECENT.INI, HIBERNAT.BIN, gush_history) are
put back afterwards and the demo folder removed. Each shot is one frame
of the VIC video stream (exact pixels, the pointer included), cropped to
the 320x200 screen, every pixel doubled (640x400), in the U64's palette:
docs/images/<name>.png. With
NAMEs only those are written (the walk is the same). Needs
`make samples` first (the samples D81 and CVTs).

The desktop is driven as in the U64 tests: routines called through a
one-shot appMain stub (as samples/shots.py in VICE), keys through
keyVector (tests/desktop/du64.py), clicks through mouseData/pressFlag.
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
import localcfg  # noqa: E402
from feu64 import U64  # noqa: E402
sys.path.insert(0, os.path.join(localcfg.GEOUTOOLS, "tests", "e2e"))
from ultimate import Ultimate  # noqa: E402

HOME = "/USB0/GEOULTRA/"
DEMO = HOME + "demo/"
OUT = os.path.join(ROOT, "docs", "images")
BUILD = os.path.join(ROOT, "build", "docshots")
KEEP = ("MOUNTS.INI", "SETTINGS.INI", "RECENT.INI", "HIBERNAT.BIN", "gush_history")
STREAM_PORT = 11002
SCREEN = (32, 35)               # the 320x200 screen in the stream's 384x272 frame
U64_PAL = [(0x00, 0x00, 0x00), (0xF7, 0xF7, 0xF7), (0x8D, 0x2F, 0x34), (0x6A, 0xD4, 0xCD),
           (0x98, 0x35, 0xA4), (0x4C, 0xB4, 0x42), (0x2C, 0x29, 0xB1), (0xEF, 0xEF, 0x5D),
           (0x98, 0x4E, 0x20), (0x5B, 0x38, 0x00), (0xD1, 0x67, 0x6D), (0x4A, 0x4A, 0x4A),
           (0x7B, 0x7B, 0x7B), (0x9F, 0xEF, 0x93), (0x6D, 0x6A, 0xEF), (0xB2, 0xB2, 0xB2)]
KEY_STUB = 0xC0A0
KEY_DOWN, KEY_HOME, CR = 17, 18, 13
DLG_X, DLG_Y = 64, 32           # DEF_DB_POS's top left
VIEW_LIST, VIEW_ICONS = 0, 1
SIDE_TOP, SIDE_ROW = 16, 16     # Settings' side list (src/settings/settings.inc)
PAGE_THEME, PAGE_PRINTING, PAGE_SERIALS = 0, 8, 9
INI = (b"[desktop]\r\ntheme=GeoUltra\r\nview=list\r\n\r\n"
       b"[favourites]\r\n/usb0/geoultra/demo\r\n")
RECENT = b"[recent]\r\n/a/Brochure\r\n/a/Quick start\r\n"
MOUNTS = ("[drives]\r\nA=" + DEMO + "samples.d81\r\nB=" + DEMO + "demo.dnp\r\n").encode()


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def demo_files():
    """build/docshots: demo.dnp (Documents, Pictures from the samples'
    CVTs) and extra.d64 (empty, to mount)."""
    os.makedirs(BUILD, exist_ok=True)
    cvt = os.path.join(ROOT, "build", "samples", "cvt")
    toml = os.path.join(BUILD, "demo.toml")
    open(toml, "w").write(
        '[dnp]\nout = "demo.dnp"\nname = "Demo"\nid = "DM"\ntracks = 8\nstrict = true\n\n'
        '[sources]\ns = "%s"\n\n[[folder]]\npath = "Documents"\n'
        'files = ["s:Brochure.cvt", "s:Letter.cvt", "s:Quick start.cvt"]\n\n'
        '[[folder]]\npath = "Pictures"\nfiles = ["s:GeoUltra logo.cvt"]\n' % cvt)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml], cwd=BUILD,
                   check=True, capture_output=True)
    extra = os.path.join(BUILD, "extra.d64")
    if os.path.exists(extra):
        os.remove(extra)
    subprocess.run([localcfg.C1541, "-format", "extra,ex", "d64", extra], check=True, capture_output=True)
    return {"samples.d81": os.path.join(ROOT, "build", "samples", "geoultra-samples.d81"),
            "demo.dnp": os.path.join(BUILD, "demo.dnp"), "extra.d64": extra}


def main():
    want = set(sys.argv[1:])
    files = demo_files()
    import png
    u = U64()
    ult = Ultimate(u.ip)
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    os.makedirs(OUT, exist_ok=True)

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def get(path):
        b = io.BytesIO()
        f = ftp()
        try:
            f.retrbinary("RETR " + path, b.write)
        except ftplib.error_perm:
            return None
        finally:
            f.quit()
        return b.getvalue()

    def put(path, data):
        f = ftp()
        if data is None:
            try:
                f.delete(path)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + path, io.BytesIO(data))
        f.quit()

    def shot(name, pointer=None, crop=None):
        if pointer:                                     # the pointer out of the way
            u.write(0x3A, bytes([pointer[0] & 0xFF, pointer[0] >> 8, pointer[1]]))
            time.sleep(0.5)
        print("shot", name, flush=True)
        if want and name not in want:
            return
        for attempt in range(3):
            try:
                with ult.video_stream(STREAM_PORT) as st:
                    frame = st.frames(1)[0]
                break
            except Exception as e:                      # (the REST side stalls at times)
                print("  frame failed:", e)
                time.sleep(5)
        else:
            return
        x0, y0 = SCREEN                                 # the screen, every pixel
        cx0, cy0, cx1, cy1 = crop or (0, 0, 320, 200)   # (a part: C64 coordinates)
        cx1, cy1 = min(cx1, 320), min(cy1, 200)
        rows = [[c for c in row[x0 + cx0:x0 + cx1] for _ in (0, 1)]  # doubled (sharp
                for row in frame[y0 + cy0:y0 + cy1] for _ in (0, 1)]   # in the PDF)
        path = os.path.join(OUT, name + ".png")
        png.write(path, rows, U64_PAL)
        from PIL import Image                           # 144 dpi: the PDFs print
        Image.open(path).save(path, dpi=(144, 144))     # it at about 70% width

    def call(routine, a=0, x=0, s=4):
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                 0x84, 0xA9, a, 0xA2, x, 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def press(x, y, s=4):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(s)

    def key(c, s=0.4):
        old = u.read(0x849B, 2)
        u.write(KEY_STUB, bytes([0xA9, c, 0x8D, 0x04, 0x85, 0xA9, old[0], 0x8D, 0x9B, 0x84,
                                 0xA9, old[1], 0x8D, 0x9C, 0x84, 0x6C, 0xA3, 0x84]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def typed(text, s=3):
        for ch in text:
            key(ord(ch))
        time.sleep(s)

    def side(code, s=5):
        n = u.read(k["sideCount"], 1)[0]
        letters = bytes(u.read(k["sideLetters"], n))
        top = u.read(k["sideTops"] + letters.index(bytes([code])), 1)[0]
        press(20, top + 4, s)

    def row_y(i):
        return u.read(k["listTop"], 1)[0] + i * u.read(k["rowH"], 1)[0] + 4

    kept = {n: get(HOME + n) for n in KEEP}
    f = ftp()
    try:
        f.mkd(DEMO)
    except ftplib.error_perm:
        pass
    for n, p in files.items():
        f.storbinary("STOR " + DEMO + n, open(p, "rb"))
    f.quit()
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(HOME + "SETTINGS.INI", INI)
        put(HOME + "RECENT.INI", RECENT)
        put(HOME + "MOUNTS.INI", MOUNTS)
        u.boot(os.path.join(ROOT, "build", "geoultra64.crt"))
        time.sleep(20)
        # --- the start, the Ultimate's files, mounting
        shot("start", pointer=(300, 190))
        side(0x80)                                      # the favourite: the demo folder
        shot("mount-icons", pointer=(300, 190))
        lr = u.read(k["listR"], 2)
        iconx = ((lr[0] | lr[1] << 8) >> 3) * 8 + 4
        press(iconx, row_y(2), 6)                       # extra.d64's mount icon (.., demo.dnp,
        shot("mount-dialog")                            # extra.d64, samples.d81)
        press(DLG_X + 8 + 20, DLG_Y + 20 + 3 * 18 + 8, 20)  # drive D
        shot("mounted", pointer=(300, 190))
        # --- the desktop on drive A: list, context menu, icons, two panes
        call(k["Drive"], ord("a"))
        shot("desktop-list", pointer=(250, 120))
        u.write(k["cur"], bytes([1, 0]))                # Brochure (after "..")
        u.write(0x3A, bytes([200, 0, row_y(1)]))
        call(k["Popup"], 0, s=3)
        shot("context-menu")
        press(250, 170, 2)                              # (closed: a click outside)
        # --- the menus, each cropped to it and some desktop around it
        # (the user, 2026-11-20); right edges and item counts from the tables
        # (desktop.s: GEOS_R 99, SYS_R 191, FILE_R 163, VIEW_R 129; 14 a row)
        def menu(name, title_x, right, items, sub=None):
            press(title_x, 5, 2)
            if sub:                                     # a submenu: its item
                press(sub[0], 14 + sub[1] * 14 + 7, 2)
            shot("menu-" + name, crop=(0, 0, right + 24, 14 + items * 14 + 16))
            press(250, 190, 2)                          # (closed)
        menu("geos", 12, 191, 8, sub=(30, 0))           # geos > GeoUltra
        menu("file", 38, 163, 13)
        menu("view", 66, 129, 6)
        menu("view-view", 66, 200, 6, sub=(80, 1))
        menu("view-theme", 66, 230, 10, sub=(80, 0))
        menu("go", 88, 180, 8)
        menu("clipboard", 120, 200, 3)
        call(k["Drive"], ord("e"))
        call(k["View"], VIEW_ICONS, s=8)
        shot("desktop-icons", pointer=(300, 190))
        call(k["View"], VIEW_LIST)
        call(k["Drive"], ord("b"))
        call(k["TwoPanes"], 0, s=8)
        call(k["PaneSwitch"], 0, s=4)
        call(k["Drive"], ord("a"))
        call(k["PaneSwitch"], 0, s=4)
        shot("two-panes", pointer=(300, 190))
        call(k["TwoPanes"], 0, s=20)                    # (one list: the desktop restarts)
        # --- gush
        call(k["Gush"], 0, s=10)
        for line in ("cd /b", "ls -l Documents", "df", "free", "date"):
            typed(line + "\r")
        shot("gush")
        typed("exit\r", s=12)
        # --- Settings
        call(k["Settings"], 0, s=10)
        shot("settings-desktop", pointer=(300, 190))
        press(20, SIDE_TOP + PAGE_THEME * SIDE_ROW + 7, 5)
        shot("settings-theme", pointer=(300, 190))
        press(20, SIDE_TOP + PAGE_PRINTING * SIDE_ROW + 7, 5)
        shot("settings-printing", pointer=(300, 190))
        press(20, SIDE_TOP + PAGE_SERIALS * SIDE_ROW + 7, 5)
        shot("settings-serials", pointer=(300, 190))
        press(190, 186, 14)                             # OK: back to the desktop
        # --- the task list
        u.write(kern["taskReq"], b"\x80")
        time.sleep(3)
        shot("task-list")
    finally:
        f = ftp()
        for n in files:
            try:
                f.delete(DEMO + n)
            except ftplib.error_perm:
                pass
        try:
            f.rmd(DEMO)
        except ftplib.error_perm:
            pass
        f.quit()
        u.stop()                                        # (GeoUltra off first: a
        for n, d in kept.items():                       # running one wrote its
            put(HOME + n, d)                            # own INIs after these)
        print("the user's files back:", all(get(HOME + n) == d for n, d in kept.items()))
        if kept.get("HIBERNAT.BIN"):
            u.boot()                                    # (resumes the user's session)


if __name__ == "__main__":
    main()
