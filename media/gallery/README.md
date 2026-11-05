# Gallery images

Source for the CurseForge gallery: one HTML page per image (1920×1080), shared look in `style.css` (taken over
from KeepOrSell, plus the Guildy window styles at the end). Names, guild and chat are made up.

Render all pages to JPG (or a single one with `sh render.sh 02-census.html`):

```sh
sh render.sh
```

The logo is `../logo.svg`; `sh ../render-logo.sh` renders `../logo.png`.

Not in the repo (Blizzard assets, git-ignored), fetch them before rendering:

- `fonts/FRIZQT__.TTF`: `curl -L -o fonts/FRIZQT__.TTF https://wago.tools/api/casc/615960`
- `icons/<name>.jpg`: `curl -o icons/<name>.jpg https://wow.zamimg.com/images/wow/icons/large/<name>.jpg`
  for every `icons/…` referenced in the pages
