# Gallery images

The gallery pictures are real in-game screenshots (German client), unretouched. Three steps make them:

```sh
python collect.py "<WoW folder>/_forever_/Screenshots"   # the newest /guildy shots run -> src/
python crop.py                                            # the window cut out -> src/crop/
python gallery.py                                         # 1920x1080 JPGs in this folder
```

`build.py`, `screens.py`, `promo.html` and `sync.html` made the pictures up to 1.2.0 (made-up names painted over
the real ones, a rendered overview and a sharing explainer). They are kept for reference and no longer used.

## Reference screenshots

`/guildy shots` (with Guildy open) walks through every tab, Hall of Fame page, the character page and the options
and takes one screenshot per view, in about 40 seconds. During the run a plain dark sheet covers the screen behind
Guildy (`/guildy shots backdrop` switches it on and off for pictures taken by hand). Then:

```sh
python media/gallery/collect.py "<WoW folder>/_forever_/Screenshots"
```

copies that run to `src/` as `01-chat.jpg` … `19-options-professions.jpg` (the list is in `UI/Shots.lua`).

Local only, git-ignored: `src/` (the raw screenshots and the cut-outs) and `screens.py`.

Needed: Pillow and numpy. The old `build.py` also needs Chrome and the game font, which is not in the repo
(Blizzard asset, git-ignored):

- `fonts/FRIZQT__.TTF`: `curl -L -o fonts/FRIZQT__.TTF https://wago.tools/api/casc/615960`

The logo is `../logo.svg`; `sh ../render-logo.sh` renders `../logo.png`.
