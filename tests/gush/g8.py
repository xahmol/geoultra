#!/usr/bin/env python3
"""gush's cp -r in VICE (docs/design/GUSH.md, "Commands"): a folder with files
and a folder in it (1581 partitions, mkdir -t) copied to a new name and
into an existing folder; without -r a folder is refused, as by mv.
Usage: tests/gush/g8.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    paths = []
    for name, data in (("one", b"first\r"), ("two", b"second\r"), ("three", b"third\r")):
        path = os.path.join(OUT, name)
        open(path, "wb").write(data)
        paths.append(path)
    g = Gush("g8", 6570, paths)
    check = g.check

    def ls(path):
        g.run("ls " + path)
        return sorted(g.lines()[-2].split())
    try:
        g.start()
        g.run("cd /b")
        g.run("mkdir -t 8 SRC")
        g.run("cp ONE TWO SRC")
        g.run("mkdir -t 3 SRC/SUB")
        g.run("cp THREE SRC/SUB")
        check("the source tree", (ls("SRC"), ls("SRC/SUB")), (["ONE", "SUB", "TWO"], ["THREE"]))
        g.run("cp SRC DST")
        check("cp of a folder without -r", g.lines()[-2], "gush: cp: SRC: is a folder")
        g.run("cp -r SRC DST", settle=6)
        check("cp -r to a new name", (ls("DST"), ls("DST/SUB")), (["ONE", "SUB", "TWO"], ["THREE"]))
        g.run("cat DST/SUB/THREE")
        check("its file's bytes", g.lines()[-2], "third")
        g.run("mkdir -t 12 OUTER")              # (room for SRC's 8 tracks)
        g.run("cp -r SRC OUTER", settle=6)
        check("cp -r into an existing folder", (ls("OUTER"), ls("OUTER/SRC/SUB")), (["SRC"], ["THREE"]))
        g.run("mv SRC MOVED")
        check("mv of a folder", g.lines()[-2], "gush: mv: SRC: is a folder")
        g.png("g8-tree")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
