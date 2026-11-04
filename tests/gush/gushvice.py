"""gush in VICE, for tests/gush/*.py (docs/GUSH.md, "Tests").

GeoUltra boots with drive A the GEOS 2.0 disk (GEOS_ORACLE, only read) and
drive B a D81 made for the test with gush on it (from build/gush/gush.cvt,
written by VICE's c1541), plus what the test puts there. gush is started
from drive B with GetFile, keys go to it through keyVector (a one-shot
appMain routine, as tools/harness/apprun.py does), and its screen is read
from its text shadow (build/gush/gush.lbl) or rendered as a PNG.
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "gush")
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")
COLS, ROWS_TEXT = 53, 24
KEY_STUB = 0xC0A0               # unused bytes in GeoUltra's information block
NAME = 0x4F00


def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "gush", "gush.lbl")):
        parts = line.split()
        out[parts[2].lstrip(".")] = int(parts[1], 16)
    return out


class Gush:
    def __init__(self, name, port, files=()):
        """A D81 with gush and FILES (paths of .cvt or plain files)."""
        os.makedirs(OUT, exist_ok=True)
        self.ok = True
        disk = os.path.join(OUT, name + ".d81")
        if os.path.exists(disk):
            os.remove(disk)
        cmd = [C1541, "-format", "gush test,gt", "d81", disk,
               "-geoswrite", os.path.join(ROOT, "build", "gush", "gush.cvt")]
        for f in files:
            cmd += ["-geoswrite" if f.endswith(".cvt") else "-write", f]
        subprocess.run(cmd, capture_output=True, check=True)
        self.disk = disk
        apprun.APPS_DISK = disk
        apprun.REU_IMAGE = os.path.join(OUT, "reu-%s.bin" % name)
        if os.path.exists(apprun.REU_IMAGE):
            os.remove(apprun.REU_IMAGE)
        apprun.reu_image()
        self.lbl = labels()
        cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
               "-binarymonitoraddress", "127.0.0.1:%d" % port,
               "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
               "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "-reuimagerw"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.v = Vice(port=port)

    def start(self, wait=4):
        """Up to MainLoop, then gush from drive B."""
        v = self.v
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        t = harness.jumptab()

        def jsr(name):
            return [0x20, t[name] & 0xFF, t[name] >> 8]
        start = harness.TRAMPOLINE
        code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
                + [0xA9, NAME & 0xFF, 0x85, 0x0E, 0xA9, NAME >> 8, 0x85, 0x0F, 0xA9, 0x00, 0x85, 0x02]
                + jsr("GetFile") + [0x8E, 0xF0, 0x02])
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(start, bytes(code))
        v.mem_set(NAME, b"gush\0")
        v.mem_set(0x02F0, b"\xEE")
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(wait)
        v.ping()

    def runsys(self, name, wait=5):
        """Up to MainLoop, then FE_RUNSYS NAME (an application on drive E);
        returns X when it came back (an error), None when it did not."""
        v = self.v
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        k = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            parts = line.split()
            k[parts[2].lstrip(".")] = int(parts[1], 16)
        fe = k["ExtTable"] + 30
        start = harness.TRAMPOLINE
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, NAME & 0xFF, 0x85, 0x02, 0xA9, NAME >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF0, 0x02]
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(start, bytes(code))
        v.mem_set(NAME, name.encode("latin1") + b"\0")
        v.mem_set(0x02F0, b"\xEE")
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(wait)
        v.ping()
        x = v.mem_get(0x02F0, 0x02F0)[0]
        return None if x == 0xEE else x

    def keys(self, text, settle=0.25):
        """Keys to gush (a str; "\\r" is RETURN; or a list of codes)."""
        v = self.v
        codes = [ord(c) for c in text] if isinstance(text, str) else text
        for c in codes:
            old = v.mem_get(0x849B, 0x849C)
            for _ in range(40):             # the previous key taken first
                if (old[0] | old[1] << 8) != KEY_STUB:
                    break
                v.resume()
                time.sleep(0.25)
                v.ping()
                old = v.mem_get(0x849B, 0x849C)
            stub = [0xA9, c, 0x8D, 0x04, 0x85,            # keyData
                    0xA9, old[0], 0x8D, 0x9B, 0x84,       # appMain back
                    0xA9, old[1], 0x8D, 0x9C, 0x84,
                    0x6C, 0xA3, 0x84]                     # jmp (keyVector)
            v.mem_set(KEY_STUB, bytes(stub))
            v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            v.resume()
            time.sleep(settle)
            v.ping()

    def queue(self, text, settle=1.0):
        """Keys into GEOS's key queue (a command's question reads them with
        GetNextChar; idle, MainLoop hands them to keyVector)."""
        k = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            parts = line.split()
            k[parts[2].lstrip(".")] = int(parts[1], 16)
        v = self.v
        for c in ([ord(ch) for ch in text] if isinstance(text, str) else text):
            head = v.mem_get(k["qHead"], k["qHead"])[0]
            v.mem_set(k["keyQueue"] + head, bytes([c]))
            v.mem_set(k["qHead"], bytes([(head + 1) & 15]))
            flag = v.mem_get(0x39, 0x39)[0] | 0x80
            v.mem_set(0x39, bytes([flag]))
            v.resume()
            time.sleep(0.3)
            v.ping()
        v.resume()
        time.sleep(settle)
        v.ping()

    def run(self, line, settle=1.0):
        """A command line typed and RETURN; then a pause."""
        self.keys(line + "\r")
        self.v.resume()
        time.sleep(settle)
        self.v.ping()

    def click(self, x, y, settle=2.0):
        """A mouse click at x, y (pointer moved, pressed, released)."""
        v = self.v
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        for data in (0x00, 0x80):
            v.mem_set(0x8505, bytes([data]))
            v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
            v.resume()
            time.sleep(0.5)
            v.ping()
        v.resume()
        time.sleep(settle)
        v.ping()

    def screen(self):
        """Rows 1-24 from the shadow, right spaces off."""
        s = self.lbl["shadow"]
        data = self.v.mem_get(s, s + COLS * ROWS_TEXT - 1)
        return [data[r * COLS:(r + 1) * COLS].decode("latin1").rstrip() for r in range(ROWS_TEXT)]

    def lines(self):
        """The screen's text lines, without the empty ones at the end."""
        rows = self.screen()
        while rows and not rows[-1]:
            rows.pop()
        return rows

    def png(self, name):
        path = os.path.join(OUT, name + ".png")
        apprun.render(self.v.mem_get(0xA000, 0xBF3F), self.v.mem_get(0x8C00, 0x8FE7), path)
        return path

    def check(self, title, got, want):
        good = got == want
        self.ok = self.ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    def stop(self):
        try:
            self.v.quit()
        finally:
            self.proc.wait(timeout=30)
