#!/usr/bin/env python3
"""gush's network commands in VICE (docs/design/GUSH.md):
only what needs no network (VICE has no Ultimate): their help, wget's
words and URLs refused, ifconfig failing without a Command Interface.
The network itself: gu64.py on the U64.
Usage: tests/gush/g19.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402


def main():
    g = Gush("g19", 6597)
    check = g.check

    def out(line, n=1, settle=3.0):
        g.run(line, settle=settle)
        rows = g.lines()
        return rows[-1 - n:-1] if n > 1 else rows[-2]
    try:
        g.start()
        check("help wget", out("help wget"), "wget [-O name] http://host[:port]/path")
        check("help ifconfig", out("help ifconfig"), "ifconfig")
        check("wget without a URL", out("wget"), "gush: wget: wrong words (see help)")
        check("wget, not http://", out("wget ftp://h/x"),
              "gush: wget: ftp://h/x: bad URL (http:// only)")
        check("wget -O without a URL", out("wget -O name"), "gush: wget: wrong words (see help)")
        check("wget, no host", out("wget http:///x"), "gush: wget: http:///x: bad URL (http:// only)")
        check("ifconfig without the Ultimate: failed", out("ifconfig; echo $?", 2)[1], "1")
        check("an overlay of the others afterwards", out("test 1 -eq 1; echo $?"), "0")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
