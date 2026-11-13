#!/usr/bin/env python3
"""Edit the GeoUltra sneak-peek take into a video: 1920x1080, 50 fps, H.264.

Adapted from the UBoot64 v4.0.0 video's edit.py (video workflow of
2026-10-03, ~/.claude/youtube_video_workflow.md). Picture: stream rows
9-264, 4x nearest-neighbour (1536x1024), the Ultimate 64's default
palette (src/settings/ptheme.s DefaultPal, read from a U64-II), with the
Settings scene's live palette step applied (the stream carries colour
indexes only); captions in a strip below; title and closing card with
the idi8b logo; Piper "Alba" voice-over 0.3 s into each scene.

Usage: edit.py TAKE_DIR VOICE_DIR out.mp4
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from frames import repaired  # noqa: E402

TAKE, VO_DIR, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
W, H, FPS = 1920, 1080, 50
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONTB = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
LOGO = '/home/xahmol/git/idreamtin8bits-astro/src/assets/idi8b-logo-lowercase_large.png'
U64_PAL = [(0x00, 0x00, 0x00), (0xF7, 0xF7, 0xF7), (0x8D, 0x2F, 0x34), (0x6A, 0xD4, 0xCD),
           (0x98, 0x35, 0xA4), (0x4C, 0xB4, 0x42), (0x2C, 0x29, 0xB1), (0xEF, 0xEF, 0x5D),
           (0x98, 0x4E, 0x20), (0x5B, 0x38, 0x00), (0xD1, 0x67, 0x6D), (0x4A, 0x4A, 0x4A),
           (0x7B, 0x7B, 0x7B), (0x9F, 0xEF, 0x93), (0x6D, 0x6A, 0xEF), (0xB2, 0xB2, 0xB2)]
PAL = np.array(U64_PAL, np.uint8)
PAL_STEP = np.array(U64_PAL, np.uint8)
PAL_STEP[6, 0] = min(255, PAL_STEP[6, 0] + 6 * 4)      # blue's red, six steps of 4

ev = json.load(open(os.path.join(TAKE, 'events.json')))
T = {}
for e in ev:
    T.setdefault((e['kind'], e.get('name')), e['t'])


def m(name):
    return T[('mark', name)]


def sc(name):
    return T[('scene', name)]


# (source start, source end, speed, caption, voice line, chapter)
SEGMENTS = [
    (sc('boot') + 1, m('desktop'), 2, 'Booting from the cartridge: the system copied into the REU (2x speed)',
     'boot', 'Boot'),
    (m('desktop'), m('icons'), 1, "GeoUltra's own desktop: drives, the Ultimate's storage, favourites",
     'desktop', 'The desktop'),
    (m('icons'), sc('panes'), 1, 'List, icon and detailed views; themes in the view menu', 'views', 'Views'),
    (sc('panes'), m('leftc'), 1, 'Two panes with drive letters; U lists the Ultimate\'s roots', 'panes',
     'Two panes'),
    (m('leftc'), m('dragged'), 1, 'Drag and drop: a GEOS file onto usb0 becomes a .cvt file', 'drag',
     'Drag and drop'),
    (sc('geowrite'), m('back'), 2.5, 'geoWrite from a folder on a native drive; its Open dialog with drive '
     'letters (2.5x speed)', 'geowrite', 'geoWrite'),
    (sc('geos'), sc('gush'), 1, 'The geos menu: GeoUltra info, settings, gush and geoFolder first', 'geofolder',
     'The geos menu'),
    (sc('gush'), sc('settings'), 1.5, 'gush, the GeoUltra shell: commands, scripting, ifconfig (1.5x speed)',
     'gush', 'gush'),
    (sc('settings'), m('end'), 2, 'GeoUltra Settings: themes, the palette in RGB, pointers, time (2x speed)',
     'settings', 'Settings'),
]
PAL_FROM, PAL_TO = m('theme-next') + 3, m('leave')      # the palette step's stretch
LEAD, TAIL = 0.3, 0.6


def clip_len(key):
    w = wave.open('%s/%s.wav' % (VO_DIR, key))
    return w.getnframes() / w.getframerate()


voice_at = []
out_time = [0.0]
chapters = []


def font(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


_cap = {}


def caption_strip(text):
    if text not in _cap:
        im = Image.new('RGB', (W, H - 1024), (0, 0, 0))
        d = ImageDraw.Draw(im)
        f = font(28)
        w = d.textlength(text, font=f)
        d.text(((W - w) / 2, 12), text, font=f, fill=(235, 235, 235))
        _cap[text] = np.asarray(im)
    return _cap[text]


def card(lines, logo_height=0):
    im = Image.new('RGB', (W, H), (0, 0, 0))
    d = ImageDraw.Draw(im)
    total = sum(s * 1.6 for _, s, _, _ in lines)
    gap = 70 if logo_height else 0
    y = (H - total - logo_height - gap) / 2
    if logo_height:
        lg = Image.open(LOGO).convert('RGBA')
        lg = lg.resize((round(lg.width * logo_height / lg.height), logo_height), Image.LANCZOS)
        im.paste(lg, ((W - lg.width) // 2, int(y)), lg)
        y += logo_height + gap
    for text, size, bold, col in lines:
        f = font(size, bold)
        w = d.textlength(text, font=f)
        d.text(((W - w) / 2, y), text, font=f, fill=col)
        y += size * 1.6
    return np.asarray(im)


ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
                       '-s', '%dx%d' % (W, H), '-r', str(FPS), '-i', '-',
                       '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p',
                       '-movflags', '+faststart', OUT], stdin=subprocess.PIPE)


def emit(img, seconds=None):
    n = int(round((seconds or 1 / FPS) * FPS))
    for _ in range(n):
        ff.stdin.write(img.tobytes())
    out_time[0] += n / FPS


def card_with_voice(img, seconds, key):
    voice_at.append((out_time[0] + 0.5, key))
    emit(img, max(seconds, clip_len(key) + 1.5))


WHITE, GREY, DIM = (255, 255, 255), (200, 200, 200), (150, 150, 150)
chapters.append((out_time[0], 'Intro'))
card_with_voice(card([('GeoUltra', 96, True, WHITE),
                      ('A sneak peek at version 0.1, in development', 40, False, GREY),
                      ('A GEOS compatible system for the Ultimate 64', 34, False, GREY),
                      ('Ultimate 64-II, firmware 3.15a. Captured from the VIC video stream, no emulator',
                       28, False, DIM)], logo_height=280), 7, 'title')

canvas = np.zeros((H, W, 3), np.uint8)
src = repaired(os.path.join(TAKE, 'take.pkts'))
cur_t, cur_f = next(src)
nxt_t, nxt_f = next(src)


def advance():
    global cur_t, cur_f, nxt_t, nxt_f
    cur_t, cur_f = nxt_t, nxt_f
    nxt_t, nxt_f = next(src)


for s0, s1, speed, text, key, chapter in SEGMENTS:
    chapters.append((out_time[0], chapter))
    strip = caption_strip(text)
    need = clip_len(key) + LEAD + TAIL
    voice_at.append((out_time[0] + LEAD, key))
    n = int(round((s1 - s0) / speed * FPS))
    for k in range(n):
        t = s0 + k * speed / FPS
        while nxt_t <= t:
            advance()
        pal = PAL_STEP if PAL_FROM <= t < PAL_TO else PAL
        rgb = pal[cur_f[9:265]]
        canvas[0:1024, 192:192 + 1536] = rgb.repeat(4, axis=0).repeat(4, axis=1)
        canvas[1024:] = strip
        emit(canvas)
    hold = need - (s1 - s0) / speed
    if hold > 0:
        emit(canvas, hold)
    print('segment done', key, round(out_time[0], 1), flush=True)

chapters.append((out_time[0], 'Credits'))
card_with_voice(card([('GeoUltra 0.1, in development', 64, True, WHITE),
                      ('Code: Xander Mol, written with Claude (Anthropic)', 32, False, GREY),
                      ('geoWrite: Berkeley Softworks; GEOS 64 disk: Click Here Software Co.', 28, False, GREY),
                      ('Narration: Piper text-to-speech, voice "Alba" (CC BY 4.0)', 28, False, GREY),
                      ('Free software (GPL v3) at its first release', 32, True, WHITE)], logo_height=220),
                10, 'closing')
ff.stdin.close()
ff.wait()

rate = 22050
track = np.zeros(int((out_time[0] + 1) * rate), np.float32)
for t, key in voice_at:
    w = wave.open('%s/%s.wav' % (VO_DIR, key))
    a = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32)
    i = int(t * rate)
    track[i:i + len(a)] += a[:len(track) - i]
track = np.clip(track, -32768, 32767).astype(np.int16)
wav = OUT + '.vo.wav'
w = wave.open(wav, 'wb')
w.setnchannels(1)
w.setsampwidth(2)
w.setframerate(rate)
w.writeframes(track.tobytes())
w.close()
silent = OUT + '.silent.mp4'
os.replace(OUT, silent)
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', silent, '-i', wav, '-map', '0:v', '-map', '1:a',
                '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k', '-ar', '48000', '-ac', '2',
                '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-shortest', '-movflags', '+faststart', OUT],
               check=True)
with open(OUT + '.chapters.txt', 'w') as f:
    for t, name in chapters:
        f.write('%d:%02d %s\n' % (int(t) // 60, int(t) % 60, name))
print('written', OUT, round(out_time[0], 1), 's')
