#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: system fonts installed and uninstalled
(docs/design/DESIGN.md "System font folder", step F; fontact.s, ctxmenu.s,
list.s TaskOrMount). MOUNTS.INI for the test: A and B only (test copies:
GEOS64.D81, neos.d64), so C and D are free; no FONTS.DNP. In /b, the
cursor on Roma, item 1 of the context menu (FontAct): FONTS.DNP made and
Roma in it (read back from the stick); "Restart now?" YES: the session
resumed (the desktop in /b again), now with /f listing Roma. In /f, the
cursor on Roma, FontAct again (uninstall), NO to the restart: Roma gone
from FONTS.DNP. The user's MOUNTS.INI, SETTINGS.INI, RECENT.INI,
HIBERNAT.BIN, FONTS.DNP and gush_history are set aside and put back as
they were. Screens: build/harness/gush/d32u64-*.png.
Usage: tests/desktop/d32u64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
from feu64 import U64  # noqa: E402
import apprun  # noqa: E402

HOME = "/USB0/GEOULTRA/"
MOUNTS = b"[drives]\r\nA=/USB0/GEOULTRA/test/GEOS64.D81\r\nB=/USB0/GEOULTRA/test/neos.d64\r\n"
KEY_STUB = 0xC0A0
DLG_X, DLG_Y = 64, 32
OUT = os.path.join(ROOT, "build", "harness", "gush")
KEEP = ("MOUNTS.INI", "SETTINGS.INI", "RECENT.INI", "HIBERNAT.BIN", "FONTS.DNP", "gush_history")


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    u = U64()
    ok = True
    os.makedirs(OUT, exist_ok=True)

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)),
              flush=True)

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

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "d32u64-%s.png" % name))

    def press(x, y, s=6):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(s)

    def call(routine, a=0, x=0, s=6):
        """routine from appMain (A, X), ClockTick's stand-in once."""
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0xA9, a, 0xA2, x, 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def word(name):
        return int.from_bytes(bytes(u.read(k[name], 2)), "little")

    def names():
        out = []
        for i in range(word("count")):
            call(k["Fetch"], i & 0xFF, i >> 8, s=0.7)
            out.append(bytes(u.read(k["entryName"], 17)).split(b"\0")[0].decode("latin1"))
        return out

    def path():
        return bytes(u.read(k["path"], 32)).split(b"\0")[0].decode("latin1")

    def into(p):
        u.write(0x4F00, p.encode() + b"\0")
        call(k["Into"], 0x00, 0x4F, s=8)

    def stored():
        data = get(HOME + "FONTS.DNP")
        if data is None:
            return None
        local = os.path.join(OUT, "d32-FONTS.DNP")
        open(local, "wb").write(data)
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "geosdisk.py"), "list", local],
                           capture_output=True, text=True)
        return [l.split()[1] for l in r.stdout.splitlines()
                if len(l.split()) > 2 and l.split()[0].isdigit() and "blocks free" not in l]

    kept = {n: get(HOME + n) for n in KEEP}
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(HOME + "FONTS.DNP", None)
        put(HOME + "MOUNTS.INI", MOUNTS)
        u.boot(crt)
        time.sleep(20)
        into("/b")
        lst = names()
        check("in /b, Roma there", (path(), "Roma" in lst), ("/b", True))
        u.write(k["cur"], bytes([lst.index("Roma"), 0]))
        call(k["TaskOrMount"], s=25)                        # install (item 1)
        shot("asked")
        check("FONTS.DNP made, Roma in it", stored(), ["Roma"])
        press(DLG_X + 8 + 20, DLG_Y + 72 + 8, 60)           # YES: restarted, the session kept
        time.sleep(20)
        shot("resumed")
        check("the session resumed: the desktop in /b", path(), "/b")
        into("/f")
        lst = names()
        check("/f lists Roma", (path(), "Roma" in lst), ("/f", True))
        u.write(k["cur"], bytes([lst.index("Roma") if "Roma" in lst else 0, 0]))
        call(k["TaskOrMount"], s=25)                        # uninstall (item 1)
        shot("asked2")
        press(DLG_X + 17 * 8 + 20, DLG_Y + 72 + 8, 8)       # NO
        check("uninstalled: Roma out of FONTS.DNP", stored(), [])
    finally:
        for n, d in kept.items():
            put(HOME + n, d)
        back = all(get(HOME + n) == d for n, d in kept.items())
        check("the user's files back as they were", back, True)
    print("d32u64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
