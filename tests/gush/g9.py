#!/usr/bin/env python3
"""gush's "program document" in VICE (docs/GUSH.md, "Starting programs"):
DocPeek (tests/gush/docpeek.s) keeps what GEOS passed it at $5000; it is
started with a document on its own drive and folder, on the other drive,
in another folder of its drive (refused), missing, and with two words.
Usage: tests/gush/g9.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT, ROOT  # noqa: E402

PEEK = 0x5000


def main():
    os.makedirs(OUT, exist_ok=True)
    letter = os.path.join(OUT, "letter")
    open(letter, "wb").write(b"Dear reader\r")
    g = Gush("g9", 6573, [os.path.join(ROOT, "build", "gush", "docpeek.cvt"), letter])
    check = g.check

    def name(b):
        return bytes(b).split(b"\0")[0].rstrip(b"\xa0").decode("latin1")

    def disk(drive):
        at = 0x841E + 18 * (drive - 8)
        return name(g.v.mem_get(at, at + 15))

    def peek(line):
        """r0L, curDrive, the disk name and file name DocPeek was given."""
        g.v.mem_set(PEEK, bytes(0x31))
        g.run(line, settle=4)
        m = g.v.mem_get(PEEK, PEEK + 0x30)
        if m[0x30] != 0xA5:
            return None
        return m[0], m[1], name(m[2:20]), name(m[20:37])

    try:
        g.start()
        g.run("cd /b")
        g.run("ls")
        doc = [w for w in g.lines()[-2].split() if w.lower() == "letter"][0]
        check("a document in the program's folder", peek("DocPeek " + doc), (0x80, 9, disk(9), doc))
        g.start()
        g.run("cd /b")
        check("a document on the other drive: the program's drive current, the document's disk",
              peek("DocPeek /a/CONVERT"), (0x80, 9, disk(8), "CONVERT"))
        g.start()
        g.run("cd /b")
        g.run("mkdir -t 3 SUB")
        g.run("cp %s SUB" % doc)                    # (one of that name here too)
        g.run("DocPeek SUB/" + doc)
        check("another folder of the program's drive", "".join(g.lines()[-3:-1]),   # (54 columns)
              "gush: DocPeek: SUB/%s: not in the program's folder" % doc)
        g.run("cp %s SUB/ONLY" % doc)
        g.run("DocPeek SUB/ONLY")
        check("another folder, no such name here", g.lines()[-2],
              "gush: DocPeek: SUB/ONLY: not in the program's folder")
        g.start()
        g.run("cd /b")
        g.run("DocPeek NOPE")
        check("a missing document", g.lines()[-2], "gush: DocPeek: NOPE: no such file or folder")
        g.run("DocPeek %s %s" % (doc, doc))
        check("two documents", g.lines()[-2], "gush: DocPeek: %s: one document at a time" % doc)
        m = peek("DocPeek")
        check("no document", m and m[0], 0)
        g.png("g9-doc")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
