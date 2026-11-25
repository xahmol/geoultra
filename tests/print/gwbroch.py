#!/usr/bin/env python3
"""geoWrite printing the sample brochure (build/samples/cvt/Brochure.cvt,
5 pages with pictures) through GU Epson FX-80 to VICE's printer 4 (the
user's hand test 2026-11-21: Epson and PDF hung on page 3). geoWrite
prints a 640-dot line in two bands of the background screen, lines
144-151 and 152-159 ($7680-$78FF, just below the printer driver at $7900);
a character of the second band past x 319 wrapped into the driver's
jump table, and its next call ran wild (text.s DrawRow: that band's
pixels now end with its card row). Drive A the user's GEOS64.D81
(GEOS_ORACLE81, a copy; its "ReadMe 1581" replaced by the brochure, so
it is the file box's only document), drive B a native image with
geoWrite in "Writing" (as tests/print/gwcross.py). Checks: all 5 pages
reach the printer, geoWrite back in its editor (no "Printing" box), the
driver's entries intact.
Usage: tests/print/gwbroch.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import epsonstream                               # noqa: E402
sys.path.insert(0, os.path.join(ROOT, "tools"))
import localcfg  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "print")
D81 = localcfg.disk("GEOS_ORACLE81", "GEOS64.D81")
BROCHURE = os.environ.get("GWBROCH_CVT", os.path.join(ROOT, "build", "samples", "cvt", "Brochure.cvt"))
PAGES = 5


def main():
    os.makedirs(OUT, exist_ok=True)
    if not os.path.exists(BROCHURE):
        sys.exit("gwbroch: %s missing (make samples)" % BROCHURE)
    d81 = os.path.join(OUT, "gwbroch.d81")
    shutil.copyfile(D81, d81)
    gd = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]
    subprocess.run(gd + ["delete", d81, "ReadMe 1581"], check=True, capture_output=True)
    subprocess.run(gd + ["add", d81, BROCHURE], check=True, capture_output=True)
    toml = os.path.join(OUT, "gwbroch.toml")
    open(toml, "w").write('[dnp]\nout = "gwbroch.dnp"\nname = "Apps test"\nid = "AT"\ntracks = 8\n'
                          'strict = true\n\n[sources]\ng = "%s"\n\n[[folder]]\npath = "Writing"\n'
                          'files = ["g:GEOWRITE"]\n' % d81)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml], cwd=OUT,
                   check=True, capture_output=True)
    pre = os.path.join(OUT, "gwbroch-pre.py")
    open(pre, "w").write('v.mem_set(0x8465, b"GU Epson FX-80\\0")\n')
    post = os.path.join(OUT, "gwbroch-post.py")              # the driver's entries
    open(post, "w").write('v.ping()\nprint("GWB box %d table %s" % (b"Printing" in bytes(v.mem_get(0x0400, 0x5FFF)),'
                          ' bytes(v.mem_get(0x7900, 0x7917)).hex()), flush=True)\n')
    raw = os.path.join(OUT, "gwbroch.raw")
    if os.path.exists(raw):
        os.remove(raw)
    after = os.path.join(OUT, "gwbroch-after.png")
    env = dict(os.environ, APPRUN_DRIVE_A=d81, APPRUN_PREHOOK=pre,
               GEOS_APPS_DISK=os.path.join(OUT, "gwbroch.dnp"),
               PYTHONPATH=os.path.join(ROOT, "tools", "dev", "harness"),
               APPRUN_VICE_ARGS="-devicebackend4 1 -busdevice4 -pr4drv raw -pr4output text -pr4txtdev 1 -prtxtdev2 " + raw)
    clicks = ["103,86,p", "w:1", "103,86,r", "w:4",          # Open
              "223,98,p", "w:1", "223,98,r", "w:4",          # Drive: A
              "223,63,p", "w:1", "223,63,r", "w:20",         # Open "Brochure"
              "35,6,p", "w:2", "45,92,p", "w:3",             # file > print
              "111,120,p", "w:1", "111,120,r", "w:600",      # OK: pages 1 to 5
              "s:" + after, "h:" + post]
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "harness", "apprun.py"), "--wait", "15",
                        "--select", "/b/Writing/GEOWRITE", "--out", os.path.join(OUT, "gwbroch.png"), "GEOWRITE"]
                       + clicks, env=env, capture_output=True, text=True, timeout=1800)
    line = next((l for l in r.stdout.splitlines() if l.startswith("GWB")), "")
    data = open(raw, "rb").read() if os.path.exists(raw) else b""
    got = epsonstream.parse(data)
    rows = [len({y for s in p.values() for x, y in s}) for p in got["pages"]]
    ok = True

    def check(title, good, got):
        nonlocal ok
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got))

    check("all %d pages printed" % PAGES, len(rows) == PAGES and all(rows), rows)
    check("only known printer codes", not got["unknown"], got["unknown"][:5])
    f = line.split()
    check("geoWrite back in its editor (no \"Printing\" box)", len(f) > 2 and f[2] == "0", line)
    check("the driver's entries intact (jsr/jmp each)", len(f) > 4 and all(
        bytes.fromhex(f[4])[i] in (0x20, 0x4C) for i in range(0, 24, 3)), line)
    print("gwbroch: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
