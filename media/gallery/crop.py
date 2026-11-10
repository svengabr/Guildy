"""Cuts Guildy's window out of the reference screenshots (src/NN-*.jpg, taken by /guildy shots in front
of its plain backdrop) and writes it to src/crop/NN-*.png: the window with its side tabs and bottom tabs,
and the options window next to it where one is open.

    python media/gallery/crop.py

Needs Pillow and numpy. src/ is git-ignored (real character names and guild chat).
"""
import glob
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(SRC, "crop")
PAD = 20      # backdrop left around the window
TABS = 34     # the bottom tabs hang below the window's border
JOIN = 60     # the options window stands this close to Guildy's; anything further away is not part of it


def runs(values, threshold, gap):
    """(start, stop) of the stretches where values > threshold, joined over holes up to `gap`."""
    idx = np.where(values > threshold)[0]
    out = []
    if len(idx) == 0:
        return out
    start = prev = idx[0]
    for i in idx[1:]:
        if i - prev > gap:
            out.append((int(start), int(prev)))
            start = i
        prev = i
    out.append((int(start), int(prev)))
    return out


def window_box(img):
    a = np.asarray(img.convert("RGB")).astype(int)
    backdrop = a[-3, 3]  # bottom left corner: never covered by a window
    mask = np.abs(a - backdrop).sum(axis=2) > 30
    # the window's left border is not backdrop over its whole height
    cols = runs(mask.mean(axis=0), 0.2, 14)
    left = cols[0][0]
    y0, y1 = runs(mask[:, left:left + 24].mean(axis=1), 0.3, 40)[0]
    xs = runs(mask[y0:y1].mean(axis=0), 0.05, 14)
    x0, x1 = xs[0]
    for start, stop in xs[1:]:
        if start - x1 <= JOIN:
            x1 = stop
    # the options window may be taller than Guildy's at its smallest size
    for start, stop in runs(mask[:, x0:x1].mean(axis=1), 0.05, 40):
        if start <= y1 and stop >= y0:
            y0, y1 = min(y0, start), max(y1, stop - TABS)
    h, w = mask.shape
    return (max(0, x0 - PAD), max(0, y0 - PAD), min(w, x1 + PAD), min(h, y1 + TABS + PAD))


def main():
    os.makedirs(OUT, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(SRC, "[0-9][0-9]-*.jpg"))):
        img = Image.open(path)
        box = window_box(img)
        name = os.path.splitext(os.path.basename(path))[0] + ".png"
        img.crop(box).save(os.path.join(OUT, name))
        print("%s  %d x %d" % (name, box[2] - box[0], box[3] - box[1]))


if __name__ == "__main__":
    main()
