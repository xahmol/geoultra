#!/usr/bin/env python3
"""The video autopilot's PC side (tools/dev/video/autopilot.s; docs/design/DESIGN.md,
Beta 1: the first-look video). Pilot(backend) installs the routine at
$0334 on GEOS's intBotVector and drives the pointer with one short write
per command: glide (eased), press, release; clicks, double clicks and
drags are made of them. Keys go as taps on the keyboard matrix (U64:
REST machine:input). Backends: U64 (UBoot64-v2's tests/e2e/ultimate.py)
and Vice (tools/dev/harness/vicemon.py, for trying scenes out).
Own code.
"""
import math
import os
import subprocess
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = 0x0334
CHAIN = 0x035A + 1              # Chain's operand (autopilot.s, jmp $FFFF)
CMD = 0x03FA
INT_BOT = 0x849F
OP_GLIDE, OP_PRESS, OP_RELEASE = 1, 2, 3


def build():
    """autopilot.s assembled; its bytes."""
    out = os.path.join(HERE, "..", "..", "..", "build", "video")
    os.makedirs(out, exist_ok=True)
    o, b = os.path.join(out, "autopilot.o"), os.path.join(out, "autopilot.bin")
    subprocess.run(["ca65", "-o", o, os.path.join(HERE, "autopilot.s")], check=True)
    subprocess.run(["ld65", "-t", "none", "-o", b, o], check=True)
    return open(b, "rb").read()


class U64:
    def __init__(self, u):
        self.u = u

    def read(self, addr, n):
        return bytes(self.u.read_memory(addr, n))

    def write(self, addr, data):
        self.u.write_memory(addr, bytes(data))

    def keys(self, names):
        self.u.tap_keys(names)


class Vice:
    def __init__(self, v):
        self.v = v

    def read(self, addr, n):
        return bytes(self.v.mem_get(addr, addr + n - 1))

    def write(self, addr, data):
        self.v.mem_set(addr, bytes(data))
        self.v.resume()

    def keys(self, names):
        raise NotImplementedError("keys: VICE has no matrix input here")


KEYNAMES = {" ": "space", "\r": "return", "/": "slash", "-": "minus", ".": "period",
            ",": "comma", ":": "colon", "=": "equal", "*": "asterisk", "+": "plus",
            ";": "semicolon", "$": ["left_shift", "4"]}


class Pilot:
    def __init__(self, backend):
        self.b = backend
        self.seq = 0
        self.x, self.y = 160, 100

    def install(self):
        code = bytearray(build())
        old = self.b.read(INT_BOT, 2)
        if old == b"\0\0":                     # no vector before: Chain to an
            rts = BASE + len(code) - 5          # rts (Step's last; 4 data bytes
            assert code[rts - BASE] == 0x60     # follow it)
            old = bytes([rts & 0xFF, rts >> 8])
        code[CHAIN - BASE] = old[0]
        code[CHAIN - BASE + 1] = old[1]
        self.b.write(BASE, code)
        self.b.write(CMD, bytes(6))             # seq 0 = done 0: idle
        self.b.write(INT_BOT, bytes([BASE & 0xFF, BASE >> 8]))
        pos = self.b.read(0x3A, 3)
        self.x, self.y = pos[0] | pos[1] << 8, pos[2]

    def _cmd(self, op, x=0, y=0, speed=3):
        self.seq = (self.seq + 1) & 0xFF or 1
        self.b.write(CMD, bytes([self.seq, op, x & 0xFF, x >> 8, y, speed]))

    def glide(self, x, y, speed=3):
        """The pointer to x, y; returns when it is there (the time
        reckoned: no reads while recording)."""
        d = max(abs(x - self.x), abs(y - self.y), 1)
        k = 1 - 2.0 ** -speed
        frames = math.log(max(d, 2 ** speed) / 2 ** speed) / -math.log(k) + 2 ** speed + 4
        self._cmd(OP_GLIDE, x, y, speed)
        time.sleep(frames / 50.0 + 0.1)
        self.x, self.y = x, y

    def press(self):
        self._cmd(OP_PRESS)
        time.sleep(0.06)

    def release(self):
        self._cmd(OP_RELEASE)
        time.sleep(0.06)

    def click(self, x, y, hold=0.15, after=0.5):
        self.glide(x, y)
        self.press()
        time.sleep(hold)
        self.release()
        time.sleep(after)

    def double(self, x, y, after=0.8):
        self.glide(x, y)
        for _ in range(2):
            self.press()
            time.sleep(0.08)
            self.release()
            time.sleep(0.08)
        time.sleep(after)

    def drag(self, x0, y0, x1, y1, after=1.0):
        self.glide(x0, y0)
        self.press()
        time.sleep(0.4)
        self.glide(x1, y1, speed=4)
        time.sleep(0.3)
        self.release()
        time.sleep(after)

    def type(self, text, pause=0.12):
        names = []
        for ch in text:
            if ch.isalnum():
                names.append(ch.lower() if not ch.isupper() else ["left_shift", ch.lower()])
            elif ch in KEYNAMES:
                names.append(KEYNAMES[ch])
        for n in names:                          # (one at a time: a readable pace)
            self.b.keys([n])
            time.sleep(pause)
