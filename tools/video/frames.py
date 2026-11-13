"""Read a .pkts capture back as frames: yields (time, frame) with frame a
numpy uint8 array of 272 x 384 colour indexes. Lines missing from a
frame keep the previous frame's content."""
import struct
import numpy as np

HDR = 12

def frames(path):
    cur = np.zeros((272, 384), np.uint8)
    fid, t_first = None, None
    with open(path, 'rb') as f:
        while True:
            h = f.read(10)
            if len(h) < 10:
                return
            t, n = struct.unpack('<dH', h)
            data = f.read(n)
            _, frame, line, width, per, bpp, _ = struct.unpack_from('<HHHHBBH', data)
            if width != 384 or bpp != 4:
                continue
            last = bool(line & 0x8000)
            line &= 0x7FFF
            if fid is None:
                fid, t_first = frame, t
            payload = np.frombuffer(data, np.uint8, offset=HDR)
            for i in range(per):
                y = line + i
                if y >= 272:
                    break
                row = payload[i * 192:(i + 1) * 192]
                if len(row) < 192:
                    break
                cur[y, 0::2] = row & 15
                cur[y, 1::2] = row >> 4
            if last:
                yield t_first, cur.copy()
                fid = None


def deglitched(path):
    """frames() with one-frame glitches removed: a frame that differs from
    the one before it while the one after it equals the one before (the
    DMA stall of a REST memory read) is replaced by the one before."""
    it = frames(path)
    try:
        t0, a = next(it)
        t1, b = next(it)
    except StopIteration:
        return
    yield t0, a
    for t2, c in it:
        if not np.array_equal(b, a) and np.array_equal(c, a):
            b = a
        yield t1, b
        a, t1, b = b, t2, c
    yield t1, b


def repaired(path, stats=None):
    """frames() with REST-read glitches repaired. A REST memory read stalls
    the CPU (DMA) while the picture is drawn, so from some line on the rest
    of that frame is the picture shifted by a line or two. Compared with
    the last good frame: if the changed lines from the first changed one
    down are (mostly) that frame shifted by 1-2 lines, they are replaced by
    the good frame's lines; everything else (progress, flicker, markers)
    passes unchanged."""
    good = None
    for t, f in frames(path):
        if good is None:
            good = f
            yield t, f
            continue
        changed = np.nonzero((f != good).any(axis=1))[0]
        if len(changed) >= 3:
            r = changed[0]
            rows = [y for y in changed if 2 <= y < 270 and y > r]
            shifted = 0
            for y in rows:
                if any(np.array_equal(f[y], good[y - k]) for k in (1, -1, 2, -2)):
                    shifted += 1
            if rows and shifted >= 2 and shifted >= 0.7 * len(rows):
                out = f.copy()
                out[r:] = good[r:]
                if stats is not None:
                    stats.append((round(t, 2), int(r), len(rows)))
                yield t, out
                continue
        good = f
        yield t, f
