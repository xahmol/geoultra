#!/usr/bin/env python3
"""gush step 1.5 in VICE (docs/GUSH.md, "Starting programs", "help"):
help, help CMD, starting an application by name (gush itself: a fresh
screen), by path and from a drive's root when it is not in the current
directory; a file that is no program; an unknown name.
Usage: tests/gush/g5.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "alpha")
    open(path, "wb").write(bytes(range(10)))
    g = Gush("g5", 6566, [path])
    check = g.check

    def fresh():
        rows = g.lines()
        return len(rows) == 2 and rows[0].startswith("gush, the GeoUltra shell") and rows[1] == "$"
    try:
        g.start()
        g.run("help")
        check("help", g.lines()[-7:-1], ["commands: cd clear cp date df echo exit free help ls",
                                          "mkdir mkimg more mount mv ntp pwd reboot rm rmdir",
                                          "set source turbo umount unset; NAME=value sets a",
                                          "variable, $NAME uses it; a program's name or a",
                                          "script's starts it.",
                                          "help NAME: a command's use."])
        g.run("help cp")
        check("help cp", g.lines()[-2], "cp [-frR] source... target")
        g.run("help frob")
        check("help for nothing", g.lines()[-2], "gush: no help for frob")
        g.run("cd /b")
        g.run("ALPHA")
        check("a plain file: run as a script (3.3; these bytes: nothing)", g.lines()[-2], "$ ALPHA")
        g.run("frob")
        check("an unknown name", g.lines()[-2], "gush: frob: not found")
        g.run("gush", settle=5)
        check("an application by name: gush again, a fresh screen", fresh(), True)
        g.run("echo marker")
        g.run("/b/gush", settle=5)
        check("by path", fresh(), True)
        g.run("cd /a")
        g.run("gush", settle=5)
        check("from drive B's root, the current directory being /a", fresh(), True)
        g.png("g5-started")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
