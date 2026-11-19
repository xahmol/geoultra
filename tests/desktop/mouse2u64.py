#!/usr/bin/env python3
"""The right mouse button on the U64 (docs/design/DESKTOP.md, "Toolbar and
right-click": checked on the hardware first). Boots GeoUltra and watches
guMouse2 ($C0E6: bit 7 clear while the right button is held, bit 6 at a
press) and GEOS's mouseData ($8505, the left button) while someone
presses the buttons of the mouse on port 1 (the U64's USB mouse as a
1351, or a real 1351). Prints every change (the left button's in
mouseData: it should not move with the right one); passes when the
right button was seen held and released. A hand test: it needs a
person at the mouse.
Usage: tests/desktop/mouse2u64.py [SECONDS]   (default 60)
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64  # noqa: E402

GU_MOUSE2, MOUSE_DATA = 0xC0E6, 0x8505


def main():
    seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    u = U64()
    u.boot(os.path.join(ROOT, "build", "geoultra64.crt"))
    u.write(GU_MOUSE2, b"\x80")
    print("Press the right mouse button a few times, then the left one "
          "(%d seconds)." % seconds, flush=True)
    last = None
    held = released = False
    end = time.time() + seconds
    while time.time() < end:
        right, left = u.read(GU_MOUSE2, 1)[0], u.read(MOUSE_DATA, 1)[0]
        if (right, left) != last:
            print("%6.1f s  guMouse2 $%02X  mouseData $%02X" % (seconds - (end - time.time()), right, left),
                  flush=True)
            if not right & 0x80:
                held = True
            elif held:
                released = True
            last = (right, left)
        time.sleep(0.1)
    ok = held and released
    print(("pass" if ok else "FAIL") + " the right button seen held and released: %s, %s" % (held, released))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
