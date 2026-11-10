"""Collects the pictures of one /guildy shots all run, by language.

    python media/e2e/collect.py "<WoW folder>/_forever_/Screenshots"

/guildy shots all (UI/Shots.lua) takes every view of Guildy in every language, at the smallest window
size: the end-to-end check of the translations. This script takes the newest such run from the game's
Screenshots folder (one group of pictures per language, as many pictures per group as the list in
UI/Shots.lua has), cuts Guildy's window out of each picture and writes it to
media/e2e/<language>/<name>.png. The folder can also come from the environment variable
GUILDY_SCREENSHOTS.

The language folders are git-ignored. Needs Pillow and numpy.
"""
import os
import re
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "media", "gallery"))
from crop import window_box  # noqa: E402  (the window in front of the run's plain backdrop)

GAP = 6        # seconds: the pictures of one language are two seconds apart
RUN_GAP = 300  # seconds: between two languages lie a reload and the wait for J; longer ends the run


def shot_names():
    lua = open(os.path.join(ROOT, "UI", "Shots.lua"), encoding="utf-8").read()
    return re.findall(r'^\s*\{ "(\d\d-[a-z-]+)",', lua, re.M)


def languages():
    lua = open(os.path.join(ROOT, "Locales", "Locales.lua"), encoding="utf-8").read()
    order = re.search(r"Locale\.ORDER = \{([^}]*)\}", lua).group(1)
    codes = re.findall(r'"(\w+)"', order)
    return [code for code in codes if os.path.exists(os.path.join(ROOT, "Locales", code + ".lua"))]


def newest_run(files):
    """The groups of the newest run, oldest group first; files are sorted by time."""
    groups = [[files[-1]]] if files else []
    for path in reversed(files[:-1]):
        pause = os.path.getmtime(groups[0][0]) - os.path.getmtime(path)
        if pause <= GAP:
            groups[0].insert(0, path)
        elif pause <= RUN_GAP:
            groups.insert(0, [path])
        else:
            break
    return groups


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GUILDY_SCREENSHOTS")
    if not folder or not os.path.isdir(folder):
        sys.exit("Give the game's Screenshots folder as argument (or in GUILDY_SCREENSHOTS).")
    names, codes = shot_names(), languages()
    files = [os.path.join(folder, f) for f in os.listdir(folder) if f.lower().endswith((".jpg", ".png", ".tga"))]
    files.sort(key=os.path.getmtime)
    groups = newest_run(files)
    if [len(group) for group in groups] != [len(names)] * len(codes):
        sys.exit("The newest run has groups of %s pictures; /guildy shots all takes %d groups of %d. Nothing written.\n"
                 "Run /guildy shots all again and take no other screenshot during it."
                 % ([len(group) for group in groups] or "no", len(codes), len(names)))
    uncut = 0
    for code, group in zip(codes, groups):
        out = os.path.join(HERE, code)
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out)
        for name, path in zip(names, group):
            img = Image.open(path)
            try:
                img = img.crop(window_box(img))
            except (IndexError, ValueError):  # no window found in front of the backdrop: the whole picture
                uncut += 1
            img.save(os.path.join(out, name + ".png"))
        print("%s  %d pictures" % (os.path.relpath(out, ROOT), len(group)))
    if uncut:
        print("%d pictures kept whole: no window found in them." % uncut)


if __name__ == "__main__":
    main()
