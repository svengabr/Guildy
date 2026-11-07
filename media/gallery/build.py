"""Builds the CurseForge gallery from real in-game screenshots (src/*.webp).

Each screenshot is cut out of the game world and placed on a neutral background (1920x1080 JPG). All
character names are replaced by made-up ones (same class colour, game font, same name in every image);
the guild chat is rewritten. Needs Pillow, numpy and
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
    # daytime sky (blue or bright) or a dark night sky (dark, at least as blue as red)
    day = ((a[..., 2] > 110) & (a[..., 2] > a[..., 0] + 12)) | (a.sum(2) > 540)
    night = ((a[..., 2] >= a[..., 0] + 4) & (a.sum(2) < 200)) | (a.sum(2) < 24) | (a[..., 2] > a[..., 1] + 12)
    edge = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    dark = edge.sum(1).mean() < 150
    sky = (night if dark else day).astype(np.uint8) * 255
    m = Image.fromarray(sky).copy()
    w, h = m.size
    border = ([(x, 0) for x in range(0, w, 16)] + [(x, h - 1) for x in range(0, w, 16)]
              + [(0, y) for y in range(0, h, 16)] + [(w - 1, y) for y in range(0, h, 16)])
    for s in border:
        if m.getpixel(s) == 255:
            ImageDraw.floodfill(m, s, 128)
    fg = np.asarray(m) != 128


    if dark:
        # At night other UI blends into the world: keep only the window's own shapes (frame, portrait
        # ring, side button, tabs), measured on daytime screenshots relative to the frame.
        cols = np.nonzero(fg.sum(0) > 0.6 * h)[0]
        rows = np.nonzero(fg.sum(1) > 0.6 * w)[0]
        xl, xr, yt, yb = int(cols.min()), int(cols.max()), int(rows.min()), int(rows.max())
        k = (xr - xl) / 1712
        keep = np.zeros_like(fg)
        keep[yt - 3:yb + 4, xl - 3:xr + 4] = True
        keep[yt + int(85 * k):yt + int(178 * k), xr:xr + int(78 * k)] = True
        keep[yb:yb + int(52 * k), xl:xl + int(790 * k)] = True
        yy, xx = np.mgrid[0:h, 0:w]
        keep |= (xx - (xl + 35 * k)) ** 2 + (yy - (yt + 35 * k)) ** 2 <= (45 * k) ** 2
        fg &= keep

    # Specks of other UI above the window: nothing reaches higher than the portrait ring.
    bar = int(np.nonzero(fg.sum(1) > w // 2)[0].min())
    fg[: max(bar - 14, 0)] = False

    # Blizzard's own (hidden) guild tabs peek out under the frame right of Guildy's tabs: drop them.
    col = fg[:, w // 2 + 300]
    bottom = int(np.nonzero(col)[0].max())
    if bottom + 22 < h:
        tabs = np.nonzero(fg[bottom + 22, : w // 2 + 200])[0]
        if len(tabs):
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


# --- made-up names ------------------------------------------------------------------------------------

# Every character name in the screenshots is replaced by a made-up one; the colour (class) is taken from
# the screenshot, so only the letters change. The real names, the screenshots and the per-screen edits stay
# out of the repo (screens.py and src/ are git-ignored).
FAKE = {}  # real name -> made-up name, filled by screens.py (not in the repo)
COLORS = {}  # made-up name -> colour found in the screenshot (for the rewritten chat)


def parse(spec):
    """'{Anna} befördert {Ben} zu X' -> [(shown, new, is_name)]. '{real|shown}' when the game
    truncated the name, '{old=>new}' for any other text to replace."""
    out, rest = [], spec
    while rest:
        i = rest.find("{")
        if i < 0:
            out.append((rest, rest, False))
            break
        if i:
            out.append((rest[:i], rest[:i], False))
        j = rest.index("}", i)
        inner = rest[i + 1:j]
        if "=>" in inner:
            old, new = inner.split("=>")
            out.append((old, new, False))
        else:
            real, _, shown = inner.partition("|")
            out.append((shown or real, FAKE[real], True))
        rest = rest[j + 1:]
    return out


def find_lines(img, band, sample_x, thr=90):
    """Text lines inside `band` as ink boxes (x0, y0, x1, y1), comparing every pixel row with the panel
    colour at `sample_x` in that row."""
    x0, y0, x1, y1 = band
    a = np.asarray(img).astype(int)
    bg = a[y0:y1, sample_x:sample_x + 1]
    ink = np.abs(a[y0:y1, x0:x1] - bg).sum(2) > thr
    rows = np.nonzero(ink.any(1))[0]
    lines, start, prev = [], None, None
    for r in rows:
        if start is None:
            start = prev = r
        elif r - prev > 2:
            lines.append((start, prev))
            start = r
        prev = r
    if start is not None:
        lines.append((start, prev))
    out = []
    for s, e in lines:
        cols = np.nonzero(ink[s:e + 1].any(0))[0]
        out.append((x0 + int(cols.min()), y0 + s, x0 + int(cols.max()), y0 + e))
    return out


def _hsv(c):
    r, g, b = [v / 255 for v in c]
    mx, mn = max(r, g, b), min(r, g, b)
    if mx == mn:
        h = 0.0
    elif mx == r:
        h = (60 * (g - b) / (mx - mn)) % 360
    elif mx == g:
        h = 60 * (b - r) / (mx - mn) + 120
    else:
        h = 60 * (r - g) / (mx - mn) + 240
    return h, (mx - mn) / mx if mx else 0.0, mx


TEXT = [(0, 255, 0), (255, 32, 32), (255, 209, 0)]


def seg_color(img, box, sample_x, is_name=False):
    """Colour of a text segment. The screenshots are WebP with halved colour resolution, so thin text comes
    out washed; the hue survives, so snap to the class colours (names) or the usual text colours."""
    x0, y0, x1, y1 = box
    a = np.asarray(img).astype(int)
    reg = a[y0:y1 + 1, x0:x1 + 1].reshape(-1, 3)
    bg = np.repeat(a[y0:y1 + 1, sample_x], x1 - x0 + 1, axis=0)
    d = np.abs(reg - bg).sum(1)
    if d.max() < 60:
        return (255, 255, 255)
    lit = reg[d > 0.5 * d.max()]
    v = lit.max(1)
    top = lit[v >= np.percentile(v, 70)]
    sats = np.array([_hsv(c)[1] for c in top])
    core = top[sats >= np.percentile(sats, 60)]
    h, sat, _ = _hsv(tuple(np.median(core, axis=0)))
    bright = float(np.percentile(v, 90)) / 255
    if sat < 0.13:
        g = int(round(255 * (1.0 if bright > 0.72 else bright * 1.1)))
        return (g, g, g)
    pal = [c for c in CLASS.values() if c != (255, 255, 255)] if is_name else TEXT
    def dist(c):
        ch, cs, _ = _hsv(c)
        dh = min(abs(ch - h), 360 - abs(ch - h))
        return dh + 40 * abs(cs - min(1.0, sat * 1.9))
    best = min(pal, key=dist)
    scale = min(1.0, bright / (max(best) / 255) * 1.04)
    scale = 1.0 if scale > 0.68 else scale * 1.15  # washed but lit, or dimmed (offline members)
    return tuple(int(round(c * scale)) for c in best)


def replace_lines(img, band, sample_x, specs, font_path=None, sx=1.0, max_w=None, shadow=True, thr=90,
                  probe=False):
    """Re-sets every text line in `band`: specs[i] describes line i (None = leave it, "ERASE" = wipe it)."""
    boxes = find_lines(img, band, sample_x, thr)
    if probe or len(boxes) != len(specs):
        print(f"  band {band}: {len(boxes)} lines, {len(specs)} specs")
        for b in boxes:
            print("   ", b)
        if len(boxes) != len(specs):
            raise SystemExit("line count mismatch")
    for li, (box, spec) in enumerate(zip(boxes, specs)):
        mw = max_w[li] if isinstance(max_w, list) else max_w
        if spec is None:
            continue
        x0, y0, x1, y1 = box
        fill_rows(img, (x0 - 2, y0 - 2, x1 + 3, y1 + 3), sample_x)
        if spec == "ERASE":
            continue
        segs = parse(spec)
        shown = "".join(s for s, _, _ in segs)
        get = (lambda size: ImageFont.truetype(font_path, size)) if font_path else font
        lo, hi = 6.0, 40.0
        for _ in range(30):
            mid = (lo + hi) / 2
            b = get(mid).getbbox(shown)
            lo, hi = (mid, hi) if (b[2] - b[0]) * sx < x1 - x0 + 1 else (lo, mid)
        f = get(lo)
        b = f.getbbox(shown)
        pen = x0 - b[0] * sx
        # colours of the original segments
        colors, idx = [], 0
        for s, _, nm in segs:
            a0 = pen + f.getlength(shown[:idx]) * sx
            sb = (int(max(a0, x0)), y0, int(min(a0 + f.getlength(s) * sx, x1)), y1)
            colors.append(seg_color(img_orig[0], sb, sample_x, nm) if sb[2] > sb[0] + 1 else (255, 255, 255))
            idx += len(s)
        news = [n for _, n, _ in segs]
        if mw:
            while f.getlength("".join(news)) * sx > mw:
                k = max(i for i, (_, _, nm) in enumerate(segs) if nm)
                t = news[k].rstrip(".")
                news[k] = t[:-1].rstrip() + "..."
        layer = Image.new("RGBA", (int(f.getlength("".join(news))) + 8, int(f.size * 2)), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        px = 0.0
        for (s, n, nm), c, newtext in zip(segs, colors, news):
            if shadow:
                d.text((px + 1, 1), newtext, font=f, fill=(0, 0, 0, 255))
            d.text((px, 0), newtext, font=f, fill=c + (255,))
            if nm:
                COLORS.setdefault(newtext, c)
            px += f.getlength(newtext)
        if sx != 1.0:
            layer = layer.resize((max(1, round(layer.width * sx)), layer.height), Image.LANCZOS)
        img.paste(layer, (round(pen), round(y0 - b[1])), layer)


img_orig = [None]  # untouched copy of the screenshot being edited (colours are sampled from it)

PROBE = os.environ.get("PROBE") == "1"


def names(img, band, sample_x, specs, **kw):
    replace_lines(img, band, sample_x, specs, probe=PROBE, **kw)


def plain(*real):
    return ["{%s}" % r for r in real]


def main(only=None):
    from screens import JOBS  # local only: real names and per-screen positions
    for out, src, edit in JOBS:
        if only and not out.startswith(only):
            continue
        im = Image.open(os.path.join(HERE, "src", src + ".webp")).convert("RGB")
        img_orig[0] = im.copy()
        edit(im)
        compose(cutout(im)).save(os.path.join(HERE, out + ".jpg"), quality=90, optimize=True, progressive=True,
                                 subsampling=0)
        print(out + ".jpg")




CHROME = os.environ.get("CHROME", "C:/Program Files/Google/Chrome/Application/chrome.exe")


def render_sync():
    """sync.html (the sync explainer) -> 11-sync.jpg (English) and sync-de.jpg (German), via headless Chrome."""
    import subprocess
    import tempfile
    for out, frag in (("12-sync", ""), ("sync-de", "#de")):
        png = os.path.join(tempfile.gettempdir(), out + ".png")
        url = "file:///" + os.path.join(HERE, "sync.html").replace("\\", "/") + frag
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", "--window-size=1920,1080", "--virtual-time-budget=4000",
                        "--allow-file-access-from-files", "--screenshot=" + png, url],
                       check=True, capture_output=True)
        Image.open(png).convert("RGB").save(os.path.join(HERE, out + ".jpg"), quality=92, optimize=True,
                                            progressive=True, subsampling=0)
        os.remove(png)
        print(out + ".jpg")


if __name__ == "__main__":
    import build  # run inside the importable module, which screens.py shares its state with
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    if arg in (None, "12", "sync"):
        build.render_sync()
    if arg not in ("sync", "12"):
        build.main(arg)
