#!/usr/bin/env python3
"""Conformance harness: run kernal routines on GEOS 2.0 and on GeoUltra in
VICE and compare the results (docs/ARCHITECTURE.md, DESIGN.md).

Usage: harness.py [--rebuild] [--keep] CASEFILE.py [CASEFILE.py ...]

For each system the harness boots VICE once, stops at the top of
MainLoop and saves a snapshot (build/harness/<system>.vsf, reused unless
--rebuild). Every test case then restores the snapshot, clears both
screen buffers, writes its inputs, calls the routine through a
trampoline in the cassette buffer and reads the results. A case passes
when every item in its `compare` list is equal on both systems.

Case files define CASES, a list of dicts:
  name     text
  routine  jump table name (src/kernal/jumptab.txt)
  a, x, y  register values (optional)
  r        {"r3": 10, "r11L": 50, ...} pseudo-register inputs
  pattern  8 bytes for curPattern (optional; curPattern points to them)
  disp     dispBufferOn (default $C0: foreground and background)
  fill     byte both screen buffers are filled with first (default 0)
  mem      {address: bytes} extra memory writes
  pre      routines called (in order) before the r-register inputs are set
           and the routine runs, e.g. ["UseSystemFont"]
  compare  list of: "fore", "back" (screen buffers), "A", "X", "Y",
           r-register names (r0..r15, r0L..r15H), "mem:$ADDR-$ADDR"

The trampoline at $0340 is generated per case: sei, jsr to each `pre`
routine, lda/sta of the r-register inputs, lda/ldx/ldy, jsr routine.
"""
import argparse
import importlib.util
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "harness")
# Headless VICE 3.10 (no window, no sound) when built, else the GTK one.
VICE = os.environ.get("VICE_HARNESS") or next(
    (p for p in (os.path.expanduser("~/.local/opt/vice-3.10-headless/bin/x64sc"),
                 os.path.expanduser("~/.local/opt/vice-3.10/bin/x64sc"))
     if os.path.exists(p)))
ORACLE_DISK = os.environ.get(
    "GEOS_ORACLE", os.path.expanduser("~/geos-dev/u64-usb/GEOS64-v2.0-unkeyed.d64"))

SYSTEMS = {
    "geos": ["-drive8truedrive", "+autostart-delay-random", "-autostart-delay", "3",
             "-autostart", ORACLE_DISK],
    "geoultra": ["-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
                 "-reu", "-reusize", "16384"],
}
PORTS = {"geos": 6502, "geoultra": 6503}

TRAMPOLINE = 0x0340
PATTERN_BUF = 0x0380
FORE = (0xA000, 0xBF3F)
BACK = (0x6000, 0x7F3F)
CUR_PATTERN = 0x22
DISP_BUFFER_ON = 0x2F


def jumptab():
    names = [l.split("#")[0].strip()
             for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
    names = [n for n in names if n]
    return dict((n, 0xC100 + 3 * i) for i, n in enumerate(names))


def rreg(name):
    """Address and size of r0..r15, r0L..r15H."""
    base = name.rstrip("LH")
    addr = 2 + 2 * int(base[1:])
    if name.endswith("H"):
        return addr + 1, 1
    if name.endswith("L"):
        return addr, 1
    return addr, 2


class System:
    def __init__(self, name, rebuild):
        self.name = name
        self.snapshot = os.path.join(OUT, name + ".vsf")
        args = [VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
                "-binarymonitoraddress", "127.0.0.1:%d" % PORTS[name]] + SYSTEMS[name]
        self.log = open(os.path.join(OUT, name + ".log"), "w")
        self.proc = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT)
        self.vice = Vice(port=PORTS[name])
        crt = os.path.join(ROOT, "build", "geoultra64.crt")
        stale = (name == "geoultra" and os.path.exists(self.snapshot)
                 and os.path.getmtime(crt) > os.path.getmtime(self.snapshot))
        if rebuild or stale or not os.path.exists(self.snapshot):
            self.make_snapshot()

    def make_snapshot(self):
        """Let the system boot, then stop at the top of its MainLoop."""
        v = self.vice
        for _ in range(60):
            v.resume()
            time.sleep(2)
            v.ping()                        # stops the emulation
            jt = v.mem_get(0xC1C3, 0xC1C5)
            if jt[0] == 0x4C and v.mem_get(0xA000, 0xA000)[0] != 0:
                break
        else:
            raise SystemExit("%s: no GEOS kernal after boot" % self.name)
        time.sleep(0)
        main = jt[1] | jt[2] << 8
        v.checkpoint(main)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.dump(self.snapshot)
        print("%s: snapshot at MainLoop $%04X" % (self.name, main))

    def run(self, case, table):
        v = self.vice
        v.undump(self.snapshot)
        fill = case.get("fill", 0)
        v.mem_set(FORE[0], bytes([fill]) * (FORE[1] - FORE[0] + 1))
        v.mem_set(BACK[0], bytes([fill]) * (BACK[1] - BACK[0] + 1))
        code = [0x78]
        for pre in case.get("pre", []):
            a = table[pre]
            code += [0x20, a & 0xFF, a >> 8]
        for name, value in case.get("r", {}).items():
            a, size = rreg(name)
            for i in range(size):
                code += [0xA9, value >> (8 * i) & 0xFF, 0x85, a + i]
        for reg, op in (("a", 0xA9), ("x", 0xA2), ("y", 0xA0)):
            if reg in case:
                code += [op, case[reg]]
        a = table[case["routine"]]
        code += [0x20, a & 0xFF, a >> 8]
        end = TRAMPOLINE + len(code)
        code += [0xEA, 0x4C, end & 0xFF, end >> 8]
        v.mem_set(TRAMPOLINE, bytes(code))
        v.mem_set(DISP_BUFFER_ON, bytes([case.get("disp", 0xC0)]))
        if "pattern" in case:
            v.mem_set(PATTERN_BUF, bytes(case["pattern"]))
            v.mem_set(CUR_PATTERN, bytes([PATTERN_BUF & 0xFF, PATTERN_BUF >> 8]))
        for a, data in case.get("mem", {}).items():
            v.mem_set(a, bytes(data))
        v.regs_set({"PC": TRAMPOLINE})
        v.checkpoint(end)
        v.resume()
        v.wait_event(RESP_CHECKPOINT, timeout=30)
        out = {}
        cpu = v.regs_get()
        for item in case["compare"]:
            if item == "fore":
                out[item] = v.mem_get(*FORE)
            elif item == "back":
                out[item] = v.mem_get(*BACK)
            elif item in ("A", "X", "Y"):
                out[item] = cpu[item]
            elif item.startswith("mem:"):
                lo, hi = item[4:].replace("$", "").split("-")
                out[item] = v.mem_get(int(lo, 16), int(hi, 16))
            else:
                a, size = rreg(item)
                out[item] = v.mem_get(a, a + size - 1)
        return out

    def close(self):
        self.vice.quit()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def describe(item, ours, ref):
    if isinstance(ref, bytes) and len(ref) > 2:
        diffs = [i for i in range(len(ref)) if ref[i] != ours[i]]
        base = FORE[0] if item == "fore" else BACK[0]
        shown = ", ".join("$%04X geos %02X ours %02X" % (base + i, ref[i], ours[i])
                          for i in diffs[:4])
        return "%s: %d bytes differ (%s)" % (item, len(diffs), shown)
    return "%s: geos %s ours %s" % (item, ref.hex() if isinstance(ref, bytes) else ref,
                                     ours.hex() if isinstance(ours, bytes) else ours)


def pixels(fore, x0, y0, x1, y1):
    """ASCII rows of the foreground screen area (inclusive)."""
    out = []
    for y in range(y0, y1 + 1):
        line = ""
        for x in range(x0, x1 + 1):
            byte = fore[(y >> 3) * 320 + (y & 7) + (x & 0x1F8)]
            line += "#" if byte & (0x80 >> (x & 7)) else "."
        out.append(line)
    return out


def load_cases(paths):
    cases = []
    for p in paths:
        spec = importlib.util.spec_from_file_location(os.path.basename(p)[:-3], p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        cases += mod.CASES
    return cases


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--rebuild", action="store_true", help="make new snapshots")
    ap.add_argument("--show", metavar="NAME",
                    help="run only the cases whose name contains NAME and print "
                         "the --area of both foreground screens")
    ap.add_argument("--area", default="0,0,63,15", help="x0,y0,x1,y1 for --show")
    ap.add_argument("casefiles", nargs="+")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    cases = load_cases(args.casefiles)
    if args.show:
        cases = [c for c in cases if args.show in c["name"]]
        for c in cases:
            if "fore" not in c["compare"]:
                c["compare"] = c["compare"] + ["fore"]
    table = jumptab()
    results = {}
    for name in ("geos", "geoultra"):
        system = System(name, args.rebuild)
        try:
            results[name] = [system.run(c, table) for c in cases]
        finally:
            system.close()
    if args.show:
        area = [int(n) for n in args.area.split(",")]
        for i, case in enumerate(cases):
            print("%s   (x %d-%d, y %d-%d)" % (case["name"], area[0], area[2], area[1], area[3]))
            g = pixels(results["geos"][i]["fore"], *area)
            o = pixels(results["geoultra"][i]["fore"], *area)
            print("%-*s   %s" % (len(g[0]), "GEOS 2.0", "GeoUltra"))
            for a, b in zip(g, o):
                print("%s   %s%s" % (a, b, "   <" if a != b else ""))
        return
    failed = 0
    for i, case in enumerate(cases):
        ref, ours = results["geos"][i], results["geoultra"][i]
        bad = [k for k in case["compare"] if ref[k] != ours[k]]
        if bad:
            failed += 1
            print("FAIL %-40s %s" % (case["name"], "; ".join(
                describe(k, ours[k], ref[k]) for k in bad)))
        else:
            print("pass %s" % case["name"])
    print("%d of %d cases pass" % (len(cases) - failed, len(cases)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
