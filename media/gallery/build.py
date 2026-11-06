"""Builds the CurseForge gallery from real in-game screenshots (src/*.webp).

Each screenshot is cut out of the game world, placed on a neutral background (1920x1080 JPG) and, where the
test guild looked empty, filled up with made-up members in the game font. Needs Pillow, numpy and
fonts/FRIZQT__.TTF (see README.md).

    python build.py            # all images
    python build.py 05         # only images whose output name starts with 05
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
W, H = 1920, 1080

CLASS = {
    "WARRIOR": (198, 155, 109), "PALADIN": (244, 140, 186), "HUNTER": (170, 211, 114),
    "ROGUE": (255, 244, 104), "PRIEST": (255, 255, 255), "SHAMAN": (0, 112, 221),
    "MAGE": (63, 199, 235), "WARLOCK": (135, 136, 238), "DRUID": (255, 124, 10),
}

# Made-up members that fill the hall of fame (name, class).
MOCK = [
    ("Brannoc Eisenbart", "WARRIOR"), ("Liora Sonnfeld", "PALADIN"), ("Kesh Dornpfeil", "HUNTER"),
    ("Vexa Nachtmantel", "ROGUE"), ("Elwin Lichtquell", "PRIEST"), ("Torva Sturmruf", "SHAMAN"),
    ("Miri Funkenschlag", "MAGE"), ("Grimbald Aschenherz", "WARLOCK"), ("Fenna Mooswind", "DRUID"),
    ("Holgar Steinfaust", "WARRIOR"), ("Selene Morgentau", "PRIEST"), ("Jorik Wolfsfährte", "HUNTER"),
    ("Talia Frostfeder", "MAGE"), ("Odo Kupferkessel", "ROGUE"), ("Ysolde Glanzschild", "PALADIN"),
    ("Brakk Donnerhuf", "SHAMAN"), ("Nerys Schattenranke", "WARLOCK"), ("Pip Rabenschwinge", "DRUID"),
    ("Arnulf Graubart", "WARRIOR"), ("Wenna Distelkraut", "PRIEST"),
]


# --- helpers ------------------------------------------------------------------------------------------

_fonts = {}


def font(size):
    if size not in _fonts:
        _fonts[size] = ImageFont.truetype(FONT, size)
    return _fonts[size]


def fit(sample, width):
    """Font size whose ink width for `sample` matches a width measured in the screenshot."""
    lo, hi = 6.0, 40.0
    for _ in range(30):
        mid = (lo + hi) / 2
        b = font(mid).getbbox(sample)
        lo, hi = (mid, hi) if b[2] - b[0] < width else (lo, mid)
    return round(lo, 2)


def text(img, x, cap_top, s, size, color, anchor="l", shadow=True, sx=1.0):
    """Draws `s` with its cap height starting at `cap_top`; x is the ink's left/right edge or centre.
    `sx` squeezes the text horizontally (the game's numbers are narrower than Friz Quadrata's)."""
    f = font(size)
    b = f.getbbox(s)
    cap = f.getbbox("H")[1]
    layer = Image.new("RGBA", (b[2] + 4, b[3] + 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if shadow:
        d.text((1, 1), s, font=f, fill=(0, 0, 0, 255))
    d.text((0, 0), s, font=f, fill=color + (255,))
    if sx != 1.0:
        layer = layer.resize((max(1, round(layer.width * sx)), layer.height), Image.LANCZOS)
    left, right = b[0] * sx, b[2] * sx
    x0 = {"l": x - left, "r": x - right, "c": x - (left + right) / 2}[anchor]
    img.paste(layer, (round(x0), round(cap_top - cap)), layer)


def squeeze(sample, width, size):
    b = font(size).getbbox(sample)
    return width / (b[2] - b[0])


def truncate(s, size, width):
    f = font(size)
    if f.getlength(s) <= width:
        return s
    while s and f.getlength(s + "...") > width:
        s = s[:-1]
    return s.rstrip() + "..."


def fill_rows(img, box, sample_x):
    """Wipes `box` by repeating, per pixel row, the colour found at column `sample_x` (flat panels)."""
    x0, y0, x1, y1 = box
    a = np.asarray(img).copy()
    a[y0:y1, x0:x1] = a[y0:y1, sample_x:sample_x + 1]
    img.paste(Image.fromarray(a))


def patch(img, box, src_x):
    """Wipes `box` with the same-sized area starting at column `src_x` (textured backgrounds)."""
    x0, y0, x1, y1 = box
    img.paste(img.crop((src_x, y0, src_x + x1 - x0, y1)), (x0, y0))


def color_at(img, box):
    """Text colour inside `box`: the median of its brightest pixels."""
    a = np.asarray(img.crop(box)).reshape(-1, 3).astype(int)
    s = a.sum(1)
    return tuple(int(v) for v in np.median(a[s >= np.percentile(s, 97)], axis=0))


def de(n):
    return f"{n:,}".replace(",", ".")


def sprite(img, box, bg):
    """Cuts a glyph out of a flat background as (colour, alpha) so it can be stamped onto other rows."""
    a = np.asarray(img.crop(box)).astype(float)
    bg = np.array(bg, float)
    dist = np.abs(a - bg).sum(2)
    peak = a.reshape(-1, 3)[dist.argmax()]
    alpha = np.clip(dist / max(np.abs(peak - bg).sum(), 1), 0, 1)
    return peak, alpha


def stamp(img, spr, x, y):
    peak, alpha = spr
    h, w = alpha.shape
    a = np.asarray(img).astype(float)
    reg = a[y:y + h, x:x + w]
    a[y:y + h, x:x + w] = reg * (1 - alpha[..., None]) + peak * alpha[..., None]
    img.paste(Image.fromarray(a.round().astype(np.uint8)))


# --- cut the window out of the game world -------------------------------------------------------------

def cutout(im):
    a = np.asarray(im).astype(int)
    sky = (((a[..., 2] > 110) & (a[..., 2] > a[..., 0] + 12)) | (a.sum(2) > 540)).astype(np.uint8) * 255
    m = Image.fromarray(sky).copy()
    w, h = m.size
    border = ([(x, 0) for x in range(0, w, 16)] + [(x, h - 1) for x in range(0, w, 16)]
              + [(0, y) for y in range(0, h, 16)] + [(w - 1, y) for y in range(0, h, 16)])
    for s in border:
        if m.getpixel(s) == 255:
            ImageDraw.floodfill(m, s, 128)
    fg = np.asarray(m) != 128

    # Specks of other UI above the window: nothing reaches higher than the portrait ring.
    bar = int(np.nonzero(fg.sum(1) > w // 2)[0].min())
    fg[: max(bar - 14, 0)] = False

    # Blizzard's own (hidden) guild tabs peek out under the frame right of Guildy's tabs: drop them.
    col = fg[:, w // 2 + 300]
    bottom = int(np.nonzero(col)[0].max())
    tabs = np.nonzero(fg[bottom + 22, : w // 2 + 200])[0]
    fg[bottom + 1:, int(tabs.max()) + 3:] = False

    alpha = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out.crop(out.getbbox())


def compose(win):
    bg = Image.new("RGB", (W, H))
    yy, xx = np.mgrid[0:H, 0:W]
    r = np.sqrt(((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H * 0.42) / (H * 0.75)) ** 2)
    t = np.clip(r, 0, 1)[..., None]
    inner, outer = np.array([58, 61, 66]), np.array([24, 25, 28])
    bg = Image.fromarray((inner * (1 - t) + outer * t).astype(np.uint8))
    noise = (np.random.default_rng(7).normal(0, 2.2, (H, W, 1))).repeat(3, 2)
    bg = Image.fromarray(np.clip(np.asarray(bg).astype(float) + noise, 0, 255).astype(np.uint8))

    scale = min((W - 80) / win.width, (H - 50) / win.height, 1.0)
    if scale < 1:
        win = win.resize((round(win.width * scale), round(win.height * scale)), Image.LANCZOS)
    x, y = (W - win.width) // 2, (H - win.height) // 2
    shadow = Image.new("L", (W, H), 0)
    shadow.paste(win.getchannel("A"), (x, y + 10))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18)).point(lambda v: v * 0.75)
    bg.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), shadow)
    bg.paste(win, (x, y), win)
    return bg


# --- per-screenshot edits -----------------------------------------------------------------------------

def header_members(img, x_right, cap_top, box, src_x, shown):
    color = color_at(img, box)
    patch(img, box, src_x)
    size = fit("4 / 68 Mitglieder · 1 geteilt, 3 in der Nähe gelesen", 350)
    text(img, x_right, cap_top, shown, size, color, "r", shadow=False)


# Kreaturen getötet of the made-up members, and where their numbers came from (g = shared, n = read nearby).
KILLS = [1098, 1037, 986, 941, 903, 872, 820, 776, 731, 688, 642, 597, 548, 503, 461, 412, 358, 297, 241, 176]
SOURCES = ["g", "n", "g", "n", "n", "g", "n", "g", "n", "n", "g", "n", "n", "g", "n", "g", "n", "n", "g", "n"]
TOTAL = 5337 + sum(KILLS)
MEMBERS = 4 + len(KILLS)
HEADER = (f"{MEMBERS} / 68 Mitglieder · {SOURCES.count('g') + 1} geteilt, "
          f"{SOURCES.count('n') + 3} in der Nähe gelesen")


def hall_of_fame_ranking(img):
    """Kreaturen getötet: 4 real entries, 20 made-up ones below them."""
    values, sources, total, members = KILLS, SOURCES, TOTAL, MEMBERS
    header_members(img, 1508, 84, (1150, 80, 1516, 101), 690, HEADER)

    big, small = fit("5.337", 61), fit("Gilde gesamt", 92)
    gold, grey = color_at(img, (600, 182, 668, 201)), color_at(img, (585, 208, 690, 224))
    fill_rows(img, (560, 179, 710, 227), 450)
    fill_rows(img, (960, 179, 1170, 227), 880)
    text(img, 634, 184, de(total), big, gold, "c")
    text(img, 1067, 184, de(round(total / members)), big, gold, "c")
    text(img, 634, 210, "Gilde gesamt", small, grey, "c")
    text(img, 1065, 210, f"Ø von {members} Mitgliedern", small, grey, "c")

    name_size = fit("Maerith Withersong", 137)
    val_size, val_sx = name_size, squeeze("1.201", 31, name_size)
    src_size = fit("eigene · heute", 99)
    src_grey = color_at(img, (1575, 266, 1678, 282))
    dark, light = img.crop((420, 316, 1688, 344)), img.crop((420, 344, 1688, 372))
    for i, v in enumerate(values):
        rank = 5 + i
        top = 260 + 28 * (rank - 1)
        img.paste(dark if rank % 2 else light, (420, top))
        fill_rows(img, (436, top, 692, top + 28), 670)
        fill_rows(img, (694 + round(667 * v / 1559), top, 1518, top + 28), 670)
        if sources[i] == "g":
            fill_rows(img, (1520, top, 1682, top + 28), 670)
            text(img, 1676, top + 8, "geteilt · heute" if i % 3 else "geteilt · gestern", src_size, src_grey,
                 "r", shadow=False)
        name, cls = MOCK[i]
        text(img, 451, top + 9, str(rank), val_size, (200, 200, 200), "r", sx=val_sx)
        text(img, 461, top + 9, name, name_size, CLASS[cls])
        text(img, 1513, top + 9, de(v), val_size, (255, 255, 255), "r", sx=val_sx)


DUNGEONS = ["Flammenschlund", "Todesminen", "Ruinen von Lordaeron", "Höhlen des Wehklagens", "Burg Schattenfang",
            "Verlies von Stormwind", "Blackfathom-Tiefe"]


def hall_of_fame(img):
    """Overview: bigger guild totals and a fuller dungeon progress grid."""
    header_members(img, 1515, 83, (1150, 79, 1522, 100), 680,
                   HEADER)

    big = fit("5.337", 75)
    for cx, value in ((214, de(TOTAL)), (552, "2.146"), (889, "163"), (1228, "121g"), (1567, "47")):
        gold = color_at(img, (cx - 40, 124, cx + 40, 147))
        fill_rows(img, (cx - 120, 121, cx + 120, 153), cx - 140)
        text(img, cx, 126, value, big, gold, "c")

    # dungeon grid: columns are 146 px apart, rows ~25.5 px
    hdr_size, name_size = fit("Flammenschlund", 116), fit("Maerith Withersong", 140)
    hdr_grey = color_at(img, (300, 415, 415, 427))
    fill_rows(img, (280, 412, 1500, 430), 1600)
    for k, dname in enumerate(DUNGEONS):
        text(img, 357 + 146 * k, 416, truncate(dname, hdr_size, 141), hdr_size, hdr_grey, "c", shadow=False)

    check = sprite(img, (350, 441, 364, 456), (23, 19, 14))
    dot_grey = (90, 85, 78)
    two_size = name_size
    two_sx = squeeze("1.201", 31, name_size)

    def row_top(i):
        return round(436 + 25.5 * i)

    # cleared count per dungeon column (0 = not yet); real rows only get the added columns
    extra_real = [[1, 1, 0, 0], [1, 1, 0, 0], [1, 0, 0, 0], [0, 0, 0, 0]]
    mock = [
        [1, 2, 1, 1, 1, 0, 0], [1, 1, 1, 1, 0, 1, 0], [1, 1, 0, 2, 1, 0, 1], [1, 1, 1, 1, 0, 0, 0],
        [2, 1, 1, 1, 0, 0, 0], [1, 1, 0, 1, 1, 0, 0], [1, 1, 1, 0, 0, 0, 0], [1, 3, 1, 1, 0, 0, 0],
        [1, 1, 0, 1, 0, 0, 0], [1, 1, 1, 0, 0, 0, 0], [1, 1, 0, 0, 0, 0, 0], [1, 2, 0, 1, 0, 0, 0],
        [1, 1, 0, 0, 0, 0, 0], [1, 0, 0, 0, 0, 0, 0], [1, 1, 0, 0, 0, 0, 0], [1, 0, 0, 0, 0, 0, 0],
    ]

    def cell(top, k, n):
        cx = 357 + 146 * k
        if n == 0:
            d = ImageDraw.Draw(img)
            d.rectangle((cx - 9 + 8, top + 13, cx - 8 + 8, top + 14), fill=dot_grey)
            return
        if n == 1:
            stamp(img, check, cx - 7, top + 5)
        else:
            stamp(img, check, cx - 12, top + 5)
            text(img, cx + 5, top + 7, str(n), two_size, (255, 255, 255), "l", sx=two_sx)

    for i, cleared in enumerate(extra_real):  # real rows: add the new columns
        top = row_top(i)
        fill_rows(img, (357 + 146 * 3 - 30, top + 1, 1500, top + 24), 1600)
        for k, n in enumerate(cleared):
            cell(top, 3 + k, n)

    dark, light = img.crop((60, 436, 1692, 461)), img.crop((60, 462, 1692, 487))
    for j, cleared in enumerate(mock):
        i = 4 + j
        top = row_top(i)
        img.paste(light if i % 2 else dark, (60, top))
        fill_rows(img, (62, top, 1500, top + 25), 1600)
        name, cls = MOCK[j]
        text(img, 69, top + 7, name, name_size, CLASS[cls])
        for k, n in enumerate(cleared):
            cell(top, k, n)


def info_log(img):
    """Guild info box: a few more lines under the Discord link."""
    size = fit("Discord Server", 102)
    lines = ["", "Willkommen bei der Murloc Mafia! Mrglmrgl :)", "",
             "Gildenabend: Mittwoch ab 20 Uhr, Treffpunkt Ironforge",
             "Dungeon-Gruppen bitte im Gildenchat ansagen",
             "Berufe teilen: Guildy installieren, Häkchen unten setzen",
             "", "Gildenbank: bei Ran Fred oder Maerith melden"]
    white = color_at(img, (139, 238, 245, 251))
    for i, line in enumerate(lines):
        if line:
            text(img, 139, 252 + 14 * (i + 1), line, size, white, shadow=False)


JOBS = [
    ("01-chat", "chat", None),
    ("02-members", "members", None),
    ("03-overview", "overview", None),
    ("04-hall-of-fame", "hall-of-fame", hall_of_fame),
    ("05-hall-of-fame-ranking", "hall-of-fame-ranking", hall_of_fame_ranking),
    ("06-professions", "professions", None),
    ("07-info-log", "info-log", info_log),
    ("08-ranks", "ranks", None),
]


def main(only=None):
    for out, src, edit in JOBS:
        if only and not out.startswith(only):
            continue
        im = Image.open(os.path.join(HERE, "src", src + ".webp")).convert("RGB")
        if edit:
            edit(im)
        compose(cutout(im)).save(os.path.join(HERE, out + ".jpg"), quality=90, optimize=True, progressive=True,
                                 subsampling=0)
        print(out + ".jpg")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
