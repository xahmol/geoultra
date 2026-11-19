"""localcfg.py - the settings of this PC for GeoUltra's tools and tests.

Every value comes from, in this order: the environment, the file `.env`
in the repository's root (KEY=value lines, gitignored; `.env.example`
lists the keys), or a default that needs nothing of a particular PC:
programs on the PATH, sibling checkouts next to this repository
(`../GeoUTools`, only for some U64 tests), and your own disk images in the
gitignored `private/` folder. `~` and `$HOME` in values are expanded.
The Makefile reads the same `.env` (and passes it on to the scripts).

    import localcfg
    localcfg.C1541                       # VICE's c1541
    localcfg.disk("GEOS_ORACLE", "GEOS64-v2.0-unkeyed.d64")
"""
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _dotenv():
    out = {}
    try:
        lines = open(os.path.join(ROOT, ".env"), encoding="utf-8").read().splitlines()
    except OSError:
        return out
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k.startswith("export "):
            k = k[7:].strip()
        k = k.rstrip("?:").strip()          # (make's ?= and :=)
        out[k] = v.strip().strip('"').strip("'")
    return out


_ENV = _dotenv()


def get(key, default=None):
    """KEY's value (environment, .env, default), ~ and $HOME expanded."""
    v = os.environ.get(key) or _ENV.get(key) or default
    if v is None:
        return None
    return os.path.expanduser(os.path.expandvars(v))


def _tool(dir_key, name, fallback_key=None):
    d = get(dir_key) or (get(fallback_key) if fallback_key else None)
    if d:
        return os.path.join(d, name)
    return shutil.which(name) or name


# VICE 3.10 or later (the Megabyter cartridge needs 3.10): VICE_BIN the
# folder with x64sc and c1541; VICE_HEADLESS_BIN a build without window
# and sound for the unattended runs (VICE_BIN's when not set).
VICE_BIN = get("VICE_BIN") or os.path.dirname(shutil.which("x64sc") or "") or None
X64SC = _tool("VICE_BIN", "x64sc")
X64SC_HEADLESS = _tool("VICE_HEADLESS_BIN", "x64sc", "VICE_BIN")
C1541 = _tool("VICE_BIN", "c1541")

# geosapp.py packs GEOS applications (a copy of geos-oscar64's, in tools/).
GEOSAPP = os.path.join(ROOT, "tools", "geosapp.py")
# A sibling project, optional: GeoUTools (its manual and screenshot tool,
# some U64 tests and the video scripts).
GEOUTOOLS = get("GEOUTOOLS", os.path.join(os.path.dirname(ROOT), "GeoUTools"))
GEOUTOOLS_SHOT = os.path.join(GEOUTOOLS, "tests", "e2e", "shot.py")

# Your own GEOS disk images (never committed): GEOS_DEV the folder that
# holds them; each can also be named on its own (GEOS_ORACLE ...).
GEOS_DEV = get("GEOS_DEV", os.path.join(ROOT, "private"))


def disk(key, name):
    """A disk image of yours: KEY's value, else NAME in GEOS_DEV."""
    return get(key, os.path.join(GEOS_DEV, name))
