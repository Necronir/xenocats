#!/usr/bin/env python3
"""
Procedural Pixel-Art & Retro Audio Generator for Xenocats: Bremen-4
Generates shaded Nearest-Neighbor pixel sprites, 64x64 character portraits,
and 16-bit PCM WAV files in the warm "cyber fairy tale of Bremen" style.
"""

import argparse
import math
import os
import random
import struct
import wave
from PIL import Image, ImageDraw

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(PROJECT_DIR, "assets")

# --- Pixel-Art Palette & Shading Toolkit ---
OUTLINE = (18, 16, 26, 255)
OUTLINE_SOFT = (34, 28, 44, 255)

# 4-tone hue-shifted ramps: (shadow, mid, light, highlight)
RAMP_CHROME = ((44, 56, 78), (88, 112, 144), (150, 182, 214), (222, 242, 255))
RAMP_STEEL = ((36, 42, 56), (68, 78, 98), (112, 126, 152), (168, 184, 210))
RAMP_DARK_IRON = ((24, 26, 36), (46, 50, 66), (76, 82, 102), (118, 126, 148))
RAMP_COBALT = ((22, 46, 94), (42, 92, 162), (72, 146, 218), (138, 206, 250))
RAMP_CRIMSON = ((96, 20, 30), (166, 36, 44), (218, 68, 56), (248, 142, 98))
RAMP_GOLD = ((116, 68, 18), (188, 128, 28), (238, 182, 48), (255, 232, 134))
RAMP_PURPLE = ((64, 24, 96), (118, 48, 164), (170, 82, 214), (224, 152, 248))
RAMP_LEATHER = ((52, 30, 20), (98, 60, 36), (148, 96, 54), (198, 142, 86))
RAMP_COPPER = ((76, 36, 24), (134, 68, 40), (188, 104, 56), (234, 156, 96))
RAMP_TITAN = ((48, 58, 76), (94, 112, 136), (150, 172, 198), (212, 232, 248))
RAMP_TEAL = ((24, 68, 74), (44, 122, 126), (78, 178, 170), (144, 230, 210))
RAMP_ACID = ((32, 88, 36), (62, 154, 58), (116, 216, 72), (196, 255, 132))
RAMP_OLIVE = ((48, 56, 36), (86, 98, 58), (128, 144, 84), (178, 194, 124))
RAMP_BLONDE = ((118, 74, 22), (184, 126, 36), (236, 184, 64), (255, 236, 154))

BAYER_2X2 = ((0, 2), (3, 1))


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def _rgba(col) -> tuple[int, int, int, int]:
    if len(col) == 4:
        return (int(col[0]), int(col[1]), int(col[2]), int(col[3]))
    return (int(col[0]), int(col[1]), int(col[2]), 255)


def put_px(img: Image.Image, x: int, y: int, col) -> None:
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), _rgba(col))


def get_px(img: Image.Image, x: int, y: int) -> tuple[int, int, int, int]:
    if 0 <= x < img.width and 0 <= y < img.height:
        return img.getpixel((x, y))
    return (0, 0, 0, 0)


def blend_px(img: Image.Image, x: int, y: int, col, alpha: float) -> None:
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    r, g, b, a = _rgba(col)
    br, bg, bb, ba = img.getpixel((x, y))
    if ba == 0:
        img.putpixel((x, y), (r, g, b, int(a * alpha)))
        return
    t = max(0.0, min(1.0, alpha))
    nr = int(br * (1.0 - t) + r * t)
    ng = int(bg * (1.0 - t) + g * t)
    nb = int(bb * (1.0 - t) + b * t)
    na = max(ba, int(a * t))
    img.putpixel((x, y), (nr, ng, nb, na))


def ramp_tone(ramp: tuple, t: float, x: int = 0, y: int = 0, dither: bool = False) -> tuple[int, int, int, int]:
    """Maps normalized brightness t in [0..1] onto a 4-tone color ramp with optional 2x2 Bayer dither."""
    idx_f = max(0.0, min(1.0, t)) * 3.0
    lo = int(math.floor(idx_f))
    hi = min(3, lo + 1)
    frac = idx_f - lo
    if dither and lo != hi:
        threshold = (BAYER_2X2[y & 1][x & 1] + 0.5) / 4.0
        chosen = hi if frac > threshold else lo
    else:
        chosen = round(idx_f)
    return _rgba(ramp[chosen])


def shaded_rect(
    img: Image.Image,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    ramp: tuple,
    bevel: bool = True,
    rivets: bool = False,
    dither: bool = False,
) -> None:
    """Fills a rectangle with top-left key light, beveled rim, and optional corner rivets."""
    if x1 < x0 or y1 < y0:
        return
    w = max(1, x1 - x0)
    h = max(1, y1 - y0)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            nx = (x - x0) / w
            ny = (y - y0) / h
            # Key light from top-left
            t = 0.72 - 0.38 * nx - 0.36 * ny
            if bevel:
                if y == y0 or x == x0:
                    t += 0.24
                if y == y1 or x == x1:
                    t -= 0.28
                if y == y0 + 1 and x0 < x < x1:
                    t += 0.12
            put_px(img, x, y, ramp_tone(ramp, t, x, y, dither=dither))
    if rivets and w >= 5 and h >= 5:
        for rx, ry in ((x0 + 1, y0 + 1), (x1 - 1, y0 + 1), (x0 + 1, y1 - 1), (x1 - 1, y1 - 1)):
            put_px(img, rx, ry, ramp[3])


def shaded_ellipse(
    img: Image.Image,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    ramp: tuple,
    dither: bool = False,
) -> None:
    """Draws a sphere/ellipse shaded with a top-left key light and bottom-right core shadow."""
    x0 = int(math.floor(cx - rx))
    x1 = int(math.ceil(cx + rx))
    y0 = int(math.floor(cy - ry))
    y1 = int(math.ceil(cy + ry))
    rx_safe = max(0.5, rx)
    ry_safe = max(0.5, ry)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            dx = (x - cx) / rx_safe
            dy = (y - cy) / ry_safe
            dist2 = dx * dx + dy * dy
            if dist2 <= 1.0:
                nz = math.sqrt(max(0.0, 1.0 - dist2))
                # Directional light (-0.45, -0.55, 0.7)
                dot = (-0.45 * dx - 0.55 * dy + 0.70 * nz)
                t = 0.42 + 0.56 * dot
                put_px(img, x, y, ramp_tone(ramp, t, x, y, dither=dither))


def draw_emissive_eye(img: Image.Image, x0: int, y0: int, x1: int, y1: int, glow_col, core_col=(245, 255, 255, 255)) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put_px(img, x, y, glow_col)
    mx0 = x0 + (1 if x1 - x0 >= 2 else 0)
    mx1 = x1 - (1 if x1 - x0 >= 2 else 0)
    my0 = y0 + (1 if y1 - y0 >= 2 else 0)
    my1 = y1 - (1 if y1 - y0 >= 2 else 0)
    for y in range(my0, my1 + 1):
        for x in range(mx0, mx1 + 1):
            put_px(img, x, y, core_col)


def draw_hazard_stripes(img: Image.Image, x0: int, y0: int, x1: int, y1: int, stripe_w: int = 3) -> None:
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            phase = ((x - x0) + (y - y0)) // stripe_w
            if phase % 2 == 0:
                tone = RAMP_GOLD[2] if y <= (y0 + y1) // 2 else RAMP_GOLD[1]
            else:
                tone = RAMP_DARK_IRON[1] if y <= (y0 + y1) // 2 else RAMP_DARK_IRON[0]
            put_px(img, x, y, tone)


def draw_striped_vest(img: Image.Image, x0: int, y0: int, x1: int, y1: int) -> None:
    """Troubadour crimson-and-gold striped vest pattern seen across all Bremen musicians."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            is_gold = ((x - x0) // 2) % 2 == 1
            ramp = RAMP_GOLD if is_gold else RAMP_CRIMSON
            t = 0.68 - 0.35 * ((y - y0) / max(1, y1 - y0)) - 0.25 * ((x - x0) / max(1, x1 - x0))
            put_px(img, x, y, ramp_tone(ramp, t, x, y))


def add_outline(img: Image.Image, color=OUTLINE) -> Image.Image:
    """Adds a crisp 1px 4-connected pixel outline around opaque pixels."""
    out = img.copy()
    w, h = img.size
    src = img.load()
    dst = out.load()
    col = _rgba(color)
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                has_neighbor = False
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 32:
                        has_neighbor = True
                        break
                if has_neighbor:
                    dst[x, y] = col
    return out


def draw_feathered_hat(img: Image.Image, cx: int, top_y: int, brim_w: int = 16, ramp=RAMP_LEATHER, feather_left: bool = True) -> None:
    """Draws the iconic Bremen troubadour hat with curved brim and crimson-gold plume."""
    half = brim_w // 2
    # Crown
    shaded_rect(img, cx - half + 3, top_y + 2, cx + half - 3, top_y + 6, ramp, bevel=True)
    # Hat band
    for x in range(cx - half + 3, cx + half - 2):
        put_px(img, x, top_y + 5, RAMP_CRIMSON[1])
    # Brim
    for x in range(cx - half, cx + half + 1):
        by = top_y + 6 + (1 if abs(x - cx) > half - 2 else 0)
        put_px(img, x, by, ramp[2] if x < cx else ramp[0])
        put_px(img, x, by + 1, ramp[0])
    # Crimson-gold feather plume
    dx = -1 if feather_left else 1
    for i in range(6):
        fx = cx + dx * (2 + i)
        fy = top_y + 3 - (i // 2)
        col = RAMP_CRIMSON[2] if i < 3 else RAMP_GOLD[2]
        put_px(img, fx, fy, col)
        put_px(img, fx, fy + 1, RAMP_CRIMSON[1] if i < 4 else RAMP_GOLD[1])


def draw_cat_body(cat_id: str, primary_ramp, secondary_ramp, eye_color, style: str) -> Image.Image:
    """40x36 modular mech torso+head centered at (20, 18) with standardized shoulder & hip sockets."""
    img = Image.new("RGBA", (40, 36), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Hip / pelvis socket block (y=29..34, x=13..26) so legs never show a gap
    shaded_rect(img, 13, 29, 26, 34, RAMP_DARK_IRON, bevel=True)
    put_px(img, 19, 31, eye_color)
    put_px(img, 20, 31, eye_color)

    # Torso core (x=11..28, y=18..31)
    shaded_rect(img, 11, 18, 28, 31, primary_ramp, bevel=True, rivets=True)
    # Shoulder joint pads (left x=9..12, right x=27..30, y=19..24)
    shaded_rect(img, 9, 19, 12, 24, secondary_ramp, bevel=True)
    shaded_rect(img, 27, 19, 30, 24, secondary_ramp, bevel=True)

    if style in ("felix", "mule", "hound", "cock"):
        # Warm Bremen troubadour striped vest over armored chest
        draw_striped_vest(img, 14, 19, 25, 29)
        # Collar rim
        d.line([(13, 18), (26, 18)], fill=RAMP_CRIMSON[3])
    elif style == "titan":
        # Heavy beveled chest armor + reactor vents
        shaded_rect(img, 13, 19, 26, 29, RAMP_CHROME, bevel=True, rivets=True)
        d.line([(14, 21), (17, 21)], fill=RAMP_DARK_IRON[0])
        d.line([(22, 21), (25, 21)], fill=RAMP_DARK_IRON[0])
    else:
        # Scrap welded furnace grille
        shaded_rect(img, 13, 19, 26, 29, RAMP_DARK_IRON, bevel=True)
        for gx in range(15, 25, 2):
            d.line([(gx, 21), (gx, 27)], fill=eye_color)

    # Glowing chest core reactor
    shaded_rect(img, 17, 22, 22, 26, RAMP_DARK_IRON, bevel=False)
    draw_emissive_eye(img, 18, 23, 21, 25, eye_color)

    # Head + Character-faithful silhouettes (y=1..18)
    if style == "felix":
        # Half organic cobalt cat head (left) + half chrome cyber skull (right)
        shaded_ellipse(img, 20, 12, 8.5, 6.2, RAMP_COBALT)
        # Chrome cyber half on right side (x >= 20)
        for y in range(6, 18):
            for x in range(20, 29):
                px = get_px(img, x, y)
                if px[3] > 0:
                    t = 0.7 - 0.35 * ((x - 20) / 9.0) - 0.25 * ((y - 6) / 12.0)
                    put_px(img, x, y, ramp_tone(RAMP_CHROME, t, x, y))
        # Seam rivet line down center
        for sy in range(7, 17, 2):
            put_px(img, 20, sy, RAMP_DARK_IRON[0])
        # Ears: cobalt left, chrome right
        d.polygon([(11, 9), (12, 2), (17, 7)], fill=RAMP_COBALT[1])
        d.polygon([(12, 7), (13, 4), (15, 7)], fill=RAMP_CRIMSON[2])
        d.polygon([(23, 7), (27, 2), (28, 9)], fill=RAMP_CHROME[2])
        put_px(img, 29, 7, RAMP_CRIMSON[2])  # ear cable
        # Tilted olive-brown beret with feather
        draw_feathered_hat(img, 19, 1, brim_w=14, ramp=RAMP_OLIVE, feather_left=True)
        # Golden cat eye (left) + glowing cyan cyber optic (right)
        draw_emissive_eye(img, 14, 11, 17, 13, (255, 205, 45, 255), (255, 248, 170, 255))
        shaded_rect(img, 22, 10, 26, 14, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 23, 11, 25, 13, eye_color)
        # Pink nose & grin
        put_px(img, 19, 14, (240, 100, 120, 255))
        d.line([(16, 16), (23, 16)], fill=(235, 240, 250, 255))

    elif style == "mule":
        # Golden armored donkey head + iconic bulldozer-scoop snout
        shaded_rect(img, 12, 7, 25, 17, RAMP_GOLD, bevel=True, rivets=True)
        # Tall donkey ears
        shaded_rect(img, 12, 1, 15, 7, RAMP_GOLD, bevel=True)
        shaded_rect(img, 22, 1, 25, 7, RAMP_GOLD, bevel=True)
        put_px(img, 13, 3, RAMP_LEATHER[1])
        put_px(img, 23, 3, RAMP_LEATHER[1])
        # Feathered brown hat between ears
        draw_feathered_hat(img, 19, 2, brim_w=13, ramp=RAMP_LEATHER, feather_left=True)
        # Bulldozer scoop snout protruding right (x=23..32, y=12..17)
        shaded_rect(img, 23, 12, 32, 17, RAMP_GOLD, bevel=True)
        d.line([(32, 11), (33, 17)], fill=RAMP_CHROME[3])
        d.line([(25, 13), (30, 13)], fill=RAMP_GOLD[0])
        # Cyan circular optic
        shaded_rect(img, 18, 9, 22, 13, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 19, 10, 21, 12, (70, 240, 255, 255))
        # Exhaust pipe on back
        shaded_rect(img, 8, 14, 10, 19, RAMP_CHROME, bevel=True)
        put_px(img, 8, 12, (190, 200, 215, 180))

    elif style == "hound":
        # Crimson armored hound head + leather straps + saw-tooth steel jaw
        shaded_ellipse(img, 20, 11, 8.2, 6.0, RAMP_CRIMSON)
        # Floppy red cyber-ears
        shaded_rect(img, 10, 8, 13, 15, RAMP_CRIMSON, bevel=True)
        shaded_rect(img, 27, 8, 30, 14, RAMP_CRIMSON, bevel=True)
        draw_feathered_hat(img, 20, 1, brim_w=14, ramp=RAMP_LEATHER, feather_left=True)
        # Eyepatch on left, glowing amber eye on right
        shaded_rect(img, 13, 9, 18, 12, RAMP_DARK_IRON, bevel=False)
        d.line([(12, 8), (19, 11)], fill=RAMP_DARK_IRON[2])
        shaded_rect(img, 21, 9, 25, 12, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 22, 10, 24, 11, (255, 190, 50, 255), (255, 250, 200, 255))
        # Steel jaw mask + circular saw-chin
        shaded_rect(img, 15, 13, 26, 17, RAMP_CHROME, bevel=True)
        for tx in (16, 19, 22, 25):
            put_px(img, tx, 17, RAMP_CHROME[3])
            put_px(img, tx + 1, 18, RAMP_STEEL[1])
        # Leather harness straps over vest
        d.line([(13, 19), (15, 28)], fill=RAMP_LEATHER[2], width=2)
        d.line([(26, 19), (24, 28)], fill=RAMP_LEATHER[2], width=2)

    elif style == "cock":
        # Purple cyber-rooster head + red comb + wattles + feathered hat
        shaded_ellipse(img, 19, 12, 7.0, 5.8, RAMP_PURPLE)
        # Sculpted crimson crest/comb
        for cx_off, h_top in ((15, 3), (18, 1), (21, 2), (24, 4)):
            shaded_rect(img, cx_off, h_top, cx_off + 2, 7, RAMP_CRIMSON, bevel=True)
        draw_feathered_hat(img, 18, 3, brim_w=12, ramp=RAMP_OLIVE, feather_left=True)
        # Glowing cyan eye
        shaded_rect(img, 17, 9, 22, 13, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 18, 10, 21, 12, (90, 255, 230, 255))
        # Red wattles & short silver beak prow
        shaded_rect(img, 23, 11, 29, 14, RAMP_CHROME, bevel=True)
        shaded_rect(img, 20, 15, 24, 18, RAMP_CRIMSON, bevel=True)

    elif style == "titan":
        # Tactical armored helmet + wide cyan visor
        shaded_rect(img, 11, 5, 28, 16, RAMP_TITAN, bevel=True, rivets=True)
        shaded_rect(img, 17, 2, 22, 5, RAMP_CHROME, bevel=True)  # crest
        shaded_rect(img, 13, 9, 26, 13, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 14, 10, 25, 12, eye_color)
        put_px(img, 10, 10, RAMP_TITAN[2])
        put_px(img, 29, 10, RAMP_TITAN[2])

    else:  # scrap
        # Asymmetric welded salvage boiler head
        shaded_rect(img, 11, 6, 28, 17, RAMP_COPPER, bevel=True, rivets=True)
        shaded_rect(img, 14, 3, 21, 6, RAMP_DARK_IRON, bevel=True)
        shaded_rect(img, 13, 9, 18, 13, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 14, 10, 17, 12, eye_color)
        shaded_rect(img, 21, 10, 25, 13, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 22, 11, 24, 12, (255, 100, 40, 255))

    return add_outline(img)


def draw_cat_arms(style: str, primary_ramp, secondary_ramp, glow) -> Image.Image:
    """48x30 modular weapon & shoulders centered at (24, 15).
    Left shoulder sits at x=7..14, center x=16..26 stays transparent so body vest shows cleanly,
    right shoulder sits at x=27..34, weapon extends right to x=34..46.
    """
    img = Image.new("RGBA", (48, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Left (rear) shoulder pauldron + forearm guard
    shaded_rect(img, 7, 10, 14, 19, primary_ramp, bevel=True, rivets=True)
    shaded_rect(img, 5, 16, 12, 22, secondary_ramp, bevel=True)
    # Right (front) shoulder pauldron
    shaded_rect(img, 28, 9, 35, 18, primary_ramp, bevel=True, rivets=True)

    if style == "claws":
        # Striped troubadour sleeve + chrome wrist + 3 blazing cyan laser claws
        draw_striped_vest(img, 29, 13, 35, 19)
        shaded_rect(img, 32, 11, 38, 18, RAMP_CHROME, bevel=True)
        for cy_a, cy_b in ((9, 7), (14, 14), (19, 21)):
            d.line([(38, cy_a), (46, cy_b)], fill=glow, width=2)
            d.line([(39, cy_a), (45, cy_b)], fill=(235, 255, 255, 255), width=1)
        # Left hand claw tips
        d.line([(5, 20), (2, 22)], fill=glow, width=1)
        d.line([(7, 22), (4, 24)], fill=glow, width=1)

    elif style == "shield":
        # Heavy riveted bulldozer-scoop shield on right arm + hydraulic piston
        shaded_rect(img, 30, 12, 36, 18, RAMP_CHROME, bevel=True)
        shaded_rect(img, 35, 3, 46, 26, RAMP_GOLD, bevel=True, rivets=True)
        draw_hazard_stripes(img, 37, 20, 44, 24, stripe_w=2)
        shaded_rect(img, 38, 8, 43, 17, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 39, 9, 42, 16, glow)

    elif style == "saw":
        # Crimson hydraulic arm + red hose + spinning serrated circular buzzsaw
        shaded_rect(img, 30, 12, 37, 18, RAMP_CRIMSON, bevel=True)
        d.line([(29, 18), (34, 21)], fill=RAMP_CRIMSON[2], width=1)
        cx, cy, r = 40, 12, 6
        shaded_ellipse(img, cx, cy, r, r, RAMP_CHROME)
        # Saw teeth around perimeter
        for deg in range(0, 360, 45):
            rad = math.radians(deg)
            tx = int(round(cx + math.cos(rad) * (r + 1)))
            ty = int(round(cy + math.sin(rad) * (r + 1)))
            put_px(img, tx, ty, RAMP_CHROME[3])
        draw_emissive_eye(img, cx - 1, cy - 1, cx + 1, cy + 1, glow)
        # Lower hydraulic clamp
        shaded_rect(img, 35, 20, 43, 24, RAMP_STEEL, bevel=True)

    elif style == "megaphone":
        # Purple cyber-wing feathers on left + silver acoustic megaphone horn on right
        for wy in (9, 13, 17):
            d.line([(8, wy), (2, wy + 2)], fill=RAMP_PURPLE[2], width=2)
            put_px(img, 1, wy + 2, RAMP_PURPLE[3])
        shaded_rect(img, 31, 12, 36, 17, RAMP_PURPLE, bevel=True)
        # Horn cone
        d.polygon([(35, 12), (45, 5), (45, 23), (35, 17)], fill=RAMP_CHROME[1])
        d.line([(35, 12), (45, 5)], fill=RAMP_CHROME[3])
        d.line([(35, 17), (45, 23)], fill=RAMP_CHROME[0])
        shaded_rect(img, 43, 6, 46, 22, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 44, 10, 45, 18, glow)

    elif style == "rail":
        # Vanguard twin-rail plasma cannon
        shaded_rect(img, 30, 10, 38, 19, RAMP_TITAN, bevel=True, rivets=True)
        shaded_rect(img, 36, 9, 46, 12, RAMP_CHROME, bevel=True)
        shaded_rect(img, 36, 16, 46, 19, RAMP_CHROME, bevel=True)
        draw_emissive_eye(img, 37, 13, 45, 15, glow)

    else:  # flamer (scrap)
        # Salvage copper flamethrower + pressurized fuel tank + nozzle flame
        shaded_rect(img, 6, 12, 11, 21, RAMP_CRIMSON, bevel=True)
        shaded_rect(img, 30, 11, 41, 18, RAMP_COPPER, bevel=True, rivets=True)
        shaded_rect(img, 39, 12, 43, 17, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 43, 12, 46, 16, (255, 140, 30, 255), (255, 240, 130, 255))

    return add_outline(img)


def draw_cat_legs(style: str, primary_ramp, secondary_ramp, glow) -> Image.Image:
    """40x22 modular chassis/legs centered at (20, 11).
    Top pelvis connector (y=1..8) tucks cleanly behind BodySprite so zero gap ever appears.
    """
    img = Image.new("RGBA", (40, 22), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Hip connector collar tucked behind body
    shaded_rect(img, 14, 1, 25, 8, RAMP_DARK_IRON, bevel=True)

    if style == "tracks":
        # Heavy caterpillar treads (MULE / TITAN style)
        shaded_rect(img, 4, 9, 35, 19, RAMP_DARK_IRON, bevel=True)
        # Armored track fender skirt
        shaded_rect(img, 7, 7, 32, 12, primary_ramp, bevel=True, rivets=True)
        # Bogie wheels + tread notches
        for wx in (8, 15, 24, 31):
            shaded_ellipse(img, wx, 15, 3.0, 3.0, RAMP_STEEL)
            put_px(img, wx, 15, glow)
        for tx in range(5, 35, 3):
            put_px(img, tx, 19, RAMP_CHROME[1])

    elif style == "hover":
        # Patched troubadour breeches + rooster cyber-talon + brown boot + emerald hover ring
        shaded_rect(img, 11, 5, 17, 13, RAMP_OLIVE, bevel=True)
        shaded_rect(img, 22, 5, 28, 13, RAMP_OLIVE, bevel=True)
        put_px(img, 13, 9, RAMP_CRIMSON[2])  # red knee patch
        # Left claw talon, right laced boot
        shaded_rect(img, 10, 13, 16, 16, RAMP_PURPLE, bevel=True)
        shaded_rect(img, 22, 12, 29, 16, RAMP_LEATHER, bevel=True)
        # Glowing hover coil ring
        shaded_rect(img, 8, 17, 31, 19, RAMP_DARK_IRON, bevel=False)
        draw_emissive_eye(img, 9, 18, 30, 19, glow)

    elif style == "asymmetric":
        # Felix/Hound troubadour patched leg (left) + chrome cyber-leg & laced boot (right)
        shaded_rect(img, 10, 5, 17, 15, RAMP_CRIMSON if primary_ramp == RAMP_COBALT else RAMP_STEEL, bevel=True)
        put_px(img, 13, 10, RAMP_OLIVE[2])  # stitched patch
        shaded_rect(img, 8, 15, 16, 19, primary_ramp, bevel=True)  # paw
        # Right robotic leg + brown laced boot
        shaded_rect(img, 22, 5, 27, 14, RAMP_CHROME, bevel=True)
        shaded_rect(img, 21, 14, 30, 19, RAMP_LEATHER, bevel=True)
        d.line([(23, 15), (27, 15)], fill=RAMP_CHROME[2])

    else:  # salvage mech legs
        shaded_rect(img, 10, 5, 16, 15, primary_ramp, bevel=True)
        shaded_rect(img, 23, 5, 29, 15, RAMP_CHROME, bevel=True)
        shaded_rect(img, 8, 15, 17, 19, secondary_ramp, bevel=True, rivets=True)
        shaded_rect(img, 22, 15, 31, 19, secondary_ramp, bevel=True, rivets=True)
        put_px(img, 13, 10, glow)
        put_px(img, 26, 10, glow)

    return add_outline(img)


def generate_cats() -> None:
    out_dir = os.path.join(ROOT, "sprites", "cats")
    ensure_dir(out_dir)

    configs = [
        ("felix", RAMP_COBALT, RAMP_CHROME, (80, 245, 255, 255), "felix", "claws", "asymmetric"),
        ("mule", RAMP_GOLD, RAMP_LEATHER, (255, 215, 70, 255), "mule", "shield", "tracks"),
        ("hound", RAMP_CRIMSON, RAMP_CHROME, (255, 95, 65, 255), "hound", "saw", "asymmetric"),
        ("cock", RAMP_PURPLE, RAMP_TEAL, (110, 255, 175, 255), "cock", "megaphone", "hover"),
        ("titan", RAMP_TITAN, RAMP_CHROME, (60, 235, 255, 255), "titan", "rail", "tracks"),
        ("scrap", RAMP_COPPER, RAMP_DARK_IRON, (255, 165, 50, 255), "scrap", "flamer", "salvage"),
    ]

    for cid, r1, r2, glow, body_s, arm_s, leg_s in configs:
        draw_cat_body(cid, r1, r2, glow, body_s).save(os.path.join(out_dir, f"{cid}_body.png"))
        draw_cat_arms(arm_s, r1, r2, glow).save(os.path.join(out_dir, f"{cid}_arms.png"))
        draw_cat_legs(leg_s, r1, r2, glow).save(os.path.join(out_dir, f"{cid}_legs.png"))

    # --- Tiered Bremen Pyramids (64x96) ---
    # 1. 2-Tier Small Tower: bremen_pyramid_2.png (HOUND + FELIX, inspired by robo-cat-hound.jpg)
    pyr2 = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(pyr2)
    # Hound legs & crimson-drum base
    shaded_rect(pyr2, 16, 76, 25, 93, RAMP_STEEL, bevel=True)
    shaded_rect(pyr2, 38, 76, 47, 93, RAMP_LEATHER, bevel=True)
    shaded_rect(pyr2, 14, 52, 49, 77, RAMP_CRIMSON, bevel=True, rivets=True)
    draw_striped_vest(pyr2, 20, 53, 43, 73)
    # Marching drum in front
    shaded_rect(pyr2, 22, 63, 41, 76, RAMP_LEATHER, bevel=True)
    d2.line([(22, 63), (41, 63)], fill=RAMP_CHROME[3])
    # Neck collars + Dual Felix & Hound heads seated directly onto shoulders (y=41..53)
    shaded_rect(pyr2, 19, 49, 27, 54, RAMP_CHROME, bevel=True)
    shaded_rect(pyr2, 36, 49, 44, 54, RAMP_CRIMSON, bevel=True)
    shaded_ellipse(pyr2, 23, 44, 8.5, 6.5, RAMP_COBALT)
    for y in range(37, 51):
        for x in range(23, 32):
            if get_px(pyr2, x, y)[3] > 0:
                put_px(pyr2, x, y, RAMP_CHROME[2 if y < 44 else 1])
    shaded_ellipse(pyr2, 41, 44, 8.0, 6.5, RAMP_CRIMSON)
    shaded_rect(pyr2, 36, 46, 46, 52, RAMP_CHROME, bevel=True)  # Hound saw-jaw
    draw_feathered_hat(pyr2, 22, 32, brim_w=13, ramp=RAMP_OLIVE, feather_left=True)
    draw_feathered_hat(pyr2, 41, 32, brim_w=12, ramp=RAMP_LEATHER, feather_left=False)
    draw_emissive_eye(pyr2, 18, 42, 21, 44, (255, 205, 50, 255))
    draw_emissive_eye(pyr2, 25, 42, 28, 44, (80, 250, 255, 255))
    draw_emissive_eye(pyr2, 39, 42, 42, 44, (255, 190, 50, 255))
    # Resonator antenna mounted on torso & guitar neck across chest
    shaded_rect(pyr2, 30, 32, 33, 52, RAMP_STEEL, bevel=True)
    d2.polygon([(27, 32), (32, 21), (37, 32)], fill=(80, 245, 255, 255))
    d2.line([(16, 61), (48, 48)], fill=RAMP_LEATHER[2], width=3)
    draw_emissive_eye(pyr2, 30, 55, 33, 60, (90, 255, 255, 255))
    add_outline(pyr2).save(os.path.join(out_dir, "bremen_pyramid_2.png"))

    # 2. 3-Tier Medium Tower: bremen_pyramid_3.png (MULE + HOUND + FELIX, inspired by robo-cat-hound-mule.jpg)
    pyr3 = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
    d3 = ImageDraw.Draw(pyr3)
    # Mule caterpillar tracks base
    shaded_rect(pyr3, 8, 76, 55, 93, RAMP_DARK_IRON, bevel=True)
    shaded_rect(pyr3, 14, 65, 49, 86, RAMP_GOLD, bevel=True, rivets=True)
    for wx in (13, 22, 41, 50):
        shaded_ellipse(pyr3, wx, 86, 3.5, 3.5, RAMP_STEEL)
    # Hound crimson mid-tier + twin drums
    shaded_rect(pyr3, 16, 42, 47, 66, RAMP_CRIMSON, bevel=True, rivets=True)
    draw_striped_vest(pyr3, 21, 43, 42, 61)
    shaded_rect(pyr3, 14, 55, 27, 65, RAMP_LEATHER, bevel=True)
    shaded_rect(pyr3, 36, 55, 49, 65, RAMP_LEATHER, bevel=True)
    # Neck collar + Felix cobalt/chrome upper head seated flush at y=35..43
    shaded_rect(pyr3, 26, 39, 37, 44, RAMP_CHROME, bevel=True)
    shaded_ellipse(pyr3, 32, 34, 9.5, 7.5, RAMP_COBALT)
    for y in range(26, 42):
        for x in range(32, 42):
            if get_px(pyr3, x, y)[3] > 0:
                put_px(pyr3, x, y, RAMP_CHROME[2 if y < 34 else 1])
    d3.polygon([(22, 30), (23, 22), (27, 27)], fill=RAMP_COBALT[2])
    d3.polygon([(36, 27), (40, 22), (41, 30)], fill=RAMP_CHROME[2])
    draw_feathered_hat(pyr3, 31, 21, brim_w=15, ramp=RAMP_OLIVE, feather_left=True)
    draw_emissive_eye(pyr3, 25, 32, 28, 34, (255, 205, 50, 255))
    draw_emissive_eye(pyr3, 35, 32, 38, 34, (80, 250, 255, 255))
    d3.line([(16, 54), (49, 41)], fill=RAMP_LEATHER[2], width=3)
    # Mounted resonator spire on back/hat
    shaded_rect(pyr3, 30, 18, 33, 23, RAMP_STEEL, bevel=True)
    d3.polygon([(25, 19), (32, 9), (39, 19)], fill=(80, 250, 230, 255))
    draw_emissive_eye(pyr3, 30, 68, 33, 74, (90, 255, 255, 255))
    add_outline(pyr3).save(os.path.join(out_dir, "bremen_pyramid_3.png"))

    # 3. 4-Tier Full Bremen Pyramid: bremen_pyramid.png (inspired by robo-cock-cat-hound-mule.jpg)
    pyr = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
    dp = ImageDraw.Draw(pyr)
    # Base: MULE tracks + armored donkey prow on right
    shaded_rect(pyr, 7, 78, 56, 94, RAMP_DARK_IRON, bevel=True)
    shaded_rect(pyr, 12, 68, 49, 86, RAMP_GOLD, bevel=True, rivets=True)
    shaded_rect(pyr, 38, 70, 53, 81, RAMP_GOLD, bevel=True)  # donkey prow head
    shaded_rect(pyr, 38, 63, 41, 70, RAMP_GOLD, bevel=True)  # donkey ear
    draw_emissive_eye(pyr, 42, 72, 44, 74, (70, 240, 255, 255))
    for wx in (12, 22, 42, 51):
        shaded_ellipse(pyr, wx, 87, 3.5, 3.5, RAMP_STEEL)
    # Tier 2: HOUND crimson armor + drum
    shaded_rect(pyr, 15, 49, 48, 69, RAMP_CRIMSON, bevel=True, rivets=True)
    shaded_rect(pyr, 37, 57, 50, 68, RAMP_LEATHER, bevel=True)
    # Tier 3: FELIX chrome-cobalt arms + troubadour vest + guitar
    shaded_rect(pyr, 18, 32, 45, 50, RAMP_COBALT, bevel=True)
    draw_striped_vest(pyr, 22, 33, 41, 48)
    shaded_rect(pyr, 12, 35, 19, 45, RAMP_CHROME, bevel=True)
    shaded_rect(pyr, 44, 35, 51, 45, RAMP_CHROME, bevel=True)
    dp.line([(16, 47), (49, 34)], fill=RAMP_LEATHER[2], width=3)
    # Tier 4 Apex: COCK purple neck + wings + red crest + megaphone seated onto Tier 3 (y=24..34)
    shaded_rect(pyr, 25, 28, 37, 34, RAMP_PURPLE, bevel=True)
    dp.polygon([(19, 32), (7, 19), (17, 23)], fill=RAMP_PURPLE[2])
    dp.polygon([(44, 32), (56, 19), (46, 23)], fill=RAMP_PURPLE[2])
    shaded_ellipse(pyr, 31, 23, 8.5, 6.5, RAMP_PURPLE)
    for cx_off, h_top in ((26, 10), (29, 8), (32, 9), (35, 11)):
        shaded_rect(pyr, cx_off, h_top, cx_off + 2, 17, RAMP_CRIMSON, bevel=True)
    draw_feathered_hat(pyr, 31, 11, brim_w=13, ramp=RAMP_OLIVE, feather_left=True)
    draw_emissive_eye(pyr, 29, 21, 32, 24, (90, 255, 240, 255))
    dp.polygon([(36, 20), (47, 14), (47, 27), (36, 23)], fill=RAMP_CHROME[2])
    # Subtle glowing chest/waist resonator nodes (instead of covering the guitar)
    draw_emissive_eye(pyr, 30, 52, 33, 56, (90, 250, 255, 255))
    draw_emissive_eye(pyr, 30, 71, 33, 75, (90, 250, 255, 255))
    add_outline(pyr).save(os.path.join(out_dir, "bremen_pyramid.png"))

    # 4. Classic Brothers Grimm Living Animal Pyramid (bremen_animal_pyramid.png)
    anim = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
    da = ImageDraw.Draw(anim)
    # Donkey (bottom)
    shaded_rect(anim, 10, 68, 51, 85, RAMP_GOLD, bevel=True, dither=True)
    shaded_rect(anim, 12, 85, 17, 94, RAMP_LEATHER, bevel=True)
    shaded_rect(anim, 45, 85, 50, 94, RAMP_LEATHER, bevel=True)
    shaded_rect(anim, 47, 63, 57, 74, RAMP_GOLD, bevel=True)
    shaded_rect(anim, 47, 55, 50, 63, RAMP_GOLD, bevel=True)
    shaded_rect(anim, 52, 55, 55, 63, RAMP_GOLD, bevel=True)
    put_px(anim, 53, 66, (20, 20, 30, 255))
    # Dog (2nd) — paws gripping donkey's back
    shaded_rect(anim, 15, 48, 46, 66, RAMP_CRIMSON, bevel=True, dither=True)
    shaded_rect(anim, 17, 65, 22, 69, RAMP_CRIMSON, bevel=True)
    shaded_rect(anim, 41, 65, 46, 69, RAMP_CRIMSON, bevel=True)
    shaded_rect(anim, 42, 44, 52, 56, RAMP_CRIMSON, bevel=True)
    shaded_rect(anim, 40, 46, 44, 54, RAMP_LEATHER, bevel=True)
    put_px(anim, 48, 47, (255, 220, 90, 255))
    # Cat (3rd) — arched back & paws on dog
    shaded_rect(anim, 19, 31, 43, 47, RAMP_COBALT, bevel=True, dither=True)
    shaded_rect(anim, 21, 46, 25, 50, RAMP_COBALT, bevel=True)
    shaded_rect(anim, 38, 46, 42, 50, RAMP_COBALT, bevel=True)
    shaded_ellipse(anim, 43, 32, 6.0, 5.5, RAMP_COBALT)
    da.polygon([(38, 28), (40, 21), (43, 27)], fill=RAMP_COBALT[2])
    da.polygon([(44, 27), (47, 21), (48, 28)], fill=RAMP_COBALT[2])
    da.line([(19, 36), (11, 28)], fill=RAMP_COBALT[2], width=3)
    put_px(anim, 45, 31, (255, 220, 70, 255))
    # Rooster (top) — standing on cat's back
    shaded_rect(anim, 28, 28, 34, 32, RAMP_GOLD, bevel=True)
    shaded_ellipse(anim, 31, 23, 7.5, 5.5, RAMP_PURPLE, dither=True)
    shaded_rect(anim, 34, 14, 41, 22, RAMP_PURPLE, bevel=True)
    for cx_o, ty in ((33, 8), (36, 6), (39, 9)):
        shaded_rect(anim, cx_o, ty, cx_o + 2, 14, RAMP_CRIMSON, bevel=True)
    da.polygon([(41, 16), (47, 18), (41, 20)], fill=RAMP_GOLD[2])
    put_px(anim, 38, 16, (255, 255, 255, 255))
    add_outline(anim).save(os.path.join(out_dir, "bremen_animal_pyramid.png"))


def _draw_portrait_mood_fx(
    img: Image.Image,
    mood: str,
    eye_positions: list[tuple[int, int]],
    eye_col,
    mouth_y: int,
    mouth_cx: int = 32,
) -> None:
    """Applies expressive pixel-art eyes, brows, mouth, and mood overlays onto a 64x64 bust."""
    d = ImageDraw.Draw(img)

    # 1. Eyes & brows
    for idx, (ex, ey) in enumerate(eye_positions):
        if mood == "normal":
            shaded_rect(img, ex - 3, ey - 2, ex + 3, ey + 2, RAMP_DARK_IRON, bevel=False)
            draw_emissive_eye(img, ex - 2, ey - 1, ex + 2, ey + 1, eye_col)
        elif mood == "battle":
            shaded_rect(img, ex - 3, ey - 2, ex + 3, ey + 2, RAMP_DARK_IRON, bevel=False)
            flare = (255, 95, 50, 255) if idx == 0 else eye_col
            draw_emissive_eye(img, ex - 2, ey - 1, ex + 2, ey + 1, flare)
            # Fierce angled brow
            if idx == 0:
                d.line([(ex - 4, ey - 4), (ex + 3, ey - 2)], fill=OUTLINE, width=2)
            else:
                d.line([(ex - 3, ey - 2), (ex + 4, ey - 4)], fill=OUTLINE, width=2)
        elif mood == "damaged":
            shaded_rect(img, ex - 3, ey - 2, ex + 3, ey + 2, RAMP_DARK_IRON, bevel=False)
            if idx == 0:
                d.line([(ex - 3, ey - 2), (ex + 3, ey + 2)], fill=(255, 70, 60, 255), width=2)
                d.line([(ex + 3, ey - 2), (ex - 3, ey + 2)], fill=(255, 70, 60, 255), width=2)
            else:
                draw_emissive_eye(img, ex - 2, ey, ex + 2, ey + 1, eye_col)
        elif mood == "glitch":
            shaded_rect(img, ex - 4, ey - 2, ex + 4, ey + 2, RAMP_DARK_IRON, bevel=False)
            d.line([(ex - 4, ey - 1), (ex + 4, ey - 1)], fill=(80, 255, 255, 255))
            d.line([(ex - 3, ey + 1), (ex + 5, ey + 1)], fill=(255, 60, 210, 255))
        elif mood in ("panic", "shocked"):
            # Wide white sclera + tiny trembling pupil
            d.ellipse([ex - 4, ey - 4, ex + 4, ey + 4], fill=(248, 250, 255, 255), outline=OUTLINE)
            put_px(img, ex, ey, (20, 20, 35, 255))
            put_px(img, ex + 1, ey, (20, 20, 35, 255))
            d.line([(ex - 4, ey - 6), (ex + 4, ey - 6)], fill=OUTLINE)
        elif mood == "happy":
            # Warm upturned ^ ^ crescent eyes
            d.arc([ex - 3, ey - 2, ex + 3, ey + 4], 195, 345, fill=eye_col, width=2)
            put_px(img, ex, ey - 2, (255, 255, 230, 255))

    # 2. Mouth / jaw expression
    if mood == "normal":
        d.line([(mouth_cx - 4, mouth_y), (mouth_cx + 4, mouth_y)], fill=OUTLINE)
        put_px(img, mouth_cx + 4, mouth_y - 1, OUTLINE)
    elif mood == "battle":
        d.rectangle([mouth_cx - 5, mouth_y - 1, mouth_cx + 5, mouth_y + 2], fill=(235, 240, 248, 255), outline=OUTLINE)
        d.line([(mouth_cx - 2, mouth_y - 1), (mouth_cx - 2, mouth_y + 2)], fill=OUTLINE)
        d.line([(mouth_cx + 2, mouth_y - 1), (mouth_cx + 2, mouth_y + 2)], fill=OUTLINE)
    elif mood == "damaged":
        d.line([(mouth_cx - 5, mouth_y + 1), (mouth_cx - 1, mouth_y - 1), (mouth_cx + 4, mouth_y + 1)], fill=OUTLINE)
    elif mood in ("panic", "shocked"):
        d.ellipse([mouth_cx - 4, mouth_y - 2, mouth_cx + 4, mouth_y + 4], fill=(160, 30, 45, 255), outline=OUTLINE)
    elif mood == "happy":
        d.arc([mouth_cx - 5, mouth_y - 3, mouth_cx + 5, mouth_y + 3], 10, 170, fill=OUTLINE, width=2)
        d.line([(mouth_cx - 4, mouth_y), (mouth_cx + 4, mouth_y)], fill=(250, 250, 255, 255))

    # 3. Mood-specific overlays
    if mood == "damaged":
        # Cracks & flying sparks
        d.line([(16, 22), (22, 30), (19, 36)], fill=(20, 16, 24, 255), width=1)
        d.line([(45, 28), (41, 37)], fill=(20, 16, 24, 255), width=1)
        for sx, sy in ((15, 25), (46, 23), (21, 44), (43, 41)):
            put_px(img, sx, sy, (255, 190, 50, 255))
            put_px(img, sx + 1, sy - 1, (255, 80, 40, 255))
    elif mood == "panic":
        # Sweat drop on temple
        d.polygon([(50, 18), (47, 25), (53, 25)], fill=(90, 210, 255, 255), outline=OUTLINE)
        put_px(img, 49, 23, (235, 255, 255, 255))
    elif mood == "shocked":
        # Yellow shock lightning ticks
        d.line([(8, 16), (13, 20)], fill=(255, 230, 60, 255), width=2)
        d.line([(55, 16), (50, 20)], fill=(255, 230, 60, 255), width=2)
        d.line([(32, 6), (32, 10)], fill=(255, 230, 60, 255), width=2)
    elif mood == "happy":
        # Golden music note
        d.ellipse([48, 16, 53, 20], fill=(255, 220, 70, 255))
        d.line([(53, 18), (53, 10), (57, 12)], fill=(255, 220, 70, 255), width=2)
    elif mood == "glitch":
        # Horizontal scanline displacement slices + RGB corruption bars (clamped inside portrait interior)
        tmp = img.copy()
        for sy, shift in ((15, 3), (22, -3), (29, 3), (36, -3), (44, 2)):
            strip = tmp.crop((6, sy, 58, sy + 3))
            img.paste(strip, (6 + shift, sy))
        d.rectangle([10, 18, 22, 20], fill=(80, 255, 255, 220))
        d.rectangle([40, 31, 53, 33], fill=(255, 60, 210, 220))


def generate_portraits() -> None:
    """Generates 64x64 pixel-art portraits for 8 characters x 7 moods."""
    out_dir = os.path.join(ROOT, "sprites", "portraits")
    ensure_dir(out_dir)

    char_specs = {
        "felix": (RAMP_COBALT, (80, 245, 255, 255), (28, 32, 54)),
        "mule": (RAMP_GOLD, (70, 240, 255, 255), (46, 32, 24)),
        "hound": (RAMP_CRIMSON, (255, 190, 55, 255), (42, 22, 28)),
        "cock": (RAMP_PURPLE, (95, 255, 225, 255), (34, 24, 52)),
        "atamansha": (RAMP_CRIMSON, (255, 210, 65, 255), (46, 22, 34)),
        "press": (RAMP_STEEL, (255, 70, 50, 255), (36, 26, 24)),
        "satellite": (RAMP_CHROME, (95, 245, 255, 255), (18, 28, 52)),
        "outlaw": (RAMP_BLONDE, (255, 65, 65, 255), (26, 26, 38)),
    }
    moods = ["normal", "battle", "damaged", "glitch", "panic", "shocked", "happy"]

    for name, (accent_ramp, eye_col, bg_base) in char_specs.items():
        for mood in moods:
            img = Image.new("RGBA", (64, 64), (*bg_base, 255))
            d = ImageDraw.Draw(img)

            # Warm Bremen dusk backdrop gradient
            for y in range(2, 62):
                for x in range(2, 62):
                    grad = y / 64.0
                    r = int(bg_base[0] * (1.0 - 0.3 * grad) + 28 * grad)
                    g = int(bg_base[1] * (1.0 - 0.3 * grad) + 20 * grad)
                    b = int(bg_base[2] * (1.0 - 0.2 * grad) + 18 * grad)
                    if mood == "battle":
                        r = min(255, r + 18)
                    elif mood == "damaged":
                        r = max(0, r - 8)
                        g = max(0, g - 8)
                    put_px(img, x, y, (r, g, b, 255))

            bust = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
            db = ImageDraw.Draw(bust)

            if name == "felix":
                # Troubadour striped collar & shoulders
                shaded_rect(bust, 12, 46, 51, 61, RAMP_COBALT, bevel=True)
                draw_striped_vest(bust, 17, 46, 46, 61)
                # Head: left organic cobalt cat, right chrome cybernetic face
                shaded_ellipse(bust, 32, 31, 15.5, 13.5, RAMP_COBALT, dither=True)
                for y in range(17, 46):
                    for x in range(32, 49):
                        if get_px(bust, x, y)[3] > 0:
                            t = 0.72 - 0.35 * ((x - 32) / 16.0) - 0.25 * ((y - 17) / 28.0)
                            put_px(bust, x, y, ramp_tone(RAMP_CHROME, t, x, y, dither=True))
                # Cat ears seated on head
                db.polygon([(16, 25), (17, 10), (26, 20)], fill=RAMP_COBALT[1])
                db.polygon([(18, 22), (19, 13), (23, 19)], fill=RAMP_CRIMSON[2])
                db.polygon([(38, 20), (47, 10), (48, 25)], fill=RAMP_CHROME[2])
                # Olive feathered beret seated snugly onto brow (top_y=12)
                draw_feathered_hat(bust, 31, 12, brim_w=24, ramp=RAMP_OLIVE, feather_left=True)
                # Whiskers & nose
                db.line([(12, 33), (20, 34)], fill=(230, 240, 255, 255))
                db.line([(12, 37), (20, 36)], fill=(230, 240, 255, 255))
                db.line([(44, 34), (52, 33)], fill=(210, 235, 255, 255))
                shaded_rect(bust, 30, 34, 33, 36, RAMP_CRIMSON, bevel=False)
                _draw_portrait_mood_fx(bust, mood, [(24, 29), (40, 29)], eye_col, 40, 32)

            elif name == "hound":
                shaded_rect(bust, 11, 47, 52, 61, RAMP_CRIMSON, bevel=True)
                draw_striped_vest(bust, 18, 48, 45, 61)
                db.line([(15, 47), (24, 61)], fill=RAMP_LEATHER[2], width=3)
                db.line([(48, 47), (39, 61)], fill=RAMP_LEATHER[2], width=3)
                shaded_ellipse(bust, 32, 30, 14.5, 13.0, RAMP_CRIMSON, dither=True)
                # Floppy hound ears
                shaded_rect(bust, 12, 22, 18, 37, RAMP_CRIMSON, bevel=True)
                shaded_rect(bust, 46, 22, 52, 35, RAMP_CRIMSON, bevel=True)
                # Hat seated directly onto crown (top_y=11)
                draw_feathered_hat(bust, 32, 11, brim_w=26, ramp=RAMP_LEATHER, feather_left=True)
                # Heavy steel muzzle + circular saw chin
                shaded_rect(bust, 22, 33, 42, 46, RAMP_CHROME, bevel=True, rivets=True)
                shaded_ellipse(bust, 32, 43, 6.5, 5.0, RAMP_CHROME)
                for tx in range(26, 39, 3):
                    put_px(bust, tx, 48, RAMP_CHROME[3])
                _draw_portrait_mood_fx(bust, mood, [(24, 27), (39, 27)], eye_col, 38, 32)
                if mood == "normal":
                    shaded_rect(bust, 20, 24, 28, 30, RAMP_DARK_IRON, bevel=False)
                    db.line([(17, 21), (31, 28)], fill=RAMP_DARK_IRON[2], width=2)

            elif name == "mule":
                shaded_rect(bust, 11, 47, 52, 61, RAMP_GOLD, bevel=True, rivets=True)
                draw_striped_vest(bust, 18, 48, 45, 61)
                # Long donkey ears
                shaded_rect(bust, 18, 6, 24, 20, RAMP_GOLD, bevel=True)
                shaded_rect(bust, 39, 6, 45, 20, RAMP_GOLD, bevel=True)
                shaded_rect(bust, 20, 9, 22, 17, RAMP_LEATHER, bevel=False)
                shaded_rect(bust, 41, 9, 43, 17, RAMP_LEATHER, bevel=False)
                # Hat seated on brow (top_y=13)
                draw_feathered_hat(bust, 31, 13, brim_w=24, ramp=RAMP_LEATHER, feather_left=True)
                # Golden head + bulldozer scoop snout positioned below mouth
                shaded_rect(bust, 17, 20, 44, 44, RAMP_GOLD, bevel=True, rivets=True)
                shaded_rect(bust, 23, 35, 52, 46, RAMP_GOLD, bevel=True)
                db.line([(51, 34), (53, 46)], fill=RAMP_CHROME[3], width=2)
                _draw_portrait_mood_fx(bust, mood, [(26, 27), (38, 27)], eye_col, 40, 38)

            elif name == "cock":
                shaded_rect(bust, 13, 47, 50, 61, RAMP_PURPLE, bevel=True)
                draw_striped_vest(bust, 18, 48, 45, 61)
                shaded_ellipse(bust, 29, 32, 13.0, 12.5, RAMP_PURPLE, dither=True)
                # Sculpted red comb emerging from hat crown
                for cx_o, top_y in ((20, 9), (26, 5), (32, 6), (38, 10)):
                    shaded_rect(bust, cx_o, top_y, cx_o + 5, 21, RAMP_CRIMSON, bevel=True)
                draw_feathered_hat(bust, 29, 13, brim_w=22, ramp=RAMP_OLIVE, feather_left=True)
                # Red wattles
                shaded_ellipse(bust, 31, 45, 4.5, 4.0, RAMP_CRIMSON)
                # Silver megaphone beak pointing right
                db.polygon([(36, 30), (54, 22), (54, 41), (36, 36)], fill=RAMP_CHROME[1])
                shaded_rect(bust, 51, 23, 55, 40, RAMP_DARK_IRON, bevel=False)
                _draw_portrait_mood_fx(bust, mood, [(24, 28), (33, 28)], eye_col, 39, 30)

            elif name == "atamansha":
                shaded_rect(bust, 11, 47, 52, 61, RAMP_CRIMSON, bevel=True)
                db.line([(16, 48), (44, 61)], fill=RAMP_LEATHER[2], width=3)
                # Copper cable dreadlocks framing face
                for bx in (13, 16, 46, 49):
                    shaded_rect(bust, bx, 21, bx + 3, 47, RAMP_COPPER, bevel=True)
                # Chrome face
                shaded_ellipse(bust, 32, 32, 13.5, 12.5, RAMP_CHROME, dither=True)
                # Wide pirate hat seated snugly onto forehead (top_y=13)
                draw_feathered_hat(bust, 32, 13, brim_w=32, ramp=RAMP_LEATHER, feather_left=True)
                _draw_portrait_mood_fx(bust, mood, [(25, 29), (39, 29)], eye_col, 39, 32)
                if mood == "normal":
                    draw_emissive_eye(bust, 23, 28, 27, 30, (255, 115, 45, 255))
                    draw_emissive_eye(bust, 37, 28, 41, 30, (70, 240, 255, 255))

            elif name == "press":
                shaded_rect(bust, 10, 47, 53, 61, RAMP_STEEL, bevel=True, rivets=True)
                draw_hazard_stripes(bust, 16, 51, 47, 58, stripe_w=4)
                # Horned steel factory helmet
                db.polygon([(14, 15), (9, 5), (18, 12)], fill=RAMP_CHROME[2])
                db.polygon([(49, 15), (54, 5), (45, 12)], fill=RAMP_CHROME[2])
                shaded_rect(bust, 15, 10, 48, 45, RAMP_CHROME, bevel=True, rivets=True, dither=True)
                shaded_rect(bust, 11, 18, 52, 22, RAMP_STEEL, bevel=True)
                shaded_rect(bust, 21, 36, 42, 44, RAMP_STEEL, bevel=True)
                _draw_portrait_mood_fx(bust, mood, [(24, 29), (39, 29)], eye_col, 39, 32)

            elif name == "satellite":
                for cx_b in (16, 22, 41, 47):
                    shaded_rect(bust, cx_b, 44, cx_b + 3, 61, RAMP_STEEL, bevel=True)
                db.polygon([(30, 14), (32, 4), (34, 14)], fill=RAMP_CHROME[2])
                db.polygon([(16, 22), (8, 14), (20, 18)], fill=RAMP_CHROME[2])
                db.polygon([(47, 22), (55, 14), (43, 18)], fill=RAMP_CHROME[2])
                db.polygon([(14, 34), (6, 34), (14, 37)], fill=RAMP_CHROME[1])
                db.polygon([(49, 34), (57, 34), (49, 37)], fill=RAMP_CHROME[1])
                shaded_ellipse(bust, 32, 32, 16.0, 15.5, RAMP_CHROME, dither=True)
                put_px(bust, 28, 21, (255, 65, 50, 255))
                put_px(bust, 35, 21, (255, 65, 50, 255))
                _draw_portrait_mood_fx(bust, mood, [(24, 31), (39, 31)], eye_col, 41, 32)

            else:  # outlaw (cyber-punk rock rival from Gemini_Generated_Image)
                shaded_rect(bust, 11, 47, 52, 61, RAMP_DARK_IRON, bevel=True, rivets=True)
                db.polygon([(12, 47), (10, 40), (16, 47)], fill=RAMP_CHROME[2])
                db.polygon([(51, 47), (53, 40), (47, 47)], fill=RAMP_CHROME[2])
                # Wild golden punk hair framing face
                shaded_ellipse(bust, 32, 23, 17.5, 13.5, RAMP_BLONDE, dither=True)
                db.polygon([(14, 24), (10, 11), (22, 16)], fill=RAMP_BLONDE[2])
                db.polygon([(49, 24), (54, 10), (42, 16)], fill=RAMP_BLONDE[2])
                # Neural cables in hair
                db.line([(16, 17), (13, 28)], fill=RAMP_CRIMSON[2], width=1)
                db.line([(47, 17), (50, 28)], fill=(80, 235, 255, 255), width=1)
                # Split half organic / half chrome face
                shaded_ellipse(bust, 32, 32, 12.5, 11.5, RAMP_LEATHER, dither=True)
                for y in range(21, 44):
                    for x in range(32, 45):
                        if get_px(bust, x, y)[3] > 0:
                            t = 0.7 - 0.35 * ((x - 32) / 12.0) - 0.25 * ((y - 21) / 22.0)
                            put_px(bust, x, y, ramp_tone(RAMP_CHROME, t, x, y, dither=True))
                _draw_portrait_mood_fx(bust, mood, [(25, 30), (39, 30)], eye_col, 39, 32)

            outlined_bust = add_outline(bust)
            img = Image.alpha_composite(img, outlined_bust)

            # Frame border (2px dark iron + 1px accent rim + 4 corner rivets)
            d = ImageDraw.Draw(img)
            d.rectangle([0, 0, 63, 63], outline=OUTLINE, width=2)
            d.rectangle([2, 2, 61, 61], outline=_rgba(accent_ramp[2]), width=1)
            for rx, ry in ((3, 3), (59, 3), (3, 59), (59, 59)):
                put_px(img, rx, ry, accent_ramp[3])

            img.save(os.path.join(out_dir, f"{name}_{mood}.png"))


def generate_enemies() -> None:
    out_dir = os.path.join(ROOT, "sprites", "enemies")
    ensure_dir(out_dir)

    # 1. Regular enemies (44x44, facing LEFT toward the squad, shaded pixel art + dark outline)
    regulars = [
        "scrap_drone",
        "acid_cleaner",
        "welder_raider",
        "security_hound",
        "spectre_drone",
        "core_sentinel",
    ]
    for name in regulars:
        img = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)

        if name == "scrap_drone":
            # Rotor on top
            shaded_rect(img, 14, 7, 34, 9, RAMP_STEEL, bevel=True)
            shaded_rect(img, 22, 9, 26, 13, RAMP_DARK_IRON, bevel=True)
            # Riveted copper orb hull
            shaded_ellipse(img, 24, 24, 12.0, 11.5, RAMP_COPPER, dither=True)
            shaded_rect(img, 14, 18, 25, 25, RAMP_DARK_IRON, bevel=False)
            draw_emissive_eye(img, 15, 20, 22, 23, (255, 165, 45, 255))
            # Claw arm pointing left
            shaded_rect(img, 4, 24, 14, 29, RAMP_STEEL, bevel=True)
            d.line([(4, 24), (1, 21)], fill=RAMP_CHROME[3], width=2)
            d.line([(4, 29), (1, 32)], fill=RAMP_CHROME[2], width=2)
            # Thruster glow
            draw_emissive_eye(img, 20, 36, 28, 38, (255, 110, 40, 255))

        elif name == "acid_cleaner":
            # Industrial green hazmat bot + glass acid tank + sprayer
            shaded_rect(img, 13, 28, 35, 38, RAMP_DARK_IRON, bevel=True)
            shaded_rect(img, 14, 14, 34, 29, RAMP_ACID, bevel=True, rivets=True)
            # Glass acid tank on back
            shaded_rect(img, 27, 8, 36, 22, RAMP_ACID, bevel=True)
            draw_emissive_eye(img, 29, 13, 34, 20, (180, 255, 70, 255))
            # Hazmat visor
            shaded_rect(img, 15, 17, 25, 23, RAMP_DARK_IRON, bevel=False)
            draw_emissive_eye(img, 16, 19, 23, 21, (190, 255, 80, 255))
            # Acid nozzle pointing left
            shaded_rect(img, 3, 22, 14, 27, RAMP_GOLD, bevel=True)
            draw_emissive_eye(img, 1, 23, 3, 26, (165, 255, 65, 255))

        elif name == "welder_raider":
            # Marauder bot with slatted welding mask & sparking plasma torch
            shaded_rect(img, 15, 30, 22, 40, RAMP_DARK_IRON, bevel=True)
            shaded_rect(img, 26, 30, 33, 40, RAMP_DARK_IRON, bevel=True)
            shaded_rect(img, 13, 14, 34, 31, RAMP_COPPER, bevel=True, rivets=True)
            shaded_rect(img, 32, 16, 38, 28, RAMP_CRIMSON, bevel=True)  # fuel tank
            # Slatted welding helmet
            shaded_rect(img, 14, 7, 29, 17, RAMP_STEEL, bevel=True)
            draw_emissive_eye(img, 15, 11, 22, 13, (255, 220, 60, 255))
            # Arc welder torch left
            shaded_rect(img, 4, 20, 14, 25, RAMP_STEEL, bevel=True)
            draw_emissive_eye(img, 1, 20, 4, 24, (255, 210, 70, 255))
            put_px(img, 2, 18, (255, 240, 140, 255))

        elif name == "security_hound":
            # Low-slung dark-crimson cyber-mastiff facing left
            shaded_rect(img, 12, 28, 17, 39, RAMP_STEEL, bevel=True)
            shaded_rect(img, 30, 28, 35, 39, RAMP_STEEL, bevel=True)
            shaded_rect(img, 13, 17, 36, 29, RAMP_CRIMSON, bevel=True, rivets=True)
            # Spiked collar & head
            shaded_rect(img, 6, 13, 17, 23, RAMP_CRIMSON, bevel=True)
            shaded_rect(img, 2, 18, 12, 23, RAMP_CHROME, bevel=True)  # chrome saw jaw
            for tx in (3, 6, 9):
                put_px(img, tx, 23, RAMP_CHROME[3])
            draw_emissive_eye(img, 8, 15, 12, 17, (255, 65, 95, 255))
            d.line([(36, 20), (41, 14)], fill=RAMP_STEEL[2], width=2)

        elif name == "spectre_drone":
            # Sleek angular navy-cobalt stealth interceptor
            d.polygon([(38, 10), (24, 16), (34, 22)], fill=RAMP_COBALT[2])
            d.polygon([(38, 34), (24, 28), (34, 22)], fill=RAMP_COBALT[0])
            shaded_ellipse(img, 23, 22, 11.5, 8.0, RAMP_COBALT, dither=True)
            shaded_rect(img, 12, 19, 23, 24, RAMP_DARK_IRON, bevel=False)
            draw_emissive_eye(img, 13, 20, 21, 23, (90, 245, 255, 255))
            # Twin phase barrels left
            shaded_rect(img, 2, 18, 13, 21, RAMP_CHROME, bevel=True)
            shaded_rect(img, 2, 24, 13, 27, RAMP_CHROME, bevel=True)
            put_px(img, 1, 19, (90, 245, 255, 255))
            put_px(img, 1, 25, (90, 245, 255, 255))

        else:  # core_sentinel
            # Ornate dark-violet & gold guardian turret
            shaded_ellipse(img, 24, 23, 12.5, 12.5, RAMP_PURPLE, dither=True)
            shaded_rect(img, 15, 8, 33, 12, RAMP_GOLD, bevel=True)
            shaded_rect(img, 15, 34, 33, 38, RAMP_GOLD, bevel=True)
            shaded_rect(img, 16, 17, 27, 28, RAMP_DARK_IRON, bevel=False)
            draw_emissive_eye(img, 18, 19, 25, 26, (255, 95, 240, 255))
            shaded_rect(img, 2, 17, 15, 22, RAMP_GOLD, bevel=True)
            shaded_rect(img, 2, 24, 15, 29, RAMP_GOLD, bevel=True)
            put_px(img, 1, 19, (255, 110, 245, 255))
            put_px(img, 1, 26, (255, 110, 245, 255))

        add_outline(img).save(os.path.join(out_dir, f"{name}.png"))

    # 2. Modular Elites & Bosses (_body, _arms, _legs + assembled composite {name}.png)
    # Socket offsets match combat_arena.gd: ArmsJoint = (-2, 2), LegsJoint = (0, 16)
    modular_specs = [
        ("elite_crusher", 56, 48, 56, 48, 56, 28, RAMP_GOLD, (255, 110, 45, 255)),
        ("elite_driller", 56, 48, 56, 48, 56, 28, RAMP_COPPER, (255, 210, 60, 255)),
        ("elite_aegis", 56, 48, 56, 48, 56, 28, RAMP_COBALT, (90, 250, 245, 255)),
        ("boss_press", 76, 64, 80, 64, 76, 38, RAMP_CRIMSON, (255, 185, 45, 255)),
        ("boss_atamansha", 76, 64, 80, 64, 76, 38, RAMP_CRIMSON, (255, 215, 65, 255)),
        ("boss_satellite", 80, 64, 84, 64, 80, 38, RAMP_CHROME, (105, 250, 255, 255)),
    ]

    for name, bw, bh, aw, ah, lw, lh, ramp, glow in modular_specs:
        b = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        a = Image.new("RGBA", (aw, ah), (0, 0, 0, 0))
        l = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        db = ImageDraw.Draw(b)
        da = ImageDraw.Draw(a)
        dl = ImageDraw.Draw(l)

        if name.startswith("elite_"):
            # --- ELITE BODY (56x48, center (28, 24), torso y=6..42) ---
            shaded_rect(b, 17, 14, 42, 41, ramp, bevel=True, rivets=True, dither=True)
            shaded_rect(b, 19, 6, 39, 16, RAMP_STEEL, bevel=True)  # head cowl
            shaded_rect(b, 20, 9, 34, 14, RAMP_DARK_IRON, bevel=False)
            draw_emissive_eye(b, 21, 10, 31, 13, glow)
            if name == "elite_crusher":
                draw_hazard_stripes(b, 19, 31, 40, 38, stripe_w=3)
                shaded_rect(b, 25, 19, 35, 27, RAMP_DARK_IRON, bevel=False)
                draw_emissive_eye(b, 27, 21, 33, 25, glow)
            elif name == "elite_driller":
                shaded_rect(b, 38, 16, 46, 34, RAMP_DARK_IRON, bevel=True)  # exhaust boiler
                shaded_rect(b, 24, 18, 35, 30, RAMP_DARK_IRON, bevel=False)
                draw_emissive_eye(b, 26, 20, 33, 27, glow)
            else:  # elite_aegis
                shaded_rect(b, 22, 18, 38, 34, RAMP_CHROME, bevel=True)
                draw_emissive_eye(b, 26, 22, 34, 30, glow)

            # --- ELITE ARMS (56x48, center (28, 24), attaches at x=18..25, extends left x=1..20) ---
            shaded_rect(a, 18, 17, 26, 27, RAMP_STEEL, bevel=True, rivets=True)
            if name == "elite_crusher":
                # Oversized hydraulic crushing claw/hammer
                shaded_rect(a, 10, 19, 20, 25, RAMP_CHROME, bevel=True)
                shaded_rect(a, 2, 11, 12, 33, RAMP_GOLD, bevel=True, rivets=True)
                draw_hazard_stripes(a, 3, 26, 11, 31, stripe_w=2)
                draw_emissive_eye(a, 4, 14, 9, 20, glow)
            elif name == "elite_driller":
                # Spiral titanium drill cone pointing left
                shaded_rect(a, 14, 16, 22, 28, RAMP_COPPER, bevel=True)
                da.polygon([(15, 14), (1, 22), (15, 30)], fill=RAMP_CHROME[2])
                for sx in (5, 9, 13):
                    da.line([(sx, 17), (sx + 2, 27)], fill=RAMP_DARK_IRON[0], width=1)
                put_px(a, 1, 22, glow)
            else:  # elite_aegis
                # Energy riot shield + pulse barrel
                shaded_rect(a, 3, 9, 13, 37, RAMP_COBALT, bevel=True, rivets=True)
                draw_emissive_eye(a, 5, 13, 10, 33, glow)
                shaded_rect(a, 13, 18, 22, 25, RAMP_CHROME, bevel=True)

            # --- ELITE LEGS (56x28, center (28, 14), waist y=2..16 tucks behind body) ---
            shaded_rect(l, 18, 2, 40, 15, RAMP_DARK_IRON, bevel=True)
            if name == "elite_crusher":
                shaded_rect(l, 11, 14, 46, 26, RAMP_DARK_IRON, bevel=True)
                for wx in (16, 25, 34, 42):
                    shaded_ellipse(l, wx, 21, 3.0, 3.0, RAMP_STEEL)
                    put_px(l, wx, 21, glow)
            elif name == "elite_driller":
                shaded_rect(l, 13, 13, 22, 26, RAMP_STEEL, bevel=True)
                shaded_rect(l, 34, 13, 43, 26, RAMP_STEEL, bevel=True)
                shaded_rect(l, 9, 22, 23, 26, RAMP_COPPER, bevel=True)
                shaded_rect(l, 33, 22, 47, 26, RAMP_COPPER, bevel=True)
            else:  # elite_aegis
                shaded_rect(l, 16, 13, 24, 25, RAMP_CHROME, bevel=True)
                shaded_rect(l, 33, 13, 41, 25, RAMP_CHROME, bevel=True)
                draw_emissive_eye(l, 17, 23, 23, 26, glow)
                draw_emissive_eye(l, 34, 23, 40, 26, glow)

        elif name == "boss_press":
            # Horned factory boss from press.jpg (76x64 body, 80x64 arms, 76x38 legs)
            db.polygon([(24, 11), (18, 2), (29, 9)], fill=RAMP_CHROME[2])
            db.polygon([(52, 11), (58, 2), (47, 9)], fill=RAMP_CHROME[2])
            shaded_rect(b, 23, 7, 53, 28, RAMP_CHROME, bevel=True, rivets=True, dither=True)
            shaded_rect(b, 20, 13, 56, 16, RAMP_STEEL, bevel=True)  # hat brim
            draw_emissive_eye(b, 28, 18, 34, 22, (255, 55, 45, 255))
            draw_emissive_eye(b, 42, 18, 48, 22, (255, 55, 45, 255))
            shaded_rect(b, 29, 24, 47, 28, RAMP_STEEL, bevel=True)
            # Massive press block chest with hazard stripes
            shaded_rect(b, 16, 29, 60, 56, RAMP_STEEL, bevel=True, rivets=True, dither=True)
            draw_hazard_stripes(b, 18, 34, 58, 46, stripe_w=4)
            draw_emissive_eye(b, 25, 48, 28, 52, (255, 50, 45, 255))
            draw_emissive_eye(b, 48, 48, 51, 52, (255, 50, 45, 255))
            # Hydraulic press arms extending left
            shaded_rect(a, 18, 24, 30, 36, RAMP_CHROME, bevel=True, rivets=True)
            shaded_rect(a, 2, 17, 19, 45, RAMP_STEEL, bevel=True, rivets=True)
            draw_hazard_stripes(a, 4, 24, 17, 38, stripe_w=3)
            draw_emissive_eye(a, 8, 20, 13, 23, glow)
            # Wide conveyor belt base (waist y=2..27 tucked behind body, treads y=22..36)
            shaded_rect(l, 18, 2, 58, 24, RAMP_DARK_IRON, bevel=True)
            shaded_rect(l, 7, 22, 69, 36, RAMP_STEEL, bevel=True, rivets=True)
            for wx in (14, 25, 38, 51, 62):
                shaded_ellipse(l, wx, 29, 4.5, 4.5, RAMP_CHROME)
                put_px(l, wx, 29, glow)

        elif name == "boss_atamansha":
            # Cyber outlaw crane captain from atamansha.jpg
            shaded_rect(b, 22, 26, 54, 56, RAMP_CRIMSON, bevel=True, rivets=True, dither=True)
            db.line([(26, 27), (49, 55)], fill=RAMP_LEATHER[2], width=4)  # bandolier
            # Copper cable braids + chrome face + feathered pirate hat seated snugly on brow
            for bx in (20, 23, 52, 55):
                shaded_rect(b, bx, 15, bx + 2, 32, RAMP_COPPER, bevel=True)
            shaded_ellipse(b, 38, 19, 11.5, 9.5, RAMP_CHROME, dither=True)
            draw_feathered_hat(b, 38, 5, brim_w=26, ramp=RAMP_LEATHER, feather_left=False)
            draw_emissive_eye(b, 32, 16, 35, 19, (255, 115, 45, 255))
            draw_emissive_eye(b, 41, 16, 44, 19, (70, 245, 255, 255))
            db.line([(33, 23), (43, 23)], fill=(250, 250, 255, 255), width=2)
            # Chrome arm wielding superheated plasma cleaver pointing left
            shaded_rect(a, 19, 25, 30, 35, RAMP_CHROME, bevel=True, rivets=True)
            shaded_rect(a, 14, 29, 21, 36, RAMP_LEATHER, bevel=True)
            da.polygon([(16, 30), (2, 46), (8, 51), (20, 35)], fill=RAMP_CRIMSON[2])
            da.line([(2, 46), (16, 31)], fill=(255, 230, 120, 255), width=2)
            for sx, sy in ((4, 42), (10, 49), (6, 38)):
                put_px(a, sx, sy, (255, 240, 120, 255))
            # Outlaw ragged skirt + chrome legs + spurred boots
            shaded_rect(l, 22, 2, 54, 26, RAMP_TEAL, bevel=True)
            put_px(l, 30, 18, RAMP_GOLD[2])
            shaded_rect(l, 25, 22, 32, 31, RAMP_CHROME, bevel=True)
            shaded_rect(l, 44, 22, 51, 31, RAMP_CHROME, bevel=True)
            shaded_rect(l, 21, 30, 33, 36, RAMP_LEATHER, bevel=True)
            shaded_rect(l, 42, 30, 54, 36, RAMP_LEATHER, bevel=True)

        else:  # boss_satellite (Sputnik Bremen-4 from sputnik.jpg)
            # Spikes radiating from central sphere
            db.polygon([(38, 12), (40, 2), (42, 12)], fill=RAMP_CHROME[2])
            db.polygon([(22, 18), (12, 8), (26, 14)], fill=RAMP_CHROME[2])
            db.polygon([(58, 18), (68, 8), (54, 14)], fill=RAMP_CHROME[2])
            db.polygon([(18, 32), (8, 32), (18, 36)], fill=RAMP_CHROME[1])
            db.polygon([(62, 32), (72, 32), (62, 36)], fill=RAMP_CHROME[1])
            # Massive riveted Sputnik sphere
            shaded_ellipse(b, 40, 33, 21.0, 20.5, RAMP_CHROME, dither=True)
            draw_hazard_stripes(b, 26, 48, 54, 53, stripe_w=4)
            # Twin circular ocular lenses + red LEDs
            shaded_ellipse(b, 32, 32, 6.0, 6.0, RAMP_DARK_IRON)
            shaded_ellipse(b, 48, 32, 6.0, 6.0, RAMP_DARK_IRON)
            draw_emissive_eye(b, 29, 29, 35, 35, glow)
            draw_emissive_eye(b, 45, 29, 51, 35, glow)
            put_px(b, 35, 21, (255, 60, 50, 255))
            put_px(b, 44, 21, (255, 60, 50, 255))
            # Orbital emitter dishes pointing left
            shaded_rect(a, 18, 24, 29, 38, RAMP_STEEL, bevel=True, rivets=True)
            da.polygon([(18, 22), (3, 14), (3, 46), (18, 39)], fill=RAMP_CHROME[1])
            draw_emissive_eye(a, 4, 22, 10, 38, glow)
            # Armored broadcast pedestal + anti-grav thruster ring
            shaded_rect(l, 22, 2, 58, 26, RAMP_STEEL, bevel=True, rivets=True)
            shaded_rect(l, 14, 24, 66, 34, RAMP_DARK_IRON, bevel=True)
            for gx in (20, 32, 48, 60):
                draw_emissive_eye(l, gx - 2, 28, gx + 2, 32, glow)

        b_out = add_outline(b)
        a_out = add_outline(a)
        l_out = add_outline(l)
        b_out.save(os.path.join(out_dir, f"{name}_body.png"))
        a_out.save(os.path.join(out_dir, f"{name}_arms.png"))
        l_out.save(os.path.join(out_dir, f"{name}_legs.png"))

        # Assembled composite preview matching combat_arena.gd offsets (body=(0,0), arms=(-2,2), legs=(0,16))
        cw = max(bw, aw) + 12
        ch = bh + 28
        comp = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        cx, cy = cw // 2, ch // 2 - 4
        comp.alpha_composite(l_out, (cx - lw // 2, cy + 16 - lh // 2))
        comp.alpha_composite(b_out, (cx - bw // 2, cy - bh // 2))
        comp.alpha_composite(a_out, (cx - 2 - aw // 2, cy + 2 - ah // 2))
        comp.save(os.path.join(out_dir, f"{name}.png"))



def generate_ui_and_dodge() -> None:
    ui_dir = os.path.join(ROOT, "sprites", "ui")
    ensure_dir(ui_dir)

    # 3-segment Dodge Avatar (Top=Arms, Mid=Body, Bot=Legs)
    top = Image.new("RGBA", (18, 6), (0, 0, 0, 0))
    dt = ImageDraw.Draw(top)
    dt.rectangle([2, 0, 15, 5], fill=(255, 170, 50, 255), outline=(255, 230, 140, 255))
    top.save(os.path.join(ui_dir, "dodge_top.png"))

    mid = Image.new("RGBA", (18, 8), (0, 0, 0, 0))
    dm = ImageDraw.Draw(mid)
    dm.rectangle([0, 0, 17, 7], fill=(60, 200, 255, 255), outline=(200, 255, 255, 255))
    mid.save(os.path.join(ui_dir, "dodge_mid.png"))

    bot = Image.new("RGBA", (18, 6), (0, 0, 0, 0))
    db = ImageDraw.Draw(bot)
    db.rectangle([3, 0, 14, 5], fill=(120, 240, 120, 255), outline=(200, 255, 200, 255))
    bot.save(os.path.join(ui_dir, "dodge_bot.png"))

    # Bullets
    saw = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    ds = ImageDraw.Draw(saw)
    ds.ellipse([1, 1, 10, 10], fill=(220, 220, 235, 255), outline=(255, 70, 70, 255))
    saw.save(os.path.join(ui_dir, "bullet_saw.png"))

    laser = Image.new("RGBA", (16, 6), (0, 0, 0, 0))
    dl = ImageDraw.Draw(laser)
    dl.rectangle([0, 1, 15, 4], fill=(255, 60, 90, 255), outline=(255, 200, 200, 255))
    laser.save(os.path.join(ui_dir, "bullet_laser.png"))

    acid = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    da = ImageDraw.Draw(acid)
    da.ellipse([1, 1, 8, 8], fill=(140, 255, 60, 255), outline=(40, 160, 40, 255))
    acid.save(os.path.join(ui_dir, "bullet_acid.png"))

    press = Image.new("RGBA", (22, 12), (0, 0, 0, 0))
    dp = ImageDraw.Draw(press)
    dp.rectangle([0, 0, 21, 11], fill=(200, 110, 40, 255), outline=(255, 210, 80, 255))
    press.save(os.path.join(ui_dir, "bullet_press.png"))

    # Heavy hydraulic hammer head (24x20)
    hammer = Image.new("RGBA", (24, 20), (0, 0, 0, 0))
    dh = ImageDraw.Draw(hammer)
    dh.rectangle([9, 0, 14, 6], fill=(100, 105, 115, 255), outline=(20, 22, 28, 255))
    dh.rectangle([1, 6, 22, 18], fill=(180, 70, 40, 255), outline=(255, 180, 60, 255))
    dh.line([(4, 8), (8, 16)], fill=(255, 230, 80, 255), width=2)
    dh.line([(10, 8), (14, 16)], fill=(255, 230, 80, 255), width=2)
    dh.line([(16, 8), (20, 16)], fill=(255, 230, 80, 255), width=2)
    hammer.save(os.path.join(ui_dir, "bullet_hammer.png"))

    # Metal shard / debris (10x8)
    shard = Image.new("RGBA", (10, 8), (0, 0, 0, 0))
    dsh = ImageDraw.Draw(shard)
    dsh.polygon([(1, 4), (5, 1), (9, 3), (7, 7), (2, 6)], fill=(255, 160, 50, 255), outline=(255, 240, 140, 255))
    shard.save(os.path.join(ui_dir, "bullet_shard.png"))

    # Homing radio sphere / electromagnetic orb (14x14)
    orb = Image.new("RGBA", (14, 14), (0, 0, 0, 0))
    do = ImageDraw.Draw(orb)
    do.ellipse([1, 1, 12, 12], fill=(160, 60, 240, 255), outline=(220, 140, 255, 255))
    do.ellipse([4, 4, 9, 9], fill=(255, 220, 255, 255))
    do.point([(0, 6), (0, 7), (13, 6), (13, 7), (6, 0), (7, 0), (6, 13), (7, 13)], fill=(120, 240, 255, 255))
    orb.save(os.path.join(ui_dir, "bullet_orb.png"))

    # Orbital bombardment energy bomb (14x22)
    sat_bomb = Image.new("RGBA", (14, 22), (0, 0, 0, 0))
    dsb = ImageDraw.Draw(sat_bomb)
    dsb.polygon([(6, 21), (1, 12), (3, 2), (10, 2), (12, 12)], fill=(40, 220, 255, 255), outline=(240, 255, 255, 255))
    dsb.rectangle([4, 4, 9, 14], fill=(255, 255, 255, 255))
    sat_bomb.save(os.path.join(ui_dir, "bullet_satellite_bomb.png"))

    # Phase interference / glitch pulse (18x10)
    pulse = Image.new("RGBA", (18, 10), (0, 0, 0, 0))
    dpul = ImageDraw.Draw(pulse)
    dpul.line([(1, 5), (5, 1), (9, 8), (13, 2), (17, 5)], fill=(80, 220, 255, 255), width=2)
    pulse.save(os.path.join(ui_dir, "bullet_pulse.png"))

    # Map node icons (24x24)
    nodes = [
        ("node_combat", (220, 75, 75, 255)),
        ("node_elite", (240, 160, 40, 255)),
        ("node_workshop", (70, 190, 240, 255)),
        ("node_event", (180, 100, 240, 255)),
        ("node_boss", (255, 40, 90, 255)),
    ]
    for nname, col in nodes:
        ni = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
        dn = ImageDraw.Draw(ni)
        dn.rounded_rectangle([2, 2, 21, 21], radius=4, fill=(24, 28, 38, 255), outline=col, width=2)
        dn.ellipse([7, 7, 16, 16], fill=col)
        ni.save(os.path.join(ui_dir, f"{nname}.png"))

    # Project Icon (64x64)
    icon = Image.new("RGBA", (64, 64), (18, 22, 32, 255))
    di = ImageDraw.Draw(icon)
    di.rectangle([2, 2, 61, 61], outline=(80, 240, 255, 255), width=2)
    di.polygon([(14, 24), (22, 10), (30, 24)], fill=(55, 145, 220, 255))
    di.polygon([(34, 24), (42, 10), (50, 24)], fill=(55, 145, 220, 255))
    di.rectangle([14, 24, 50, 50], fill=(55, 145, 220, 255), outline=(235, 135, 45, 255), width=2)
    di.rectangle([18, 30, 46, 38], fill=(15, 18, 26, 255))
    di.rectangle([22, 32, 28, 36], fill=(80, 255, 255, 255))
    di.rectangle([36, 32, 42, 36], fill=(80, 255, 255, 255))
    icon.save(os.path.join(PROJECT_DIR, "icon.png"))


def generate_backgrounds() -> None:
    bg_dir = os.path.join(ROOT, "sprites", "backgrounds")
    ensure_dir(bg_dir)
    bgs = [
        ("bg_sector1", (26, 22, 20), (52, 38, 30), (210, 120, 50)),
        ("bg_sector2", (20, 24, 32), (38, 44, 62), (230, 70, 110)),
        ("bg_sector3", (14, 20, 36), (26, 42, 76), (70, 230, 255)),
        ("bg_sector4", (12, 18, 36), (24, 38, 70), (60, 210, 255)),
        ("bg_hub", (22, 26, 30), (42, 50, 58), (255, 180, 60)),
    ]
    for name, sky, ground, accent in bgs:
        img = Image.new("RGBA", (640, 360), (*sky, 255))
        d = ImageDraw.Draw(img)
        # Distant skyline silhouettes
        random.seed(name)
        for x in range(0, 640, 32):
            h = random.randint(90, 180)
            d.rectangle([x, 220 - h, x + 28, 220], fill=(sky[0] + 10, sky[1] + 10, sky[2] + 14, 255))
        # Bremen-4 Relay Spire on horizon
        d.polygon([(310, 220), (320, 35), (330, 220)], fill=(45, 55, 70, 255))
        d.ellipse([317, 32, 323, 38], fill=(*accent, 255))
        # Ground plane
        d.rectangle([0, 220, 640, 360], fill=(*ground, 255))
        d.line([(0, 220), (640, 220)], fill=(*accent, 255), width=2)
        img.save(os.path.join(bg_dir, f"{name}.png"))


def _draw_mini_unit(d: ImageDraw.ImageDraw, x: int, y: int, body_col, eye_col, kind: str) -> None:
    """Draws a recognizable mini pixel-art character for story cutscene panels."""
    # Legs/tracks
    d.rectangle([x + 2, y + 18, x + 16, y + 24], fill=(55, 60, 72, 255), outline=(15, 18, 24, 255))
    # Torso
    d.rectangle([x, y + 8, x + 18, y + 19], fill=body_col, outline=(15, 18, 24, 255))
    # Head
    d.rectangle([x + 2, y, x + 16, y + 9], fill=body_col, outline=(15, 18, 24, 255))
    # Eyes
    d.rectangle([x + 5, y + 3, x + 8, y + 6], fill=eye_col)
    d.rectangle([x + 11, y + 3, x + 14, y + 6], fill=eye_col)
    if kind == "felix":
        d.polygon([(x + 2, y), (x + 5, y - 5), (x + 8, y)], fill=body_col)
        d.polygon([(x + 10, y), (x + 13, y - 5), (x + 16, y)], fill=body_col)
    elif kind == "hound":
        d.rectangle([x + 4, y + 7, x + 15, y + 10], fill=(210, 215, 225, 255))
        d.polygon([(x + 2, y), (x + 6, y - 4), (x + 9, y)], fill=body_col)
    elif kind == "mule":
        # Long donkey ears
        d.rectangle([x + 1, y - 8, x + 5, y], fill=body_col, outline=(15, 18, 24, 255))
        d.rectangle([x + 13, y - 8, x + 17, y], fill=body_col, outline=(15, 18, 24, 255))
    elif kind == "cock":
        # Red rooster crest
        d.polygon([(x + 6, y), (x + 9, y - 7), (x + 13, y)], fill=(255, 55, 110, 255))


def _draw_note(d: ImageDraw.ImageDraw, x: int, y: int, col) -> None:
    d.ellipse([x, y + 6, x + 5, y + 10], fill=col)
    d.line([(x + 5, y + 8), (x + 5, y)], fill=col, width=1)
    d.line([(x + 5, y), (x + 10, y + 2)], fill=col, width=2)


def generate_story_illustrations() -> None:
    story_dir = os.path.join(ROOT, "sprites", "story")
    ensure_dir(story_dir)
    W, H = 260, 92

    # 1. story_cat_exile.png: Old cat warming by reactor with synth-lute vs Acid disposal order
    img = Image.new("RGBA", (W, H), (22, 18, 28, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(90, 200, 255, 255), width=2)
    # Warm fireplace reactor on left
    d.rectangle([14, 22, 58, 76], fill=(65, 45, 40, 255), outline=(255, 140, 50, 255), width=2)
    d.ellipse([22, 36, 50, 68], fill=(255, 120, 30, 255))
    d.ellipse([28, 44, 44, 62], fill=(255, 230, 90, 255))
    # FELIX sitting by warm reactor with lute
    _draw_mini_unit(d, 68, 48, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    d.ellipse([78, 56, 94, 66], fill=(235, 165, 45, 255), outline=(20, 20, 20, 255))
    d.line([(88, 60), (104, 52)], fill=(235, 165, 45, 255), width=2)
    _draw_note(d, 92, 26, (80, 255, 255, 255))
    _draw_note(d, 110, 18, (255, 220, 80, 255))
    # Little cyber-mouse escaping unharmed
    d.ellipse([112, 68, 122, 74], fill=(150, 160, 175, 255))
    d.line([(106, 71), (112, 71)], fill=(255, 100, 150, 255), width=1)
    # Cruel Master monitor & Acid Vat on right
    d.rectangle([156, 12, 242, 46], fill=(45, 15, 22, 255), outline=(255, 50, 60, 255), width=2)
    d.line([(170, 20), (186, 36)], fill=(255, 60, 60, 255), width=3)
    d.line([(186, 20), (170, 36)], fill=(255, 60, 60, 255), width=3)
    d.line([(198, 28), (230, 28)], fill=(255, 80, 80, 255), width=3)
    d.polygon([(214, 38), (206, 30), (222, 30)], fill=(255, 80, 80, 255))
    # Bubbling green acid vat below monitor
    d.rectangle([162, 54, 238, 82], fill=(25, 75, 30, 255), outline=(120, 255, 80, 255), width=2)
    for bx in (176, 196, 218):
        d.ellipse([bx, 48, bx + 8, 56], fill=(140, 255, 90, 255))
    img.save(os.path.join(story_dir, "story_cat_exile.png"))

    # 2. story_cat_alone_road.png: FELIX walking alone at night toward glowing Bremen-4 tower
    img = Image.new("RGBA", (W, H), (14, 18, 34, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(80, 220, 255, 255), width=2)
    # Stars
    for sx, sy in [(25, 16), (60, 12), (105, 22), (145, 14), (180, 24)]:
        d.point((sx, sy), fill=(220, 240, 255, 255))
    # Road perspective
    d.polygon([(0, 88), (W, 88), (215, 58), (45, 58)], fill=(42, 46, 58, 255))
    d.line([(0, 58), (W, 58)], fill=(90, 110, 140, 255), width=1)
    # Distant Bremen-4 Tower with glowing beacon & music waves
    d.polygon([(205, 58), (215, 12), (225, 58)], fill=(60, 80, 115, 255), outline=(100, 240, 255, 255))
    d.ellipse([211, 8, 219, 16], fill=(255, 230, 70, 255))
    d.arc([198, 2, 232, 28], 0, 360, fill=(80, 255, 255, 255), width=1)
    _draw_note(d, 186, 12, (255, 220, 70, 255))
    # Lonely FELIX walking on left with synth-guitar
    _draw_mini_unit(d, 48, 48, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    d.line([(44, 52), (66, 64)], fill=(235, 165, 45, 255), width=3)
    _draw_note(d, 74, 36, (80, 255, 255, 255))
    img.save(os.path.join(story_dir, "story_cat_alone_road.png"))

    # 3. story_meet_hound.png: FELIX meets exhausted H.O.U.N.D. by roadside milestone
    img = Image.new("RGBA", (W, H), (28, 22, 24, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 110, 90, 255), width=2)
    d.rectangle([0, 62, W, H], fill=(52, 40, 34, 255))
    # Milestone signpost in middle
    d.rectangle([124, 30, 130, 64], fill=(120, 125, 135, 255))
    d.polygon([(112, 24), (148, 24), (156, 30), (148, 36), (112, 36)], fill=(215, 165, 45, 255), outline=(20, 20, 20, 255))
    # FELIX on left offering paw
    _draw_mini_unit(d, 64, 42, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    d.line([(82, 54), (96, 54)], fill=(80, 255, 255, 255), width=2)
    # H.O.U.N.D. sitting exhausted on right with broken chain
    _draw_mini_unit(d, 158, 44, (175, 45, 55, 255), (255, 70, 70, 255), "hound")
    d.line([(176, 62), (198, 68)], fill=(160, 165, 175, 255), width=2)
    # Hunter crosshair in distant sky (old master threat)
    d.ellipse([212, 14, 236, 38], outline=(255, 60, 60, 255), width=1)
    d.line([(224, 10), (224, 42)], fill=(255, 60, 60, 255), width=1)
    d.line([(208, 26), (240, 26)], fill=(255, 60, 60, 255), width=1)
    _draw_note(d, 98, 28, (80, 255, 255, 255))
    _draw_note(d, 162, 24, (255, 90, 90, 255))
    img.save(os.path.join(story_dir, "story_meet_hound.png"))

    # 4. story_mill_mule_captive.png: Miller-Press about to crush M.U.L.E. weighed down by ore sacks
    img = Image.new("RGBA", (W, H), (32, 20, 18, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 165, 45, 255), width=2)
    d.rectangle([0, 68, W, H], fill=(55, 38, 30, 255))
    # FELIX & HOUND charging from left
    _draw_mini_unit(d, 18, 44, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    _draw_mini_unit(d, 46, 44, (175, 45, 55, 255), (255, 70, 70, 255), "hound")
    # M.U.L.E. in center-right pinned under heavy ore sacks
    _draw_mini_unit(d, 114, 46, (215, 165, 40, 255), (255, 220, 70, 255), "mule")
    d.rounded_rectangle([108, 32, 138, 48], radius=4, fill=(130, 135, 145, 255), outline=(30, 30, 35, 255))
    d.rounded_rectangle([116, 22, 142, 36], radius=4, fill=(110, 115, 125, 255), outline=(30, 30, 35, 255))
    # Giant 3-Headed Miller-Press on right looming over M.U.L.E.
    d.rectangle([172, 12, 244, 68], fill=(180, 65, 50, 255), outline=(25, 20, 20, 255), width=2)
    for hx in (180, 202, 224):
        d.rectangle([hx, 20, hx + 14, 34], fill=(20, 22, 30, 255))
        d.rectangle([hx + 3, 24, hx + 11, 30], fill=(255, 190, 40, 255))
        # Hydraulic hammers
        d.rectangle([hx + 2, 48, hx + 12, 66], fill=(95, 100, 115, 255), outline=(255, 180, 40, 255))
    img.save(os.path.join(story_dir, "story_mill_mule_captive.png"))

    # 5. story_mule_joins.png: Miller-Press wrecked, M.U.L.E. joins FELIX & H.O.U.N.D.
    img = Image.new("RGBA", (W, H), (24, 28, 36, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 220, 70, 255), width=2)
    d.rectangle([0, 66, W, H], fill=(45, 50, 62, 255))
    # Wrecked press smoking on right
    d.rectangle([196, 42, 244, 68], fill=(80, 45, 40, 255), outline=(30, 25, 25, 255))
    d.line([(202, 46), (238, 64)], fill=(255, 120, 40, 255), width=2)
    # Trio celebrating together: FELIX, HOUND, MULE
    _draw_mini_unit(d, 48, 42, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    _draw_mini_unit(d, 88, 42, (175, 45, 55, 255), (255, 70, 70, 255), "hound")
    _draw_mini_unit(d, 130, 40, (215, 165, 40, 255), (255, 220, 70, 255), "mule")
    _draw_note(d, 58, 18, (80, 255, 255, 255))
    _draw_note(d, 98, 14, (255, 90, 90, 255))
    _draw_note(d, 138, 16, (255, 220, 70, 255))
    img.save(os.path.join(story_dir, "story_mule_joins.png"))

    # 6. story_tavern_cock_soup.png: C.O.C.K. crowing in cage above boiling soup pot & Atamansha
    img = Image.new("RGBA", (W, H), (24, 18, 34, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 70, 130, 255), width=2)
    d.rectangle([0, 68, W, H], fill=(42, 34, 54, 255))
    # Trio on left
    _draw_mini_unit(d, 14, 44, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    _draw_mini_unit(d, 38, 44, (175, 45, 55, 255), (255, 70, 70, 255), "hound")
    _draw_mini_unit(d, 62, 42, (215, 165, 40, 255), (255, 220, 70, 255), "mule")
    # Hanging cage at top-center with C.O.C.K. crowing
    d.line([(130, 2), (130, 12)], fill=(180, 185, 195, 255), width=2)
    d.rectangle([114, 12, 146, 44], fill=(20, 18, 28, 255), outline=(180, 190, 210, 255), width=2)
    _draw_mini_unit(d, 121, 18, (140, 65, 195, 255), (120, 255, 160, 255), "cock")
    for cx in range(118, 146, 6):
        d.line([(cx, 12), (cx, 44)], fill=(150, 160, 175, 255), width=1)
    # Sonic rings around cage
    d.arc([104, 6, 156, 50], 0, 360, fill=(120, 255, 160, 255), width=1)
    # Boiling plasma soup cauldron below cage
    d.polygon([(112, 54), (148, 54), (142, 74), (118, 74)], fill=(60, 65, 78, 255), outline=(255, 140, 50, 255), width=2)
    d.line([(114, 54), (146, 54)], fill=(120, 255, 90, 255), width=3)
    d.rectangle([118, 74, 142, 80], fill=(255, 90, 30, 255))
    # Atamansha boss on right with laser cleaver
    d.rectangle([178, 18, 240, 68], fill=(195, 45, 95, 255), outline=(25, 15, 25, 255), width=2)
    d.rectangle([190, 28, 228, 42], fill=(20, 18, 28, 255))
    d.rectangle([196, 32, 222, 38], fill=(255, 230, 60, 255))
    # Laser cleaver in her claw
    d.rectangle([156, 34, 178, 46], fill=(255, 50, 90, 255), outline=(255, 220, 220, 255))
    img.save(os.path.join(story_dir, "story_tavern_cock_soup.png"))

    # 7. story_cock_joins_quartet.png: All 4 Bremen Musicians united!
    img = Image.new("RGBA", (W, H), (20, 24, 38, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(120, 255, 160, 255), width=2)
    d.rectangle([0, 66, W, H], fill=(38, 44, 66, 255))
    _draw_mini_unit(d, 38, 40, (215, 165, 40, 255), (255, 220, 70, 255), "mule")
    _draw_mini_unit(d, 86, 42, (175, 45, 55, 255), (255, 70, 70, 255), "hound")
    _draw_mini_unit(d, 134, 42, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    _draw_mini_unit(d, 182, 42, (140, 65, 195, 255), (120, 255, 160, 255), "cock")
    for nx, ncol in [(44, (255, 220, 70, 255)), (92, (255, 90, 90, 255)), (140, (80, 255, 255, 255)), (188, (120, 255, 160, 255))]:
        _draw_note(d, nx, 16, ncol)
    img.save(os.path.join(story_dir, "story_cock_joins_quartet.png"))

    # 7.5. story_cabin_mega_pyramid.png: Towering 15m Robo-Mega-Pyramid at outlaw radio cabin window
    img = Image.new("RGBA", (W, H), (10, 12, 24, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(80, 180, 255, 255), width=2)
    # Outlaw radio cabin on right
    d.rectangle([130, 14, 250, 86], fill=(42, 30, 24, 255), outline=(230, 160, 50, 255), width=2)
    d.rectangle([124, 24, 134, 76], fill=(255, 230, 120, 255)) # Window
    # Outlaw shadow behind window
    d.rectangle([150, 34, 174, 60], fill=(20, 16, 22, 255))
    # Giant Towering Robo-Mega-Pyramid on left
    d.rectangle([40, 62, 104, 86], fill=(215, 165, 40, 255), outline=(15, 18, 24, 255), width=2) # MULE
    d.rectangle([48, 44, 96, 62], fill=(175, 45, 55, 255), outline=(15, 18, 24, 255), width=2)  # HOUND
    d.rectangle([54, 26, 90, 44], fill=(55, 145, 220, 255), outline=(15, 18, 24, 255), width=2)  # FELIX
    d.rectangle([60, 10, 84, 26], fill=(140, 65, 195, 255), outline=(15, 18, 24, 255), width=2) # COCK
    d.polygon([(56, 10), (72, 2), (88, 10)], fill=(80, 255, 220, 255)) # Resonator antenna
    # Glowing energy spine & laser eyes
    d.rectangle([70, 14, 74, 82], fill=(120, 255, 255, 255))
    d.ellipse([80, 30, 86, 36], fill=(255, 60, 60, 255))
    d.line([(86, 33), (124, 38)], fill=(255, 50, 50, 255), width=2) # Laser pointer to window
    img.save(os.path.join(story_dir, "story_cabin_mega_pyramid.png"))

    # 8. story_bremen_window_pyramid.png: 4 Musicians stacked in Pyramid at window scaring the Satellite Boss
    img = Image.new("RGBA", (W, H), (14, 18, 32, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(100, 245, 255, 255), width=2)
    # Warm Broadcast House interior on right half
    d.rectangle([120, 6, 254, 86], fill=(48, 34, 28, 255), outline=(255, 190, 70, 255), width=2)
    # Glowing window frame in center (x=116..126)
    d.rectangle([114, 10, 126, 82], fill=(255, 235, 130, 255))
    # Pyramid of 4 animals stacked vertically on left of window (x=68)
    # Bottom: MULE
    d.rectangle([62, 64, 96, 84], fill=(215, 165, 40, 255), outline=(15, 18, 24, 255))
    # 2nd: HOUND
    d.rectangle([65, 46, 93, 64], fill=(175, 45, 55, 255), outline=(15, 18, 24, 255))
    # 3rd: FELIX
    d.rectangle([68, 28, 90, 46], fill=(55, 145, 220, 255), outline=(15, 18, 24, 255))
    # Top: COCK with red crest
    d.rectangle([71, 12, 87, 28], fill=(140, 65, 195, 255), outline=(15, 18, 24, 255))
    d.polygon([(74, 12), (79, 4), (84, 12)], fill=(255, 55, 110, 255))
    # Sonic blast crashing through window!
    for r in (16, 28, 40):
        d.arc([95 - r, 46 - r, 95 + r, 46 + r], -55, 55, fill=(120, 255, 255, 255), width=2)
    # Feast table of golden AI cores & terrified Satellite Boss inside house
    d.rectangle([142, 58, 186, 82], fill=(95, 65, 40, 255), outline=(20, 20, 20, 255))
    d.ellipse([152, 48, 164, 58], fill=(255, 220, 60, 255))
    d.ellipse([166, 48, 178, 58], fill=(80, 245, 255, 255))
    # Startled Satellite Boss
    d.rectangle([194, 22, 244, 72], fill=(70, 95, 185, 255), outline=(120, 255, 255, 255), width=2)
    d.rectangle([204, 34, 234, 48], fill=(15, 20, 32, 255))
    d.ellipse([212, 36, 226, 46], fill=(255, 70, 70, 255))
    img.save(os.path.join(story_dir, "story_bremen_window_pyramid.png"))

    # 9. story_bremen_victory_concert.png: Satellite flees into dark space, 4 Musicians broadcast from house
    img = Image.new("RGBA", (W, H), (26, 20, 36, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 225, 70, 255), width=2)
    d.rectangle([0, 68, W, H], fill=(55, 40, 48, 255))
    # Golden Microphone & Transmitter in center
    d.rectangle([124, 26, 132, 68], fill=(255, 210, 60, 255))
    d.ellipse([118, 14, 138, 32], fill=(255, 235, 90, 255), outline=(255, 140, 40, 255), width=2)
    for rad in (22, 36, 50):
        d.arc([128 - rad, 22 - rad, 128 + rad, 22 + rad], 0, 360, fill=(80, 245, 255, 255), width=1)
    # 4 Musicians around the Golden Microphone
    _draw_mini_unit(d, 26, 42, (215, 165, 40, 255), (255, 220, 70, 255), "mule")
    _draw_mini_unit(d, 64, 44, (175, 45, 55, 255), (255, 70, 70, 255), "hound")
    _draw_mini_unit(d, 152, 44, (55, 145, 220, 255), (80, 255, 255, 255), "felix")
    _draw_mini_unit(d, 188, 44, (140, 65, 195, 255), (120, 255, 160, 255), "cock")
    # Scratched & battered Satellite fleeing in top-right corner
    d.rectangle([222, 8, 250, 32], fill=(70, 95, 185, 255), outline=(255, 80, 80, 255))
    d.line([(224, 10), (248, 30)], fill=(255, 60, 60, 255), width=2)
    img.save(os.path.join(story_dir, "story_bremen_victory_concert.png"))


def write_wav(path: str, samples: list[float], sample_rate: int = 22050) -> None:
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        frames = bytearray()
        for s in samples:
            clamped = max(-1.0, min(1.0, s))
            frames.extend(struct.pack("<h", int(clamped * 32767)))
        wf.writeframes(bytes(frames))


def generate_audio() -> None:
    sfx_dir = os.path.join(ROOT, "audio", "sfx")
    tape_dir = os.path.join(ROOT, "audio", "tapes")
    ensure_dir(sfx_dir)
    ensure_dir(tape_dir)
    sr = 22050

    # 1. SFX
    # hit.wav
    write_wav(
        os.path.join(sfx_dir, "hit.wav"),
        [
            math.sin(2 * math.pi * (180 - 120 * (i / (sr * 0.15))) * (i / sr))
            * (1.0 - i / (sr * 0.15))
            * 0.6
            for i in range(int(sr * 0.15))
        ],
        sr,
    )
    # laser.wav
    write_wav(
        os.path.join(sfx_dir, "laser.wav"),
        [
            math.sin(2 * math.pi * (880 - 660 * (i / (sr * 0.18))) * (i / sr)) * 0.45
            for i in range(int(sr * 0.18))
        ],
        sr,
    )
    # part_break.wav
    random.seed(42)
    write_wav(
        os.path.join(sfx_dir, "part_break.wav"),
        [
            (random.uniform(-0.7, 0.7) + math.sin(2 * math.pi * 95 * (i / sr)) * 0.5)
            * (1.0 - i / (sr * 0.35))
            * 0.5
            for i in range(int(sr * 0.35))
        ],
        sr,
    )
    # qte_perfect.wav
    write_wav(
        os.path.join(sfx_dir, "qte_perfect.wav"),
        [
            math.sin(2 * math.pi * (523.25 if i < sr * 0.08 else 783.99) * (i / sr)) * 0.5
            for i in range(int(sr * 0.22))
        ],
        sr,
    )
    # qte_good.wav
    write_wav(
        os.path.join(sfx_dir, "qte_good.wav"),
        [math.sin(2 * math.pi * 440.0 * (i / sr)) * 0.4 for i in range(int(sr * 0.14))],
        sr,
    )
    # qte_miss.wav
    write_wav(
        os.path.join(sfx_dir, "qte_miss.wav"),
        [math.sin(2 * math.pi * 150.0 * (i / sr)) * 0.45 for i in range(int(sr * 0.18))],
        sr,
    )
    # pyramid_siren.wav
    write_wav(
        os.path.join(sfx_dir, "pyramid_siren.wav"),
        [
            math.sin(2 * math.pi * (330 + 220 * math.sin(2 * math.pi * 4 * (i / sr))) * (i / sr)) * 0.5
            for i in range(int(sr * 0.5))
        ],
        sr,
    )
    # pyramid_undock.wav (pneumatic hiss + descending 4-note chord release on undock)
    random.seed(99)
    undock_notes = [1046.50, 783.99, 659.25, 523.25]
    undock_samples: list[float] = []
    undock_len = int(sr * 0.48)
    for i in range(undock_len):
        t = i / sr
        progress = i / undock_len
        note_idx = min(3, int(progress * 4))
        freq = undock_notes[note_idx]
        env = (1.0 - progress) * 0.75
        hiss = random.uniform(-0.35, 0.35) * max(0.0, 1.0 - progress * 2.2)
        tone = (
            math.sin(2 * math.pi * freq * t) * 0.45
            + math.sin(2 * math.pi * (freq * 0.5) * t) * 0.25
        )
        undock_samples.append((tone + hiss) * env)
    write_wav(os.path.join(sfx_dir, "pyramid_undock.wav"), undock_samples, sr)
    # ui_click.wav
    write_wav(
        os.path.join(sfx_dir, "ui_click.wav"),
        [math.sin(2 * math.pi * 660.0 * (i / sr)) * (1.0 - i / (sr * 0.05)) * 0.35 for i in range(int(sr * 0.05))],
        sr,
    )
    # heal.wav
    write_wav(
        os.path.join(sfx_dir, "heal.wav"),
        [
            math.sin(2 * math.pi * (392.0 + 260.0 * (i / (sr * 0.25))) * (i / sr)) * 0.4
            for i in range(int(sr * 0.25))
        ],
        sr,
    )
    # comic_slide.wav (cartoon slide whistle + spring boing on disassembly)
    comic_len = int(sr * 0.45)
    comic_samples = []
    for i in range(comic_len):
        t = i / sr
        prog = i / comic_len
        f = 880.0 * (1.0 - 0.75 * prog) + math.sin(2 * math.pi * 14.0 * t) * 45.0
        env = (1.0 - prog * 0.5) * math.sin(math.pi * min(1.0, prog * 10.0)) * 0.55
        bounce = math.sin(2 * math.pi * 350.0 * t) * max(0.0, prog - 0.7) * 0.3
        comic_samples.append((math.sin(2 * math.pi * f * t) + bounce) * env)
    write_wav(os.path.join(sfx_dir, "comic_slide.wav"), comic_samples, sr)

    # 2. Music Tapes (2.4s loopable retro synth tracks)
    tapes = [
        ("tape_hardbass.wav", [110.0, 110.0, 220.0, 130.81, 146.83, 110.0, 164.81, 146.83]),
        ("tape_blues.wav", [146.83, 174.61, 196.00, 207.65, 196.00, 174.61, 146.83, 130.81]),
        ("tape_synth.wav", [220.0, 261.63, 329.63, 392.0, 329.63, 261.63, 246.94, 196.0]),
        ("tape_bremen_triumph.wav", [293.66, 329.63, 369.99, 440.0, 440.0, 369.99, 440.0, 587.33]),
    ]
    for fname, notes in tapes:
        samples: list[float] = []
        step_len = int(sr * 0.3)
        for note in notes:
            for i in range(step_len):
                env = max(0.15, 1.0 - (i / step_len) * 0.75)
                val = (
                    math.sin(2 * math.pi * note * (i / sr)) * 0.22
                    + math.sin(2 * math.pi * (note * 0.5) * (i / sr)) * 0.12
                ) * env
                samples.append(val)
        write_wav(os.path.join(tape_dir, fname), samples, sr)

    # 3. Character Instrument Themes & Full Ensemble (Issue #9)
    # 16 steps * 0.20s = 3.20s loop in D minor (FELIX=Guitar, MULE=Bass, HOUND=Drums, COCK=Synth)
    theme_dir = os.path.join(ROOT, "audio", "themes")
    ensure_dir(theme_dir)
    step_s = int(sr * 0.20)
    total_steps = 16

    # FELIX: Solo Guitar (plucked riff with sparse pauses — feels lonely without the rest of the band)
    guitar_notes = [
        293.66, 0.0, 349.23, 440.00, 0.0, 0.0, 392.00, 0.0,
        349.23, 0.0, 329.63, 293.66, 0.0, 0.0, 440.00, 0.0,
    ]
    # MULE: Solo Bass (deep low-end foundation filling the harmonic gaps)
    bass_notes = [
        73.42, 73.42, 0.0, 0.0, 87.31, 87.31, 0.0, 98.00,
        110.00, 110.00, 0.0, 0.0, 87.31, 82.41, 73.42, 110.00,
    ]
    # COCK: Solo Synthesizer (soaring high counter-melody lead)
    synth_notes = [
        587.33, 0.0, 698.46, 0.0, 880.00, 783.99, 698.46, 659.25,
        587.33, 659.25, 698.46, 880.00, 1046.50, 880.00, 783.99, 587.33,
    ]
    # TOWER RESONATOR ("Резонатор-Сирена Бремен"): High-energy harmonic power-chord + siren lead
    resonator_notes = [
        587.33, 587.33, 698.46, 880.00, 1046.50, 880.00, 783.99, 880.00,
        1174.66, 1046.50, 880.00, 783.99, 880.00, 1046.50, 1174.66, 1318.51,
    ]

    guitar_track: list[float] = []
    bass_track: list[float] = []
    drums_track: list[float] = []
    synth_track: list[float] = []
    duo_track: list[float] = []
    trio_track: list[float] = []
    ensemble_track: list[float] = []
    pyramid_2_track: list[float] = []
    pyramid_3_track: list[float] = []
    pyramid_4_track: list[float] = []

    random.seed(404)
    for step_idx in range(total_steps):
        g_freq = guitar_notes[step_idx]
        b_freq = bass_notes[step_idx]
        s_freq = synth_notes[step_idx]
        r_freq = resonator_notes[step_idx]
        is_kick = step_idx in (0, 4, 8, 11, 12)
        is_snare = step_idx in (2, 6, 10, 14, 15)
        is_hat = (step_idx % 2 == 1)

        for i in range(step_s):
            t = i / sr
            local_p = i / step_s

            # Guitar sample (plucked harmonics)
            g_val = 0.0
            if g_freq > 0.0:
                g_env = math.exp(-3.8 * local_p)
                g_val = (
                    math.sin(2 * math.pi * g_freq * t) * 0.30
                    + math.sin(2 * math.pi * (g_freq * 2.0) * t) * 0.16
                    + math.sin(2 * math.pi * (g_freq * 3.0) * t) * 0.08
                ) * g_env

            # Bass sample (warm sub + punchy 2nd harmonic)
            b_val = 0.0
            if b_freq > 0.0:
                b_env = max(0.15, 1.0 - local_p * 0.7)
                b_val = (
                    math.sin(2 * math.pi * b_freq * t) * 0.36
                    + math.sin(2 * math.pi * (b_freq * 2.0) * t) * 0.18
                ) * b_env

            # Drums sample (kick + snare + hi-hat)
            d_val = 0.0
            if is_kick and local_p < 0.65:
                k_freq = 145.0 - 95.0 * (local_p / 0.65)
                k_env = 1.0 - (local_p / 0.65)
                d_val += math.sin(2 * math.pi * k_freq * t) * k_env * 0.48
            if is_snare and local_p < 0.55:
                sn_env = 1.0 - (local_p / 0.55)
                d_val += (random.uniform(-0.6, 0.6) + math.sin(2 * math.pi * 190.0 * t) * 0.3) * sn_env * 0.38
            if is_hat and local_p < 0.25:
                h_env = 1.0 - (local_p / 0.25)
                d_val += random.uniform(-0.45, 0.45) * h_env * 0.22

            # Synth sample (lead with vibrato & octave shimmer)
            s_val = 0.0
            if s_freq > 0.0:
                s_env = max(0.25, 1.0 - local_p * 0.5)
                vib = 1.0 + 0.006 * math.sin(2 * math.pi * 6.0 * t)
                s_val = (
                    math.sin(2 * math.pi * (s_freq * vib) * t) * 0.24
                    + math.sin(2 * math.pi * (s_freq * 0.5 * vib) * t) * 0.12
                ) * s_env

            # Tower Resonator-Siren sample (overdrive fifth chord + siren shimmer)
            r_env = max(0.35, 1.0 - local_p * 0.35)
            siren_mod = 1.0 + 0.014 * math.sin(2 * math.pi * 8.5 * t)
            r_val = (
                math.sin(2 * math.pi * (r_freq * siren_mod) * t) * 0.26
                + math.sin(2 * math.pi * (r_freq * 0.75 * siren_mod) * t) * 0.18
                + math.sin(2 * math.pi * (r_freq * 0.5) * t) * 0.16
            ) * r_env

            guitar_track.append(g_val)
            bass_track.append(b_val)
            drums_track.append(d_val)
            synth_track.append(s_val)
            duo_track.append((g_val + d_val) * 0.78)
            trio_track.append((g_val + d_val + b_val) * 0.68)
            ensemble_track.append((g_val + b_val + d_val + s_val) * 0.62)
            pyramid_2_track.append((g_val + d_val + r_val) * 0.64)
            pyramid_3_track.append((g_val + d_val + b_val + r_val) * 0.58)
            pyramid_4_track.append((g_val + b_val + d_val + s_val + r_val * 1.15) * 0.54)

    write_wav(os.path.join(theme_dir, "theme_felix_guitar.wav"), guitar_track, sr)
    write_wav(os.path.join(theme_dir, "theme_mule_bass.wav"), bass_track, sr)
    write_wav(os.path.join(theme_dir, "theme_hound_drums.wav"), drums_track, sr)
    write_wav(os.path.join(theme_dir, "theme_cock_synth.wav"), synth_track, sr)
    write_wav(os.path.join(theme_dir, "theme_duo_cat_hound.wav"), duo_track, sr)
    write_wav(os.path.join(theme_dir, "theme_trio_cat_hound_mule.wav"), trio_track, sr)
    write_wav(os.path.join(theme_dir, "theme_bremen_ensemble.wav"), ensemble_track, sr)
    write_wav(os.path.join(theme_dir, "theme_pyramid_2.wav"), pyramid_2_track, sr)
    write_wav(os.path.join(theme_dir, "theme_pyramid_3.wav"), pyramid_3_track, sr)
    write_wav(os.path.join(theme_dir, "theme_pyramid_4.wav"), pyramid_4_track, sr)

    # 4. Boss Battle Themes on the Party's Existing Instruments (Phrygian / Minor Overdrive, 3.20s loop)
    # Boss 1 (Mill Press, Sector 1): Guitar + Drums
    boss1_guitar = [
        146.83, 155.56, 146.83, 174.61, 146.83, 155.56, 207.65, 196.00,
        146.83, 155.56, 146.83, 220.00, 207.65, 196.00, 174.61, 155.56,
    ]
    # Boss 2 (Atamansha, Sector 2): Guitar + Drums + Bass
    boss2_guitar = [
        220.00, 261.63, 246.94, 220.00, 329.63, 293.66, 261.63, 246.94,
        220.00, 261.63, 293.66, 329.63, 349.23, 329.63, 293.66, 246.94,
    ]
    boss2_bass = [
        110.00, 110.00, 123.47, 110.00, 87.31, 87.31, 98.00, 123.47,
        110.00, 110.00, 146.83, 130.81, 87.31, 98.00, 82.41, 110.00,
    ]
    # Boss 3 (Silence Conductor Satellite, Sector 3): Guitar + Drums + Bass + Synth (D harmonic minor)
    boss3_guitar = [
        293.66, 349.23, 415.30, 440.00, 466.16, 440.00, 415.30, 349.23,
        293.66, 440.00, 466.16, 554.37, 587.33, 554.37, 466.16, 440.00,
    ]
    boss3_bass = [
        73.42, 146.83, 73.42, 146.83, 87.31, 174.61, 82.41, 164.81,
        73.42, 146.83, 110.00, 98.00, 87.31, 82.41, 73.42, 110.00,
    ]
    boss3_synth = [
        587.33, 698.46, 830.61, 880.00, 932.33, 880.00, 830.61, 698.46,
        1174.66, 1108.73, 932.33, 880.00, 830.61, 698.46, 830.61, 1174.66,
    ]

    boss1_track: list[float] = []
    boss2_track: list[float] = []
    boss3_track: list[float] = []

    random.seed(707)
    for step_idx in range(total_steps):
        b1_g = boss1_guitar[step_idx]
        b2_g = boss2_guitar[step_idx]
        b2_b = boss2_bass[step_idx]
        b3_g = boss3_guitar[step_idx]
        b3_b = boss3_bass[step_idx]
        b3_s = boss3_synth[step_idx]

        for i in range(step_s):
            t = i / sr
            local_p = i / step_s
            # Double-time aggressive boss drum pattern (sub-step inside 0.20s step)
            sub_p = (local_p * 2.0) % 1.0
            is_sub_second = local_p >= 0.5

            # Aggressive drums (double-kick + sharp snare)
            bd_val = 0.0
            if sub_p < 0.55:
                kf = 160.0 - 110.0 * (sub_p / 0.55)
                bd_val += math.sin(2 * math.pi * kf * t) * (1.0 - sub_p / 0.55) * 0.46
            if (step_idx % 2 == 1 or is_sub_second) and sub_p < 0.45:
                bd_val += (random.uniform(-0.65, 0.65) + math.sin(2 * math.pi * 210.0 * t) * 0.35) * (1.0 - sub_p / 0.45) * 0.34

            # Overdriven guitar helper
            g_env = math.exp(-3.2 * local_p)
            g1_raw = math.sin(2 * math.pi * b1_g * t) * 0.38 + math.sin(2 * math.pi * (b1_g * 2.0) * t) * 0.24
            g1_val = math.tanh(g1_raw * 2.2) * 0.42 * g_env

            g2_raw = math.sin(2 * math.pi * b2_g * t) * 0.36 + math.sin(2 * math.pi * (b2_g * 2.0) * t) * 0.22
            g2_val = math.tanh(g2_raw * 2.0) * 0.38 * g_env

            g3_raw = math.sin(2 * math.pi * b3_g * t) * 0.34 + math.sin(2 * math.pi * (b3_g * 2.0) * t) * 0.20
            g3_val = math.tanh(g3_raw * 2.0) * 0.35 * g_env

            # Boss bass
            b_env = max(0.2, 1.0 - local_p * 0.65)
            b2_val = (math.sin(2 * math.pi * b2_b * t) * 0.38 + math.sin(2 * math.pi * (b2_b * 2.0) * t) * 0.22) * b_env
            b3_val = (math.sin(2 * math.pi * b3_b * t) * 0.38 + math.sin(2 * math.pi * (b3_b * 2.0) * t) * 0.22) * b_env

            # Boss 3 synth arpeggio
            s3_env = max(0.25, 1.0 - sub_p * 0.55)
            s3_freq = b3_s if not is_sub_second else (b3_s * 1.5)
            s3_val = (
                math.sin(2 * math.pi * s3_freq * t) * 0.24
                + math.sin(2 * math.pi * (s3_freq * 0.5) * t) * 0.14
            ) * s3_env

            boss1_track.append((g1_val + bd_val) * 0.76)
            boss2_track.append((g2_val + b2_val + bd_val) * 0.66)
            boss3_track.append((g3_val + b3_val + bd_val + s3_val) * 0.58)

    write_wav(os.path.join(theme_dir, "theme_boss_sector1.wav"), boss1_track, sr)
    write_wav(os.path.join(theme_dir, "theme_boss_sector2.wav"), boss2_track, sr)
    write_wav(os.path.join(theme_dir, "theme_boss_sector3.wav"), boss3_track, sr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate Xenocats pixel-art sprites and WAV audio.")
    parser.add_argument(
        "--only",
        default="all",
        help="Comma-separated sections to run (cats,portraits,enemies,ui,backgrounds,story,audio) or 'all'.",
    )
    args = parser.parse_args()
    targets = {item.strip().lower() for item in args.only.split(",") if item.strip()}
    run_all = "all" in targets or not targets

    if run_all or "cats" in targets:
        generate_cats()
    if run_all or "portraits" in targets:
        generate_portraits()
    if run_all or "enemies" in targets:
        generate_enemies()
    if run_all or "ui" in targets:
        generate_ui_and_dodge()
    if run_all or "backgrounds" in targets:
        generate_backgrounds()
    if run_all or "story" in targets:
        generate_story_illustrations()
    if run_all or "audio" in targets:
        generate_audio()
    print("All Xenocats pixel-art sprites and WAV audio assets generated!")

