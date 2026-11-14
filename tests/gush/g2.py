#!/usr/bin/env python3
"""gush in VICE (docs/GUSH.md, "Keys and the line editor"):
inserting in the middle, DEL and INST, the cursor keys, HOME, CTRL+A, E,
K, U (through gush's test flag: VICE's monitor cannot hold a key),
RUN/STOP, the history (up, down, no repeats), a line longer than the
screen row.
Usage: tests/gush/g2.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402

DEL, INST, LEFT, RIGHT, HOME, UP, DOWN, STOP, CR = 29, 28, 8, 30, 18, 16, 17, 22, 13


def main():
    g = Gush("g2", 6562)
    check = g.check
    ctrl = g.lbl["testCtrl"]

    def with_ctrl(key):
        g.v.mem_set(ctrl, b"\x01")
        g.keys(key)
        g.v.mem_set(ctrl, b"\x00")

    def last(n=1):
        return g.lines()[-1 - n:-1] if n > 1 else g.lines()[-2]
    try:
        g.start()
        g.keys("echo helo")
        g.keys([LEFT])
        g.keys("l\r")
        check("insert in the middle", last(), "hello")
        g.keys("echo abcd")
        g.keys([HOME] + [RIGHT] * 5 + [INST, CR])
        check("HOME, cursor right, INST", last(), "bcd")
        g.keys("echo xyzzy")
        g.keys([DEL, DEL, CR])
        check("DEL", last(), "xyz")
        g.keys("cho one")
        with_ctrl("a")
        g.keys("e")
        with_ctrl("e")
        g.keys(" two\r")
        check("CTRL+A, CTRL+E", last(), "one two")
        g.keys("echo keep this+drop this")             # (a "|" would be a pipe now)
        g.keys([LEFT] * 9)
        with_ctrl("k")
        g.keys("\r")
        check("CTRL+K", last(), "keep this+")
        g.keys("echo a ")                       # up arrow: "|"; C= + ( ) - ' up: { } _ ` ~
        g.keys([21])                            # (KEY_UPARROW; user, 2026-11-06)
        g.keys(" cat\r")
        check("up arrow types |", last(), "a")
        g.keys("echo ")
        g.keys([0x80 | ord("("), 0x80 | ord(")"), 0x80 | ord("-"), 0x80 | ord("'"), 0x80 | 21, 13])
        check("C= keys type { } _ ` ~", last(), "{}_`~")
        g.keys("rubbish echo cut")
        g.keys([LEFT] * 8)
        with_ctrl("u")
        g.keys("\r")
        check("CTRL+U", last(), "cut")
        g.keys("echo never")
        g.keys([STOP])
        check("RUN/STOP drops the line", g.lines()[-2:], ["$ echo never^C", "$"])
        g.run("echo first")
        g.run("echo second")
        g.run("echo second")
        g.keys([UP, UP, CR])
        check("history: two up (no repeat of 'echo second')", last(), "first")
        g.keys([UP, UP, DOWN, CR])
        check("history: up, up, down", last(), "first")
        g.keys([UP, DOWN, DOWN])
        g.keys("echo fresh\r")
        check("history: down past the newest: an empty line", last(), "fresh")
        long = "echo " + "".join(chr(ord("a") + i % 26) for i in range(70))
        g.keys(long)
        row = g.screen()[g.v.mem_get(g.lbl["conRow"], g.lbl["conRow"])[0] - 1]
        check("a long line scrolls sideways", row, "$ " + long[-50:])
        g.keys("\r")
        out = g.lines()
        check("and runs whole", (out[-3] + out[-2]), long[5:])
        g.keys([UP], settle=1)                  # recalled: its start shown (user, 2026-11-06)
        row = g.screen()[g.v.mem_get(g.lbl["conRow"], g.lbl["conRow"])[0] - 1]
        pos = g.v.mem_get(g.lbl["linePos"], g.lbl["linePos"])[0]
        check("a recalled long line: its start, the cursor there", (row, pos), ("$ " + long[:51], 0))
        g.keys([STOP])
        g.png("g2-editor")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
