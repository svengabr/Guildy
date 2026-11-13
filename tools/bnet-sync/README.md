# bnet-sync

Fills Guildy's SavedVariables with the guild members' data from the Battle.net profile API
(WoW Forever, `profile-forever-eu`). Run it by hand on your own PC with the game closed. Guildy reads
the file at the next start. It is a personal tool and is not part of the addon package (`.pkgmeta`
ignores `tools/`).

## Running it

1. Copy `sync.example.cmd` to `sync.cmd`. Git ignores the copy.
2. In `sync.cmd`, set `ENV_FILE` to a file that holds `BATTLENET_CLIENT_ID` and
   `BATTLENET_CLIENT_SECRET`. Raidy's `.env.local` works. Also set `GUILDY_SV` to the account's
   `SavedVariables\Guildy.lua`.
3. Close WoW and double-click `sync.cmd`. Pass `--dry-run` to write the result to
   `%TEMP%\Guildy.bnet-dry-run.lua` instead of the game file.

`--out <file>` writes the result to that file and leaves the game file alone. This works while WoW
is running, but the result is based on the file as it was before the session: copying it over the
game file after logging out would lose what Guildy saved in that session. Run the script again
instead.

Without `--out`, the script stops if WoW is running, because the game overwrites the file when it exits. Before
writing, it saves a backup next to the file as `Guildy.lua.bnet-<time>.bak` and keeps the last 7.

## What it writes

The script reads every guild in GuildyDB. For each one it fetches the roster from the API: members
at level 10 or above are added, and lower levels are skipped because the API has no profile for
them. Your own characters (`ownChars`) are skipped. Each character costs 4 requests: profile,
`/achievements/statistics`, `/equipment` and `/professions`.

| Guildy | From the API |
|---|---|
| `stats.v`: Blizzard statistics (kills, deaths, quests, dungeon end bosses, reputation counts 931/1466/529/378/377, …) | `/achievements/statistics` |
| `stats.v`: equipment (item level, quality counts, quality per slot, the `Stats.GEAR` IDs) | `/equipment`, computed like `Stats.ReadGear` |
| `profs[skillLine]`: rank and max | `/professions` |

Records look like data that Guildy itself read in the game. Statistics carry `src = "seen"`,
professions carry `src = "relay"`, and the timestamp is the character's last login. Data read in the
game after that login keeps winning, and Guildy shares everything with the guild as usual.

| `profs[skillLine].recipes`: the recipe book as spell IDs | `/professions` `known_recipes`, through the name bridge |
| `profs[skillLine].spec`: the specialization (`src = "api"`) | `/professions` `specialization` |

**Recipe books and specializations need the name bridge.** The API numbers recipes differently from
the game; the name is what both share. Guildy saves the names of every recipe it has seen, and of the
specializations, in the client's language (`GuildyDB.recipeNames`). It does so only once this script
has run (it sets `settings.recipeNames`), so the first run writes ranks, and the run after the next
login writes books too.

The profile API names recipes in English whatever locale is asked (found 2026-11-13: not one German
book matched). Its static recipe entries (`/data/wow/recipe/{id}`) do honor the locale, so the script
looks up each recipe's name in the client's language there, once: the names are kept in
`out/recipe-names-<locale>.json` (git ignores `out/`) and only new recipes are asked for. Checked on
2026-11-13: "Kräutergebackenes Ei" and "Magentafarbener Farbstoff" came back exactly as the game names
them, and one run took the guild from 66 books to 199. At the end the script says how many books it
could translate.

A book is written whole or not at all: if one name has no match, that profession's list stays as it
was. A book read in the game after the member's last login is never replaced. Gathering professions
get no list. Specializations follow the game's rules (`Core/Specs.lua`): the API replaces one
inferred from a book, but not one the game itself reported later; "no specialization" from the API
revokes one.

The API has gaps:

- It returns only part of the statistics, and none of the gold statistics. Stored values that the
  API leaves out are kept, and API values replace only the ones it returns.
- A recipe whose name Guildy has never seen cannot be translated; its whole book waits until Guildy
  has seen that recipe once, in any member's book.
- A member whose first record comes from the API has no gold values until Guildy reads them in the
  game.

## Tests

```bash
node --test "tools/bnet-sync/*.test.mjs"
```

`GUILDY_SV=<path to Guildy.lua>` adds a round trip of the real file.
