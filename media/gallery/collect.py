"""Collects the reference screenshots of one /guildy shots run.

    python media/gallery/collect.py "<WoW folder>/_forever_/Screenshots"

/guildy shots (UI/Shots.lua) walks through every view of Guildy and takes one screenshot per view, two
seconds apart. This script takes the newest run from the game's Screenshots folder (as many pictures
as the list in UI/Shots.lua has, taken in one go) and copies them, unchanged, to media/gallery/src/
under the names of that list. The folder can also come from the environment variable
GUILDY_SCREENSHOTS.

src/ is git-ignored: the pictures show the real character names and the real guild chat.
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(HERE, "src")
GAP = 6  # seconds: pictures of one run are two seconds apart; a longer pause ends the run


def shot_names():
    lua = open(os.path.join(ROOT, "UI", "Shots.lua"), encoding="utf-8").read()
    return re.findall(r'^\s*\{ "(\d\d-[a-z-]+)",', lua, re.M)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GUILDY_SCREENSHOTS")
    if not folder or not os.path.isdir(folder):
        sys.exit("Give the game's Screenshots folder as argument (or in GUILDY_SCREENSHOTS).")
    names = shot_names()
    files = [os.path.join(folder, f) for f in os.listdir(folder) if f.lower().endswith((".jpg", ".png", ".tga"))]
    files.sort(key=os.path.getmtime)
    # the newest run: from the last picture back while the pictures follow each other closely
    run = files[-1:]
    for path in reversed(files[:-1]):
        if os.path.getmtime(run[0]) - os.path.getmtime(path) > GAP:
            break
        run.insert(0, path)
    if len(run) != len(names):
        sys.exit("The newest run has %d pictures, /guildy shots takes %d. Nothing copied.\n"
                 "Run /guildy shots again and take no other screenshot right before or after it."
                 % (len(run), len(names)))
    os.makedirs(SRC, exist_ok=True)
    for name, path in zip(names, run):
        target = os.path.join(SRC, name + os.path.splitext(path)[1].lower())
        shutil.copy2(path, target)
        print("%s  <-  %s" % (os.path.relpath(target, ROOT), os.path.basename(path)))


if __name__ == "__main__":
    main()
