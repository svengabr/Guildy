"""Mock-ups of a guild bank tab, drawn into the real reference screenshots (src/crop/, see crop.py) the same
way as mock_endgame.py: frame, boxes, buttons, tabs, scroll bar and icons are the game's own pixels, the content
is drawn with the game's font.

    python media/gallery/mock_bank.py        ->  mock/bank-a.png … -d.png

A: the ledger, every movement in one list.  B: the balance per member.  C: stock and history.
D: A with the gold chart of C above the ledger.
All names and numbers are made up. Needs Pillow; src/ and fonts/ are local only.
"""
import os
import random

from PIL import Image, ImageDraw, ImageFont

from mock_endgame import (BAR_GOLD, CLASSES, CROP, F_H, F_N, F_S, FONT, GAP, GOLD, GREEN, GREY, HERE, M, OUT, RED,
                          TRACK, WHITE, X0, X1, Y0, Y1, ZEBRA, Kit, bar, blend, parts, text_at, title)

ICONS = os.path.join(HERE, "icons")
F_T = ImageFont.truetype(FONT, 15.2)   # the window's tabs
NOW_GOLD = 1284 * 10000 + 3700          # the bank's money today, in copper
RANKS = ["Gildenmeister", "Offizier", "Raidleiter", "Mitglied", "Freund", "Neuling"]
BANK_TABS = [("Verbrauch", "trade_alchemy", 71), ("Handwerk", "trade_blacksmithing", 44),
             ("Kräuter & Erze", "trade_herbalism", 88), ("Stoffe & Leder", "trade_tailoring", 23)]
# (name, icon, bank tab, in stock)
ITEMS = [("Erheblicher Heiltrank", "inv_potion_54", 0, 143), ("Überragender Heiltrank", "inv_potion_51", 0, 61),
         ("Elixier des Mungos", "inv_potion_32", 0, 38), ("Gerösteter Raptor", "inv_misc_food_15", 0, 220),
         ("Robustes Rüstungsset", "inv_misc_armorkit_17", 1, 47), ("Traumblatt", "trade_herbalism", 2, 312),
         ("Dicker Wolfspelz", "inv_misc_pelt_wolf_01", 3, 96)]
VERB = {"in": "legt ein", "out": "entnimmt", "move": "verschiebt", "gold_in": "zahlt ein", "gold_out": "hebt ab",
        "repair": "repariert", "buytab": "kauft Fach 4"}
SIGN = {"in": ("+", GREEN), "out": ("-", RED), "move": ("·", GREY), "gold_in": ("+", GREEN), "gold_out": ("-", RED),
        "repair": ("-", RED), "buytab": ("-", RED)}


# --- made-up bank log ---------------------------------------------------------------------------------

def ledger():
    """Newest first. What the game reports per entry: kind, name, item, count, bank tab(s) or amount, and how
    long ago in whole hours."""
    rnd = random.Random(41)
    actors = rnd.sample(M, 26)
    for i, m in enumerate(actors):
        m["rank"] = 0 if i == 0 else 1 if i < 4 else 2 if i < 6 else 3 if i < 18 else 4 if i < 22 else 5
        m["weight"] = rnd.uniform(0.3, 1.0) * (2.6 if m["rank"] <= 2 else 1.0)
        m["giver"] = rnd.uniform(0.25, 0.8)
    rows = []
    for _ in range(170):
        m = rnd.choices(actors, [a["weight"] for a in actors])[0]
        hours = int(720 * rnd.random() ** 2.1)
        roll = rnd.random()
        row = {"who": m, "hours": hours}
        if roll < 0.66:
            item = rnd.randrange(len(ITEMS))
            row.update(kind="in" if rnd.random() < m["giver"] else "out", item=item, tab=ITEMS[item][2],
                       count=rnd.choice((1, 2, 4, 5, 5, 10, 10, 20, 20)))
        elif roll < 0.70:
            item = rnd.randrange(len(ITEMS))
            row.update(kind="move", item=item, tab=ITEMS[item][2], count=rnd.choice((5, 10, 20)))
        elif roll < 0.82:
            row.update(kind="gold_in", amount=rnd.choice((5, 10, 10, 20, 25, 50, 50, 100, 120)) * 10000)
        elif roll < 0.89 and m["rank"] <= 2:
            row.update(kind="gold_out", amount=rnd.choice((5, 10, 15, 20, 30, 40)) * 10000)
        else:
            row.update(kind="repair", amount=rnd.randint(40, 620) * 100 + rnd.randint(0, 99))
        rows.append(row)
    rows.append({"who": actors[0], "hours": 11 * 24 + 3, "kind": "buytab", "amount": 250 * 10000})
    rows.sort(key=lambda r: r["hours"])
    money = NOW_GOLD
    for r in rows:
        r["after"] = money
        if "amount" in r:
            money += -r["amount"] if r["kind"] == "gold_in" else r["amount"]
    return rows, actors


LOG, ACTORS = ledger()


def when(hours):
    if hours < 24:
        return "vor %d Std." % max(1, hours)
    return "vor %d Tg." % (hours // 24)


def dots(n):
    return "{:,}".format(n).replace(",", ".")


# --- pieces --------------------------------------------------------------------------------------------

def coin(size, kind):
    fill, rim, light = {"g": ((238, 186, 40), (122, 78, 8), (255, 236, 150)),
                        "s": ((196, 198, 204), (84, 86, 94), (246, 246, 250)),
                        "c": ((200, 112, 52), (98, 48, 18), (240, 172, 120))}[kind]
    k = 6
    big = Image.new("RGBA", (size * k, size * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.ellipse((0, 0, size * k - 1, size * k - 1), fill=rim + (255,))
    d.ellipse((k, k, size * k - k - 1, size * k - k - 1), fill=fill + (255,))
    d.ellipse((size * k * 0.24, size * k * 0.18, size * k * 0.56, size * k * 0.46), fill=light + (255,))
    return big.resize((size, size), Image.LANCZOS)


COINS = {}


def money(img, x, y, copper, font=F_S, color=WHITE, right=False, sign=""):
    """An amount with the coins behind the numbers, baseline y; with right=True it ends at x."""
    d = ImageDraw.Draw(img)
    size = {F_S: 12, F_N: 14, F_H: 22}[font]
    gold, silver = copper // 10000, copper // 100 % 100
    pieces = []
    if gold:
        pieces.append((sign + dots(gold), "g"))
    if silver and gold < 100 or not gold:
        pieces.append((("" if gold else sign) + str(silver), "s"))
    gap = 3 if font is not F_H else 5
    width = sum(font.getlength(s) + gap + size for s, _ in pieces) + (len(pieces) - 1) * (gap + 2)
    if right:
        x -= width
    for s, kind in pieces:
        text_at(d, (round(x), y), s, font, color)
        x += font.getlength(s) + gap
        c = COINS.setdefault((size, kind), coin(size, kind))
        img.paste(c, (round(x), y - size + (1 if font is not F_H else 0)), c)
        x += size + gap + 2
    return x - gap - 2


ICON_CACHE = {}


def icon(img, name, x, y, size=18):
    key = (name, size)
    if key not in ICON_CACHE:
        src = Image.open(os.path.join(ICONS, name + ".jpg")).convert("RGB").crop((4, 4, 52, 52))
        ICON_CACHE[key] = src.resize((size, size), Image.LANCZOS)
    img.paste(ICON_CACHE[key], (x, y))
    ImageDraw.Draw(img).rectangle((x - 1, y - 1, x + size, y + size), outline=(8, 7, 5))


def bottom_tabs(kit, img):
    """The window's tabs with an eighth one, 'Bank', selected."""
    ranks = Image.open(os.path.join(CROP, "11-ranks.png")).convert("RGB")
    info = Image.open(os.path.join(CROP, "10-info.png")).convert("RGB")
    img.paste(ranks.crop((30, 878, 692, 940)), (30, 878))
    img.paste(info.crop((692, 878, 802, 940)), (692, 878))
    tab = ranks.crop((694, 880, 801, 934))
    column = tab.crop((9, 0, 10, tab.height))
    for x in range(10, tab.width - 10):
        tab.paste(column, (x, 0))
    img.paste(tab, (694 + 108, 880))
    text_at(ImageDraw.Draw(img), (694 + 108 + 51, 911), "Bank", F_T, WHITE, "ms")


def page(kit, buttons, status=True):
    img = kit.base()
    bottom_tabs(kit, img)
    d = ImageDraw.Draw(img)
    x = 118
    for group in buttons:
        if isinstance(group, str):
            text_at(d, (x + 6, 91), group, F_S, GOLD)
            x += round(F_S.getlength(group)) + 20
            continue
        for label, selected in group:
            x = kit.button(img, x, label, selected)
        x += 14
    if status:
        parts(d, 1680, 91, [("Stand: ", GREY), ("vor 2 Std.", WHITE), (" · am Bankfach gelesen von ", GREY),
                            ("Alva Abendrot", CLASSES[8][1])], right=True)
    return img, d


def zebra(d, box, y, pitch, i, right=9):
    if i % 2 == 1:
        d.rectangle((box[0] + 8, y, box[2] - right, y + pitch - 2), fill=ZEBRA)


def head(d, box, y, columns):
    for label, x, anchor in columns:
        text_at(d, (x, y), label, F_S, GREY, anchor)
    d.line((box[0] + 10, y + 8, box[2] - 11, y + 8), fill=TRACK)


def what(img, d, r, x, y, pitch, limit=None):
    """Item with icon and count, or the amount; y is the top of the row."""
    base = y + pitch - 9
    if "amount" in r:
        return money(img, x, base, r["amount"], color=WHITE)
    name, ico = ITEMS[r["item"]][:2]
    icon(img, ico, x, y + (pitch - 2 - 18) // 2)
    return parts(d, x + 26, base, [(name, WHITE), ("  × %d" % r["count"], GOLD)])


def tabs_box(kit, img, d, box, pitch=40, hint="belegte Plätze"):
    title(d, box, "Fächer", hint)
    for i, (name, ico, used) in enumerate(BANK_TABS):
        y = box[1] + 42 + i * pitch
        icon(img, ico, box[0] + 16, y, 26)
        text_at(d, (box[0] + 52, y + 12), name, F_S, WHITE)
        bar(d, box[0] + 52, y + 18, box[2] - 16, used / 98, BAR_GOLD if used < 80 else (214, 122, 50), 8)
        parts(d, box[2] - 16, y + 12, [(str(used), GOLD), (" / 98", GREY)], right=True)
    y = box[1] + 42 + len(BANK_TABS) * pitch
    text_at(d, (box[0] + 52, y + 17), "Fach 5 kostet", F_S, GREY)
    money(img, box[2] - 16, y + 17, 500 * 10000, color=GREY, right=True)


def scrollbar(img, y0, y1):
    """The game's scroll bar between y0 and y1, at the right edge of the window's body."""
    src = Image.open(os.path.join(CROP, "10-info.png")).convert("RGB").crop((1656, 146, 1686, 858))
    track = src.crop((0, 300, 30, 320))
    for y in range(y0, y1, 20):
        img.paste(track.crop((0, 0, 30, min(20, y1 - y))), (1656, y))
    img.paste(src.crop((0, 0, 30, 56)), (1656, y0))
    img.paste(src.crop((0, 682, 30, 712)), (1656, y1 - 30))


def week(kind, hours=168):
    return [r for r in LOG if r["hours"] < hours and r["kind"] in kind]


# --- A: the ledger ---------------------------------------------------------------------------------------

def variant_a(kit, chart=False):
    img, d = page(kit, [[("Alles", True), ("Gold", False), ("Gegenstände", False)], "Fach",
                        [("Alle", True)] + [(t[0], False) for t in BANK_TABS]])
    side = X0 + 340

    total = kit.box(img, X0, Y0, side, 349)
    title(d, total, "Gildenbank")
    money(img, total[0] + 16, total[1] + 74, NOW_GOLD, F_H, GOLD)
    text_at(d, (total[0] + 16, total[1] + 96), "in den letzten 7 Tagen", F_S, GREY)
    rows = [("Eingezahlt", sum(r["amount"] for r in week(("gold_in",))), GREEN, "+"),
            ("Abgehoben", sum(r["amount"] for r in week(("gold_out",))), RED, "-"),
            ("Reparaturen", sum(r["amount"] for r in week(("repair",))), RED, "-")]
    for i, (label, value, color, sign) in enumerate(rows):
        y = total[1] + 124 + i * 24
        text_at(d, (total[0] + 16, y), label, F_S, WHITE)
        money(img, total[2] - 16, y, value, color=color, right=True, sign=sign)
    y = total[1] + 124 + 3 * 24
    text_at(d, (total[0] + 16, y), "Gegenstände", F_S, WHITE)
    parts(d, total[2] - 16, y, [("+%d" % sum(r["count"] for r in week(("in",))), GREEN), ("  /  ", GREY),
                                ("-%d" % sum(r["count"] for r in week(("out",))), RED)], right=True)

    tabs = kit.box(img, X0, 349 + GAP, side, 615)
    tabs_box(kit, img, d, tabs)

    mine = kit.box(img, X0, 615 + GAP, side, Y1)
    title(d, mine, "Dein Zugriff", "Rang Offizier")
    text_at(d, (mine[0] + 16, mine[1] + 56), "Gold heute noch", F_S, WHITE)
    money(img, mine[2] - 16, mine[1] + 56, 38 * 10000, color=GOLD, right=True)
    bar(d, mine[0] + 16, mine[1] + 64, mine[2] - 16, 38 / 50, BAR_GOLD, 8)
    text_at(d, (mine[0] + 16, mine[1] + 100), "Entnahmen heute noch", F_S, GREY)
    for i, (name, _, _) in enumerate(BANK_TABS):
        y = mine[1] + 124 + i * 23
        left, limit = ((8, 10), (10, 10), (3, 5), (0, 0))[i]
        text_at(d, (mine[0] + 16, y), name, F_S, WHITE)
        if limit:
            parts(d, mine[2] - 16, y, [(str(left), GOLD), (" / %d" % limit, GREY)], right=True)
        else:
            text_at(d, (mine[2] - 16, y), "nur ansehen", F_S, GREY, "rs")

    book_top = Y0
    if chart:
        gold = kit.box(img, side + GAP, Y0, X1, Y0 + 244)
        gold_chart(img, gold)
        d = ImageDraw.Draw(img)
        book_top = gold[3] + GAP
    book = kit.box(img, side + GAP, book_top, X1, Y1)
    title(d, book, "Kassenbuch", "Gold und alle Fächer · Klick auf einen Namen zeigt nur ihn",
          "%d Einträge" % len(LOG))
    cw, cn, cv, ci, cf, cb = book[0] + 16, book[0] + 118, book[0] + 330, book[0] + 480, book[0] + 900, book[2] - 48
    head(d, book, book[1] + 52, [("Wann", cw, "ls"), ("Wer", cn, "ls"), ("Vorgang", cv, "ls"),
                                 ("Gegenstand / Betrag", ci, "ls"), ("Fach", cf, "ls"), ("Gold danach", cb, "rs")])
    pitch, top = 26, book[1] + 66
    count = (book[3] - top - 6) // pitch
    scrollbar(img, book[1] + 35, book[3] - 5)
    shown = LOG[:count]
    gap_at = count - (4 if chart else 6)
    since = when(shown[gap_at]["hours"])
    for i in range(count):
        y = top + i * pitch
        base = y + pitch - 9
        zebra(d, book, y, pitch, i, 40)
        if i == gap_at:
            text_at(d, (cw, base), since, F_S, GREY)
            text_at(d, (cn, base), "Lücke: Zwischen zwei Lesungen lagen mehr als 25 Bewegungen, ältere Einträge "
                                   "können fehlen.", F_S, (214, 122, 50))
            continue
        r = shown[i - (1 if i > gap_at else 0)]
        text_at(d, (cw, base), when(r["hours"]), F_S, GREY)
        text_at(d, (cn, base), r["who"]["name"], F_S, CLASSES[r["who"]["cls"]][1])
        sign, color = SIGN[r["kind"]]
        text_at(d, (cv, base), sign, F_S, color)
        text_at(d, (cv + 14, base), VERB[r["kind"]], F_S, WHITE)
        what(img, d, r, ci, y, pitch)
        if "item" in r:
            name = BANK_TABS[r["tab"]][0]
            if r["kind"] == "move":
                name += "  >  " + BANK_TABS[(r["tab"] + 1) % 4][0]
            text_at(d, (cf, base), name, F_S, GREY)
        else:
            text_at(d, (cf, base), "Gold", F_S, blend(GOLD, 0.7))
            money(img, cb, base, r["after"], color=GOLD, right=True)
    return img


# --- B: the balance per member -----------------------------------------------------------------------------

def balance():
    out = []
    for m in ACTORS:
        mine = [r for r in LOG if r["who"] is m]
        if not mine:
            continue
        out.append({"m": m, "rows": mine,
                    "paid": sum(r["amount"] for r in mine if r["kind"] == "gold_in"),
                    "taken": sum(r["amount"] for r in mine if r["kind"] in ("gold_out", "repair", "buytab")),
                    "repair": sum(r["amount"] for r in mine if r["kind"] == "repair"),
                    "in": sum(r["count"] for r in mine if r["kind"] == "in"),
                    "out": sum(r["count"] for r in mine if r["kind"] == "out")})
    out.sort(key=lambda b: b["taken"] - b["paid"])
    return out


def variant_b(kit):
    img, d = page(kit, [[("Mitglieder", True), ("Ränge", False)], "Zeitraum",
                        [("7 Tage", False), ("30 Tage", True), ("Alles", False)]])
    split = 1128
    rows = balance()
    pick = max(rows, key=lambda b: len(b["rows"]) if 14 <= len(b["rows"]) else 0)
    sel = Image.open(os.path.join(CROP, "11-ranks.png")).convert("RGB").getpixel((240, 186))

    table = kit.box(img, X0, Y0, split, Y1)
    title(d, table, "Wer gibt, wer nimmt", "30 Tage · Klick auf eine Spalte sortiert · Klick auf eine Zeile zeigt die "
                                           "Bewegungen", "%d Mitglieder" % len(rows))
    cn, cr = table[0] + 16, table[0] + 216
    cp, ct, mid, half = table[0] + 470, table[0] + 590, table[0] + 720, 100
    ci, co, cl = table[0] + 890, table[0] + 960, table[2] - 16
    text_at(d, (mid, table[1] + 52), "Gold: Saldo", F_S, GREY, "ms")
    head(d, table, table[1] + 52, [("Name", cn, "ls"), ("Rang", cr, "ls"), ("eingezahlt", cp, "rs"),
                                   ("entnommen", ct, "rs"), ("Gegenst. +", ci, "rs"), ("-", co, "rs"),
                                   ("zuletzt", cl, "rs")])
    pitch, top = 26, table[1] + 66
    peak = max(abs(b["paid"] - b["taken"]) for b in rows)
    for i, b in enumerate(rows[:(table[3] - top - 6) // pitch]):
        y = top + i * pitch
        base = y + pitch - 9
        zebra(d, table, y, pitch, i)
        if b is pick:
            d.rectangle((table[0] + 8, y, table[2] - 9, y + pitch - 2), fill=sel)
        m = b["m"]
        text_at(d, (cn, base), m["name"], F_S, CLASSES[m["cls"]][1])
        text_at(d, (cr, base), RANKS[m["rank"]], F_S, GREY)
        if b["paid"]:
            money(img, cp, base, b["paid"], color=WHITE, right=True)
        else:
            text_at(d, (cp, base), "-", F_S, GREY, "rs")
        if b["taken"]:
            money(img, ct, base, b["taken"], color=WHITE, right=True)
        else:
            text_at(d, (ct, base), "-", F_S, GREY, "rs")
        net = b["paid"] - b["taken"]
        w = round(half * abs(net) / peak)
        if net >= 0:
            d.rectangle((mid, y + 6, mid + max(w, 1), y + pitch - 9), fill=blend(GREEN, 0.8))
        else:
            d.rectangle((mid - max(w, 1), y + 6, mid, y + pitch - 9), fill=blend(RED, 0.85))
        d.line((mid, y + 2, mid, y + pitch - 4), fill=(110, 104, 90))
        text_at(d, (ci, base), "+%d" % b["in"] if b["in"] else "-", F_S, GREEN if b["in"] else GREY, "rs")
        text_at(d, (co, base), "-%d" % b["out"] if b["out"] else "-", F_S, RED if b["out"] else GREY, "rs")
        text_at(d, (cl, base), when(b["rows"][0]["hours"]), F_S, GREY, "rs")

    one = kit.box(img, split + GAP, Y0, X1, 560)
    m = pick["m"]
    text_at(d, (one[0] + 13, one[1] + 23), m["name"], F_N, CLASSES[m["cls"]][1])
    text_at(d, (one[0] + 27 + round(F_N.getlength(m["name"])), one[1] + 23),
            "%s · %s" % (RANKS[m["rank"]], CLASSES[m["cls"]][0]), F_S, GREY)
    text_at(d, (one[2] - 14, one[1] + 23), "%d Bewegungen" % len(pick["rows"]), F_S, GREY, "rs")
    third = (one[2] - one[0] - 32) / 3
    for i, (label, value, color, sign) in enumerate((("eingezahlt", pick["paid"], GREEN, "+"),
                                                     ("entnommen", pick["taken"], RED, "-"),
                                                     ("davon Reparaturen", pick["repair"], WHITE, ""))):
        x = round(one[0] + 16 + i * third)
        money(img, x, one[1] + 66, value, F_N, color, sign=sign)
        text_at(d, (x, one[1] + 84), label, F_S, GREY)
    head(d, one, one[1] + 112, [("Wann", one[0] + 16, "ls"), ("Vorgang", one[0] + 110, "ls"),
                                ("Gegenstand / Betrag", one[0] + 250, "ls")])
    pitch, top = 26, one[1] + 126
    for i, r in enumerate(pick["rows"][:(one[3] - top - 6) // pitch]):
        y = top + i * pitch
        base = y + pitch - 9
        zebra(d, one, y, pitch, i)
        text_at(d, (one[0] + 16, base), when(r["hours"]), F_S, GREY)
        sign, color = SIGN[r["kind"]]
        text_at(d, (one[0] + 110, base), sign, F_S, color)
        text_at(d, (one[0] + 124, base), VERB[r["kind"]], F_S, WHITE)
        what(img, d, r, one[0] + 250, y, pitch)

    big = kit.box(img, split + GAP, 560 + GAP, X1, Y1)
    title(d, big, "Größte Entnahmen", "7 Tage · Gold und Gegenstände")
    takes = sorted(week(("gold_out", "out", "repair")), key=lambda r: -(r.get("amount", 0) + r.get("count", 0) * 9000))
    pitch, top = 26, big[1] + 40
    for i, r in enumerate(takes[:(big[3] - top - 6) // pitch]):
        y = top + i * pitch
        base = y + pitch - 9
        zebra(d, big, y, pitch, i)
        text_at(d, (big[0] + 16, base), r["who"]["name"], F_S, CLASSES[r["who"]["cls"]][1])
        x = what(img, d, r, big[0] + 216, y, pitch)
        if r["kind"] == "repair":
            text_at(d, (round(x) + 10, base), "Reparatur", F_S, GREY)
        text_at(d, (big[2] - 16, base), when(r["hours"]), F_S, GREY, "rs")
    return img


def gold_chart(img, chart):
    """The bank's gold over 30 days as a stepped line, with the day's deposits and withdrawals as bars."""
    d = ImageDraw.Draw(img)
    title(d, chart, "Gold in der Bank", "30 Tage · Balken: Ein- und Auszahlungen pro Tag")
    left, right, top, bottom = chart[0] + 66, chart[2] - 150, chart[1] + 50, chart[3] - 34
    lo, hi = 800, 1600
    scale = (bottom - top) / 750
    ypos = lambda copper: bottom - (bottom - top) * (copper / 10000 - lo) / (hi - lo)   # noqa: E731
    xpos = lambda hours: right - (right - left) * hours / 720                           # noqa: E731
    for value in range(lo, hi + 1, 200):
        y = round(ypos(value * 10000))
        d.line((left, y, right, y), fill=TRACK)
        text_at(d, (left - 10, y + 5), dots(value), F_S, GREY, "rs")
    for day in range(0, 31, 5):
        text_at(d, (round(xpos(day * 24)), chart[3] - 12), "heute" if day == 0 else "vor %d Tg." % day, F_S,
                WHITE if day == 0 else GREY, "ms")
    dw = (right - left) / 30
    for day in range(30):
        mine = [r for r in LOG if r["hours"] // 24 == day and "amount" in r]
        plus = sum(r["amount"] for r in mine if r["kind"] == "gold_in") / 10000
        minus = sum(r["amount"] for r in mine if r["kind"] != "gold_in") / 10000
        x = xpos((day + 1) * 24)
        if plus:
            d.rectangle((round(x) + 2, round(bottom - plus * scale), round(x + dw) - 3, bottom), fill=blend(GREEN, 0.38))
        if minus:
            d.rectangle((round(x) + 2, round(bottom - min(minus, 300) * scale), round(x + dw / 2) - 1, bottom),
                        fill=blend(RED, 0.55))
    k = 3
    big = Image.new("RGBA", (img.width * k, img.height * k), (0, 0, 0, 0))
    bd = ImageDraw.Draw(big)
    pts = [(xpos(0), ypos(NOW_GOLD))]
    money_rows = [r for r in LOG if "amount" in r]
    for r in money_rows:
        if r["hours"] > 700:
            break
        before = r["after"] + (-r["amount"] if r["kind"] == "gold_in" else r["amount"])
        pts += [(xpos(r["hours"]), ypos(r["after"])), (xpos(r["hours"]), ypos(before))]
    pts.append((left, pts[-1][1]))
    bd.line([(x * k, y * k) for x, y in pts], fill=GOLD + (255,), width=2 * k, joint="curve")
    small = big.resize(img.size, Image.LANCZOS)
    img.paste(small, (0, 0), small)
    d = ImageDraw.Draw(img)
    money(img, right + 12, round(ypos(NOW_GOLD)) + 5, NOW_GOLD, color=GOLD)
    text_at(d, (right + 12, round(ypos(NOW_GOLD)) + 23), "heute", F_S, GREY)
    buy = next(r for r in LOG if r["kind"] == "buytab")
    x, y = round(xpos(buy["hours"])), round(ypos(buy["after"] + buy["amount"]))
    d.line((x, y - 34, x, y - 6), fill=blend(GOLD, 0.45))
    icon(img, "trade_tailoring", x - 10, y - 58, 20)
    parts(d, x + 18, y - 43, [("Fach 4 gekauft von ", WHITE), (buy["who"]["name"], CLASSES[buy["who"]["cls"]][1])])


# --- C: stock and history ----------------------------------------------------------------------------------

def variant_c(kit):
    img, d = page(kit, [[("Bestand & Verlauf", True), ("Kassenbuch", False), ("Mitglieder", False)], "Zeitraum",
                        [("7 Tage", False), ("30 Tage", True), ("Alles", False)]])
    third = (X1 - X0 - 2 * GAP) / 3
    month = lambda kind: sum(r["amount"] for r in LOG if r["kind"] in kind)   # noqa: E731

    tiles = [(NOW_GOLD, "Gold in der Bank", GOLD, ""), (month(("gold_in",)), "eingezahlt · 30 Tage", GREEN, "+"),
             (month(("gold_out",)), "abgehoben · 30 Tage", RED, "-"),
             (month(("repair",)), "Reparaturen · 30 Tage", RED, "-")]
    tw = (X1 - X0 - GAP * 4) / 5
    for i, (value, label, color, sign) in enumerate(tiles):
        x = round(X0 + i * (tw + GAP))
        box = kit.box(img, x, Y0, round(x + tw), 211)
        cx = (box[0] + box[2]) // 2
        probe = Image.new("RGB", (10, 10))
        width = money(probe, 0, 0, value, F_H, sign=sign)
        money(img, round(cx - width / 2), 155, value, F_H, color, sign=sign)
        text_at(d, (cx, 186), label, F_S, GREY, "ms")
    box = kit.box(img, round(X0 + 4 * (tw + GAP)), Y0, X1, 211)
    cx = (box[0] + box[2]) // 2
    used = sum(t[2] for t in BANK_TABS)
    parts(d, cx - (F_H.getlength(str(used)) + F_N.getlength(" / 392")) / 2, 155, [(str(used), GOLD)], F_H)
    text_at(d, (round(cx + (F_H.getlength(str(used)) - F_N.getlength(" / 392")) / 2), 155), " / 392", F_N, GREY)
    text_at(d, (cx, 186), "Plätze belegt · 4 Fächer", F_S, GREY, "ms")

    chart = kit.box(img, X0, 211 + GAP, round(X0 + 2 * third + GAP), 560)
    gold_chart(img, chart)
    d = ImageDraw.Draw(img)

    stock = kit.box(img, chart[2] + GAP, 211 + GAP, X1, 560)
    title(d, stock, "Bestand", "Klick zeigt, wer eingelegt und entnommen hat")
    head(d, stock, stock[1] + 52, [("Gegenstand", stock[0] + 16, "ls"), ("7 Tage", stock[2] - 110, "rs"),
                                   ("in der Bank", stock[2] - 16, "rs")])
    pitch, top = 37, stock[1] + 66
    for i, (name, ico, tab, have) in enumerate(ITEMS):
        y = top + i * pitch
        zebra(d, stock, y, pitch, i)
        icon(img, ico, stock[0] + 16, y + 4, 26)
        text_at(d, (stock[0] + 52, y + 15), name, F_S, WHITE)
        text_at(d, (stock[0] + 52, y + 31), BANK_TABS[tab][0], F_S, GREY)
        delta = sum(r["count"] * (1 if r["kind"] == "in" else -1) for r in week(("in", "out")) if r["item"] == i)
        text_at(d, (stock[2] - 110, y + 23), "%+d" % delta if delta else "0", F_S,
                GREEN if delta > 0 else RED if delta < 0 else GREY, "rs")
        text_at(d, (stock[2] - 16, y + 23), str(have), F_S, GOLD, "rs")

    last = kit.box(img, X0, 560 + GAP, round(X0 + third), Y1)
    title(d, last, "Letzte Bewegungen", "Klick öffnet das Kassenbuch")
    pitch, top = 26, last[1] + 40
    for i, r in enumerate(LOG[:(last[3] - top - 6) // pitch]):
        y = top + i * pitch
        base = y + pitch - 9
        zebra(d, last, y, pitch, i)
        sign, color = SIGN[r["kind"]]
        text_at(d, (last[0] + 16, base), sign, F_S, color)
        text_at(d, (last[0] + 30, base), r["who"]["name"], F_S, CLASSES[r["who"]["cls"]][1])
        if "amount" in r:
            money(img, last[0] + 200, base, r["amount"])
        else:
            icon(img, ITEMS[r["item"]][1], last[0] + 200, y + 3)
            text_at(d, (last[0] + 226, base), "× %d" % r["count"], F_S, GOLD)
        text_at(d, (last[2] - 16, base), when(r["hours"]), F_S, GREY, "rs")

    tabs = kit.box(img, last[2] + GAP, 560 + GAP, round(X0 + 2 * third + GAP), Y1)
    tabs_box(kit, img, d, tabs, 50)

    top5 = kit.box(img, tabs[2] + GAP, 560 + GAP, X1, Y1)
    title(d, top5, "Größte Einzahler", "Gold · 30 Tage")
    givers = sorted(balance(), key=lambda b: -b["paid"])[:9]
    pitch, top = 26, top5[1] + 40
    for i, b in enumerate(givers[:(top5[3] - top - 6) // pitch]):
        y = top + i * pitch
        base = y + pitch - 9
        zebra(d, top5, y, pitch, i)
        text_at(d, (top5[0] + 16, base), b["m"]["name"], F_S, CLASSES[b["m"]["cls"]][1])
        bar(d, top5[0] + 210, y + 7, top5[2] - 110, b["paid"] / givers[0]["paid"], BAR_GOLD, 10)
        money(img, top5[2] - 16, base, b["paid"], color=GOLD, right=True)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    kit = Kit()
    for key, build in (("a", variant_a), ("b", variant_b), ("c", variant_c),
                       ("d", lambda k: variant_a(k, True))):
        img = build(kit)
        path = os.path.join(OUT, "bank-%s.png" % key)
        img.save(path)
        print(path, img.size)


if __name__ == "__main__":
    main()
