#!/usr/bin/env python3
"""gush steps 1.1-1.2 in VICE (docs/GUSH.md): the frame. gush starts and greets,
shows the prompt; echo, pwd, an unknown command, DEL while typing, clear,
the screen scrolling after 24 lines, exit back to the deskTop. Screens in
build/harness/gush/g1-*.png.
Usage: tests/gush/g1.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402


def main():
    g = Gush("g1", 6560)
    check = g.check
    try:
        g.start()
        rows = g.lines()
        check("the greeting and the prompt", (rows[0].startswith("gush, the GeoUltra shell"), rows[1:]), (True, ["$"]))
        g.png("g1-start")
        ours = g.v.mem_get(0x84A3, 0x84A4)
        g.run("echo hello, world")
        check("echo", g.lines()[-3:], ["$ echo hello, world", "hello, world", "$"])
        g.run("pwd")
        check("pwd", g.lines()[-3:], ["$ pwd", "/", "$"])
        g.run("frobnicate now")
        check("an unknown command", g.lines()[-2], "gush: frobnicate: not found")
        g.keys("echo abX")
        g.keys([29])                            # DEL
        g.run("c")
        check("DEL while typing", g.lines()[-2:], ["abc", "$"])
        g.png("g1-commands")
        for i in range(14):
            g.run("echo line %d" % i, settle=0.3)
        rows = g.screen()
        check("scrolled: the last line at the bottom", (rows[-2], rows[-1]), ("line 13", "$"))
        g.png("g1-scrolled")
        g.run("clear")
        check("clear", g.lines(), ["$"])
        g.run("exit", settle=4)
        check("exit: back to the deskTop (gush's keyVector gone)", g.v.mem_get(0x84A3, 0x84A4) != ours, True)
        g.png("g1-exit")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
