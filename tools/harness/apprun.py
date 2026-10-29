#!/usr/bin/env python3
"""Run a GEOS application on GeoUltra in VICE and render the screen.

Usage: apprun.py NAME [--wait S] [--out PNG] [EVENT ...]

Drive A is the GEOS 2.0 oracle disk (GEOS_ORACLE), drive B an
applications disk (GEOS_APPS_DISK: a D64, D81 or DNP image, by its
extension, e.g. a GEOS disk with geoWrite and geoPaint; the user's own,
never committed); both are mounted through an
REU image as in the conformance harness. After the boot the application
NAME is started from drive B with GetFile; after --wait seconds the
events run in order, then the foreground screen (bitmap and colour
matrix, no sprites) is written to --out:

  x,y,-        move the pointer          x,y,p / x,y,r   press / release
  k:TEXT       type TEXT                 k:#13           one key code
  w:S          let it run S seconds

Keys arrive through keyVector from MainLoop (a one-shot appMain routine
in GeoUltra's information block, restoring the application's appMain).
"""
import argparse
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

APPS_DISK = os.environ.get("GEOS_APPS_DISK", os.path.expanduser(
    "~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))
REU_IMAGE = os.path.join(harness.OUT, "reu-apps.bin")
PORT = 6504
KEY_STUB = 0xC0A0               # unused bytes in GeoUltra's information block
PALETTE = [(0, 0, 0), (255, 255, 255), (136, 57, 50), (103, 182, 189), (139, 63, 150),
           (85, 160, 73), (64, 49, 141), (191, 206, 114), (139, 84, 41), (87, 66, 0),
           (184, 105, 98), (80, 80, 80), (120, 120, 120), (148, 224, 137), (120, 105, 196),
           (159, 159, 159)]


def reu_image():
    """Drive A: the oracle disk at bank 31; drive B: the apps disk at 40."""
    newest = max(os.path.getmtime(p) for p in (harness.ORACLE_DISK, APPS_DISK, __file__))
    if (os.path.exists(REU_IMAGE) and os.path.getmtime(REU_IMAGE) > newest
            and open(REU_IMAGE + ".src").read() == APPS_DISK):
        return
    open(REU_IMAGE + ".src", "w").write(APPS_DISK)
    reu = bytearray(16 << 20)
    reu[0x010100:0x010105] = b"GUMT\x01"
    for slot, (path, bank) in enumerate(((harness.ORACLE_DISK, 31), (APPS_DISK, 40))):
        image = open(path, "rb").read()
        ext = os.path.splitext(path)[1].lower()
        dtype, tracks = {".d81": (3, 0), ".dnp": (4, len(image) >> 16)}.get(ext, (1, 0))
        image = image[:{1: 683 * 256, 3: 3200 * 256, 4: len(image)}[dtype]]
        reu[0x010120 + 32 * slot:0x010124 + 32 * slot] = bytes([dtype, bank, tracks, 0])
        reu[bank << 16:(bank << 16) + len(image)] = image
    os.makedirs(harness.OUT, exist_ok=True)
    open(REU_IMAGE, "wb").write(reu)


def render(bitmap, colours, path):
    from PIL import Image
    im = Image.new("RGB", (320, 200))
    px = im.load()
    for cy in range(25):
        for cx in range(40):
            c = colours[cy * 40 + cx]
            fg, bg = PALETTE[c >> 4], PALETTE[c & 15]
            for row in range(8):
                byte = bitmap[cy * 320 + cx * 8 + row]
                for bit in range(8):
                    px[cx * 8 + bit, cy * 8 + row] = fg if byte & (0x80 >> bit) else bg
    im.resize((640, 400), Image.NEAREST).save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("name")
    ap.add_argument("--wait", type=float, default=8)
    ap.add_argument("--out", default=os.path.join(harness.OUT, "app.png"))
    ap.add_argument("--serial", help="serial number (hex) for GetSerialNumber, as "
                    "[system] serial= in SETTINGS.INI on the Ultimate")
    ap.add_argument("--bypass", action="store_true", help="serial number per "
                    "application, as [system] protection=bypass (src/kernal/bypass.s)")
    ap.add_argument("events", nargs="*")
    args = ap.parse_args()
    reu_image()
    cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
           "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
           "-cartcrt", os.path.join(harness.ROOT, "build", "geoultra64.crt"),
           "-reu", "-reusize", "16384", "-reuimage", REU_IMAGE, "+reuimagerw"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = Vice(port=PORT)
    try:
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)                  # stop at the top of MainLoop
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        table = harness.jumptab()

        def jsr(name):
            a = table[name]
            return [0x20, a & 0xFF, a >> 8]
        start = harness.TRAMPOLINE
        code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk")
                + [0xA9, 0x00, 0x85, 0x0E, 0xA9, 0x4F, 0x85, 0x0F, 0xA9, 0x00, 0x85, 0x02]
                + jsr("GetFile") + [0x8E, 0xF0, 0x02])
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]            # GetFile returned: X at $02F0
        v.mem_set(start, bytes(code))
        v.mem_set(0x4F00, args.name.encode() + b"\0")
        lbl = open(os.path.join(harness.ROOT, "build", "kernal64.lbl")).read()

        def label(name):
            return int(next(l.split()[1] for l in lbl.splitlines()
                            if l.endswith("." + name)), 16)
        if args.serial:
            serial = int(args.serial, 16)
            v.mem_set(label("serialNumber"), bytes([serial & 0xFF, serial >> 8]))
        if args.bypass:
            v.mem_set(label("bypassOn"), b"\x80")
        if os.environ.get("APPRUN_FILL"):   # memory before the start: hex addr,len,byte
            addr, n, b = (int(x, 16) for x in os.environ["APPRUN_FILL"].split(","))
            v.mem_set(addr, bytes([b]) * n)
        v.mem_set(0x02F0, b"\xEE")
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(args.wait)
        v.ping()
        for ev in args.events:
            if ev.startswith("k:"):
                text = ev[2:]
                for c in [int(text[1:])] if text.startswith("#") else [ord(ch) for ch in text]:
                    old = v.mem_get(0x849B, 0x849C)
                    stub = [0xA9, c, 0x8D, 0x04, 0x85,            # keyData
                            0xA9, old[0], 0x8D, 0x9B, 0x84,       # appMain back
                            0xA9, old[1], 0x8D, 0x9C, 0x84,
                            0x6C, 0xA3, 0x84]                     # jmp (keyVector)
                    v.mem_set(KEY_STUB, bytes(stub))
                    v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
                    v.resume()
                    time.sleep(0.25)
                    v.ping()
            elif ev.startswith("w:"):
                v.resume()
                time.sleep(float(ev[2:]))
                v.ping()
            else:
                x, y, button = ev.split(",")
                x, y = int(x), int(y)
                v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
                flag = v.mem_get(0x39, 0x39)[0] | 0x40
                if button != "-":
                    v.mem_set(0x8505, bytes([0x00 if button == "p" else 0x80]))
                    flag |= 0x20
                v.mem_set(0x39, bytes([flag]))
                v.resume()
                time.sleep(0.5)
                v.ping()
        v.resume()
        time.sleep(1)
        v.ping()
        print("GetFile returned: %s; trap: %s; PC $%04X" % (
            "no (application running)" if v.mem_get(0x2F0, 0x2F0)[0] == 0xEE
            else "X = $%02X" % v.mem_get(0x2F0, 0x2F0)[0],
            v.mem_get(0xC0F1, 0xC0F2).hex(), v.regs_get()["PC"]))
        render(v.mem_get(0xA000, 0xBF3F), v.mem_get(0x8C00, 0x8FE7), args.out)
        print("screen:", args.out)
    finally:
        v.quit()
        proc.kill()


if __name__ == "__main__":
    main()
