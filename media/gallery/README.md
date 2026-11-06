# Gallery images

The CurseForge gallery is built from real in-game screenshots (`src/*.webp`, German client). `build.py` cuts the
Guildy window out of the game world, places it on a neutral background (1920×1080 JPG) and fills the Hall of
Fame screenshots with made-up members (names, kills, dungeon clears) so the test guild doesn't look empty.

```sh
python build.py        # all images
python build.py 05     # only 05-hall-of-fame-ranking.jpg
```

Needs Pillow and numpy, plus the game font, which is not in the repo (Blizzard asset, git-ignored):

- `fonts/FRIZQT__.TTF`: `curl -L -o fonts/FRIZQT__.TTF https://wago.tools/api/casc/615960`

New screenshots: take them at the same UI scale and window size, else the pixel positions of the Hall of Fame
edits in `build.py` need adjusting. The logo is `../logo.svg`; `sh ../render-logo.sh` renders `../logo.png`.
