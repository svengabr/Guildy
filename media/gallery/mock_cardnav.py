"""Mock-ups of previous/next buttons on the character page (community wish: browse online members without
going back to the list), drawn into the gallery picture 14-character.jpg: frame, boxes and the Back button
are the game's own pixels, the new buttons are cut from Blizzard's red and grey buttons in that picture.

    python media/gallery/mock_cardnav.py   # mock/cardnav-a.png (arrows + counter, tooltip),
                                           # mock/cardnav-b.png (neighbour names on the buttons),
                                           # mock/cardnav-c.png (offline member opened: both disabled)

Order is the members list as it is sorted and filtered right now, offline members skipped. Names are made up.
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mock")
FONT = os.path.join(HERE, "fonts", "FRIZQT__.TTF")
BASE = Image.open(os.path.join(HERE, "14-character.jpg")).convert("RGB")

GOLD, WHITE, GREY, MUTED = (255, 209, 0), (255, 255, 255), (128, 128, 128), (154, 143, 120)
GREEN = (64, 224, 64)
F_S = ImageFont.truetype(FONT, 14.5)
F_N = ImageFont.truetype(FONT, 16.3)

# Blizzard's buttons in the picture: "Zurück" (red, enabled) and "Entfernen ..." (grey, disabled)
RED = (197, 177, 317, 204)
DIS = (372, 858, 477, 885)
Y, H = 177, 27


def skin(src, w):
  """A button of width w from a source button: both caps kept, a text-free stretch of the middle."""
  x0, y0, x1, y1 = src
  cap = 9
  left = BASE.crop((x0, y0, x0 + cap, y1))
  right = BASE.crop((x1 - cap, y0, x1, y1))
  mid = BASE.crop((x0 + cap, y0, x0 + cap + 3, y1)).resize((w - 2 * cap, y1 - y0))
  out = Image.new("RGB", (w, y1 - y0))
  out.paste(left, (0, 0))
  out.paste(mid, (cap, 0))
  out.paste(right, (w - cap, 0))
  return out


def chevron(d, cx, cy, left, color):
  s = -1 if left else 1
  d.line([(cx - 3 * s, cy - 6), (cx + 3 * s, cy), (cx - 3 * s, cy + 6)], fill=color, width=3, joint="curve")


def button(im, x, w, label, enabled=True, font=F_S, dy=0, arrow=None):
  """arrow: None, "left" (chevron before the label) or "right" (after); a label of "" is an arrow button."""
  im.paste(skin(RED if enabled else DIS, w), (x, Y))
  d = ImageDraw.Draw(im)
  color = GOLD if enabled else GREY
  cy = Y + H / 2
  if not label:
    chevron(d, x + w / 2, cy, arrow == "left", color)
    return x + w
  tw = d.textlength(label, font=font)
  gap = 14 if arrow else 0
  tx = x + (w - tw - gap) / 2 + (gap if arrow == "left" else 0)
  d.text((tx, cy + dy), label, font=font, fill=color, anchor="lm")
  if arrow == "left":
    chevron(d, tx - 10, cy, True, color)
  elif arrow == "right":
    chevron(d, tx + tw + 10, cy, False, color)
  return x + w


def tooltip(im, x, y, lines):
  d = ImageDraw.Draw(im, "RGBA")
  pad, gap = 10, 5
  w = max(d.textlength(t, font=f) for t, f, _ in lines) + 2 * pad
  h = sum(f.size for _, f, _ in lines) + gap * (len(lines) - 1) + 2 * pad
  d.rounded_rectangle((x, y, x + w, y + h), 5, fill=(6, 6, 12, 238), outline=(150, 150, 160, 255), width=2)
  cy = y + pad
  for t, f, c in lines:
    d.text((x + pad, cy), t, font=f, fill=c)
    cy += f.size + gap


def offline(im):
  """The hero card says offline: 'online' (green) becomes grey 'offline'."""
  d = ImageDraw.Draw(im)
  d.rectangle((210, 672, 410, 692), fill=im.getpixel((150, 700)))
  rest = "offline, vor 3 Tagen"
  parts = [("Offizier", GOLD), (" · Tanaris · ", MUTED), (rest, GREY)]
  x = 306 - sum(d.textlength(t, font=F_S) for t, _ in parts) / 2
  for t, c in parts:
    d.text((x, 682), t, font=F_S, fill=c, anchor="lm")
    x += d.textlength(t, font=F_S)


def mock_a():
  im = BASE.copy()
  d = ImageDraw.Draw(im)
  x = button(im, 329, 34, "", arrow="left") + 4
  x = button(im, x, 34, "", arrow="right") + 12
  d.text((x, Y + H / 2), "4 von 23 online", font=F_S, fill=MUTED, anchor="lm")
  # hover on "›"
  tooltip(im, 367, 210, [("Nächstes Mitglied", F_N, WHITE),
                         ("Kalle Kupferkessel", F_S, (63, 199, 235)),
                         ("Stufe 34 Magier · Brennende Steppe", F_S, WHITE),
                         ("Reihenfolge wie in der Mitgliederliste", F_S, GREEN)])
  im.save(os.path.join(OUT, "cardnav-a.png"))


def mock_b():
  im = BASE.copy()
  d = ImageDraw.Draw(im)
  x = button(im, 329, 180, "Bruno Brandt", arrow="left") + 4
  x = button(im, x, 180, "Kalle Kupferkessel", arrow="right") + 12
  d.text((x, Y + H / 2), "4 von 23 online", font=F_S, fill=MUTED, anchor="lm")
  im.save(os.path.join(OUT, "cardnav-b.png"))


def mock_c():
  im = BASE.copy()
  d = ImageDraw.Draw(im)
  x = button(im, 329, 34, "", enabled=False, arrow="left") + 4
  x = button(im, x, 34, "", enabled=False, arrow="right") + 12
  d.text((x, Y + H / 2), "Offline: Blättern nur zwischen Online-Mitgliedern", font=F_S, fill=GREY, anchor="lm")
  offline(im)
  im.save(os.path.join(OUT, "cardnav-c.png"))


if __name__ == "__main__":
  os.makedirs(OUT, exist_ok=True)
  mock_a()
  mock_b()
  mock_c()
