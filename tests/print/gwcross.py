#!/usr/bin/env python3
"""geoWrite printing a document from another drive (the user's U64,
2026-11-16; docs/design/DESIGN.md "Printing"): drive A the user's GEOS64.D81
(GEOS_ORACLE81, a copy; never committed) with "ReadMe 1581", drive B a
native image made here with geoWrite in a folder "Writing". geoWrite
starts in /b/Writing, opens the document from A, prints it with GU Epson
FX-80 (drive E) to VICE's printer 4. geoWrite switches drives with
SetDevice alone (its document's, its own for the driver, back), so a
drive must find its directory from its own state (folders.s module 117):
before that fix it failed "reading printer driver" here and "reading
page" with a garbled printout on the U64. Checks: the printout is the
document (VICE's printer got the page, its text rows), no error dialog.
Usage: tests/print/gwcross.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import epsonstream                               # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "print")
D81 = localcfg.disk("GEOS_ORACLE81", "GEOS64.D81")


def main():
    os.makedirs(OUT, exist_ok=True)
    d81 = os.path.join(OUT, "gwcross.d81")
    shutil.copyfile(D81, d81)
    toml = os.path.join(OUT, "gwcross.toml")
    open(toml, "w").write('[dnp]\nout = "gwcross.dnp"\nname = "Apps test"\nid = "AT"\ntracks = 8\n'
                          'strict = true\n\n[sources]\ng = "%s"\n\n[[folder]]\npath = "Writing"\n'
                          'files = ["g:GEOWRITE"]\n' % d81)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml], cwd=OUT,
                   check=True, capture_output=True)
    pre = os.path.join(OUT, "gwcross-pre.py")
    open(pre, "w").write('v.mem_set(0x8465, b"GU Epson FX-80\\0")\n')
    raw = os.path.join(OUT, "gwcross.raw")
    if os.path.exists(raw):
        os.remove(raw)
    after = os.path.join(OUT, "gwcross-after.png")
    env = dict(os.environ, APPRUN_DRIVE_A=d81, APPRUN_PREHOOK=pre,
               GEOS_APPS_DISK=os.path.join(OUT, "gwcross.dnp"), PYTHONPATH=os.path.join(ROOT, "tools", "dev", "harness"),
               APPRUN_VICE_ARGS="-devicebackend4 1 -busdevice4 -pr4drv raw -pr4output text -pr4txtdev 1 -prtxtdev2 " + raw)
    clicks = ["103,86,p", "w:1", "103,86,r", "w:4",          # Open
              "223,98,p", "w:1", "223,98,r", "w:4",          # Drive: A
              "223,63,p", "w:1", "223,63,r", "w:15",         # Open "ReadMe 1581"
              "35,6,p", "w:2", "45,92,p", "w:3",             # file > print
              "111,120,p", "w:1", "111,120,r", "w:240",      # OK
              "s:" + after]
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "harness", "apprun.py"), "--wait", "15",
                    "--select", "/b/Writing/GEOWRITE", "--out", os.path.join(OUT, "gwcross.png"), "GEOWRITE"]
                   + clicks, env=env, capture_output=True, text=True, timeout=900)
    data = open(raw, "rb").read() if os.path.exists(raw) else b""
    got = epsonstream.parse(data)
    dots = set()
    for p in got["pages"]:
        for s in p.values():
            dots |= s
    rows = len({y for x, y in dots})
    ok = len(got["pages"]) == 1 and not got["unknown"] and rows > 200 and len(data) > 20000
    print("%s the document printed from drive A, geoWrite in /b/Writing: %d bytes, %d dot rows"
          % ("pass" if ok else "FAIL", len(data), rows))
    print("gwcross: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
