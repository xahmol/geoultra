#!/usr/bin/env python3
"""The shared clipboard in VICE (docs/DESIGN.md "Clipboard"; src/kernal/
scrap.s): geoWrite on drive B types a line, selects it, copies it, closes
the document and quits (geoWrite writes "Text  Scrap" then); the scrap is
in the store (its blocks on tracks 246-247), FindFile finds it from
drive A too, ReadFile through drive A reads the copied text, and
DeleteFile through drive A removes it (FindFile: not found). A paste in
another program is a hand test (docs/DESIGN.md "For the user"): the
harness's click on geoWrite's paste item does not arrive. Through
tools/harness/apprun.py (h: hooks) with a copy of an applications disk
(GEOS_APPS_DISK, the user's own, default the neos-mouse-driver disk with
geoWrite 1.1; never committed). Screens: build/harness/clip/*.png.
Usage: tests/apps/clipboard.py
"""
import os
import shutil
import subprocess
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "clip")
APPS_DISK = localcfg.disk("GEOS_APPS_DISK", "neos-mouse-driver-for-geos.d64")
SCRAP_TRACKS = (246, 247)

# A hook: code at the harness's trampoline (SetDevice DRIVE, OpenDisk,
# then FindFile or GetFile of the name at $4F00), results at $02F0.
HOOK = '''
import time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402
jt = harness.jumptab()
def jsr(n):
    a = jt[n]; return [0x20, a & 0xFF, a >> 8]
v.ping()
v.mem_set(0x4F00, %(name)r + b"\\0")
v.mem_set(0x02F0, b"\\xEE")
start = harness.TRAMPOLINE
code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, %(drive)d] + jsr("SetDevice") + jsr("OpenDisk")
        + [0xA9, 0x00, 0x85, 0x0E, 0xA9, 0x4F, 0x85, 0x0F, 0xA9, 0x00, 0x85, 0x02]
        + jsr(%(call)r) + [0x8E, 0xF0, 0x02])
end = start + len(code)
code += [0x4C, end & 0xFF, end >> 8]
v.mem_set(start, bytes(code))
v.regs_set({"PC": start})
v.resume(); time.sleep(%(wait)d); v.ping()
if %(call)r == "ReadFile":
    pass
if %(call)r == "FindFile":
    e = v.mem_get(0x8400, 0x841D)
    print("HOOK FindFile drive %%d: X=%%02x track %%d header track %%d" %% (%(drive)d, v.mem_get(0x2F0, 0x2F0)[0], e[1], e[19]))
'''


READ = '''
import time
jt = harness.jumptab()
def jsr(n):
    a = jt[n]; return [0x20, a & 0xFF, a >> 8]
v.ping()
v.mem_set(0x4F00, b"Text  Scrap\\0")
v.mem_set(0x5000, bytes(64))
v.mem_set(0x02F0, b"\\xEE\\xEE")
start = harness.TRAMPOLINE
code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, %(drive)d] + jsr("SetDevice") + jsr("OpenDisk")
        + [0xA9, 0x00, 0x85, 0x0E, 0xA9, 0x4F, 0x85, 0x0F] + jsr("FindFile") + [0x8E, 0xF0, 0x02]
        + [0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05,     # r1 = its data
           0xA9, 0x00, 0x85, 0x10, 0xA9, 0x50, 0x85, 0x11,                 # r7 = $5000
           0xA9, 0x00, 0x85, 0x06, 0xA9, 0x10, 0x85, 0x07]                 # r2 = $1000
        + jsr("ReadFile") + [0x8E, 0xF1, 0x02])
end = start + len(code)
code += [0x4C, end & 0xFF, end >> 8]
v.mem_set(start, bytes(code))
v.regs_set({"PC": start})
v.resume(); time.sleep(4); v.ping()
x = v.mem_get(0x2F0, 0x2F1)
print("READ drive %%d: FindFile X=%%02x ReadFile X=%%02x data %%r" %% (%(drive)d, x[0], x[1], bytes(v.mem_get(0x5000, 0x5020))))
'''


def readhook(drive):
    path = os.path.join(OUT, "hook-read-%d.py" % drive)
    open(path, "w").write(READ % {"drive": drive})
    return "h:" + path


DELETE = '''
import time
jt = harness.jumptab()
def jsr(n):
    a = jt[n]; return [0x20, a & 0xFF, a >> 8]
v.ping()
v.mem_set(0x4F00, b"Text  Scrap\\0")
v.mem_set(0x02F0, b"\\xEE\\xEE")
start = harness.TRAMPOLINE
code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, %(drive)d] + jsr("SetDevice") + jsr("OpenDisk")
        + [0xA9, 0x00, 0x85, 0x02, 0xA9, 0x4F, 0x85, 0x03] + jsr("DeleteFile") + [0x8E, 0xF0, 0x02]
        + [0xA9, 0x00, 0x85, 0x0E, 0xA9, 0x4F, 0x85, 0x0F] + jsr("FindFile") + [0x8E, 0xF1, 0x02])
end = start + len(code)
code += [0x4C, end & 0xFF, end >> 8]
v.mem_set(start, bytes(code))
v.regs_set({"PC": start})
v.resume(); time.sleep(4); v.ping()
x = v.mem_get(0x2F0, 0x2F1)
print("DELETE drive %%d: DeleteFile X=%%02x FindFile X=%%02x" %% (%(drive)d, x[0], x[1]))
'''


def delhook(drive):
    path = os.path.join(OUT, "hook-delete-%d.py" % drive)
    open(path, "w").write(DELETE % {"drive": drive})
    return "h:" + path


def hook(name, drive, call, wait):
    path = os.path.join(OUT, "hook-%s-%d.py" % (call, drive))
    open(path, "w").write(HOOK % {"name": name, "drive": drive, "call": call, "wait": wait})
    return "h:" + path


def main():
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "apps.d64")
    shutil.copyfile(APPS_DISK, disk)
    shot = lambda n: "s:" + os.path.join(OUT, n + ".png")
    menu = lambda x, y: ["%d,6,p" % x, "w:2", "%d,%d,p" % (x, y), "w:1", "%d,%d,r" % (x, y), "w:4"]
    ev = (["102,63,p", "102,63,r", "w:3", "k:GU copy", "k:#13", "w:8",       # Create
           "k:Hello GeoUltra.", "w:3", "300,150,-", "w:1", shot("typed"),
           "1,33,p", "w:1", "75,33,-", "w:1", "75,33,r", "w:2"]             # select
          + menu(60, 35)                                                    # edit > copy
          + menu(30, 21) + ["w:6", "102,111,p", "w:1", "102,111,r", "w:12"]  # close, Quit
          + [hook(b"Text  Scrap", 9, "FindFile", 3), hook(b"Text  Scrap", 8, "FindFile", 3),
             readhook(8), delhook(8)])                                      # read, delete via A
    env = dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "harness"))
    apprun = [sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "12"]
    r = subprocess.run(apprun + ["--out", os.path.join(OUT, "end.png"), "GEOWRITE"] + ev,
                       env=env, capture_output=True, text=True, timeout=590)
    print(r.stdout.strip())
    if r.returncode:
        print(r.stderr[-800:])
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    found = [l for l in r.stdout.splitlines() if l.startswith("HOOK FindFile")]
    check("the scrap found from drive B, in the store",
          any("drive 9: X=00" in l and any("track %d" % t in l for t in SCRAP_TRACKS) for l in found), True)
    check("and from drive A", any("drive 8: X=00" in l for l in found), True)
    read = [l for l in r.stdout.splitlines() if l.startswith("READ")]
    check("read through drive A (ReadFile by its blocks): the copied text",
          bool(read) and "FindFile X=00 ReadFile X=00" in read[0] and "Hello GeoUltra." in read[0], True)
    dele = [l for l in r.stdout.splitlines() if l.startswith("DELETE")]
    check("DeleteFile through drive A: gone from the store (FindFile: not found)",
          bool(dele) and "DeleteFile X=00 FindFile X=05" in dele[0], True)
    print("clipboard: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
