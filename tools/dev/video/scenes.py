#!/usr/bin/env python3
"""GeoUltra's first-look video: the scenes, driven by the autopilot
(pilot.py) on the U64 (docs/design/DESIGN.md, Beta 1; the user chose the
scenes 2026-11-13: boot and desktop views, two panes and drag and drop,
geoWrite from a folder, gush and Settings).

  scenes.py dry OUTDIR      every step, a screenshot after each (a contact
                            sheet OUTDIR/sheet.png to check the places)
  scenes.py rec OUTDIR      the take: the VIC stream recorded to
                            OUTDIR/take.pkts, the steps logged to
                            OUTDIR/events.json (for the edit)

The user's SETTINGS.INI, RECENT.INI and HIBERNAT.BIN are kept first and
put back byte for byte at the end. Own code.
"""
import ftplib
import io
import json
import os
import struct
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import localcfg  # noqa: E402
sys.path.insert(0, os.path.join(localcfg.GEOUTOOLS, "tests", "e2e"))
import pilot  # noqa: E402
from ultimate import Ultimate  # noqa: E402
import png  # noqa: E402

IP = localcfg.get("ULTIP1", "192.168.1.64")   # the Ultimate (.env)
STREAM_PORT = 11002             # (11000 is OBS's on the Windows side: WSL shares
                                # ports; the firewall rule allows 11000-11010)
HOME = "/USB0/GEOULTRA/"
PALETTE = [(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x81, 0x33, 0x38), (0x75, 0xCE, 0xC8),
           (0x8E, 0x3C, 0x97), (0x56, 0xAC, 0x4D), (0x2E, 0x2C, 0x9B), (0xED, 0xF1, 0x71),
           (0x8E, 0x50, 0x29), (0x55, 0x38, 0x00), (0xC4, 0x6C, 0x71), (0x4A, 0x4A, 0x4A),
           (0x7B, 0x7B, 0x7B), (0xA9, 0xFF, 0x9F), (0x70, 0x6D, 0xEB), (0xB2, 0xB2, 0xB2)]
# The desktop (default theme, two-line toolbar): the toolbar's buttons
TB_Y = 23
TB_VIEW, TB_PANES, TB_SETTINGS, TB_GUSH = 127, 143, 288, 304
MENU_GEOS, MENU_VIEW = (12, 5), (75, 5)
PATH_Y = 39                     # the path line's baseline on the U64 (letters at
                                # rows 33-39; measured from a dry run's frame)
ROW0_Y = 47                     # the list's first row
ROW_H = 9
GW_FILE = 38                    # geoWrite's file menu; its quit (7th item)
GW_QUIT_Y = 15 + 6 * 14 + 7
SIDE_TOP, SIDE_ROW = 20, 14     # Settings (tests/settings/s2.py, s4.py)
THEME_Y, PART_Y, STYLE_Y = 36, 54, 72
START_INI = b"[desktop]\r\ntheme=GeoUltra\r\nview=list\r\n"


class Take:
    def __init__(self, out, mode):
        self.out, self.mode = out, mode
        os.makedirs(out, exist_ok=True)
        self.u = Ultimate(IP)
        self.p = pilot.Pilot(pilot.U64(self.u))
        self.t0 = time.monotonic()
        self.events, self.shots = [], []
        self.stop = False

    def ev(self, kind, **kw):
        e = dict(t=round(time.monotonic() - self.t0, 3), kind=kind, **kw)
        self.events.append(e)
        print(e, flush=True)

    def mark(self, name):
        """A scene or step boundary: logged; in a dry run, a screenshot."""
        self.ev("mark", name=name)
        if self.mode == "dry":
            for attempt in range(2):            # (the REST interface stalls
                try:                            # at times: once more, then on
                    with self.u.video_stream(STREAM_PORT) as st:    # without it)
                        frame = st.frames(1)[0]
                    break
                except Exception as e:
                    print("screenshot failed:", e)
                    time.sleep(5)
            else:
                return
            path = os.path.join(self.out, "%02d-%s.png" % (len(self.shots), name))
            png.write(path, frame, PALETTE)
            self.shots.append((name, path))

    # --- files on the Ultimate
    def ftp(self):
        f = ftplib.FTP(IP)
        f.login()
        return f

    def get(self, name):
        out = io.BytesIO()
        try:
            f = self.ftp()
            f.retrbinary("RETR " + HOME + name, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

    def put(self, name, data):
        f = self.ftp()
        if data is None:
            try:
                f.delete(HOME + name)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + HOME + name, io.BytesIO(data))
        f.quit()

    # --- the recording
    def capture(self, st):
        f = open(os.path.join(self.out, "take.pkts"), "wb")
        st.sock.settimeout(0.5)
        while not self.stop:
            try:
                data, addr = st.sock.recvfrom(2048)
            except OSError:
                continue
            if addr[0] != st.source:
                continue
            f.write(struct.pack("<dH", time.monotonic() - self.t0, len(data)) + data)
        f.close()

    def sheet(self):
        from PIL import Image, ImageDraw
        imgs = [(n, Image.open(p)) for n, p in self.shots]
        if not imgs:
            return
        w, h = imgs[0][1].size
        cols = 4
        rows = (len(imgs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * w, rows * (h + 14)), "white")
        d = ImageDraw.Draw(sheet)
        for i, (n, im) in enumerate(imgs):
            x, y = (i % cols) * w, (i // cols) * (h + 14)
            sheet.paste(im.convert("RGB"), (x, y + 14))
            d.text((x + 4, y), "%02d %s" % (i, n), fill="black")
        sheet.save(os.path.join(self.out, "sheet.png"))


def remove(f, path):
    """A file (only .cvt) or a folder with everything in it, over FTP."""
    try:
        f.cwd(path)
    except ftplib.error_perm:
        if path.lower().endswith(".cvt"):
            f.delete(path)
        return
    f.cwd("/")
    for n in f.nlst(path):
        remove(f, n if n.startswith("/") else path + "/" + n)
    f.rmd(path)


def scenes(t):
    p = t.p
    # 1. boot and the desktop's views
    t.ev("scene", name="boot")
    f = t.ftp()                                  # the build under test (the
    f.storbinary("STOR /Flash/carts/geoultra64.crt",   # flash holds the last
                 open(os.path.join(ROOT, "build", "geoultra64.crt"), "rb"))  # test's)
    f.quit()
    t.u._json("PUT", "/v1/machine:reboot")
    time.sleep(22)
    p.install()
    t.mark("desktop")
    p.click(TB_VIEW, TB_Y)                       # icons
    time.sleep(2)
    t.mark("icons")
    p.click(TB_VIEW, TB_Y)                       # detailed
    time.sleep(2)
    t.mark("detailed")
    p.click(TB_VIEW, TB_Y)                       # list again
    time.sleep(1)
    p.click(*MENU_VIEW)                          # the view menu (themes)
    time.sleep(1)
    t.mark("viewmenu")
    p.glide(160, 120)
    p.press(); p.release()                       # (closes it)
    time.sleep(1)
    # 2. two panes
    t.ev("scene", name="panes")
    p.click(TB_PANES, TB_Y)
    time.sleep(3)
    t.mark("panes")
    p.click(314, PATH_Y - 3)                     # U in the right pane (x 312-315)
    time.sleep(2)
    t.mark("roots")
    p.click(296, PATH_Y + 8)                     # its first root (usb0)
    time.sleep(4)
    t.mark("root")
    p.click(135, PATH_Y - 3)                     # C in the left pane (A B C E U)
    time.sleep(4)
    t.mark("leftc")
    y = ROW0_Y + 14 * ROW_H                      # "alarm clock" in C (row 0 "..",
    p.drag(60, y, 240, ROW0_Y + 3 * ROW_H)       # 1-12 folders): to usb0 as .cvt
    time.sleep(6)
    t.mark("dragged")
    # 3. geoWrite from the geos menu's GU Folder, and gush
    t.ev("scene", name="geowrite")
    p.double(60, ROW0_Y + 12 * ROW_H)            # C's folder Writing
    time.sleep(4)
    t.mark("folder")
    p.double(60, ROW0_Y + 10 * ROW_H)            # GEOWRITE in it
    time.sleep(14)
    p.install()                                  # (geoWrite's start reset the hook)
    t.mark("geowrite")
    p.click(102, 86)                             # its Open
    time.sleep(4)
    p.install()                                  # (every dialog box resets the
    t.mark("open")                               # vectors too: DoDlgBox)
    p.click(75, 116)                             # the drive letter A (MegaPatch's)
    time.sleep(6)
    p.install()
    t.mark("open-a")
    p.double(90, 46)                             # "ReadMe 1581" on A: opened
    time.sleep(10)                               # (read only: nothing written)
    p.install()
    t.mark("document")
    p.glide(200, 150)
    time.sleep(3)
    p.click(GW_FILE, 5)                          # geoWrite's file menu
    time.sleep(1)
    t.mark("gwfile")
    p.click(GW_FILE + 10, GW_QUIT_Y)             # quit
    time.sleep(14)
    p.install()
    t.mark("back")
    t.ev("scene", name="geos")
    p.click(*MENU_GEOS)
    time.sleep(1)
    t.mark("geosmenu")
    p.glide(160, 120)
    p.press(); p.release()
    time.sleep(1)
    # 4. gush
    t.ev("scene", name="gush")
    p.click(TB_GUSH, TB_Y)
    time.sleep(8)
    p.install()                                  # (a program's start resets
    t.mark("gush")                               # GEOS's vectors: hooked again)
    for line, wait in (("ls /usb0", 3), ("ifconfig", 4),              # (the user: commands,
                       ("for D in a b c; do ls /$D; done", 5),     # scripting, ifconfig)
                       ("if test -d /usb0; then echo the Ultimate is there; fi", 3)):
        p.type(line + "\r")
        time.sleep(wait)
        t.mark("gush-" + line.split()[0])
    p.click(308, 3)                              # its close button
    time.sleep(10)
    p.install()
    # 5. Settings
    t.ev("scene", name="settings")
    p.click(TB_SETTINGS, TB_Y)
    time.sleep(8)
    p.install()
    t.mark("settings")
    p.click(20, SIDE_TOP + 0 * SIDE_ROW + 7)     # the Theme page
    time.sleep(4)
    t.mark("theme")
    for _ in range(2):                           # the next themes in the preview
        p.click(242, THEME_Y - 3)
        time.sleep(3)
    t.mark("theme-next")
    p.click(286, PART_Y - 3)                     # the palette part
    time.sleep(3)
    p.click(152 + 6 * 8 + 3, 99)                 # blue
    for _ in range(6):                           # R + : the colour changes live
        p.click(165, STYLE_Y - 3, after=0.4)
    t.mark("palette")
    p.click(20, SIDE_TOP + 6 * SIDE_ROW + 7)     # the Pointer page
    time.sleep(4)
    for x in (100 + 2 * 56 + 3, 100 + 3 * 56 + 3, 100 + 3):   # hand, cross, classic
        p.click(x, 33, after=2.5)
        t.mark("pointer")
    p.click(20, SIDE_TOP + 3 * SIDE_ROW + 7)     # the Time page
    time.sleep(4)
    p.click(200, 33)                             # the server list
    time.sleep(2)
    t.mark("time-list")
    p.click(200, 170)                            # (closed: a click outside)
    time.sleep(2)
    p.click(240, 188)                            # Cancel
    time.sleep(2)
    p.install()                                  # (its question: a dialog)
    t.mark("leave")
    p.click(90, 110)                             # Yes: nothing saved
    time.sleep(14)
    p.install()
    t.mark("end")


def main():
    mode, out = sys.argv[1], sys.argv[2]
    t = Take(out, mode)
    keep = {n: t.get(n) for n in ("SETTINGS.INI", "RECENT.INI", "HIBERNAT.BIN")}
    f = t.ftp()
    usb0 = set(f.nlst("/USB0"))                  # (the drag's copy taken away after)
    f.quit()
    cap = None
    try:
        t.put("HIBERNAT.BIN", None)
        t.put("SETTINGS.INI", START_INI)
        if mode == "rec":
            st = t.u.video_stream(STREAM_PORT).__enter__()
            cap = threading.Thread(target=t.capture, args=(st,))
            cap.start()
        scenes(t)
    finally:
        t.stop = True
        if cap:
            cap.join()
        for n, d in keep.items():
            t.put(n, d)
        f = t.ftp()
        for n in set(f.nlst("/USB0")) - usb0:   # (only what the take made: new
            print("removed from usb0:", n)      # entries, files only .cvt)
            remove(f, n if n.startswith("/") else "/USB0/" + n)
        f.quit()
        json.dump(t.events, open(os.path.join(out, "events.json"), "w"), indent=1)
        t.sheet()
        print("files back:", all(t.get(n) == d for n, d in keep.items()))


if __name__ == "__main__":
    main()
