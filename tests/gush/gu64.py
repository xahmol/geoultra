#!/usr/bin/env python3
"""gush on the Ultimate 64 (docs/GUSH.md, "Tests").

Before the reboot gush (and geoFolder) are written onto drive A's test
copy (/USB0/GEOULTRA/test/GEOS64.D81, by FTP and VICE's c1541; never the
user's own image), then GeoUltra boots from the U64's flash with the
cartridge given, gush starts from drive A (GetFile through appMain), and
its commands run on the Ultimate's file system in
/USB0/GEOULTRA/test/gush (made and removed by the test): ls, cd, pwd,
mkdir, cp both ways (asked before overwriting), mv, rm, cat, wildcards,
long names, cp -r both ways; then a desk accessory (geoFolder) started
and closed, gush's screen back, and its gush button (a fresh gush).
Usage: tests/gush/gu64.py [build/geoultra64.crt]
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, HERE)
from feu64 import U64  # noqa: E402
from gushvice import labels, COLS, ROWS_TEXT, C1541, OUT  # noqa: E402

KEY_STUB = 0xC0A0
IMAGE = "/USB0/GEOULTRA/test/GEOS64.D81"
HOME = "/usb0/geoultra/test/gush"


class GushU64:
    def __init__(self, crt):
        self.u = U64()
        self.ok = True
        self.lbl = labels()
        os.makedirs(OUT, exist_ok=True)
        # Old copies out through GeoUltra itself (c1541's -delete does not
        # match GEOS's lower-case names), written back; then the new ones
        # added to the image and the U64 booted with it.
        self.settle()
        self.u.boot(crt)
        for name in ("/a/gush", "/a/geoFolder"):
            while self.u.fe(7, s0=name)[0] == 0:            # FE_DELETE
                pass
        time.sleep(4)
        self.settle()
        local = os.path.join(OUT, "u64-a.d81")
        self.u.ftp_get(IMAGE, local)
        subprocess.run([C1541, "-attach", local,
                        "-geoswrite", os.path.join(ROOT, "build", "gush", "gush.cvt"),
                        "-geoswrite", os.path.join(ROOT, "build", "tools", "geofolder.cvt")],
                       capture_output=True, check=True)
        self.u.ftp_put(local, IMAGE)
        self.u.boot(crt)

    def settle(self):
        """Wait until the running session has written its drives back
        (wbPending 0 three times in a row; a write-back runs a few seconds
        after the last write). A reset would not do: the cold start keeps
        a drive with unsaved changes in the REU and writes it back later."""
        k = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            p = line.split()
            k[p[2].lstrip(".")] = int(p[1], 16)
        clean, end = 0, time.time() + 120
        while clean < 3 and time.time() < end:
            clean = clean + 1 if self.u.read(k["wbPending"], 1)[0] == 0 else 0
            time.sleep(2)

    def start(self):
        """gush from drive A: SetDevice, OpenDisk, GetFile through appMain."""
        jt = {"SetDevice": 0xC2B0, "OpenDisk": 0xC2A1, "GetFile": 0xC208}
        name = 0x5100
        code = [0xA9, 0x00, 0x8D, 0x9B, 0x84, 0x8D, 0x9C, 0x84,      # appMain off
                0xA9, 0x08, 0x20] + [jt["SetDevice"] & 0xFF, jt["SetDevice"] >> 8]
        code += [0x20, jt["OpenDisk"] & 0xFF, jt["OpenDisk"] >> 8]
        code += [0xA9, name & 0xFF, 0x85, 0x0E, 0xA9, name >> 8, 0x85, 0x0F, 0xA9, 0x00, 0x85, 0x02]
        code += [0x20, jt["GetFile"] & 0xFF, jt["GetFile"] >> 8, 0x60]
        self.u.write(name, b"gush\0")
        self.u.write(0x5000, bytes(code))
        self.u.write(0x849B, b"\x00\x50")
        time.sleep(6)

    def keys(self, text, settle=0.4):
        u = self.u
        for c in ([ord(ch) for ch in text] if isinstance(text, str) else text):
            end = time.time() + 60          # the previous key taken first
            while True:
                old = u.read(0x849B, 2)
                if (old[0] | old[1] << 8) != KEY_STUB or time.time() > end:
                    break
                time.sleep(0.2)
            stub = [0xA9, c, 0x8D, 0x04, 0x85, 0xA9, old[0], 0x8D, 0x9B, 0x84,
                    0xA9, old[1], 0x8D, 0x9C, 0x84, 0x6C, 0xA3, 0x84]
            u.write(KEY_STUB, bytes(stub))
            u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            time.sleep(settle)

    def queue(self, text, settle=1.5):
        k = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            p = line.split()
            k[p[2].lstrip(".")] = int(p[1], 16)
        for c in text:
            head = self.u.read(k["qHead"], 1)[0]
            self.u.write(k["keyQueue"] + head, [ord(c)])
            self.u.write(k["qHead"], [(head + 1) & 15])
            self.u.write(0x39, [self.u.read(0x39, 1)[0] | 0x80])
            time.sleep(0.4)
        time.sleep(settle)

    def run(self, line, settle=2.0):
        self.keys(line + "\r")
        time.sleep(settle)

    def lines(self):
        s = self.lbl["shadow"]
        data = self.u.read(s, COLS * ROWS_TEXT)
        rows = [data[r * COLS:(r + 1) * COLS].decode("latin1").rstrip() for r in range(ROWS_TEXT)]
        while rows and not rows[-1]:
            rows.pop()
        return rows

    def out(self, line, settle=2.0):
        """The line before the next prompt, after running LINE."""
        self.run(line, settle)
        return self.lines()[-2]

    def check(self, title, got, want):
        good = got == want
        self.ok = self.ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else None
    g = GushU64(crt)
    check, out = g.check, g.out
    g.start()
    rows = g.lines()
    check("gush started on the U64", rows[0].startswith("gush, the GeoUltra shell") if rows else rows, True)
    g.run("rm -f /a/INI '/a/A long name for the copy on the stick'")   # (left over)
    g.run("rm -f %s/*" % HOME)
    g.run("rmdir " + HOME)
    check("mkdir on the Ultimate", out("mkdir " + HOME), "$ mkdir " + HOME)
    g.run("cd " + HOME)
    check("cd, pwd", out("pwd"), HOME)
    g.run("cp /usb0/geoultra/MOUNTS.INI /a/INI")    # (the user's file only read)
    check("cp from the stick onto drive A, cat", out("cat /a/INI", settle=3).startswith("B="), True)
    g.run("cp /a/INI ini.txt")
    check("cp back onto the stick, ls", out("ls"), "ini.txt")
    g.run("cp /a/INI ini.txt", settle=3)
    check("cp onto a file asks", g.lines()[-1], "gush: cp: overwrite /a/INI? (y/n/a)")
    g.queue("n")
    g.run("cp /a/INI 'A long name for the copy on the stick'")
    g.run("ls")
    check("a long name on the Ultimate", sorted(g.lines()[-2].split("  ")),
          ["A long name for the copy on the stick", "ini.txt"])
    g.run("cp 'A long name for the copy on the stick' /a/", settle=4)
    check("back onto drive A with its long name", out("ls /a/A\\ long\\ name*"),
          "/a/A long name for the copy on the stick")
    g.run("cp /a/GEOS .", settle=4)                  # CVT, and -R raw
    check("cp of a GEOS file onto the Ultimate: a .cvt", out("ls GEOS*"), "GEOS.cvt")
    g.run("cp -R /a/GEOS geos.raw", settle=4)
    check("cp -R: raw, no .cvt", out("ls *.raw"), "geos.raw")
    g.run("rm -f GEOS.cvt geos.raw")
    g.run("mkdir -t 3 /a/TREE")                      # cp -r both ways
    g.run("cp /a/INI /a/TREE")
    g.run("cp -r /a/TREE .", settle=4)
    check("cp -r a 1581 partition onto the Ultimate", out("ls TREE"), "INI")
    g.run("cp -r TREE /a/TREE2", settle=4)
    check("cp -r an Ultimate folder onto drive A", out("ls /a/TREE2"), "INI")
    g.run("rm -f /a/TREE/* /a/TREE2/* TREE/*")
    g.run("rmdir /a/TREE /a/TREE2 TREE")
    g.run("rm -f '/a/A long name for the copy on the stick' /a/INI")
    g.run("mv ini.txt moved")
    check("mv on the Ultimate", out("ls m*"), "moved")
    g.run("rm -f *")
    g.run("cd /")
    g.run("rmdir " + HOME)
    g.run("ls /usb0/geoultra/test/gu*")
    check("cleaned up", "".join(g.lines()[-3:-1]).endswith("no such file or folder"), True)
    g.run("cd /a")
    g.run("geoFolder", settle=4)
    # geoFolder's dialog: OK (a click on its icon, at 224,90) closes it;
    # gush redraws its screen.
    u = g.u
    u.write(0x3A, bytes([224, 0, 90]))                # the pointer onto OK
    time.sleep(0.5)
    u.write(0x8505, b"\x00")                          # pressed, released
    u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
    time.sleep(1)
    u.write(0x8505, b"\x80")
    u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
    time.sleep(3)
    check("after geoFolder: gush's prompt again", g.lines()[-1], "$")
    g.run("geoFolder /a/INI")                        # (in VICE no DA by name)
    check("a desk accessory with a document", "".join(g.lines()[-3:-1]),   # (two lines)
          "gush: geoFolder: /a/INI: a desk accessory takes no document")
    g.run("geoFolder", settle=4)                     # its gush button
    u.write(0x3A, bytes([224, 0, 78]))
    time.sleep(0.5)
    for data in (b"\x00", b"\x80"):
        u.write(0x8505, data)
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(1)
    time.sleep(4)
    rows = g.lines()
    check("geoFolder's gush button: a fresh gush", (rows[0].startswith("gush, the GeoUltra shell") if rows
                                                     else rows, rows[1:]), (True, ["$"]))
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
