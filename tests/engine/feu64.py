"""Calling the file engine on GeoUltra on the Ultimate 64, for the U64
tests of tests/engine/ (docs/design/FILE_ENGINE.md, "Tests").

GeoUltra boots from the U64's flash (the cartridge in /Flash/carts,
REU and Command Interface on; MOUNTS.INI points at the test copies in
/USB0/GEOULTRA/test, never at the user's own images). Each call is a
small program written to C64 memory and run by MainLoop through appMain:
it switches appMain off, loads r0-r3, calls FileEngine and leaves X, A,
r0-r4 and a done flag where the REST interface reads them.
"""
import atexit
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUB, PATH, PATH2, BUF, RES, DONE = 0x5000, 0x5E00, 0x5F00, 0x5200, 0x50E0, 0x50FF
APP_MAIN = 0x849B
FILE_ENGINE = 6                     # extension table entry


def env_ip():
    for line in open(os.path.join(ROOT, ".env")):
        key, _, value = line.partition("=")
        if key.strip() == "ULTIP1":
            return value.strip()
    raise SystemExit("no ULTIP1 in .env")


class U64:
    def __init__(self):
        self.ip = env_ip()
        self.rest = "http://%s/v1" % self.ip
        labels = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            parts = line.split()
            labels[parts[2].lstrip(".")] = int(parts[1], 16)
        self.ext = labels["ExtTable"]

    def _req(self, method, url, data=None):
        """A REST request; tried again after a timeout (the Ultimate's REST
        server sometimes stalls for a while under many requests)."""
        for attempt in range(4):
            req = urllib.request.Request(url, data=data, method=method)
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    return r.read()
            except (OSError, urllib.error.URLError):
                if attempt == 3:
                    raise
                time.sleep(10)

    def read(self, addr, n):
        return self._req("GET", "%s/machine:readmem?address=%04X&length=%d" % (self.rest, addr, n))

    def write(self, addr, data):
        self._req("POST", "%s/machine:writemem?address=%04X" % (self.rest, addr), bytes(data))

    def ftp_get(self, path, dest):
        subprocess.run(["curl", "-s", "-o", dest, "ftp://%s%s" % (self.ip, path)], check=True)

    def ftp_put(self, src, path):
        subprocess.run(["curl", "-s", "-T", src, "ftp://%s%s" % (self.ip, path)], check=True)

    CART = "/configs/C64%20and%20Cartridge%20Settings/Cartridge"

    def boot(self, crt=None):
        """The cartridge into flash (when given) and a reboot; back at
        the banner (MainLoop running). With crt the Ultimate's Cartridge
        setting is set to that flash copy for the test (the user's is
        empty: the user runs the .crt from the file browser) and the
        user's setting is put back when the test ends."""
        if crt:
            self.ftp_put(crt, "/Flash/carts/geoultra64.crt")
            self.cart_hold()
        self._req("PUT", self.rest + "/machine:reboot")
        time.sleep(15)

    def cart_hold(self):
        """The Cartridge setting geoultra64.crt until the test ends (once)."""
        if getattr(self, "cart_kept", None) is not None:
            return
        got = json.loads(self._req("GET", self.rest + self.CART))
        self.cart_kept = got["C64 and Cartridge Settings"]["Cartridge"]["current"]
        if self.cart_kept != "geoultra64.crt":
            self._req("PUT", self.rest + self.CART + "?value=geoultra64.crt")
            atexit.register(self.cart_back)

    def cart_back(self):
        """The user's Cartridge setting again (not saved to flash: it is
        the setting of the session)."""
        self._req("PUT", self.rest + self.CART + "?value=" + urllib.parse.quote(self.cart_kept))

    def text(self, addr, s):
        self.write(addr, s.encode("latin1") + b"\0")

    def fe(self, func, r0=None, r1=None, r2=None, r3=None, y=0, s0=None, s1=None, timeout=60):
        """One engine call; returns X, A, r0-r4 as words."""
        if s0 is not None:
            self.text(PATH, s0)
            r0 = PATH
        if s1 is not None:
            self.text(PATH2, s1)
            r1 = PATH2
        if func == 1 and r2 is None:                # FE_STAT: no long name wanted
            r2 = 0
        if func == 3 and r3 is None:                # FE_READDIR: no short name wanted
            r3 = 0
        if func in (5, 6):                          # FE_COPY, FE_MOVE
            r2 = 0 if r2 is None else r2
            r3 = 0 if r3 is None else r3
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8,
                0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8]
        for value, zp in ((r0, 0x02), (r1, 0x04), (r2, 0x06), (r3, 0x08)):
            if value is not None:
                code += [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]
        call = self.ext + 5 * FILE_ENGINE
        code += [0xA9, func, 0xA0, y, 0x20, call & 0xFF, call >> 8]
        code += [0x8E, RES & 0xFF, RES >> 8, 0x8D, (RES + 1) & 0xFF, RES >> 8]
        for i in range(10):
            code += [0xA5, 0x02 + i, 0x8D, (RES + 2 + i) & 0xFF, RES >> 8]
        code += [0xA9, 0x01, 0x8D, DONE & 0xFF, DONE >> 8, 0x60]
        assert len(code) < RES - STUB
        self.write(STUB, code)
        self.write(DONE, [0])
        self.write(APP_MAIN, [STUB & 0xFF, STUB >> 8])
        end = time.time() + timeout
        while self.read(DONE, 1)[0] != 1:
            if time.time() > end:
                raise TimeoutError("FileEngine %d did not return" % func)
            time.sleep(0.2)
        r = self.read(RES, 12)
        return r[0], r[1], [r[2 + 2 * i] | r[3 + 2 * i] << 8 for i in range(5)]

    # --- raw UCI commands (tests/engine/uciprobe.s, built to build/uciprobe.bin)

    PROBE, P_CMD, P_LEN, P_DATALEN, P_PACKETS, P_DONE, P_STAT, P_DATA = (
        0x5300, 0x5500, 0x5580, 0x5583, 0x5585, 0x5586, 0x55C0, 0x5600)

    def uci(self, cmd, timeout=30):
        """One UCI command (bytes, the target first); returns (status,
        data, packets)."""
        if not getattr(self, "_probe", False):
            self.write(self.PROBE, open(os.path.join(ROOT, "build", "uciprobe.bin"), "rb").read())
            self._probe = True
        cmd = bytes(cmd)
        self.write(self.P_CMD, cmd)
        self.write(self.P_LEN, [len(cmd)])
        self.write(self.P_PACKETS, [0, 0])
        self.write(APP_MAIN, [self.PROBE & 0xFF, self.PROBE >> 8])
        end = time.time() + timeout
        while self.read(self.P_DONE, 1)[0] != 1:
            if time.time() > end:
                raise TimeoutError("UCI command %s did not finish" % cmd[:2].hex())
            time.sleep(0.2)
        n = self.read(self.P_DATALEN, 3)
        length = (n[0] | n[1] << 8) - self.P_DATA
        status = self.read(self.P_STAT, 64).split(b"\0")[0].decode("latin1")
        data = self.read(self.P_DATA, length) if length > 0 else b""
        return status, data, n[2]
