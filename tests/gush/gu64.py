#!/usr/bin/env python3
"""gush on the Ultimate 64 (docs/design/GUSH.md, "Tests").

Before the reboot gush (and geoFolder) are copied onto drive A's test
copy (/USB0/GEOULTRA/test/GEOS64.D81, mounted on A; never the user's own
image) through GeoUltra (FTP into a scratch folder, then FE_COPY: never
an edit of the mounted image behind GeoUltra's back), then GeoUltra boots from the U64's flash with the
cartridge given, gush starts from drive A (GetFile through appMain), and
its commands run on the Ultimate's file system in
/USB0/GEOULTRA/test/gush (made and removed by the test): ls, cd, pwd,
mkdir, cp both ways (asked before overwriting), mv, rm, cat, wildcards,
long names, cp -r both ways; then a desk accessory (geoFolder) started
and closed, gush's screen back, and its gush button (a fresh gush).
Usage: tests/gush/gu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, HERE)
from feu64 import U64, env_ip  # noqa: E402
from gushvice import labels, COLS, ROWS_TEXT, OUT  # noqa: E402

KEY_STUB = 0xC0A0
CVTS = "/USB0/GEOULTRA/test/gu64cvt"         # (made and removed here)
USER_FILES = ("HIBERNAT.BIN", "gush_history")
HOME = "/usb0/geoultra/test/gush"


class GushU64:
    def __init__(self, crt):
        self.u = U64()
        self.ok = True
        self.lbl = labels()
        os.makedirs(OUT, exist_ok=True)
        # Old copies out and the new ones in through GeoUltra itself
        # (drive A's image is mounted: edited by FTP and c1541 behind its
        # back, the REU copy written back over it, which once damaged
        # geoFolder on it): the CVTs put in a scratch folder by FTP and
        # copied onto /a by FE_COPY; written back, then a fresh boot.
        self.settle()
        self.u.boot(crt)
        for name in ("/a/gush", "/a/geoFolder"):
            while self.u.fe(7, s0=name)[0] == 0:            # FE_DELETE
                pass
        subprocess.run(["curl", "-s", "--ftp-create-dirs", "-T",
                        os.path.join(ROOT, "build", "gush", "gush.cvt"),
                        "ftp://%s%s/" % (self.u.ip, CVTS)], check=True)
        subprocess.run(["curl", "-s", "-T", os.path.join(ROOT, "build", "tools", "geofolder.cvt"),
                        "ftp://%s%s/" % (self.u.ip, CVTS)], check=True)
        for cvt, name in (("gush.cvt", "gush"), ("geofolder.cvt", "geoFolder")):
            x = self.u.fe(5, s0="%s/%s" % (CVTS.lower(), cvt), s1="/a/" + name, timeout=300)[0]
            if x:
                raise RuntimeError("FE_COPY %s onto /a: error %d" % (cvt, x))
        for cvt in ("gush.cvt", "geofolder.cvt"):
            subprocess.run(["curl", "-s", "-Q", "DELE %s/%s" % (CVTS, cvt),
                            "ftp://%s/" % self.u.ip], capture_output=True)
        subprocess.run(["curl", "-s", "-Q", "RMD %s" % CVTS, "ftp://%s/" % self.u.ip], capture_output=True)
        time.sleep(4)
        self.settle()
        self.u.boot(crt)

    def settle(self):
        """Wait until the running session has written its drives back
        (wbPending 0 three times in a row; a write-back runs a few seconds
        after the last write). A reset would not do: the cold start keeps
        a drive with unsaved changes in the REU and writes it back later."""
        k = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            p = line.split()
            k[p[2].lstrip(".")] = int(p[1], 16)
        clean, end = 0, time.time() + 120
        while clean < 3 and time.time() < end:
            clean = clean + 1 if self.u.read(k["wbPending"], 1)[0] == 0 else 0
            time.sleep(2)

    def start(self):
        """gush from drive A: SetDevice, OpenDisk, GetFile through appMain."""
        jt = {"SetDevice": 0xC2B0, "OpenDisk": 0xC2A1, "GetFile": 0xC208}
        name = 0x5100
        code = [0xA9, 0x00, 0x8D, 0x9B, 0x84, 0x8D, 0x9C, 0x84,      # appMain off
                0xA9, 0x08, 0x20] + [jt["SetDevice"] & 0xFF, jt["SetDevice"] >> 8]
        code += [0x20, jt["OpenDisk"] & 0xFF, jt["OpenDisk"] >> 8]
        code += [0xA9, name & 0xFF, 0x85, 0x0E, 0xA9, name >> 8, 0x85, 0x0F, 0xA9, 0x00, 0x85, 0x02]
        code += [0x20, jt["GetFile"] & 0xFF, jt["GetFile"] >> 8, 0x60]
        self.u.write(name, b"gush\0")
        self.u.write(0x5000, bytes(code))
        self.u.write(0x849B, b"\x00\x50")
        time.sleep(6)

    def keys(self, text, settle=0.4):
        u = self.u
        for c in ([ord(ch) for ch in text] if isinstance(text, str) else text):
            end = time.time() + 60          # the previous key taken first
            while True:
                old = u.read(0x849B, 2)
                if (old[0] | old[1] << 8) != KEY_STUB or time.time() > end:
                    break
                time.sleep(0.2)
            stub = [0xA9, c, 0x8D, 0x04, 0x85, 0xA9, old[0], 0x8D, 0x9B, 0x84,
                    0xA9, old[1], 0x8D, 0x9C, 0x84, 0x6C, 0xA3, 0x84]
            u.write(KEY_STUB, bytes(stub))
            u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            time.sleep(settle)

    def queue(self, text, settle=1.5):
        k = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            p = line.split()
            k[p[2].lstrip(".")] = int(p[1], 16)
        for c in text:
            head = self.u.read(k["qHead"], 1)[0]
            self.u.write(k["keyQueue"] + head, [ord(c)])
            self.u.write(k["qHead"], [(head + 1) & 15])
            self.u.write(0x39, [self.u.read(0x39, 1)[0] | 0x80])
            time.sleep(0.4)
        time.sleep(settle)

    def run(self, line, settle=2.0):
        self.keys(line + "\r")
        time.sleep(settle)

    def lines(self):
        s = self.lbl["shadow"]
        data = self.u.read(s, COLS * ROWS_TEXT)
        rows = [data[r * COLS:(r + 1) * COLS].decode("latin1").rstrip() for r in range(ROWS_TEXT)]
        while rows and not rows[-1]:
            rows.pop()
        return rows

    def out(self, line, settle=2.0):
        """The line before the next prompt, after running LINE."""
        self.run(line, settle)
        return self.lines()[-2]

    def check(self, title, got, want):
        good = got == want
        self.ok = self.ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))


def mounts(g):
    """mount, umount (gush): MOUNTS.INI saved first and put back."""
    check, out = g.check, g.out
    ini = os.path.join(OUT, "gu64-mounts.ini")
    g.u.ftp_get("/USB0/GEOULTRA/MOUNTS.INI", ini)
    try:
        g.run("mount")
        drives = [(l[0].lower(), l[2:]) for l in open(ini, "rb").read().decode("latin1").split("\r\n")
                  if len(l) > 2 and l[1] == "="]
        listed = [(l.split()[0][1:], l.split()[-1]) for l in g.lines()[-1 - len(drives):-1]]
        check("mount: the drives' images (as MOUNTS.INI has them)", listed, drives)
        g.run("mount /usb0/geoultra/test/geopub.d64 /d", settle=8)
        g.run("ls /d", settle=3)
        check("mount an image into /d, ls /d", "GEOPUBLISH" in " ".join(g.lines()[-6:]), True)
        g.run("cd /d")
        g.run("umount /d", settle=8)
        check("umount /d: out of it, back at /", (out("pwd"), out("ls /d")),
              ("/", "gush: ls: /d: no such drive"))
        check("umount /a (gush's own drive)", out("umount /a"), "gush: umount: /a: gush runs from there")
        check("mount with one word", out("mount x"), "gush: mount: wrong words (see help)")
        g.run("mkimg d81 /usb0/geoultra/test/gumk", settle=8)          # ".d81" added
        g.run("mount /usb0/geoultra/test/gumk.d81 /d", settle=8)
        check("mkimg d81, mounted: empty", out("df /d"), "3160 blocks free of 3160 blocks")
        g.run("umount /d", settle=8)
        g.run("rm -f /usb0/geoultra/test/gumk.d81")
        g.run("mkimg -t 2 dnp /usb0/geoultra/test/gumk", settle=8)   # (the sweep's find)
        check("mkimg -t 2 dnp", out("ls /usb0/geoultra/test/gumk*", settle=3), "/usb0/geoultra/test/gumk.dnp")
        g.run("rm -f /usb0/geoultra/test/gumk.dnp")
        import ftplib
        f = ftplib.FTP(g.u.ip)
        f.login()
        check("and removed", [n for n, _ in f.mlsd("/USB0/GEOULTRA/test") if "gumk" in n.lower()], [])
    finally:
        g.u.ftp_put(ini, "/USB0/GEOULTRA/MOUNTS.INI")


def system(g):
    """turbo, turbo -s, date (gush): SETTINGS.INI as it was after
    (none on the test stick: removed again); the clock set to the time it
    shows, so it moves by a second or two at most."""
    import ftplib
    import io
    check, out = g.check, g.out
    f = ftplib.FTP(g.u.ip)
    f.login()
    names = [n for n, _ in f.mlsd("/USB0/GEOULTRA")]
    before = None
    if "SETTINGS.INI" in names:
        b = io.BytesIO()
        f.retrbinary("RETR /USB0/GEOULTRA/SETTINGS.INI", b.write)
        before = b.getvalue()
    try:
        g.run("turbo")
        check("turbo: step 15 (full speed at boot)", g.lines()[-3:-1],
              ["turbo: step 15 of 15", "48 MHz (U64, Elite I), 64 MHz (Elite II, C64U)"])
        g.run("turbo 12")
        check("turbo 12", g.lines()[-3], "turbo: step 12 of 15")
        g.run("turbo -s 15", settle=4)
        b = io.BytesIO()
        f.retrbinary("RETR /USB0/GEOULTRA/SETTINGS.INI", b.write)
        want = (before or b"") + (b"" if before and b"[system]" in before.lower() else b"[system]\r\n") + b"turbo=15\r\n"
        check("turbo -s 15: SETTINGS.INI", b.getvalue() if before is None else b.getvalue().count(b"turbo=15"),
              want if before is None else 1)
        for old, new in ((b"[time]\r\nx=1", b"[time]\r\nx=1\r\n[system]\r\nturbo=15\r\n"),
                         (b"[system]", b"[system]\r\nturbo=15\r\n")):   # (no line end at the end)
            f.storbinary("STOR /USB0/GEOULTRA/SETTINGS.INI", io.BytesIO(old))
            g.run("turbo -s 15", settle=4)
            b = io.BytesIO()
            f.retrbinary("RETR /USB0/GEOULTRA/SETTINGS.INI", b.write)
            check("turbo -s on %r" % old, b.getvalue(), new)
        now = out("date")
        import datetime                             # ntp: SETTINGS.INI [time] with
        utc = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)   # the clock's
        clock = datetime.datetime.strptime(now, "%Y-%m-%d %H:%M:%S")                # own offset,
        off = round((clock - utc).total_seconds() / 900) * 900                     # so it stays
        f.storbinary("STOR /USB0/GEOULTRA/SETTINGS.INI",
                     io.BytesIO(b"[time]\r\nntp=pool.ntp.org\r\noffset=%d\r\n" % off))
        for attempt in range(3):                    # (a server may not answer once)
            g.run("ntp", settle=8)
            if not g.lines()[-2].startswith("gush:"):
                break
        try:
            got = datetime.datetime.strptime(g.lines()[-2], "%Y-%m-%d %H:%M:%S")
            want = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(seconds=off)
            good = abs((got - want).total_seconds()) < 60
        except ValueError:
            good = g.lines()[-2]
        check("ntp (offset %d s): the clock within a minute of UTC + offset" % off, good, True)
        now = out("date")
        g.run("date " + now, settle=3)
        shown = " ".join(g.lines()[-4:-1])
        check("date set to what it shows (%s)" % now, now[:16] in shown or "clock setting off" in shown, True)
    finally:
        if before is None:
            f.delete("/USB0/GEOULTRA/SETTINGS.INI")
        else:
            f.storbinary("STOR /USB0/GEOULTRA/SETTINGS.INI", io.BytesIO(before))
        f.quit()


def ntp_try(g, ini, off):
    """SETTINGS.INI = INI, ntp run (up to three times: a server may not
    answer once): True when the clock is then within a minute of UTC +
    OFF, else what gush showed."""
    import datetime
    import ftplib
    import io
    f = ftplib.FTP(g.u.ip)
    f.login()
    f.storbinary("STOR /USB0/GEOULTRA/SETTINGS.INI", io.BytesIO(ini))
    f.quit()
    for attempt in range(3):
        g.run("ntp", settle=8)
        if not g.lines()[-2].startswith("gush:"):
            break
    try:
        got = datetime.datetime.strptime(g.lines()[-2], "%Y-%m-%d %H:%M:%S")
        want = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(seconds=off)
        return abs((got - want).total_seconds()) < 60
    except ValueError:
        return g.lines()[-2]


def ntp_long(g):
    """ntp with SETTINGS.INI read in parts (enginentp.s, modules 77 and 79;
    2026-11-14, before only its first 511 bytes): a file over 1 KB with
    [time]'s ntp= line across the first part's end and offset= two parts
    on, and one of exactly 511 bytes (the read after it finds the file's
    end). The offsets an hour apart from the clock's own, so a lost
    offset= shows; the clock's own offset back at the end. SETTINGS.INI as
    it was after (none: removed again)."""
    import datetime
    import ftplib
    import io
    check = g.check
    f = ftplib.FTP(g.u.ip)
    f.login()
    names = [n for n, _ in f.mlsd("/USB0/GEOULTRA")]
    before = None
    if "SETTINGS.INI" in names:
        b = io.BytesIO()
        f.retrbinary("RETR /USB0/GEOULTRA/SETTINGS.INI", b.write)
        before = b.getvalue()
    f.quit()
    try:
        now = g.out("date")
        utc = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        clock = datetime.datetime.strptime(now, "%Y-%m-%d %H:%M:%S")
        off = round((clock - utc).total_seconds() / 900) * 900
        ntp = b"ntp=pool.ntp.org\r\n"
        head = b"[desktop]\r\n"
        fill = 511 - 6 - len(head) - len(b"[time]\r\n") - len(b"note=\r\n")
        ini = head + b"note=" + b"a" * fill + b"\r\n" + b"[time]\r\n" + ntp
        check("long SETTINGS.INI: ntp= across byte 511", ini.index(ntp) < 511 < ini.index(ntp) + len(ntp), True)
        n = 0
        while len(ini) < 1100:
            ini += b"pad%02d=a line the module skips\r\n" % n
            n += 1
        ini += b"offset=%d\r\n" % (off + 3600)
        check("long SETTINGS.INI (%d bytes): ntp and offset= found" % len(ini), ntp_try(g, ini, off + 3600), True)
        ini = b"[time]\r\n" + ntp
        last = b"offset=%d\r\n" % (off - 3600)
        ini += b"note=" + b"b" * (511 - len(ini) - len(last) - len(b"note=\r\n")) + b"\r\n" + last
        check("SETTINGS.INI of exactly 511 bytes", (len(ini), ntp_try(g, ini, off - 3600)), (511, True))
        check("the clock's own offset again", ntp_try(g, b"[time]\r\n" + ntp + b"offset=%d\r\n" % off, off), True)
    finally:
        f = ftplib.FTP(g.u.ip)
        f.login()
        if before is None:
            f.delete("/USB0/GEOULTRA/SETTINGS.INI")
        else:
            f.storbinary("STOR /USB0/GEOULTRA/SETTINGS.INI", io.BytesIO(before))
        f.quit()


def main():
    """The user's HIBERNAT.BIN and gush_history set aside first (the test
    reboots, which would resume or use them, and writes a history) and
    put back at the end, whatever happens."""
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    ftp = ftplib.FTP(env_ip())
    ftp.login()
    kept = {}
    for name in USER_FILES:
        data = io.BytesIO()
        try:
            ftp.retrbinary("RETR /USB0/GEOULTRA/" + name, data.write)
            kept[name] = data.getvalue()
            ftp.delete("/USB0/GEOULTRA/" + name)
        except ftplib.error_perm:
            pass
    ftp.quit()
    try:
        ok = run(crt)
    finally:
        ftp = ftplib.FTP(env_ip())
        ftp.login()
        for name in USER_FILES:
            try:
                ftp.delete("/USB0/GEOULTRA/" + name)
            except ftplib.error_perm:
                pass
            if name in kept:
                ftp.storbinary("STOR /USB0/GEOULTRA/" + name, io.BytesIO(kept[name]))
        ftp.quit()
    sys.exit(0 if ok else 1)


def run(crt):
    g = GushU64(crt)
    check, out = g.check, g.out
    g.start()
    rows = g.lines()
    check("gush started on the U64", rows[0].startswith("gush, the GeoUltra shell") if rows else rows, True)
    check("HOME and PATH", (out("echo $HOME"), out("echo $PATH")),
          ("/USB0/GEOULTRA", "/e/bin:/USB0/GEOULTRA/bin"))
    g.run("rm -f /a/INI '/a/A long name for the copy on the stick'")   # (left over)
    g.run("rm -f %s/*" % HOME)
    g.run("rmdir " + HOME)
    check("mkdir on the Ultimate", out("mkdir " + HOME), "$ mkdir " + HOME)
    g.run("cd " + HOME)
    check("cd, pwd", out("pwd"), HOME)
    g.run("cp /usb0/geoultra/MOUNTS.INI /a/INI")    # (the user's file only read)
    last = [l for l in mounts_ini().split("\r\n") if l][-1]
    check("cp from the stick onto drive A, cat (its last line)", out("cat /a/INI", settle=3), last)
    g.run("cp /a/INI ini.txt")
    check("cp back onto the stick, ls", out("ls"), "ini.txt")
    check("cat on the stick", out("cat ini.txt", settle=3), last)
    g.run("echo redirected > r.txt", settle=3)     # (> on the stick)
    g.run("cat < r.txt", settle=3)
    check("> and < on the stick", g.lines()[-2], "redirected")
    g.run("cat r.txt | cat", settle=3)             # (a pipe)
    check("a pipe from the stick", g.lines()[-2], "redirected")
    g.run("a:")                                     # (drive switch: usb0: back here)
    check("usb0: back in the folder on the stick", out("usb0:; pwd"), HOME)
    g.keys("cat r.t")                               # (completion)
    g.keys([20], settle=4)                          # (KEY_LARROW)
    check("completion on the stick", g.lines()[-1].rstrip(), "$ cat r.txt")
    g.keys("\r", settle=3)
    import ftplib
    ftp = ftplib.FTP(g.u.ip)                          # (a module as CVT)
    ftp.login()
    with open(os.path.join(ROOT, "build", "cmds", "wc.cvt"), "rb") as f:
        ftp.storbinary("STOR /USB0/GEOULTRA/test/gush/wc.cvt", f)
    g.run("wc r.txt", settle=6)
    check("an external command on the stick (wc.cvt)", g.lines()[-2].split(), ["1", "1", "11", "r.txt"])
    ftp.delete("/USB0/GEOULTRA/test/gush/wc.cvt")
    ftp.quit()
    g.run("ifconfig", settle=4)                     # (the network)
    rows = g.lines()[-5:-1]
    check("ifconfig: the U64's own address", rows[0], "address  " + g.u.ip)
    ntp_long(g)
    check("ifconfig: netmask, gateway, mac", [r.split()[0] for r in rows], ["address", "netmask", "gateway", "mac"])
    g.run("wget http://example.com/", settle=20)
    got = g.lines()[-2]
    check("wget http://example.com/: index.html", got.startswith("index.html: ") and got.endswith(" bytes"), True)
    g.run("wget -O ex.htm http://example.com/", settle=20)
    check("wget -O", g.lines()[-2].startswith("ex.htm: "), True)
    g.run("wget http://example.com/gush-nope", settle=20)
    check("wget of a missing page: its status", g.lines()[-2].startswith("gush: wget: HTTP/1.") and " 404" in g.lines()[-2],
          True)
    import io
    ftp = ftplib.FTP(g.u.ip)
    ftp.login()
    page = io.BytesIO()
    ftp.retrbinary("RETR /USB0/GEOULTRA/test/gush/index.html", page.write)
    check("wget: the page as served", b"Example Domain" in page.getvalue() and page.getvalue().rstrip().endswith(b"</html>"),
          True)
    for f in ("index.html", "ex.htm", "gush-nope"):
        try:
            ftp.delete("/USB0/GEOULTRA/test/gush/" + f)
        except ftplib.error_perm:
            pass
    ftp.quit()
    g.run("rm -f r.txt")
    g.run("cp /a/INI ini.txt", settle=3)
    check("cp onto a file asks", g.lines()[-1], "gush: cp: overwrite /a/INI? (y/n/a)")
    g.queue("n")
    g.run("cp /a/INI 'A long name for the copy on the stick'")
    g.run("ls")
    check("a long name on the Ultimate", sorted(g.lines()[-2].split("  ")),
          ["A long name for the copy on the stick", "ini.txt"])
    g.run("cp 'A long name for the copy on the stick' /a/", settle=4)
    check("back onto drive A with its long name", out("ls /a/A\\ long\\ name*"),
          "/a/A long name for the copy on the stick")
    g.run("cp /a/GEOS .", settle=4)                  # CVT, and -R raw
    check("cp of a GEOS file onto the Ultimate: a .cvt", out("ls GEOS*"), "GEOS.cvt")
    g.run("cp -R /a/GEOS geos.raw", settle=4)
    check("cp -R: raw, no .cvt", out("ls *.raw"), "geos.raw")
    g.run("rm -f GEOS.cvt geos.raw")
    g.run("mkdir -t 3 /a/TREE")                      # cp -r both ways
    g.run("cp /a/INI /a/TREE")
    g.run("cp -r /a/TREE .", settle=4)
    check("cp -r a 1581 partition onto the Ultimate", out("ls TREE"), "INI")
    g.run("cp -r TREE /a/TREE2", settle=4)
    check("cp -r an Ultimate folder onto drive A", out("ls /a/TREE2"), "INI")
    g.run("rm -f /a/TREE/* /a/TREE2/* TREE/*")
    g.run("rmdir /a/TREE /a/TREE2 TREE")
    g.run("rm -f '/a/A long name for the copy on the stick' /a/INI")
    g.run("mv ini.txt moved")
    check("mv on the Ultimate", out("ls m*"), "moved")
    g.run("rm -f *")
    g.run("cd /")
    g.run("rmdir " + HOME)
    g.run("ls /usb0/geoultra/test/gu*")
    check("cleaned up", "".join(g.lines()[-3:-1]).endswith("no such file or folder"), True)
    mounts(g)
    system(g)
    g.run("cd /a")
    g.run("geoFolder", settle=4)
    # geoFolder's dialog: OK (a click on its icon, at 224,90) closes it;
    # gush redraws its screen.
    u = g.u
    u.write(0x3A, bytes([224, 0, 90]))                # the pointer onto OK
    time.sleep(0.5)
    u.write(0x8505, b"\x00")                          # pressed, released
    u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
    time.sleep(1)
    u.write(0x8505, b"\x80")
    u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
    time.sleep(3)
    check("after geoFolder: gush's prompt again", g.lines()[-1], "$")
    g.run("geoFolder /a/INI")                        # (in VICE no DA by name)
    check("a desk accessory with a document", "".join(g.lines()[-3:-1]),   # (two lines)
          "gush: geoFolder: /a/INI: a desk accessory takes no document")
    import ftplib
    import io
    ftp = ftplib.FTP(u.ip)                          # gushrc for the fresh gush
    ftp.login()
    ftp.storbinary("STOR /USB0/GEOULTRA/gushrc", io.BytesIO(b"# gu64\rG='from gushrc'\r"))
    g.run("geoFolder", settle=4)                     # its gush button
    u.write(0x3A, bytes([224, 0, 78]))
    time.sleep(0.5)
    for data in (b"\x00", b"\x80"):
        u.write(0x8505, data)
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(1)
    time.sleep(4)
    rows = g.lines()
    check("geoFolder's gush button: a fresh gush", (rows[0].startswith("gush, the GeoUltra shell") if rows
                                                     else rows, rows[1:]), (True, ["$"]))
    check("gushrc run at its start", out("echo $G"), "from gushrc")
    ftp.delete("/USB0/GEOULTRA/gushrc")
    ftp.quit()
    g.run("reboot", settle=1)                       # (last: it ends the session)
    time.sleep(25)
    desk = open(os.path.join(ROOT, "build", "desktop", "desktop.bin"), "rb").read()[:16]
    check("reboot: GeoUltra started afresh (the cold start ends in the desktop)",
          bytes(u.read(0x0400, 16)), desk)
    g.start()                                       # (the history kept)
    lb = g.lbl["lineBuf"]
    got = []
    for _ in range(2):
        g.keys([16], settle=1)                      # cursor up
        got.append(bytes(u.read(lb, 16)).split(b"\0")[0])
    check("history across sessions: reboot, then the line before", got, [b"reboot", b"echo $G"])
    return g.ok


def mounts_ini():
    """MOUNTS.INI's text (only read)."""
    ftp = ftplib.FTP(env_ip())
    ftp.login()
    data = io.BytesIO()
    ftp.retrbinary("RETR /USB0/GEOULTRA/MOUNTS.INI", data.write)
    ftp.quit()
    return data.getvalue().decode("latin1")


if __name__ == "__main__":
    main()
