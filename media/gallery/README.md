# Gallery images

The gallery pictures are real in-game screenshots (German client), not retouched afterwards: while `/guildy shots`
runs, Guildy shows made-up names, notes and chat by itself. Three steps make them:

```sh
python collect.py "<WoW folder>/_forever_/Screenshots"   # the newest /guildy shots run -> src/
python crop.py                                            # the window cut out -> src/crop/
python gallery.py                                         # 1920x1080 JPGs in this folder
```

## Reference screenshots

`/guildy shots` (with Guildy open) walks through every tab, Hall of Fame page, the character page and the options
and takes one screenshot per view, in about 40 seconds. During the run a plain dark sheet covers the screen behind
Guildy, and character names, guild and community names, notes, the message of the day, the guild information and
the chat are replaced by made-up ones (`Core/Anon.lua`); the PvP statistics are sample values, everything else
is the guild's real data. For pictures taken by hand, `/guildy shots backdrop` and
`/guildy shots anon` switch the two on and off. Then:

```sh
python media/gallery/collect.py "<WoW folder>/_forever_/Screenshots"
```

copies that run to `src/` as `01-chat.jpg` … `19-options-professions.jpg` (the list is in `UI/Shots.lua`).

## Pictures in every language

`/guildy shots all` is the check that the translations fit: it takes the same views in every language Guildy
has, with the window at its smallest size (1130 x 560), where long texts run out of room first. Guildy's
language only changes with a reload of the interface, so the run sets a language, reloads, and waits until you
press J (only the game itself can open the guild window); then it takes the 19 pictures and goes on to the next
language. Six languages take about five minutes. At the end, and also when the run is stopped
(`/guildy shots stop`) or cut off, language and window size are what they were before. Then:

```sh
python media/e2e/collect.py "<WoW folder>/_forever_/Screenshots"
```

cuts the window out of every picture and files them as `media/e2e/<language>/01-chat.png` … (git-ignored).
What the game itself supplies (class and zone names, Blizzard's dialogs) and the made-up names, notes and chat
stay as they are in every language; the check is about Guildy's own texts.

Local only, git-ignored: `src/` (the raw screenshots and the cut-outs). Needed: Pillow and numpy.

The logo is `../logo.svg`; `sh ../render-logo.sh` renders `../logo.png`.
