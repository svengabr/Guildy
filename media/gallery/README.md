# Gallery images

The CurseForge gallery is built from real in-game screenshots (German client). `build.py` cuts the Guildy window
out of the game world (day or night sky), places it on a neutral background (1920×1080 JPG) and replaces every
character name with a made-up one in the same class colour and the game font; the guild chat is rewritten.
`11-sync.jpg` (English) and `sync-de.jpg` (German) are rendered from `sync.html` with headless Chrome.

```sh
python build.py        # everything
python build.py 05     # only 05-…
python build.py sync   # only the sync explainer
```

Local only, git-ignored (they contain the real names): `src/*.webp` (the screenshots) and `screens.py` (where each
name sits, real → made-up names, the rewritten chat). `PROBE=1 python build.py` prints the text lines it finds.

Also needed: Pillow, numpy, Chrome and the game font, which is not in the repo (Blizzard asset, git-ignored):

- `fonts/FRIZQT__.TTF`: `curl -L -o fonts/FRIZQT__.TTF https://wago.tools/api/casc/615960`

The logo is `../logo.svg`; `sh ../render-logo.sh` renders `../logo.png`.
