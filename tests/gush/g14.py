#!/usr/bin/env python3
"""gush's scripts in VICE (docs/design/GUSH.md): a script
by name and with source, $0 $1 $#, comments, exit N and $?, variables
shared, a script running a script, a script's output into a file, a
script found along PATH. (gushrc: gu64.py, it needs the home folder.)
Usage: tests/gush/g14.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402

S1 = b"# a comment\recho first $1 $#\rX='set by S1'\recho $0\rexit 3\recho never\r"
S2 = b"S1 inner\recho after\r"


def main():
    os.makedirs(OUT, exist_ok=True)
    files = []
    for name, data in (("s1", S1), ("s2", S2)):
        path = os.path.join(OUT, name)
        open(path, "wb").write(data)
        files.append(path + ",s")             # (SEQ: a PRG would run in BASIC)
    g = Gush("g14", 6580, files)
    check = g.check
    try:
        g.start()
        g.run("cd /b")
        g.run("S1 a b", settle=3)
        check("a script by name: $1 $#, $0, exit ends it", g.lines()[-3:-1], ["first a 2", "S1"])
        g.run("echo $?")
        check("exit 3: its status", g.lines()[-2], "3")
        check("its variable shared", (g.run("echo $X") or g.lines()[-2]), "set by S1")
        g.run("source S1 z", settle=3)
        check("source", g.lines()[-3], "first z 1")
        g.run("S2", settle=4)
        check("a script running a script", g.lines()[-4:-1], ["first inner 1", "S1", "after"])
        g.run("S2 > OUT", settle=4)
        check("a script's output into a file", g.lines()[-2], "$ S2 > OUT")
        g.run("cat OUT")
        check("the file", g.lines()[-4:-1], ["first inner 1", "S1", "after"])
        g.run("mkdir -t 3 BIN")
        g.run("cp S1 BIN/S3")
        g.run("PATH=/b/BIN")
        g.run("cd /a")
        g.run("S3 p", settle=3)
        check("along PATH", g.lines()[-3], "first p 1")
        g.png("g14")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
