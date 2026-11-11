"""Mock-ups of an endgame view for the overview tab, drawn into the real reference screenshot
(src/crop/03-overview.png, see crop.py): frame, boxes, buttons and icons are the game's own pixels,
the content is drawn with the game's font at the sizes measured in the screenshot.

    python media/gallery/mock_endgame.py        ->  mock/endgame-a.png, -b.png, -c.png

All names and numbers are made up. Needs Pillow; src/ and fonts/ are local only.
"""
import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
CROP = os.path.join(HERE, "src", "crop")
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")

# the body of the window in the screenshot: the gold lines of the outermost boxes (x1/y1 exclusive)
X0, Y0, X1, Y1 = 42, 111, 1689, 863
GAP = 16
BG = (22, 19, 14)          # inside of a box
TRACK = (33, 29, 20)       # empty part of a bar
ZEBRA = (29, 26, 21)
GOLD, WHITE, GREY = (255, 209, 0), (255, 255, 255), (128, 128, 128)
GREEN, RED = (64, 224, 64), (255, 90, 74)
BAR_GOLD = (204, 168, 84)

F_S = ImageFont.truetype(FONT, 13.8)   # GameFont...Small
F_N = ImageFont.truetype(FONT, 16.3)   # GameFontNormal
F_H = ImageFont.truetype(FONT, 27.5)   # GameFontNormalHuge

CLASSES = [
    ("Krieger", (198, 155, 109)), ("Paladin", (244, 140, 186)), ("Jäger", (170, 211, 114)),
    ("Schurke", (255, 244, 104)), ("Priester", (255, 255, 255)), ("Schamane", (0, 112, 221)),
    ("Magier", (63, 199, 235)), ("Hexenmeister", (135, 136, 238)), ("Druide", (255, 124, 10)),
]
PROFS = ["Alchemie", "Schmiedekunst", "Verzauberkunst", "Ingenieurskunst", "Kräuterkunde", "Lederverarbeitung",
         "Bergbau", "Kürschnerei", "Schneiderei", "Kochkunst", "Erste Hilfe", "Angeln"]
# (members at 300, highest known skill)
PROF_VALUES = [(4, 300), (2, 300), (3, 300), (0, 285), (6, 300), (2, 300),
               (5, 300), (7, 300), (3, 300), (11, 300), (9, 300), (4, 300)]
RAIDS = ["Hügelgruft", "Hyjal", "Onyxias Hort"]   # placeholders: the game supplies the names
READY_ILVL = 56


def blend(color, alpha, bg=BG):
    return tuple(round(bg[i] + (color[i] - bg[i]) * alpha) for i in range(3))


# --- made-up guild ------------------------------------------------------------------------------------

def guild():
    rnd = random.Random(11)
    first = ["Arno", "Calla", "Hanno", "Levin", "Vera", "Dana", "Wanda", "Bero", "Falk", "Pell", "Tara", "Cord",
             "Rika", "Uwe", "Greta", "Sten", "Thea", "Alva", "Mira", "Lorn", "Runa", "Imke", "Maren", "Silas",
             "Onno", "Xara", "Gesa", "Jorin", "Edda", "Malte", "Nele", "Ragna", "Tjark", "Wiebke", "Ole", "Smilla"]
    last = ["Aschenbach", "Bruchstein", "Erlenbruch", "Weidenau", "Wolkenbruch", "Quellgrund", "Nordkamm",
            "Abendrot", "Rabenhorst", "Taubnessel", "Nebelstein", "Donnerkeil", "Uferlicht", "Falkenau",
            "Moorweide", "Dornhain", "Hagelschlag", "Silberbach", "Haselried", "Zunderfels", "Lerchenfeld",
            "Birkfeld", "Ostwind", "Glutpfad"]
    counts = [9, 10, 8, 5, 7, 6, 8, 5, 6]
    members, used = [], set()
    for c, n in enumerate(counts):
        for _ in range(n):
            while True:
                name = rnd.choice(first) + " " + rnd.choice(last)
                if name not in used:
                    used.add(name)
                    break
            ilvl = max(45.0, min(71.0, round(rnd.gauss(58.5, 5.2), 1)))
            roll = rnd.random()
            days = 0 if roll < 0.58 else rnd.randint(1, 7) if roll < 0.80 else rnd.randint(8, 14) if roll < 0.87 \
                else rnd.randint(15, 60)
            members.append({"name": name, "cls": c, "ilvl": ilvl, "days": days})
    for m in members:
        m["active"] = m["days"] <= 7
        m["ready"] = m["active"] and m["ilvl"] >= READY_ILVL
        m["silent"] = m["days"] > 14
        m["kills"] = [0, 0, 0]
        for r, chance in enumerate((0.45, 0.6, 0.8)):
            if rnd.random() < chance * (1.0 if m["ready"] else 0.5 if m["ilvl"] >= READY_ILVL else 0.12):
                m["kills"][r] = rnd.randint(1, 5)
    return members


M = guild()
READY = [m for m in M if m["ready"]]
SILENT = sorted((m for m in M if m["silent"]), key=lambda m: -m["ilvl"])
AVG = sum(m["ilvl"] for m in M) / len(M)


def de(value, digits=1):
    return ("%.*f" % (digits, value)).replace(".", ",")


def days_text(days):
    if days == 0:
        return "heute"
    if days < 30:
        return "vor %d Tg." % days
    return "vor %d Mon." % (days // 30)


# --- the game's own pixels ----------------------------------------------------------------------------

class Kit:
    def __init__(self):
        src = Image.open(os.path.join(CROP, "03-overview.png")).convert("RGB")
        fame = Image.open(os.path.join(CROP, "06-fame-dungeons.png")).convert("RGB")
        self.src = src
        self.box_src = src.crop((38, 107, 281, 367))         # the summary box with its outer fringe
        self.texture = src.crop((700, 70, 1690, 104))        # bare window background (toolbar)
        self.btn = {True: src.crop((270, 71, 364, 103)), False: src.crop((590, 71, 685, 103))}
        self.btn_mid = {True: (10, 17), False: (11, 21)}     # text-free columns inside each button
        self.prof_icons = [src.crop((54 + 541 * (i % 3), 419 + round(28.3 * (i // 3)),
                                     70 + 541 * (i % 3), 435 + round(28.3 * (i // 3)))) for i in range(12)]
        self.raid_icons = [fame.crop((x, 348, x + 29, 377)) for x in (1455, 1494, 1533)]

    def base(self):
        img = self.src.copy()
        tex, flip = self.texture, self.texture.transpose(Image.FLIP_TOP_BOTTOM)
        wide = Image.new("RGB", (tex.width * 2, tex.height))
        y, i = 106, 0
        while y < 874:
            row = flip if i % 2 == 0 else tex
            wide.paste(row, (0, 0))
            wide.paste(row.transpose(Image.FLIP_LEFT_RIGHT), (tex.width, 0))
            h = min(tex.height, 874 - y)
            img.paste(wide.crop((0, 0, 1696 - 31, h)), (31, y))
            y, i = y + tex.height, i + 1
        img.paste(self.texture.crop((0, 0, 600, 34)), (110, 70))   # toolbar without its old buttons
        return img

    def box(self, img, x0, y0, x1, y1):
        """A box whose gold lines run along x0, y0, x1 - 1, y1 - 1."""
        s, c, f = self.box_src, 14, 4
        w, h = x1 - x0 + 2 * f, y1 - y0 + 2 * f
        out = Image.new("RGB", (w, h), BG)
        top, bottom = s.crop((c, 0, s.width - c, c)), s.crop((c, s.height - c, s.width - c, s.height))
        left, right = s.crop((0, c, c, s.height - c)), s.crop((s.width - c, c, s.width, s.height - c))
        for x in range(c, w - c, top.width):
            out.paste(top, (x, 0))
            out.paste(bottom, (x, h - c))
        for y in range(c, h - c, left.height):
            out.paste(left, (0, y))
            out.paste(right, (w - c, y))
        out.paste(Image.new("RGB", (w - 2 * c, h - 2 * c), BG), (c, c))
        out.paste(s.crop((0, 0, c, c)), (0, 0))
        out.paste(s.crop((s.width - c, 0, s.width, c)), (w - c, 0))
        out.paste(s.crop((0, s.height - c, c, s.height)), (0, h - c))
        out.paste(s.crop((s.width - c, s.height - c, s.width, s.height)), (w - c, h - c))
        img.paste(out, (x0 - f, y0 - f))
        return (x0, y0, x1, y1)

    def button(self, img, x, text, selected):
        """A segmented button with its left edge at x on the toolbar; returns the x after it."""
        s, cap = self.btn[selected], 10
        w = round(F_S.getlength(text)) + 38
        out = Image.new("RGB", (w, s.height))
        a, b = self.btn_mid[selected]
        mid = s.crop((a, 0, b, s.height))
        both = Image.new("RGB", (mid.width * 2, s.height))
        both.paste(mid, (0, 0))
        both.paste(mid.transpose(Image.FLIP_LEFT_RIGHT), (mid.width, 0))
        for px in range(cap, w - cap, both.width):
            out.paste(both, (px, 0))
        out.paste(s.crop((0, 0, cap, s.height)), (0, 0))
        out.paste(s.crop((s.width - cap, 0, s.width, s.height)), (w - cap, 0))
        img.paste(out, (x, 71))
        text_at(ImageDraw.Draw(img), (x + w // 2, 91), text, F_S, WHITE if selected else GOLD, "ms")
        return x + w + 8


def text_at(d, xy, s, font=F_S, fill=WHITE, anchor="ls"):
    d.text((xy[0] + 1, xy[1] + 1), s, font=font, fill=(0, 0, 0), anchor=anchor)
    d.text(xy, s, font=font, fill=fill, anchor=anchor)


def parts(d, x, y, pieces, font=F_S, right=False):
    """Coloured pieces of one line; with right=True the line ends at x."""
    if right:
        x -= sum(font.getlength(s) for s, _ in pieces)
    for s, color in pieces:
        text_at(d, (round(x), y), s, font, color)
        x += font.getlength(s)
    return x


def title(d, box, text, hint=None, right=None):
    x = box[0] + 13
    text_at(d, (x, box[1] + 23), text, F_N, GOLD)
    if hint:
        text_at(d, (x + round(F_N.getlength(text)) + 14, box[1] + 23), hint, F_S, GREY)
    if right:
        text_at(d, (box[2] - 14, box[1] + 23), right, F_S, GREY, "rs")


def bar(d, x0, y, x1, share, color, h=14, track=True):
    if track:
        d.rectangle((x0, y, x1 - 1, y + h - 1), fill=TRACK)
    w = round((x1 - x0) * share)
    if w > 0:
        d.rectangle((x0, y, x0 + w - 1, y + h - 1), fill=color)
    return x0 + w


def toolbar(kit, img, window=True):
    d = ImageDraw.Draw(img)
    x = kit.button(img, 118, "Levelphase", False)
    x = kit.button(img, x, "Endgame", True) + 22
    text_at(d, (x, 91), "Aktiv in den letzten", F_S, GOLD)
    x += round(F_S.getlength("Aktiv in den letzten")) + 14
    for i, label in enumerate(("1 Monat", "3 Monaten", "6 Monaten", "Alle")):
        x = kit.button(img, x, label, i == 0)


# --- shared pieces ------------------------------------------------------------------------------------

def histogram(d, box, lo=45, hi=71, hint="Stufe 60"):
    title(d, box, "Itemlevel", hint)
    counts = {}
    for m in M:
        level = int(m["ilvl"])
        counts.setdefault(level, [0] * 9)[m["cls"]] += 1
    top = max(sum(v) for v in counts.values())
    text_at(d, (box[2] - 14, box[1] + 23), "höchste Säule: %d" % top, F_S, GREY, "rs")
    left, right, bottom = box[0] + 16, box[2] - 16, box[3] - 30
    height = bottom - (box[1] + 66)
    step = (right - left) / (hi - lo + 1)
    for level in range(lo, hi + 1):
        x, y = left + (level - lo) * step, bottom
        for c, n in enumerate(counts.get(level, [0] * 9)):
            if n:
                h = height * n / top
                d.rectangle((round(x), round(y - h), round(x + step) - 2, round(y) - 1), fill=blend(CLASSES[c][1], 0.9))
                y -= h
    for level in range(lo, hi + 1, 5):
        text_at(d, (round(left + (level - lo + 0.5) * step), box[3] - 10), str(level), F_S, GREY, "ms")
    # where the raid roster starts
    x = round(left + (READY_ILVL - lo) * step) - 2
    d.line((x, box[1] + 42, x, bottom), fill=blend(GOLD, 0.55), width=1)
    text_at(d, (x + 7, box[1] + 54), "Raidkader ab %d" % READY_ILVL, F_S, blend(GOLD, 0.8))


def raid_rows(kit, img, box, y, pitch, second_line=False):
    d = ImageDraw.Draw(img)
    for r, name in enumerate(RAIDS):
        won = [m for m in M if m["kills"][r]]
        new, runs = ((3, 2), (5, 3), (4, 6))[r]
        open_ready = sum(1 for m in READY if not m["kills"][r])
        top = y + r * pitch
        img.paste(kit.raid_icons[r], (box[0] + 14, top))
        text_at(d, (box[0] + 52, top + (13 if second_line else 19)), name, F_S, WHITE)
        if second_line:
            parts(d, box[0] + 52, top + 31, [("Siege diesen Monat: ", GREY), (str(runs), GOLD),
                                             ("   neu dabei: ", GREY), ("+%d" % new, GREEN)])
            bar(d, box[0] + 52, top + 42, box[2] - 96, len(won) / len(M), BAR_GOLD, 10)
            parts(d, box[2] - 16, top + 52, [(str(len(won)), GOLD), (" / %d" % len(M), GREY)], right=True)
            missing = [m for m in READY if not m["kills"][r]]
            x, limit, shown = parts(d, box[0] + 52, top + 74, [("Raidbereit ohne Sieg: ", GREY)]), box[2] - 70, 0
            for m in missing:
                piece = m["name"] + (", " if m is not missing[-1] else "")
                if x + F_S.getlength(piece) > limit:
                    break
                x = parts(d, x, top + 74, [(m["name"], CLASSES[m["cls"]][1]), (piece[len(m["name"]):], GREY)])
                shown += 1
            if shown < len(missing):
                parts(d, x, top + 74, [("+%d" % (len(missing) - shown), GOLD)])
            elif not missing:
                parts(d, x, top + 74, [("niemand", WHITE)])
        else:
            bar(d, box[0] + 190, top + 8, box[2] - 92, len(won) / len(M), BAR_GOLD)
            parts(d, box[2] - 16, top + 20, [(str(len(won)), GOLD), (" · +%d" % new, GREY)], right=True)


def silent_list(d, box, rows, pitch=25, top=40, wide=False):
    for i, m in enumerate(SILENT[:rows]):
        y = box[1] + top + i * pitch
        if i % 2 == 1:
            d.rectangle((box[0] + 8, y, box[2] - 9, y + pitch - 2), fill=ZEBRA)
        base = y + pitch - 8
        text_at(d, (box[0] + 16, base), m["name"], F_S, CLASSES[m["cls"]][1])
        if wide:
            text_at(d, (box[0] + 250, base), de(m["ilvl"]), F_S, WHITE)
            bar(d, box[0] + 300, y + 6, box[2] - 330, (m["ilvl"] - 40) / 31, blend(CLASSES[m["cls"]][1], 0.9), 12, False)
            hint = "war im Raidkader" if m["ilvl"] >= READY_ILVL else ""
            text_at(d, (box[2] - 300, base), hint, F_S, GREY)
        else:
            text_at(d, (box[2] - 110, base), de(m["ilvl"]), F_S, GREY, "rs")
        text_at(d, (box[2] - 16, base), days_text(m["days"]), F_S, GREY, "rs")


# --- A: the same page with new axes ---------------------------------------------------------------------

def variant_a(kit):
    img = kit.base()
    toolbar(kit, img)
    d = ImageDraw.Draw(img)
    third = (X1 - X0 - 2 * GAP) / 3

    summary = kit.box(img, X0, 111, 277, 363)
    text_at(d, (59, 148), str(len(READY)), F_H, GOLD)
    text_at(d, (59, 168), "raidbereit von %d auf Stufe 60" % len(M), F_S, GREY)
    lines = [("Jetzt online: ", "19", GOLD), ("Ø Itemlevel: ", de(AVG), GOLD),
             ("Neu auf 60 (30 Tage): ", "9", GREEN), ("Still seit 14 Tagen: ", str(len(SILENT)), RED)]
    for i, (label, value, color) in enumerate(lines):
        parts(d, 58, 200 + i * 22, [(label, WHITE), (value, color)])

    classes = kit.box(img, 293, 111, round(X0 + 2 * third + GAP), 363)
    title(d, classes, "Klassen", "raidbereit · auf Stufe 60 · Klick zeigt, wer")
    top = max(sum(1 for m in M if m["cls"] == c) for c in range(9))
    for c, (name, color) in enumerate(CLASSES):
        y = 150 + c * 23
        total = sum(1 for m in M if m["cls"] == c)
        ready = sum(1 for m in READY if m["cls"] == c)
        text_at(d, (classes[0] + 13, y + 11), name, F_S, color)
        d.rectangle((classes[0] + 146, y, classes[2] - 76, y + 13), fill=TRACK)
        full = classes[2] - 75 - (classes[0] + 146)
        d.rectangle((classes[0] + 146, y, classes[0] + 146 + round(full * total / top) - 1, y + 13), fill=blend(color, 0.3))
        d.rectangle((classes[0] + 146, y, classes[0] + 146 + round(full * ready / top) - 1, y + 13), fill=color)
        parts(d, classes[2] - 16, y + 12, [(str(ready), GOLD), (" · %d" % total, GREY)], right=True)

    levels = kit.box(img, classes[2] + GAP, 111, X1, 363)
    histogram(d, levels)

    profs = kit.box(img, X0, 379, X1, 538)
    title(d, profs, "Berufe", "Mitglieder auf 300 · höchster bekannter Skill · Klick zeigt, wer")
    top = max(v[0] for v in PROF_VALUES)
    for i, name in enumerate(PROFS):
        x, y = 54 + 541 * (i % 3), 419 + round(28.3 * (i // 3))
        img.paste(kit.prof_icons[i], (x, y))
        text_at(d, (x + 20, y + 12), name, F_S, BAR_GOLD)
        bar(d, x + 149, y + 1, x + 423, PROF_VALUES[i][0] / top, BAR_GOLD)
        at300, best = PROF_VALUES[i]
        parts(d, x + 520, y + 13, [(str(at300), GOLD), (" · ", GREY), (str(best), GREY if best == 300 else RED)],
              right=True)

    online = kit.box(img, X0, 553, round(X0 + third), Y1)
    title(d, online, "Zuletzt online", "Stufe 60 · Klick zeigt, wer")
    buckets = [("Heute", lambda n: n == 0), ("1-7 Tage", lambda n: 1 <= n <= 7), ("8-30 Tage", lambda n: 8 <= n <= 30),
               ("1-3 Monate", lambda n: 31 <= n <= 90), ("Länger", lambda n: n > 90)]
    values = [sum(1 for m in M if test(m["days"])) for _, test in buckets]
    for i, (label, _) in enumerate(buckets):
        y = online[1] + 42 + round(i * 39.5)
        green = 1 - i / 4
        color = tuple(round(255 * v) for v in (1 - green * 0.6, 0.35 + green * 0.5, 0.25))
        text_at(d, (online[0] + 13, y + 12), label, F_S, WHITE)
        end = bar(d, online[0] + 175, y, online[2] - 60, values[i] / max(values), color)
        if values[i] == 0:
            d.line((online[0] + 175, y, online[0] + 175, y + 13), fill=color)
        text_at(d, (online[2] - 14, y + 12), str(values[i]), F_S, GOLD, "rs")

    raids = kit.box(img, online[2] + GAP, 553, round(X0 + 2 * third + GAP), Y1)
    title(d, raids, "Schlachtzüge", "Mitglieder mit Sieg · diesen Monat")
    raid_rows(kit, img, raids, raids[1] + 42, 38)
    d = ImageDraw.Draw(img)
    y = raids[1] + 180
    text_at(d, (raids[0] + 13, y), "Kommen und Gehen (30 Tage)", F_N, GOLD)
    text_at(d, (raids[0] + 27 + round(F_N.getlength("Kommen und Gehen (30 Tage)")), y), "+3 / -2", F_S, GREY)
    changes = [("-", RED, "Gesa Lerchenfeld hat die Gilde verlassen", "vor 2 Std."),
               ("+", GREEN, "Mira Dornhain ist beigetreten", "vor 20 Std."),
               ("+", GREEN, "Falk Hagelschlag ist beigetreten", "vor 3 Tg."),
               ("-", RED, "Lorn Nebelstein hat die Gilde verlassen", "vor 9 Tg."),
               ("+", GREEN, "Runa Quellgrund ist beigetreten", "vor 12 Tg.")]
    for i, (sign, color, line, when) in enumerate(changes):
        top_y = y + 12 + i * 23
        if i % 2 == 1:
            d.rectangle((raids[0] + 8, top_y, raids[2] - 9, top_y + 21), fill=ZEBRA)
        text_at(d, (raids[0] + 16, top_y + 16), sign, F_S, color)
        text_at(d, (raids[0] + 30, top_y + 16), line, F_S, WHITE)
        text_at(d, (raids[2] - 16, top_y + 16), when, F_S, GREY, "rs")

    matrix = kit.box(img, raids[2] + GAP, 553, X1, Y1)
    title(d, matrix, "Klasse × Itemlevel", "Stufe 60")
    bands = [("bis 49", 0, 50), ("50-55", 50, 56), ("56-59", 56, 60), ("60-64", 60, 65), ("ab 65", 65, 99)]
    cells = [[sum(1 for m in M if m["cls"] == c and lo <= m["ilvl"] < hi) for _, lo, hi in bands] for c in range(9)]
    peak = max(max(row) for row in cells)
    x_cells, cw, ch = matrix[0] + 128, (matrix[2] - 14 - matrix[0] - 128) / len(bands), 27
    for b, (label, _, _) in enumerate(bands):
        text_at(d, (round(x_cells + (b + 0.5) * cw), matrix[1] + 49), label, F_S, GREY, "ms")
    for c, (name, color) in enumerate(CLASSES):
        y = matrix[1] + 60 + c * ch
        text_at(d, (matrix[0] + 13, y + 18), name, F_S, color)
        for b in range(len(bands)):
            n = cells[c][b]
            x = round(x_cells + b * cw)
            d.rectangle((x + 1, y + 1, round(x_cells + (b + 1) * cw) - 2, y + ch - 3),
                        fill=blend(color, 0.15 + 0.6 * n / peak) if n else blend(WHITE, 0.03))
            if n:
                text_at(d, (round(x_cells + (b + 0.5) * cw), y + 18), str(n), F_S, WHITE, "ms")
    return img


# --- B: can we raid tonight? ---------------------------------------------------------------------------

def variant_b(kit):
    img = kit.base()
    toolbar(kit, img)
    d = ImageDraw.Draw(img)
    split = 1040

    roster = kit.box(img, X0, 111, split, 505)
    text_at(d, (59, 150), str(len(READY)), F_H, GOLD)
    x = 59 + round(F_H.getlength(str(len(READY)))) + 12
    text_at(d, (x, 138), "im Raidkader", F_N, GOLD)
    text_at(d, (x, 156), "Stufe 60 · in den letzten 7 Tagen online · Itemlevel ab %d" % READY_ILVL, F_S, GREY)
    legend = [("raidbereit", 1.0), ("Ausrüstung fehlt", 0.42), ("nicht da", None)]
    lx = roster[2] - 16
    for label, alpha in reversed(legend):
        lx -= round(F_S.getlength(label))
        text_at(d, (lx, 147), label, F_S, GREY)
        lx -= 18
        d.rectangle((lx, 136, lx + 11, 147), fill=blend(BAR_GOLD, alpha) if alpha else (58, 54, 46))
        lx -= 18
    top = max(sum(1 for m in M if m["cls"] == c) for c in range(9))
    for c, (name, color) in enumerate(CLASSES):
        y = 180 + c * 35
        mine = [m for m in M if m["cls"] == c]
        ready = sum(1 for m in mine if m["ready"])
        gear = sum(1 for m in mine if m["active"] and not m["ready"])
        away = len(mine) - ready - gear
        if c % 2 == 1:
            d.rectangle((roster[0] + 8, y - 6, roster[2] - 9, y + 27), fill=ZEBRA)
        text_at(d, (roster[0] + 16, y + 16), name, F_N, color)
        x0, x1 = roster[0] + 190, roster[2] - 190
        unit = (x1 - x0) / top
        x = x0
        for n, fill in ((ready, color), (gear, blend(color, 0.42, ZEBRA if c % 2 else BG)), (away, (58, 54, 46))):
            for _ in range(n):
                d.rectangle((round(x), y, round(x + unit) - 3, y + 20), fill=fill)
                x += unit
        parts(d, roster[2] - 16, y + 16, [(str(ready), GOLD), (" raidbereit", WHITE), (" · %d" % len(mine), GREY)],
              right=True)

    silent = kit.box(img, X0, 505 + GAP, split, Y1)
    title(d, silent, "Stille 60er", "seit über 14 Tagen nicht online · Klick öffnet die Charakterseite",
          "%d von %d" % (len(SILENT), len(M)))
    d.text((silent[0] + 16, silent[1] + 52), "", font=F_S)
    for label, x, anchor in (("Name", silent[0] + 16, "ls"), ("Ø Gegenstandsstufe", silent[0] + 250, "ls"),
                             ("Zuletzt online", silent[2] - 16, "rs")):
        text_at(d, (x, silent[1] + 50), label, F_S, GREY, anchor)
    silent_list(d, silent, 10, 25, 58, True)

    hours = kit.box(img, split + GAP, 111, X1, 470)
    title(d, hours, "Wann sind wir online?", "Ø Stufe-60-Mitglieder · letzte 4 Wochen")
    rnd = random.Random(5)
    days = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    cols = list(range(14, 24))
    left, cw, ch = hours[0] + 52, (hours[2] - 16 - hours[0] - 52) / len(cols), 34
    grid = []
    for r in range(7):
        row = []
        for h in cols:
            evening = max(0, 1 - abs(h - 20.5) / 4.2)
            weekend = 1.15 if r >= 4 else 1.0
            special = 1.35 if (r in (2, 6) and 20 <= h <= 21) else 1.0
            early = 0.5 if (r >= 5 and h < 18) else 0.12
            row.append(round((4 + 22 * max(evening, early * 0.6)) * weekend * special + rnd.uniform(-2, 2)))
        grid.append(row)
    peak = max(max(row) for row in grid)
    for i, h in enumerate(cols):
        text_at(d, (round(left + (i + 0.5) * cw), hours[1] + 52), "%d" % h, F_S, GREY, "ms")
    for r, day in enumerate(days):
        y = hours[1] + 62 + r * ch
        text_at(d, (hours[0] + 16, y + 21), day, F_S, WHITE)
        for i in range(len(cols)):
            n = grid[r][i]
            x = round(left + i * cw)
            d.rectangle((x + 1, y + 1, round(left + (i + 1) * cw) - 2, y + ch - 3), fill=blend(BAR_GOLD, 0.06 + 0.85 * (n / peak) ** 1.5))
            text_at(d, (round(left + (i + 0.5) * cw), y + 21), str(n), F_S, WHITE if n > peak * 0.45 else GREY, "ms")
    best_r, best_i = max(((r, i) for r in range(7) for i in range(len(cols) - 1)),
                         key=lambda p: grid[p[0]][p[1]] + grid[p[0]][p[1] + 1])
    y = hours[1] + 62 + best_r * ch
    d.rectangle((round(left + best_i * cw), y, round(left + (best_i + 2) * cw) - 1, y + ch - 2), outline=GOLD, width=2)
    full = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][best_r]
    parts(d, hours[0] + 16, hours[3] - 18, [
        ("Bester Abend: ", GREY), ("%s, %d-%d Uhr" % (full, cols[best_i], cols[best_i] + 2), GOLD),
        (" · im Schnitt ", GREY), (str((grid[best_r][best_i] + grid[best_r][best_i + 1]) // 2), GOLD), (" online", GREY)])

    raids = kit.box(img, split + GAP, 470 + GAP, X1, Y1)
    title(d, raids, "Schlachtzüge", "Mitglieder mit Sieg · Klick zeigt, wer")
    raid_rows(kit, img, raids, raids[1] + 46, 108, True)
    return img


# --- C: the pulse of the guild over time -----------------------------------------------------------------

def variant_c(kit):
    img = kit.base()
    toolbar(kit, img)
    d = ImageDraw.Draw(img)
    third = (X1 - X0 - 2 * GAP) / 3

    tiles = [("74", "Gildenpuls", "+9 zum Vormonat", GREEN), (str(len(M)), "auf Stufe 60", "+9 zum Vormonat", GREEN),
             (str(len(READY)), "im Raidkader", "+6 zum Vormonat", GREEN),
             (de(AVG), "Ø Itemlevel der 60er", "+1,9 zum Vormonat", GREEN),
             (str(len(SILENT)), "still seit 14 Tagen", "+3 zum Vormonat", RED)]
    tw = (X1 - X0 - GAP * (len(tiles) - 1)) / len(tiles)
    for i, (value, label, trend, color) in enumerate(tiles):
        x = round(X0 + i * (tw + GAP))
        box = kit.box(img, x, 111, round(x + tw), 211)
        cx = (box[0] + box[2]) // 2
        text_at(d, (cx, 153), value, F_H, GOLD, "ms")
        text_at(d, (cx, 174), label, F_S, GREY, "ms")
        text_at(d, (cx, 194), trend, F_S, color, "ms")

    chart = kit.box(img, X0, 211 + GAP, round(X0 + 2 * third + GAP), 560)
    title(d, chart, "Verlauf", "Mitglieder pro Woche")
    weeks = 14
    members = [58, 63, 70, 76, 81, 84, 88, 90, 93, 94, 96, 97, 98, 98]
    sixty = [0, 0, 1, 3, 6, 11, 17, 24, 31, 38, 46, 53, 59, len(M)]
    ready = [0, 0, 0, 0, 1, 3, 6, 9, 13, 17, 21, 24, 27, len(READY)]
    left, right, top, bottom = chart[0] + 52, chart[2] - 178, chart[1] + 52, chart[3] - 34
    scale = 100
    for value in (0, 25, 50, 75, 100):
        y = round(bottom - (bottom - top) * value / scale)
        d.line((left, y, right, y), fill=TRACK)
        text_at(d, (left - 10, y + 5), str(value), F_S, GREY, "rs")
    for w in range(0, weeks, 2):
        x = round(left + (right - left) * w / (weeks - 1))
        label = "heute" if w == weeks - 1 else "vor %d Wo." % (weeks - 1 - w)
        text_at(d, (x, chart[3] - 12), label, F_S, GREY, "ms")
    text_at(d, (right, chart[3] - 12), "heute", F_S, WHITE, "ms")
    big = Image.new("RGBA", (img.width * 3, img.height * 3), (0, 0, 0, 0))
    bd = ImageDraw.Draw(big)
    series = [(members, (150, 144, 130), "aktive Mitglieder"), (sixty, GOLD, "auf Stufe 60"), (ready, GREEN, "im Raidkader")]
    for values, color, _ in series:
        pts = [(3 * (left + (right - left) * i / (weeks - 1)), 3 * (bottom - (bottom - top) * v / scale))
               for i, v in enumerate(values)]
        bd.line(pts, fill=color + (255,), width=6, joint="curve")
    img.paste(big.resize(img.size, Image.LANCZOS), (0, 0), big.resize(img.size, Image.LANCZOS))
    d = ImageDraw.Draw(img)
    for values, color, label in series:
        y = round(bottom - (bottom - top) * values[-1] / scale)
        parts(d, right + 12, y + 5, [(str(values[-1]), color), (" " + label, GREY)])
    for week, raid, down in ((5, 2, 52), (7, 1, 86), (10, 0, 30)):   # first kills
        x = round(left + (right - left) * week / (weeks - 1))
        y = round(bottom - (bottom - top) * ready[week] / scale)
        d.line((x, top + down + 22, x, y - 3), fill=blend(GOLD, 0.45))
        img.paste(kit.raid_icons[raid].resize((21, 21), Image.LANCZOS), (x - 10, top + down))
        text_at(d, (x + 17, top + down + 16), "Erster Sieg: " + RAIDS[raid], F_S, WHITE)

    pulse = kit.box(img, chart[2] + GAP, 211 + GAP, X1, 560)
    title(d, pulse, "Diesen Monat", "Gilde gesamt · Strich: Vormonat")
    rows = [("Bosse in Schlachtzügen", 41, 28), ("Dungeon-Bosse", 312, 367), ("Dungeons betreten", 188, 204),
            ("Quests abgeschlossen", 1240, 2905), ("Ehrenhafte Siege", 2210, 1480), ("Tage online je Mitglied", 11.4, 10.2)]
    for i, (label, now, before) in enumerate(rows):
        y = pulse[1] + 46 + i * 46
        text_at(d, (pulse[0] + 16, y + 12), label, F_S, WHITE)
        fmt = (lambda v: de(v)) if isinstance(now, float) else (lambda v: "{:,}".format(v).replace(",", "."))
        delta = now - before
        sign = "+" if delta >= 0 else "-"
        parts(d, pulse[2] - 16, y + 12, [(fmt(now), GOLD), ("  %s%s" % (sign, fmt(abs(delta))), GREEN if delta >= 0 else RED)],
              right=True)
        x0, x1 = pulse[0] + 16, pulse[2] - 16
        peak = max(now, before) * 1.08
        bar(d, x0, y + 20, x1, now / peak, BAR_GOLD, 10)
        mx = round(x0 + (x1 - x0) * before / peak)
        d.rectangle((mx, y + 17, mx + 1, y + 32), fill=WHITE)

    hist = kit.box(img, X0, 560 + GAP, round(X0 + third), Y1)
    histogram(d, hist)
    raids = kit.box(img, hist[2] + GAP, 560 + GAP, round(X0 + 2 * third + GAP), Y1)
    title(d, raids, "Schlachtzüge", "Mitglieder mit Sieg · diesen Monat")
    raid_rows(kit, img, raids, raids[1] + 58, 74)
    d = ImageDraw.Draw(img)
    silent = kit.box(img, raids[2] + GAP, 560 + GAP, X1, Y1)
    title(d, silent, "Stille 60er", "Itemlevel · zuletzt online", "%d von %d" % (len(SILENT), len(M)))
    silent_list(d, silent, 9, 26, 38)
    return img


# --- D and E: activity score, this month, item levels, last online, joins and departures ----------------

AREAS = [("Schlachtzüge", (255, 128, 0)), ("Dungeons", (163, 53, 238)), ("PvP", (200, 60, 50)),
         ("Quests", (255, 209, 0)), ("Unterwegs", (0, 112, 221))]


def scores():
    """Made-up activity score per member: points per area that add up to the score, and the age of the reading."""
    rnd = random.Random(23)
    for m in M:
        level = max(4, min(97, round(72 - m["days"] * 6 + rnd.gauss(0, 17)))) if m["days"] <= 14 else rnd.randint(0, 6)
        kind = rnd.choice(("raid", "raid", "pvp", "dungeon", "mixed"))
        weights = {"raid": (5, 3, 0.4, 0.3, 1.2), "pvp": (0.6, 1, 5, 0.3, 1.5), "dungeon": (1, 5, 0.5, 1, 1.5),
                   "mixed": (2, 2, 2, 1, 2)}[kind]
        weights = [w * rnd.uniform(0.6, 1.4) for w in weights]
        if not m["ready"]:
            weights[0] *= 0.15
        m["score"] = level
        m["areas"] = [level * w / sum(weights) for w in weights]
        m["read"] = 0 if rnd.random() < 0.7 else rnd.randint(1, 4)
    for m in rnd.sample(M, 5):
        m["read"] = rnd.randint(9, 20)   # reading too old: no score


scores()
RANKED = sorted(M, key=lambda m: (m["read"] > 7, -m["score"]))
MONTH = [("Bosse in Schlachtzügen", 41, 28), ("Dungeon-Bosse", 312, 367), ("Dungeons betreten", 188, 204),
         ("Quests abgeschlossen", 1240, 2905), ("Ehrenhafte Siege", 2210, 1480), ("Tage online je Mitglied", 11.4, 10.2)]
CHANGES = [("+", "Winne Tatsch", 8, "vor 6 Std."), ("-", "Gesa Lerchenfeld", None, "vor 17 Std."),
           ("-", "Lorn Nebelstein", None, "vor 1 Tg."), ("+", "Mira Dornhain", 8, "vor 1 Tg."),
           ("-", "Rika Silberbach", None, "vor 1 Tg."), ("+", "Falk Hagelschlag", 7, "vor 1 Tg."),
           ("+", "Runa Quellgrund", 5, "vor 2 Tg."), ("-", "Jorin Ostwind", None, "vor 5 Tg."),
           ("+", "Imke Haselried", 1, "vor 9 Tg."), ("+", "Maren Nordkamm", 6, "vor 12 Tg.")]


def month_box(d, box):
    title(d, box, "Diesen Monat", "Gilde gesamt · Strich: Vormonat")
    pitch = (box[3] - box[1] - 62) / len(MONTH)
    for i, (label, now, before) in enumerate(MONTH):
        y = box[1] + 46 + round(i * pitch)
        text_at(d, (box[0] + 16, y + 12), label, F_S, WHITE)
        fmt = (lambda v: de(v)) if isinstance(now, float) else (lambda v: "{:,}".format(v).replace(",", "."))
        delta = now - before
        parts(d, box[2] - 16, y + 12, [(fmt(now), GOLD), ("  %s%s" % ("+" if delta >= 0 else "-", fmt(abs(delta))),
                                                         GREEN if delta >= 0 else RED)], right=True)
        x0, x1 = box[0] + 16, box[2] - 16
        peak = max(now, before) * 1.08
        bar(d, x0, y + 20, x1, now / peak, BAR_GOLD, 10)
        mx = round(x0 + (x1 - x0) * before / peak)
        d.rectangle((mx, y + 17, mx + 1, y + 32), fill=WHITE)


def online_box(d, box):
    title(d, box, "Zuletzt online", "alle Mitglieder · Klick zeigt, wer")
    values = [61, 22, 8, 7, 0]
    for i, label in enumerate(("Heute", "1-7 Tage", "8-30 Tage", "1-3 Monate", "Länger")):
        y = box[1] + 42 + round(i * 39.5)
        green = 1 - i / 4
        color = tuple(round(255 * v) for v in (1 - green * 0.6, 0.35 + green * 0.5, 0.25))
        text_at(d, (box[0] + 13, y + 12), label, F_S, WHITE)
        bar(d, box[0] + 175, y, box[2] - 60, values[i] / max(values), color)
        if values[i] == 0:
            d.line((box[0] + 175, y, box[0] + 175, y + 13), fill=color)
        text_at(d, (box[2] - 14, y + 12), str(values[i]), F_S, GOLD, "rs")


def changes_box(d, box):
    title(d, box, "Kommen und Gehen (30 Tage)", "+%d / -%d" % (sum(1 for c in CHANGES if c[0] == "+"),
                                                             sum(1 for c in CHANGES if c[0] == "-")))
    rows = min(len(CHANGES), (box[3] - box[1] - 48) // 25)
    for i, (sign, name, cls, when) in enumerate(CHANGES[:rows]):
        y = box[1] + 38 + i * 25
        if i % 2 == 1:
            d.rectangle((box[0] + 8, y, box[2] - 9, y + 23), fill=ZEBRA)
        text_at(d, (box[0] + 16, y + 17), sign, F_S, GREEN if sign == "+" else RED)
        parts(d, box[0] + 30, y + 17, [(name, CLASSES[cls][1] if cls is not None else WHITE),
                                       (" ist beigetreten" if sign == "+" else " hat die Gilde verlassen", WHITE)])
        text_at(d, (box[2] - 16, y + 17), when, F_S, GREY, "rs")


def variant_d(kit):
    """Six boxes of equal width; the score as the guild's pulse and its distribution."""
    img = kit.base()
    toolbar(kit, img)
    d = ImageDraw.Draw(img)
    third = (X1 - X0 - 2 * GAP) / 3
    xs = [(round(X0 + i * (third + GAP)), round(X0 + i * (third + GAP) + third)) for i in range(3)]
    mid = 471

    act = kit.box(img, xs[0][0], Y0, xs[0][1], mid)
    title(d, act, "Aktivität", "Wert 0-100 aus den Spielstatistiken · 30 Tage")
    text_at(d, (act[0] + 16, act[1] + 76), "74", F_H, GOLD)
    x = act[0] + 16 + round(F_H.getlength("74")) + 12
    parts(d, x, act[1] + 62, [("Gildenpuls", GOLD), ("   +9 zum Vormonat", GREEN)], F_N)
    text_at(d, (x, act[1] + 80), "Durchschnitt der 81 Mitglieder mit aktuellem Stand", F_S, GREY)
    levels = [("Sehr aktiv", "75-100", 23), ("Aktiv", "50-74", 31), ("Gelegentlich", "25-49", 18), ("Kaum", "1-24", 9)]
    peak = max(v for _, _, v in levels)
    for i, (label, span, n) in enumerate(levels):
        y = act[1] + 112 + i * 40
        green = 1 - i / 3
        color = tuple(round(255 * v) for v in (1 - green * 0.6, 0.35 + green * 0.5, 0.25))
        parts(d, act[0] + 16, y + 12, [(label, WHITE), ("  " + span, GREY)])
        bar(d, act[0] + 175, y, act[2] - 60, n / peak, color)
        text_at(d, (act[2] - 14, y + 12), str(n), F_S, GOLD, "rs")
    y = act[1] + 112 + 4 * 40
    text_at(d, (act[0] + 16, y + 12), "Kein aktueller Stand", F_S, GREY)
    bar(d, act[0] + 175, y, act[2] - 60, 17 / peak, (88, 82, 70))
    text_at(d, (act[2] - 14, y + 12), "17", F_S, GREY, "rs")
    text_at(d, (act[0] + 16, act[3] - 16), "Klick auf einen Balken zeigt, wer", F_S, GREY)

    month_box(d, kit.box(img, xs[1][0], Y0, xs[1][1], mid))
    histogram(d, kit.box(img, xs[2][0], Y0, xs[2][1], mid))
    online_box(d, kit.box(img, xs[0][0], mid + GAP, xs[0][1], Y1))
    changes_box(d, kit.box(img, xs[1][0], mid + GAP, xs[1][1], Y1))
    raids = kit.box(img, xs[2][0], mid + GAP, xs[2][1], Y1)
    title(d, raids, "Schlachtzüge", "Mitglieder mit Sieg · Klick zeigt, wer")
    raid_rows(kit, img, raids, raids[1] + 46, 106, True)
    return img


def variant_e(kit):
    """The score per member on the left, made up of its areas; the four boxes of the guild on the right."""
    img = kit.base()
    toolbar(kit, img)
    d = ImageDraw.Draw(img)
    split = X0 + 640
    half = (X1 - split - 2 * GAP) / 2
    xa, xb = split + GAP, round(split + GAP + half + GAP)
    mid = 471

    act = kit.box(img, X0, Y0, split, Y1)
    title(d, act, "Aktivität", "Wert 0-100 aus den Spielstatistiken · 30 Tage")
    parts(d, act[2] - 16, act[1] + 23, [("Gildenpuls ", GREY), ("74", GOLD), ("  +9", GREEN)], right=True)
    x = act[0] + 16
    for label, color in AREAS:
        d.rectangle((x, act[1] + 40, x + 11, act[1] + 51), fill=blend(color, 0.85))
        text_at(d, (x + 18, act[1] + 51), label, F_S, GREY)
        x += 18 + round(F_S.getlength(label)) + 22
    for label, lx, anchor in (("Name", act[0] + 16, "ls"), ("Wert", act[2] - 96, "rs"), ("Stand", act[2] - 16, "rs")):
        text_at(d, (lx, act[1] + 78), label, F_S, GREY, anchor)
    x0, x1 = act[0] + 200, act[2] - 150
    fresh = [m for m in RANKED if m["read"] <= 7]
    shown = fresh[::max(1, len(fresh) // 23)][:23] + [m for m in RANKED if m["read"] > 7][:3]
    for i, m in enumerate(shown):
        y = act[1] + 86 + i * 25
        if i % 2 == 1:
            d.rectangle((act[0] + 8, y, act[2] - 9, y + 23), fill=ZEBRA)
        old = m["read"] > 7
        text_at(d, (act[0] + 16, y + 17), m["name"], F_S, CLASSES[m["cls"]][1])
        d.rectangle((x0, y + 5, x1 - 1, y + 17), fill=TRACK)
        if old:
            text_at(d, (x0 + 8, y + 17), "kein aktueller Stand", F_S, GREY)
            text_at(d, (act[2] - 96, y + 17), "-", F_S, GREY, "rs")
        else:
            x = x0
            for (_, color), points in zip(AREAS, m["areas"]):
                w = (x1 - x0) * points / 100
                if w >= 1:
                    d.rectangle((round(x), y + 5, round(x + w) - 1, y + 17), fill=blend(color, 0.85))
                x += w
            text_at(d, (act[2] - 96, y + 17), str(m["score"]), F_S, GOLD, "rs")
        text_at(d, (act[2] - 16, y + 17), days_text(m["read"]), F_S, GREY, "rs")

    month_box(d, kit.box(img, xa, Y0, round(xa + half), mid))
    histogram(d, kit.box(img, xb, Y0, X1, mid))
    online_box(d, kit.box(img, xa, mid + GAP, round(xa + half), Y1))
    changes_box(d, kit.box(img, xb, mid + GAP, X1, Y1))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    kit = Kit()
    for key, build in (("a", variant_a), ("b", variant_b), ("c", variant_c), ("d", variant_d), ("e", variant_e)):
        img = build(kit)
        path = os.path.join(OUT, "endgame-%s.png" % key)
        img.save(path)
        print(path, img.size)


if __name__ == "__main__":
    main()
