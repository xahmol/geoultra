#!/usr/bin/env python3
"""gush's command table (src/gush/cmds.s, Commands) well formed: every
name followed by its routine's address. (An edit that put a usage line
into the table once made pwd jump into data.) And the overlays (ovl.s):
no overlay's code calls a routine of another overlay (its return would
land in that overlay's code).
Usage: tests/gush/gtables.py
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    t = open(os.path.join(ROOT, "src", "gush", "cmds.s")).read()
    i = t.index("Commands:")
    j = t.index("        .byte 0\n", i)
    rows = [r.split(";")[0].strip() for r in t[i:j].split("\n")[1:]]
    rows = [r for r in rows if r]
    bad = [(a, b) for a, b in zip(rows[0::2], rows[1::2])
           if not (a.startswith(".byte") and b.startswith(".word"))]
    ok = not bad and len(rows) % 2 == 0
    print("%s the command table: %d entries%s" % ("pass" if ok else "FAIL", len(rows) // 2,
                                                 "" if ok else ", wrong: %s" % bad[:3]))
    ok2 = overlays()
    sys.exit(0 if ok and ok2 else 1)


def overlays():
    """Each overlay file's imports against the stubs of the other overlays."""
    ovl = open(os.path.join(ROOT, "src", "gush", "ovl.s")).read()
    stub = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\s+Stub (\w+), (\d+)", ovl, re.M)}
    bad = []
    for path in sorted(glob.glob(os.path.join(ROOT, "src", "gush", "*.s"))):
        src = open(path).read()
        mine = {int(n) for n in re.findall(r'\.segment "OV(\d+)"', src)}
        if not mine:
            continue
        for line in re.findall(r"^\s*\.import\s+(.*)$", src, re.M):
            for name in (x.strip() for x in line.split(";")[0].split(",")):
                if name in stub and stub[name] not in mine:
                    bad.append("%s calls %s (overlay %d)" % (os.path.basename(path), name, stub[name]))
    print("%s the overlays: %d stubs, no call across overlays%s" % (
        "FAIL" if bad else "pass", len(stub), ": " + "; ".join(bad) if bad else ""))
    return not bad


if __name__ == "__main__":
    main()
