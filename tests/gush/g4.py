#!/usr/bin/env python3
"""gush step 1.4 in VICE (docs/GUSH.md, "Commands"): cp (a new name, the
question before overwriting answered n and y, -f, several sources into a
folder, a progress line), mv, mkdir -t (a 1581 partition), rm (asked,
-f), rmdir (not empty, then empty), cat, more (pages, q), df, errors.
Answers go into GEOS's key queue (a question reads it with GetNextChar).
Usage: tests/gush/g4.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    files = {"alpha": bytes(range(10)), "readme": b"hello\rworld\r",
             "big": bytes(i & 0xFF for i in range(40 * 254)),
             "longtext": b"".join(b"line %d\r" % i for i in range(40))}
    paths = []
    for name, data in files.items():
        path = os.path.join(OUT, name)
        open(path, "wb").write(data)
        paths.append(path)
    g = Gush("g4", 6565, paths)
    check = g.check

    def rows():
        return g.lines()

    def ls(path=""):
        g.run("ls " + path)
        return rows()[-2].split()
    try:
        g.start()
        g.run("cd /b")
        g.run("cp README R2")
        g.run("cat R2")
        check("cp, cat", rows()[-3:-1], ["hello", "world"])
        g.run("cp README R2", settle=1.5)
        check("cp onto a file asks", rows()[-1], "gush: cp: overwrite README? (y/n/a)")
        g.queue("n")
        check("answered n", rows()[-2], "gush: cp: overwrite README? (y/n/a) n")
        g.run("cp ALPHA R2", settle=1.5)
        g.queue("y")
        g.run("ls -l R2")
        check("answered y: overwritten", rows()[-2].split()[2], "1")
        g.run("cp -f README R2")
        check("cp -f: no question", rows()[-2], "$ cp -f README R2")
        g.run("mv R2 R3")
        check("mv", ("R2" in ls(), "R3" in ls()), (False, True))
        g.run("mkdir -t 3 DIR1")
        g.run("cp ALPHA README DIR1")
        check("mkdir -t, cp several into it", ls("DIR1"), ["ALPHA", "README"])
        g.run("rm R3", settle=1.5)
        check("rm asks", rows()[-1], "gush: rm: remove R3? (y/n/a)")
        g.queue("y")
        check("answered y: removed", "R3" in ls(), False)
        g.run("rmdir DIR1")
        check("rmdir a folder with files", rows()[-2], "gush: rmdir: DIR1: folder not empty")
        g.run("rm -f DIR1/*")
        g.run("rmdir DIR1")
        check("rm -f with a wildcard, rmdir", "DIR1" in ls(), False)
        g.run("cp BIG BIG2", settle=4)
        check("a progress line for 40 blocks", rows()[-2], "      40 blocks")
        g.run("ls -l BIG2")
        check("the copy's size", rows()[-2].split()[2], "40")
        g.run("more LONGTEXT", settle=2)
        r = rows()
        check("more: a page, then the question", (r[-2], r[-1]), ("line 22", "-- more (space, return, q) --"))
        g.queue(" ")
        r = rows()
        check("more: the next page", (r[-2], r[-1]), ("line 39", "$"))
        g.run("df")
        check("df", rows()[-2].endswith("blocks free of 3160 blocks"), True)
        g.run("cat NOPE")
        check("cat a missing file", rows()[-2], "gush: cat: NOPE: no such file or folder")
        g.png("g4-files")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
