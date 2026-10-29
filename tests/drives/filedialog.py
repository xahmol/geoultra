#!/usr/bin/env python3
"""Folders in an existing application's file dialog (DBGETFILES) in VICE.

Drive B is a copy of GEOS_NATIVE_DISK (default the user's own
~/geos-dev/u64-usb/ramapps.DNP with geoWrite 2.0, only read). A folder is
made with MakeDir (extension jump table), geoWrite is started and its
"Open" dialog shown: the first row must be "/GU folder"; RETURN enters it
(the list shows ".." only); DEL goes back (the folder row again). The
rows are read from fileTrScTab, where DBGETFILES keeps the names; the
screens are written to build/harness/filedialog-N.png.
Usage: tests/drives/filedialog.py
"""
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
SOURCE = os.environ.get("GEOS_NATIVE_DISK", os.path.expanduser("~/geos-dev/u64-usb/ramapps.DNP"))
TEST_DISK = os.path.join(ROOT, "build", "harness", "filedialog-test.dnp")
os.environ["GEOS_APPS_DISK"] = TEST_DISK
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

PORT = 6527
FILE_TAB = 0x8300                               # fileTrScTab: the list's names


def label(name):
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        if line.strip().endswith("." + name):
            return int(line.split()[1], 16)
    raise SystemExit("no label " + name)


def main():
    shutil.copyfile(SOURCE, TEST_DISK)
    apprun.APPS_DISK = TEST_DISK
    apprun.REU_IMAGE = apprun.REU_IMAGE.replace("reu-apps", "reu-filedialog")
    apprun.reu_image()
    make_dir = label("ExtTable") + 20
    cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
           "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
           "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
           "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "+reuimagerw"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = Vice(port=PORT)
    t = harness.jumptab()

    def jsr(name):
        a = t[name]
        return [0x20, a & 0xFF, a >> 8]

    def wait(s):
        v.resume()
        time.sleep(s)
        v.ping()

    def key(c):
        old = v.mem_get(0x849B, 0x849C)
        stub = [0xA9, c, 0x8D, 0x04, 0x85, 0xA9, old[0], 0x8D, 0x9B, 0x84,
                0xA9, old[1], 0x8D, 0x9C, 0x84, 0x6C, 0xA3, 0x84]
        v.mem_set(apprun.KEY_STUB, bytes(stub))
        v.mem_set(0x849B, bytes([apprun.KEY_STUB & 0xFF, apprun.KEY_STUB >> 8]))
        wait(4)

    def click(x, y):
        for button in (0x00, 0x80):
            v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
            v.mem_set(0x8505, bytes([button]))
            v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x60]))
            wait(0.5)

    def rows():
        tab = v.mem_get(FILE_TAB, FILE_TAB + 16 * 17)
        return [bytes(tab[i * 17:i * 17 + 17]).split(b"\0")[0].decode("latin1") for i in range(3)]

    ok = True

    def check(n, title, good, detail):
        nonlocal ok
        ok = ok and good
        apprun.render(v.mem_get(0xA000, 0xBF3F), v.mem_get(0x8C00, 0x8FE7),
                      os.path.join(harness.OUT, "filedialog-%d.png" % n))
        print("%s %s: %s" % ("pass" if good else "FAIL", title, detail))

    try:
        wait(5)
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
                + [0xA9, 0x40, 0x85, 0x02, 0xA9, 0x4F, 0x85, 0x03,
                   0x20, make_dir & 0xFF, make_dir >> 8, 0x8E, 0xF0, 0x02,
                   0xA9, 0x00, 0x85, 0x0E, 0xA9, 0x4F, 0x85, 0x0F, 0xA9, 0x00, 0x85, 0x02]
                + jsr("GetFile"))
        start = harness.TRAMPOLINE
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(0x4F00, b"GEOWRITE\0")
        v.mem_set(0x4F40, b"GU folder\0")
        v.mem_set(start, bytes(code))
        v.regs_set({"PC": start})
        wait(12)
        made = v.mem_get(0x2F0, 0x2F0)[0]
        click(102, 86)                          # geoWrite's "Open"
        wait(4)
        r = rows()
        check(1, "folder listed", made == 0 and r[0] == "/GU folder",
              "MakeDir X=$%02X, rows %r" % (made, r))
        key(13)
        r = rows()
        check(2, "RETURN enters it", r[0] == "..", "rows %r" % r)
        key(29)
        r = rows()
        check(3, "DEL goes up", r[0] == "/GU folder", "rows %r" % r)
    finally:
        v.quit()
        proc.kill()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
