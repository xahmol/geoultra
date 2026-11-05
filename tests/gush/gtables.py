#!/usr/bin/env python3
"""gush's command table (src/gush/cmds.s, Commands) well formed: every
name followed by its routine's address. (An edit that put a usage line
into the table once made pwd jump into data.)
Usage: tests/gush/gtables.py
"""
import os
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
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
