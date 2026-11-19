#!/usr/bin/env python3
"""geosapp.py - build a GEOS sequential file (.cvt) from a raw binary.

    geosapp.py spec.toml program.bin output.cvt [--set key=value ...]

The spec (TOML) describes the GEOS file header; it replaces cc65's .grc
HEADER and the GEOSBuild .gbuild scripts. Put the result on a disk image
with VICE:  c1541 -attach disk.d81 -geoswrite output.cvt

Spec keys ([file] table):
  name     directory name, max 16 characters (required)
  type     GEOS type: APPLICATION, AUTO_EXEC, DESK_ACC, APPL_DATA, ...
  class    permanent name / class, max 12 characters (default: name)
  version  "Vx.y" (4 characters, default "V1.0")
  author   max 19 characters
  info     info text, max 95 characters
  mode     GEOS 128 compatibility: "40" (40 columns only), "40_80"
           (default), "80" (80 columns only), "no128" (not on GEOS 128)
  icon     file icon: 63 or 64 bytes of sprite data (24x21 hires); path
           relative to the spec file
  cbmtype  CBM file type: USR (default), SEQ, PRG
  load     load address (default 0x0400)
  start    start vector (default = load)
  end      end address for DESK_ACC (default: load + length - 1, the
           length padded to whole 254-byte blocks, see below)
  appdata  list of up to 23 bytes for the application data area ($89)

--set key=value overrides a spec key (e.g. --set version=V2.0).

Desk accessories are padded with zeros to whole 254-byte data blocks, and
the end address covers the padding: GEOS's LdDeskAcc saves (and RstrAppl
restores) only load..end of the application, while ReadFile loads every
byte the file's blocks hold, and some tools (VICE's c1541 -geoswrite)
write a short last block as a full one. Without the padding the
application's memory after the end address is overwritten and it crashes
when the desk accessory returns (found in GeoUltra, 2026-10-29).

CVT layout written (see GEOS_REFERENCE.md, "CVT"): 254-byte block with
the 30-byte directory entry and the signature "SEQ formatted GEOS file
V1.0" (VICE c1541 convention for sequential files), the file header block (254 bytes), then the data; the last block
is not padded.

Written 2026 by Xander Mol for geos-oscar64.
"""
import datetime
import os
import sys
import tomllib

GEOS_TYPES = {
    'NOT_GEOS': 0, 'BASIC': 1, 'ASSEMBLY': 2, 'DATA': 3, 'SYSTEM': 4,
    'DESK_ACC': 5, 'APPLICATION': 6, 'APPL_DATA': 7, 'FONT': 8,
    'PRINTER': 9, 'INPUT_DEVICE': 10, 'DISK_DEVICE': 11, 'SYSTEM_BOOT': 12,
    'TEMPORARY': 13, 'AUTO_EXEC': 14, 'INPUT_128': 15,
}
CBM_TYPES = {'SEQ': 0x81, 'PRG': 0x82, 'USR': 0x83}
MODES = {'40': 0x00, '40_80': 0x40, 'no128': 0x80, '80': 0xC0}


def die(msg):
    sys.exit('geosapp.py: ' + msg)


def ascii_bytes(text, length, pad, what):
    data = text.encode('ascii')
    if len(data) > length:
        die('%s "%s" longer than %d characters' % (what, text, length))
    return data + bytes([pad]) * (length - len(data))


def to_int(value):
    return int(value, 0) if isinstance(value, str) else int(value)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--set')]
    sets = []
    argv = sys.argv[1:]
    for i, a in enumerate(argv):
        if a == '--set' and i + 1 < len(argv):
            sets.append(argv[i + 1])
    args = [a for i, a in enumerate(argv) if a != '--set' and (i == 0 or argv[i - 1] != '--set')]
    if len(args) != 3:
        die('usage: geosapp.py spec.toml program.bin output.cvt [--set key=value ...]')
    spec_path, bin_path, out_path = args
    with open(spec_path, 'rb') as f:
        spec = tomllib.load(f).get('file', {})
    for s in sets:
        k, _, v = s.partition('=')
        spec[k] = v

    data = open(bin_path, 'rb').read()
    if not data:
        die('empty program binary')

    name = spec.get('name') or die('spec: name missing')
    gtype = spec.get('type', 'APPLICATION').upper()
    if gtype not in GEOS_TYPES:
        die('spec: unknown type ' + gtype)
    cbm = CBM_TYPES.get(spec.get('cbmtype', 'USR').upper()) or die('spec: unknown cbmtype')
    mode = MODES.get(str(spec.get('mode', '40_80')))
    if mode is None:
        die('spec: mode must be one of ' + ', '.join(MODES))
    load = to_int(spec.get('load', 0x0400))
    start = to_int(spec.get('start', load))
    if gtype == 'DESK_ACC' and len(data) % 254:
        padded = len(data) + 254 - len(data) % 254
        if load + padded > 0x8000:
            die('desk accessory padded to whole blocks ends at $%04X, beyond '
                'application memory; shorten it by %d bytes'
                % (load + padded, load + padded - 0x8000))
        data = data + bytes(padded - len(data))
    end = to_int(spec.get('end', load + len(data) - 1)) if gtype == 'DESK_ACC' else load - 1
    if load + len(data) > 0x8000 and gtype != 'APPL_DATA':
        die('program ends at $%04X, beyond application memory' % (load + len(data)))

    icon = bytes(63)
    if 'icon' in spec:
        icon_path = os.path.join(os.path.dirname(spec_path), spec['icon'])
        icon = open(icon_path, 'rb').read()
        if len(icon) not in (63, 64):
            die('icon must be 63 or 64 bytes, %s is %d' % (icon_path, len(icon)))
        icon = icon[:63]

    # File header block, 256 bytes; the CVT stores bytes 2..255.
    hdr = bytearray(256)
    hdr[0], hdr[1] = 0x00, 0xFF
    hdr[2], hdr[3], hdr[4] = 3, 21, 0x80 + 63           # icon width, height, format
    hdr[5:5 + 63] = icon
    hdr[0x44] = cbm
    hdr[0x45] = GEOS_TYPES[gtype]
    hdr[0x46] = 0                                      # SEQUENTIAL
    hdr[0x47:0x49] = load.to_bytes(2, 'little')
    hdr[0x49:0x4B] = (end & 0xFFFF).to_bytes(2, 'little')
    hdr[0x4B:0x4D] = start.to_bytes(2, 'little')
    cls = ascii_bytes(spec.get('class', name), 12, 0x20, 'class')
    ver = ascii_bytes(spec.get('version', 'V1.0'), 4, 0x20, 'version')
    hdr[0x4D:0x4D + 16] = cls + ver                    # permanent name, then 3 NULs
    hdr[0x60] = mode
    hdr[0x61:0x61 + 20] = ascii_bytes(spec.get('author', ''), 19, 0, 'author') + b'\0'
    appdata = [to_int(b) for b in spec.get('appdata', [])]
    if len(appdata) > 23:
        die('spec: appdata has more than 23 bytes')
    hdr[0x89:0x89 + len(appdata)] = bytes(appdata)
    hdr[0xA0:0xA0 + 96] = ascii_bytes(spec.get('info', ''), 95, 0, 'info') + b'\0'

    blocks = 1 + (len(data) + 253) // 254
    now = datetime.datetime.now()

    # Directory entry, 30 bytes (T/S fields are not meaningful in a CVT).
    entry = bytearray(30)
    entry[0] = cbm
    entry[3:19] = ascii_bytes(name, 16, 0xA0, 'name')
    entry[21] = 0                                      # SEQUENTIAL
    entry[22] = GEOS_TYPES[gtype]
    entry[23:28] = bytes([now.year % 100, now.month, now.day, now.hour, now.minute])
    entry[28:30] = blocks.to_bytes(2, 'little')

    sig = bytearray(254)
    sig[0:30] = entry
    sig[30:30 + 28] = b'SEQ formatted GEOS file V1.0'  # VLIR files: 'PRG formatted'

    with open(out_path, 'wb') as f:
        f.write(sig)
        f.write(hdr[2:])
        f.write(data)
    print('%s: %s, %s, $%04X-$%04X, %d blocks' % (out_path, name, gtype,
          load, load + len(data) - 1, blocks))


if __name__ == '__main__':
    main()
