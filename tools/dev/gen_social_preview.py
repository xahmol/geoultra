#!/usr/bin/env python3
"""
Generate the GitHub social preview image for GeoUltra: the same layout as
the other idi8b projects' (u64-bbcbasic's tools/gen_social_preview.py,
mandelbrot-upic's, heartbeat-demo's).

Input:  docs/images/desktop-icons.png (a frame from the U64's VIC stream,
        tools/dev/docshots.py)
Output: docs/images/social-preview.png (1280x640); upload it under the
        repository's Settings > General > Social preview.
Usage:  tools/dev/gen_social_preview.py
"""

import os
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCREEN_SHOT = os.path.join(REPO_ROOT, 'docs', 'images', 'desktop-icons.png')
# the idi8b logo is cut from locifilemanager-v2's preview, a repository next
# to this one (FM_PREVIEW overrides), as in the other idi8b projects
FM_PREVIEW = os.environ.get('FM_PREVIEW', os.path.join(
    REPO_ROOT, '..', 'locifilemanager-v2', 'screenshots', 'social-preview.png'))
OUT_PATH = os.path.join(REPO_ROOT, 'docs', 'images', 'social-preview.png')
LOGO_C64 = os.path.join(REPO_ROOT, 'tools', 'dev', 'splash', 'idi8b-logo.png')
FONT_PATH = '/usr/share/fonts/truetype/ubuntu/UbuntuMono[wght].ttf'

W, H = 1280, 640
BG = (16, 16, 16)
C_CYAN = (16, 235, 235)
C_YELLOW = (235, 235, 16)
C_WHITE = (235, 235, 235)
C_GREEN = (15, 235, 16)

# Left panel: the screenshot with a green border; right panel from x 760
SHOT_X1, SHOT_Y1 = 32, 95
SHOT_X2, SHOT_Y2 = 727, 543
TEXT_X = 760
LOGO_FM = (768, 95, 1243, 275)          # the idi8b logo in the FM preview
TITLE_Y, VERS_Y, DESC_Y, URL_Y = 320, 390, 447, 593


def main():
    shot = Image.open(SCREEN_SHOT).convert('RGB')
    panel_w, panel_h = SHOT_X2 - SHOT_X1, SHOT_Y2 - SHOT_Y1
    # whole multiples where possible keep the C64 pixels sharp
    scale = min(panel_w / shot.width, panel_h / shot.height)
    new_w, new_h = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((new_w, new_h), Image.NEAREST)
    off_x = SHOT_X1 + (panel_w - new_w) // 2
    off_y = SHOT_Y1 + (panel_h - new_h) // 2

    # the idi8b logo in the C64's pastel colours (the boot splash's,
    # tools/dev/splash/idi8b-logo.png), scaled by a whole factor: the
    # crop of locifilemanager-v2's preview had the saturated VDC/Oric
    # colours (the user, 2026-11-27: C64 colours in every project)
    src = Image.open(LOGO_C64).convert('RGBA')
    k = max(1, min((1260 - TEXT_X) // src.width, 200 // src.height))
    logo = src.resize((src.width * k, src.height * k), Image.NEAREST)

    f_title = ImageFont.truetype(FONT_PATH, 46)
    f_vers = ImageFont.truetype(FONT_PATH, 40)
    f_desc = ImageFont.truetype(FONT_PATH, 26)
    f_url = ImageFont.truetype(FONT_PATH, 24)

    canvas = Image.new('RGB', (W, H), BG)
    draw = ImageDraw.Draw(canvas)
    b = 4
    draw.rectangle([off_x - b, off_y - b, off_x + new_w + b, off_y + new_h + b],
                   outline=C_GREEN, width=b)
    canvas.paste(shot, (off_x, off_y))
    canvas.paste(logo, (TEXT_X, 80 + (200 - logo.height) // 2), logo)
    draw.text((TEXT_X, TITLE_Y), "GeoUltra", font=f_title, fill=C_CYAN)
    draw.text((TEXT_X, VERS_Y), "v0.9.0 Beta 1", font=f_vers, fill=C_YELLOW)
    for i, line in enumerate(("A GEOS-compatible system",
                              "for the C64 with an",
                              "Ultimate")):
        draw.text((TEXT_X, DESC_Y + 34 * i), line, font=f_desc, fill=C_WHITE)
    draw.text((TEXT_X, URL_Y), "github.com/xahmol/geoultra", font=f_url, fill=C_GREEN)
    canvas.save(OUT_PATH, 'PNG')
    print('Saved:', OUT_PATH)


if __name__ == '__main__':
    main()
