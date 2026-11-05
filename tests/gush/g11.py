#!/usr/bin/env python3
"""gush's mouse in VICE (docs/GUSH.md, "Step 2", decision 7): a click on
the input line puts the cursor on the character pressed; a click past
the line's end puts it at the end; a click elsewhere does nothing.
Usage: tests/gush/g11.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402

PROMPT_W = 2


def main():
    g = Gush("g11", 6576)
    check = g.check
    try:
        g.start()
        row = g.v.mem_get(g.lbl["conRow"], g.lbl["conRow"])[0]

        def at(col):
            return col * 6 + 2, row * 8 + 3
        g.keys("echo hello world")
        g.click(*at(PROMPT_W + len("echo hello ")))            # on the "w"
        g.keys("X")
        g.click(*at(PROMPT_W + 40))                             # past the end
        g.keys("!")
        g.click(100, 3)                                         # the status line
        g.keys("\r", settle=1)
        check("clicks place the cursor", g.lines()[-2], "hello Xworld!")
        g.png("g11")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
