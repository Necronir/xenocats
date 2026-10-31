#!/usr/bin/env python3
"""
Procedural Pixel-Art & Retro Audio Generator for Xenocats: Bremen-4
Generates crisp Nearest-Neighbor pixel sprites and 16-bit PCM WAV files.
"""

import math
import os
import random
import struct
import wave
from PIL import Image, ImageDraw

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(PROJECT_DIR, "assets")


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def draw_cat_body(cat_id: str, primary, secondary, eye_color, ear_style: str) -> Image.Image:
    img = Image.new("RGBA", (36, 30), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Torso core
    d.rectangle([8, 12, 27, 27], fill=primary, outline=(20, 22, 28, 255))
    d.rectangle([11, 15, 24, 24], fill=secondary)
    # Glowing core reactor in chest
    d.rectangle([16, 18, 19, 21], fill=eye_color)
    # Head
    d.rectangle([9, 4, 26, 14], fill=primary, outline=(20, 22, 28, 255))
    # Visor
    d.rectangle([12, 7, 24, 11], fill=(18, 20, 30, 255))
    # Glowing eyes
    d.rectangle([14, 8, 16, 10], fill=eye_color)
    d.rectangle([20, 8, 22, 10], fill=eye_color)
    # Ears by archetype
    if ear_style == "felix":
        d.polygon([(9, 4), (11, 0), (14, 4)], fill=primary, outline=(20, 22, 28, 255))
        d.polygon([(21, 4), (24, 0), (26, 4)], fill=primary, outline=(20, 22, 28, 255))
    elif ear_style == "mule":
        # Long donkey-radar ears
        d.rectangle([8, 0, 11, 5], fill=secondary, outline=(20, 22, 28, 255))
        d.rectangle([24, 0, 27, 5], fill=secondary, outline=(20, 22, 28, 255))
    elif ear_style == "hound":
        # Heavy armored brow + jaw fangs
        d.rectangle([11, 12, 25, 15], fill=(90, 95, 105, 255))
        d.point([(13, 12), (16, 12), (19, 12), (22, 12)], fill=(240, 240, 240, 255))
        d.polygon([(9, 4), (12, 1), (15, 4)], fill=secondary)
        d.polygon([(20, 4), (23, 1), (26, 4)], fill=secondary)
    elif ear_style == "cock":
        # Cyber-crest & antenna
        d.rectangle([16, 0, 19, 4], fill=(255, 60, 120, 255))
        d.line([(6, 3), (9, 6)], fill=eye_color, width=1)
        d.line([(29, 3), (26, 6)], fill=eye_color, width=1)
    return img


def draw_cat_arms(style: str, color1, color2, glow) -> Image.Image:
    img = Image.new("RGBA", (44, 28), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Left shoulder mount
    d.rectangle([2, 8, 9, 19], fill=color1, outline=(20, 22, 28, 255))
    # Right weapon mount
    d.rectangle([26, 7, 36, 19], fill=color1, outline=(20, 22, 28, 255))
    if style == "claws":
        # Laser claws protruding right
        d.line([(36, 9), (42, 7)], fill=glow, width=2)
        d.line([(36, 13), (43, 13)], fill=glow, width=2)
        d.line([(36, 17), (42, 19)], fill=glow, width=2)
    elif style == "shield":
        # Heavy bulldozer scoop shield
        d.rectangle([32, 3, 42, 24], fill=color2, outline=(20, 22, 28, 255))
        d.rectangle([35, 6, 39, 21], fill=glow)
    elif style == "saw":
        # Circular buzzsaw & hydraulic clamp
        d.ellipse([32, 5, 43, 16], fill=color2, outline=glow)
        d.rectangle([34, 17, 42, 21], fill=color1)
    elif style == "megaphone":
        # Sonic Dish / Megaphone
        d.polygon([(34, 11), (43, 5), (43, 21), (34, 15)], fill=color2, outline=glow)
    else:
        # Heavy plasma railgun
        d.rectangle([32, 10, 43, 16], fill=color2, outline=(20, 22, 28, 255))
        d.line([(34, 13), (43, 13)], fill=glow, width=2)
    return img


def draw_cat_legs(style: str, color1, color2, glow) -> Image.Image:
    img = Image.new("RGBA", (36, 18), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if style == "tracks":
        # Caterpillar tracks
        d.rounded_rectangle([4, 3, 31, 16], radius=4, fill=(45, 48, 55, 255), outline=(20, 22, 28, 255))
        for x in (8, 15, 22, 27):
            d.ellipse([x - 2, 6, x + 2, 13], fill=color1, outline=glow)
    elif style == "hover":
        # Hover coils
        d.rectangle([7, 2, 28, 10], fill=color1, outline=(20, 22, 28, 255))
        d.ellipse([6, 11, 29, 16], fill=glow)
    else:
        # Mech legs
        d.rectangle([9, 1, 15, 13], fill=color1, outline=(20, 22, 28, 255))
        d.rectangle([20, 1, 26, 13], fill=color1, outline=(20, 22, 28, 255))
        d.rectangle([7, 12, 16, 16], fill=color2, outline=(20, 22, 28, 255))
        d.rectangle([19, 12, 28, 16], fill=color2, outline=(20, 22, 28, 255))
        d.point([(11, 7), (22, 7)], fill=glow)
    return img


def generate_cats() -> None:
    out_dir = os.path.join(ROOT, "sprites", "cats")
    ensure_dir(out_dir)

    configs = [
        ("felix", (55, 145, 220, 255), (235, 135, 45, 255), (80, 255, 255, 255), "felix", "claws", "paws"),
        ("mule", (215, 165, 40, 255), (110, 90, 50, 255), (255, 220, 70, 255), "mule", "shield", "tracks"),
        ("hound", (175, 45, 55, 255), (90, 95, 110, 255), (255, 70, 70, 255), "hound", "saw", "paws"),
        ("cock", (140, 65, 195, 255), (50, 190, 140, 255), (120, 255, 160, 255), "cock", "megaphone", "hover"),
        ("titan", (160, 175, 195, 255), (85, 100, 120, 255), (0, 230, 255, 255), "felix", "rail", "tracks"),
        ("scrap", (140, 95, 65, 255), (90, 65, 45, 255), (255, 160, 50, 255), "hound", "saw", "paws"),
    ]

    for cid, c1, c2, glow, ear, arm_s, leg_s in configs:
        b = draw_cat_body(cid, c1, c2, glow, ear)
        a = draw_cat_arms(arm_s, c1, c2, glow)
        l = draw_cat_legs(leg_s, c1, c2, glow)
        b.save(os.path.join(out_dir, f"{cid}_body.png"))
        a.save(os.path.join(out_dir, f"{cid}_arms.png"))
        l.save(os.path.join(out_dir, f"{cid}_legs.png"))

    # Bremen Pyramid Totem sprite (64x96)
    pyr = Image.new("RGBA", (64, 96), (0, 0, 0, 0))
    d = ImageDraw.Draw(pyr)
    # Base (MULE)
    d.rectangle([10, 70, 54, 94], fill=(215, 165, 40, 255), outline=(20, 22, 28, 255))
    # Mid-Low (HOUND)
    d.rectangle([14, 48, 50, 70], fill=(175, 45, 55, 255), outline=(20, 22, 28, 255))
    # Mid-High (FELIX)
    d.rectangle([18, 26, 46, 48], fill=(55, 145, 220, 255), outline=(20, 22, 28, 255))
    # Top (COCK + Sonic Dish)
    d.rectangle([22, 8, 42, 26], fill=(140, 65, 195, 255), outline=(20, 22, 28, 255))
    d.polygon([(20, 8), (32, 0), (44, 8)], fill=(80, 255, 220, 255))
    # Glowing core spine
    d.rectangle([29, 14, 35, 88], fill=(120, 255, 255, 255))
    pyr.save(os.path.join(out_dir, "bremen_pyramid.png"))


def generate_portraits() -> None:
    out_dir = os.path.join(ROOT, "sprites", "portraits")
    ensure_dir(out_dir)
    chars = {
        "felix": ((55, 145, 220, 255), (80, 255, 255, 255)),
        "mule": ((215, 165, 40, 255), (255, 220, 70, 255)),
        "hound": ((175, 45, 55, 255), (255, 70, 70, 255)),
        "cock": ((140, 65, 195, 255), (120, 255, 160, 255)),
        "atamansha": ((200, 40, 90, 255), (255, 230, 50, 255)),
        "press": ((180, 65, 50, 255), (255, 180, 40, 255)),
        "satellite": ((70, 95, 185, 255), (120, 255, 255, 255)),
    }
    moods = ["normal", "battle", "damaged", "glitch"]
    for name, (bg_col, eye_col) in chars.items():
        for mood in moods:
            img = Image.new("RGBA", (48, 48), (18, 20, 28, 255))
            d = ImageDraw.Draw(img)
            d.rectangle([0, 0, 47, 47], outline=eye_col, width=2)
            # Head silhouette
            d.rectangle([10, 12, 37, 40], fill=bg_col, outline=(10, 10, 15, 255))
            d.polygon([(10, 12), (15, 4), (21, 12)], fill=bg_col)
            d.polygon([(26, 12), (32, 4), (37, 12)], fill=bg_col)
            # Visor
            d.rectangle([13, 18, 34, 27], fill=(12, 14, 20, 255))
            if mood == "normal":
                d.rectangle([16, 20, 20, 24], fill=eye_col)
                d.rectangle([27, 20, 31, 24], fill=eye_col)
            elif mood == "battle":
                d.polygon([(15, 19), (22, 22), (15, 25)], fill=(255, 80, 50, 255))
                d.polygon([(32, 19), (25, 22), (32, 25)], fill=(255, 80, 50, 255))
            elif mood == "damaged":
                d.line([(15, 19), (21, 25)], fill=(255, 60, 60, 255), width=2)
                d.line([(21, 19), (15, 25)], fill=(255, 60, 60, 255), width=2)
                d.rectangle([27, 21, 31, 24], fill=eye_col)
            elif mood == "glitch":
                for y in range(18, 27, 2):
                    d.line([(13, y), (34, y)], fill=eye_col, width=1)
            img.save(os.path.join(out_dir, f"{name}_{mood}.png"))


def generate_enemies() -> None:
    out_dir = os.path.join(ROOT, "sprites", "enemies")
    ensure_dir(out_dir)

    # Regular enemies (single sprite 44x44)
    regulars = [
        ("scrap_drone", (160, 110, 70, 255), (255, 90, 40, 255)),
        ("acid_cleaner", (70, 165, 80, 255), (180, 255, 60, 255)),
        ("welder_raider", (190, 95, 45, 255), (255, 210, 60, 255)),
        ("security_hound", (130, 50, 65, 255), (255, 50, 80, 255)),
        ("spectre_drone", (75, 110, 190, 255), (100, 240, 255, 255)),
        ("core_sentinel", (140, 80, 180, 255), (255, 100, 240, 255)),
    ]
    for name, c1, glow in regulars:
        img = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.rectangle([8, 10, 35, 36], fill=c1, outline=(20, 22, 28, 255))
        d.rectangle([12, 16, 26, 23], fill=(20, 22, 30, 255))
        d.rectangle([14, 18, 22, 21], fill=glow)
        # Weapon arm pointing left toward cats
        d.rectangle([1, 20, 10, 26], fill=(90, 95, 105, 255), outline=(20, 22, 28, 255))
        d.rectangle([0, 21, 3, 25], fill=glow)
        img.save(os.path.join(out_dir, f"{name}.png"))

    # Modular Elites and Bosses (separate _body, _arms, _legs + full)
    modulars = [
        ("elite_crusher", (195, 135, 45, 255), (255, 90, 40, 255), 56, 56),
        ("elite_driller", (155, 95, 65, 255), (255, 200, 50, 255), 56, 56),
        ("elite_aegis", (75, 130, 195, 255), (90, 255, 240, 255), 56, 56),
        ("boss_press", (180, 65, 50, 255), (255, 180, 40, 255), 76, 76),
        ("boss_atamansha", (190, 45, 95, 255), (255, 230, 60, 255), 76, 76),
        ("boss_satellite", (70, 95, 185, 255), (120, 255, 255, 255), 80, 80),
    ]
    for name, c1, glow, w, h in modulars:
        # Body
        b = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        db = ImageDraw.Draw(b)
        db.rectangle([w // 4, h // 5, w * 3 // 4, h * 3 // 5], fill=c1, outline=(15, 18, 24, 255))
        db.rectangle([w // 3, h // 4, w * 2 // 3, h * 2 // 5], fill=(20, 22, 30, 255))
        db.rectangle([w // 3 + 3, h // 4 + 3, w * 2 // 3 - 3, h * 2 // 5 - 3], fill=glow)
        b.save(os.path.join(out_dir, f"{name}_body.png"))

        # Arms / Turrets (pointing left)
        a = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        da = ImageDraw.Draw(a)
        da.rectangle([2, h // 3, w // 3, h // 2 + 6], fill=(105, 110, 125, 255), outline=(15, 18, 24, 255))
        da.rectangle([0, h // 3 + 3, 6, h // 2 + 3], fill=glow)
        a.save(os.path.join(out_dir, f"{name}_arms.png"))

        # Legs / Chassis
        l = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dl = ImageDraw.Draw(l)
        dl.rectangle([w // 5, h * 3 // 5, w * 4 // 5, h - 4], fill=(65, 70, 82, 255), outline=(15, 18, 24, 255))
        dl.line([(w // 4, h - 8), (w * 3 // 4, h - 8)], fill=glow, width=2)
        l.save(os.path.join(out_dir, f"{name}_legs.png"))

        # Composite preview
        comp = Image.alpha_composite(Image.alpha_composite(l, b), a)
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

    # 2. Music Tapes (2.4s loopable retro synth tracks)
    tapes = [
        ("tape_hardbass.wav", [110.0, 110.0, 220.0, 130.81, 146.83, 110.0, 164.81, 146.83]),
        ("tape_blues.wav", [146.83, 174.61, 196.00, 207.65, 196.00, 174.61, 146.83, 130.81]),
        ("tape_synth.wav", [220.0, 261.63, 329.63, 392.0, 329.63, 261.63, 246.94, 196.0]),
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


if __name__ == "__main__":
    generate_cats()
    generate_portraits()
    generate_enemies()
    generate_ui_and_dodge()
    generate_backgrounds()
    generate_story_illustrations()
    generate_audio()
    print("All Xenocats pixel-art sprites and WAV audio assets generated!")

