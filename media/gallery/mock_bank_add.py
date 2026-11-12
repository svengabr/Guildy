"""Three ways to add a box to the Bank tab in edit mode, with previews instead of a menu of names. Drawn
like mock_bank.py: into the real reference screenshot, with the game's own pixels and font.

    python media/gallery/mock_bank_add.py        ->  mock/bank-add-a.png, -b.png, -c.png

A: a tray at the side, boxes are dragged from it onto the tab.  B: a gallery, pick one and see where it
lands.  C: the free places of the tab carry a "+", a click offers what fits there.
All names and numbers are made up. Needs Pillow; src/ and fonts/ are local only.
"""
import os

from PIL import Image, ImageDraw

from mock_bank import variant_a, variant_b, variant_c
from mock_endgame import F_N, F_S, GOLD, GREEN, GREY, OUT, WHITE, X0, X1, Y0, Y1, Kit, text_at

SIDE = X0 + 340
# where each box stands in the mocks it is taken from: (picture, box)
PIECES = {
    "total": ("d", (X0, 111, SIDE, 349)), "tabs": ("d", (X0, 365, SIDE, 615)), "access": ("d", (X0, 631, SIDE, Y1)),
    "chart": ("d", (SIDE + 16, 111, X1, 355)), "ledger": ("d", (SIDE + 16, 371, X1, Y1)),
    "balance": ("b", (X0, 111, 1128, Y1)), "detail": ("b", (1144, 111, X1, 560)), "largest": ("b", (1144, 576, X1, Y1)),
    "tiles": ("c", (X0, 111, X1, 211)), "givers": ("c", (1151, 576, X1, Y1)),
}
NAMES = {"total": "Gildenbank", "tabs": "Fächer", "access": "Dein Zugriff", "chart": "Gold in der Bank",
         "ledger": "Kassenbuch", "balance": "Wer gibt, wer nimmt", "detail": "Bewegungen eines Mitglieds",
         "largest": "Größte Entnahmen", "tiles": "Kennzahlen", "givers": "Größte Einzahler"}
ABOUT = {"tiles": "Gold, Ein- und Auszahlungen, Reparaturen und belegte Plätze in einer Zeile.",
         "balance": "Jedes Mitglied mit Saldo, Gold und Gegenständen. Klick sortiert.",
         "detail": "Was ein Mitglied eingelegt und entnommen hat.",
         "givers": "Wer im Zeitraum am meisten Gold eingezahlt hat.",
         "largest": "Die größten Goldbeträge und Stapel, die entnommen wurden.",
         "access": "Was du heute noch an Gold und aus jedem Fach nehmen darfst."}
SLOT = (X0, 631, SIDE, Y1)          # the free place the examples add to
GREEN_LINE, RED_LINE = (64, 224, 64), (255, 90, 74)


class Stage:
    def __init__(self):
        self.kit = Kit()
        self.pics = {"d": variant_a(self.kit, True), "b": variant_b(self.kit), "c": variant_c(self.kit)}
        self.bare = self.kit.base()

    def piece(self, key):
        pic, box = PIECES[key]
        return self.pics[pic].crop((box[0] - 4, box[1] - 4, box[2] + 4, box[3] + 4))

    def thumb(self, key, w, h):
        """The box as a miniature that fits into w x h."""
        src = self.piece(key)
        scale = min(w / src.width, h / src.height)
        return src.resize((max(1, round(src.width * scale)), max(1, round(src.height * scale))), Image.LANCZOS)

    def board(self, free=("access",)):
        """The tab in edit mode: the boxes covered by their handles, the named ones taken off."""
        img = self.pics["d"].copy()
        for key in free:
            box = PIECES[key][1]
            area = (box[0] - 5, box[1] - 5, box[2] + 5, box[3] + 5)
            img.paste(self.bare.crop(area), area[:2])
        img.paste(self.bare.crop((1150, 68, 1694, 106)), (1150, 68))
        x = 1250
        for label, on in (("Vorlage", False), ("Kasten hinzufügen", True), ("Fertig", False)):
            x = self.kit.button(img, x, label, on)
        d = ImageDraw.Draw(img)
        for key in ("total", "tabs", "access", "chart", "ledger"):
            if key in free:
                continue
            box = PIECES[key][1]
            shade(img, box, 0.7)
            d = ImageDraw.Draw(img)
            cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
            text_at(d, (cx, cy + 2), NAMES[key], F_N, GOLD, "ms")
            text_at(d, (cx, cy + 22), "ziehen zum Verschieben", F_S, GREY, "ms")
            text_at(d, (box[2] - 16, box[1] + 22), "x", F_N, WHITE, "ms")
            for i in range(3):
                d.line((box[2] - 8 - i * 5, box[3] - 5, box[2] - 5, box[3] - 8 - i * 5), fill=(190, 160, 90))
        return img


def shade(img, box, alpha, color=(0, 0, 0)):
    area = img.crop(box)
    img.paste(Image.blend(area, Image.new("RGB", area.size, color), alpha), box[:2])


def ghost(img, picture, box, alpha=0.55):
    """A picture stretched into box, see-through."""
    area = img.crop(box)
    fitted = picture.resize(area.size, Image.LANCZOS)
    img.paste(Image.blend(area, fitted, alpha), box[:2])


def outline(d, box, color, width=2, dash=None):
    x0, y0, x1, y1 = box
    if not dash:
        d.rectangle((x0, y0, x1 - 1, y1 - 1), outline=color, width=width)
        return
    for a, b, fixed, flat in ((x0, x1, y0, True), (x0, x1, y1 - width, True), (y0, y1, x0, False), (y0, y1, x1 - width, False)):
        pos = a
        while pos < b:
            end = min(b, pos + dash)
            if flat:
                d.rectangle((pos, fixed, end - 1, fixed + width - 1), fill=color)
            else:
                d.rectangle((fixed, pos, fixed + width - 1, end - 1), fill=color)
            pos += dash * 2


def cursor(d, x, y):
    d.polygon([(x, y), (x, y + 19), (x + 5, y + 14), (x + 9, y + 22), (x + 12, y + 20), (x + 8, y + 13), (x + 14, y + 13)],
              fill=(255, 255, 255), outline=(0, 0, 0))


def button_at(kit, img, x, y, text, selected):
    """kit.button anywhere, not only in the toolbar; returns the x after it."""
    strip = Image.new("RGB", (400, 40))
    strip.paste(img.crop((x, y - 1, x + 400, y + 39)), (0, 0))
    probe = kit.bare_strip.copy()
    end = kit.button(probe, 0, text, selected)
    img.paste(probe.crop((0, 71, end - 8, 103)), (x, y))
    return x + end


def wrap(text, font, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if font.getlength(trial) > width and line:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


# --- A: a tray at the side ------------------------------------------------------------------------------

def variant_tray(stage):
    img = stage.board()
    kit = stage.kit
    tray = (X1 - 318, Y0, X1, Y1)
    kit.box(img, *tray)
    d = ImageDraw.Draw(img)
    text_at(d, (tray[0] + 14, tray[1] + 24), "Kästen", F_N, GOLD)
    text_at(d, (tray[2] - 14, tray[1] + 24), "auf den Tab ziehen", F_S, GREY, "rs")
    cards = ["givers", "tiles", "balance", "largest", "access"]
    top = tray[1] + 40
    pitch = (tray[3] - top - 8) / len(cards)
    for i, key in enumerate(cards):
        y0 = round(top + i * pitch)
        card = (tray[0] + 12, y0, tray[2] - 12, round(y0 + pitch) - 8)
        shade(img, card, 0.35, (60, 52, 34) if i == 0 else (0, 0, 0))
        d = ImageDraw.Draw(img)
        outline(d, card, GOLD if i == 0 else (74, 62, 36), 2 if i == 0 else 1)
        text_at(d, (card[0] + 10, card[1] + 20), NAMES[key], F_S, GOLD if i == 0 else WHITE)
        mini = stage.thumb(key, card[2] - card[0] - 20, card[3] - card[1] - 36)
        img.paste(mini, ((card[0] + card[2] - mini.width) // 2, card[1] + 28))
        d = ImageDraw.Draw(img)
    # the first card on its way to the free place
    ghost(img, stage.piece("givers"), SLOT, 0.6)
    d = ImageDraw.Draw(img)
    outline(d, SLOT, GREEN_LINE, 3)
    text_at(d, ((SLOT[0] + SLOT[2]) // 2, SLOT[1] - 8), "loslassen legt den Kasten hier ab", F_S, GREEN, "ms")
    cursor(d, SLOT[2] - 70, SLOT[1] + 86)
    return img


# --- B: a gallery ---------------------------------------------------------------------------------------

def variant_gallery(stage):
    img = stage.board()
    kit = stage.kit
    shade(img, (32, 108, 1696, 872), 0.45)
    d = ImageDraw.Draw(img)
    outline(d, SLOT, GREEN_LINE, 3)
    text_at(d, ((SLOT[0] + SLOT[2]) // 2, (SLOT[1] + SLOT[3]) // 2 + 5), "landet hier", F_N, GREEN, "ms")
    modal = (430, 140, 1640, 836)
    kit.box(img, *modal)
    d = ImageDraw.Draw(img)
    text_at(d, (modal[0] + 16, modal[1] + 26), "Kasten hinzufügen", F_N, GOLD)
    text_at(d, (modal[0] + 190, modal[1] + 26), "Klick wählt · die Vorschau zeigt deine eigene Bank", F_S, GREY)
    text_at(d, (modal[2] - 18, modal[1] + 26), "x", F_N, WHITE, "ms")
    cards = ["givers", "tiles", "balance", "detail", "largest", "access"]
    cw, ch = (modal[2] - modal[0] - 16 * 4) // 3, 284
    for i, key in enumerate(cards):
        x0 = modal[0] + 16 + (i % 3) * (cw + 16)
        y0 = modal[1] + 44 + (i // 3) * (ch + 14)
        card = (x0, y0, x0 + cw, y0 + ch)
        chosen = i == 0
        shade(img, card, 0.4, (60, 52, 34) if chosen else (0, 0, 0))
        d = ImageDraw.Draw(img)
        outline(d, card, GOLD if chosen else (74, 62, 36), 2 if chosen else 1)
        mini = stage.thumb(key, cw - 24, 168)
        img.paste(mini, ((card[0] + card[2] - mini.width) // 2, card[1] + 12 + (168 - mini.height) // 2))
        d = ImageDraw.Draw(img)
        text_at(d, (card[0] + 14, card[1] + 208), NAMES[key], F_N, GOLD if chosen else WHITE)
        for n, line in enumerate(wrap(ABOUT[key], F_S, cw - 28)[:2]):
            text_at(d, (card[0] + 14, card[1] + 230 + n * 18), line, F_S, GREY)
        if chosen:
            text_at(d, (card[2] - 14, card[1] + 208), "passt unten links", F_S, GREEN, "rs")
    x = button_at(kit, img, modal[2] - 300, modal[3] - 46, "Hinzufügen", True)
    button_at(kit, img, x, modal[3] - 46, "Abbrechen", False)
    d = ImageDraw.Draw(img)
    cursor(d, modal[0] + 16 + cw - 60, modal[1] + 44 + 150)
    return img


# --- C: the free places carry a plus ----------------------------------------------------------------------

def variant_slots(stage):
    img = stage.board(free=("access", "tabs"))
    kit = stage.kit
    d = ImageDraw.Draw(img)
    upper = PIECES["tabs"][1]
    outline(d, upper, (150, 124, 62), 2, 10)
    cx, cy = (upper[0] + upper[2]) // 2, (upper[1] + upper[3]) // 2
    d.rectangle((cx - 16, cy - 14, cx + 16, cy - 10), fill=GOLD)
    d.rectangle((cx - 2, cy - 28, cx + 2, cy + 4), fill=GOLD)
    text_at(d, (cx, cy + 34), "Kasten hinzufügen", F_S, GREY, "ms")
    # the lower place: the box under the mouse shows right there
    ghost(img, stage.piece("givers"), SLOT, 0.62)
    d = ImageDraw.Draw(img)
    outline(d, SLOT, GREEN_LINE, 3)
    pop = (SIDE + 14, 520, SIDE + 14 + 420, Y1 + 2)
    kit.box(img, *pop)
    d = ImageDraw.Draw(img)
    text_at(d, (pop[0] + 14, pop[1] + 24), "Passt an diesen Platz", F_N, GOLD)
    rows = ["givers", "largest", "access", "detail"]
    pitch = (pop[3] - pop[1] - 44) / len(rows)
    for i, key in enumerate(rows):
        y0 = round(pop[1] + 38 + i * pitch)
        row = (pop[0] + 10, y0, pop[2] - 10, round(y0 + pitch) - 6)
        if i == 0:
            shade(img, row, 0.45, (120, 100, 50))
            d = ImageDraw.Draw(img)
            outline(d, row, GOLD, 1)
        mini = stage.thumb(key, 128, row[3] - row[1] - 8)
        img.paste(mini, (row[0] + 6, row[1] + (row[3] - row[1] - mini.height) // 2))
        d = ImageDraw.Draw(img)
        text_at(d, (row[0] + 146, row[1] + 24), NAMES[key], F_S, GOLD if i == 0 else WHITE)
        for n, line in enumerate(wrap(ABOUT[key], F_S, row[2] - row[0] - 156)[:2]):
            text_at(d, (row[0] + 146, row[1] + 42 + n * 16), line, F_S, GREY)
    cursor(d, pop[2] - 46, pop[1] + 74)
    text_at(d, (pop[2] - 14, pop[1] + 24), "Vorschau links · Klick legt ihn ab", F_S, GREEN, "rs")
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    stage = Stage()
    stage.kit.bare_strip = stage.bare.crop((700, 0, 1100, 120)).copy()
    for key, build in (("a", variant_tray), ("b", variant_gallery), ("c", variant_slots)):
        img = build(stage)
        path = os.path.join(OUT, "bank-add-%s.png" % key)
        img.save(path)
        print(path, img.size)


if __name__ == "__main__":
    main()
