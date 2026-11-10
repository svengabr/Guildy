# Languages and Screenshot Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guildy speaks French, Spanish, Russian and Brazilian Portuguese besides English and German, has a language choice in its options, and `/guildy shots all` photographs every view in every language at the smallest window size.

**Architecture:** One file per language fills `ns.LocaleTables`; `Locales/Locales.lua` becomes the resolver and makes `ns.L` a proxy that reads from the table of the language in force, so the language can be set at `ADDON_LOADED` when the saved setting is known. The screenshot run keeps its state in `GuildyDB.shotRun` across interface reloads; its decisions live in a pure module with unit tests, the game side in `UI/Shots.lua`.

**Tech Stack:** Lua 5.1 (WoW addon, Interface 16001), tests with `luajit tests/run.lua`, `luacheck`, Python 3 with Pillow and numpy for the picture scripts.

**Spec:** `docs/superpowers/specs/2026-11-10-languages-design.md`

## Global Constraints

- Languages and their order, everywhere: `enUS`, `deDE`, `frFR`, `esES`, `ruRU`, `ptBR`.
- `esMX` uses the `esES` table. `enGB` and every locale without a table use `enUS`.
- A key missing in a language falls back to English; a key missing everywhere reads as the key name (as today).
- No text is read from `ns.L` while the addon's files load.
- Placeholders appear in every language in the same order as in English.
- Terms follow the game's own wording in that language. No plural engine: Russian texts with a count use a wording that is right for every number (`"Участников: %d"`).
- The game's language is never changed. What comes from the game or from players stays as it is.
- After a screenshot run, finished, stopped or cut off, language and window size are what they were before. No reload loop.
- Code comments, commit messages and docs in English, in the style of the files around them. Commits: `feat:` / `test:` / `docs:` subject lines, no attribution lines.
- Before every commit: `luajit tests/run.lua` ends with `0 failed`, and `luacheck .` is clean. New WoW globals go into `.luacheckrc` and get a stub in `tests/wow.lua`.
- Work on branch `feat/languages`, cut from `main`. No release in this plan.

## Review Focus

1. A saved `language` that is no known code (hand-edited or from a later version): Guildy behaves as on automatic. Pinned in Task 1.
2. A run cut off by a crash or logout: at the next login Guildy restores language and size and does not reload again. Pinned in Task 9.
3. `/guildy shots all` when Guildy cannot be opened or the roster never arrives (no guild): the run ends, restores and says why. Pinned in Task 9.
4. A translation that swaps or drops a placeholder, or leaves a text empty: the tests name language and key. Pinned in Task 1, bites in Tasks 4 to 7.
5. A player whose client is French picks German and later "Automatic": back to French after the reload, and profession names from the game are still recognised under every choice. Pinned in Tasks 2 and 3.

---

### Task 1: Locale files and resolver

No change in behaviour: English and German as today, structure ready for more languages.

**Files:**
- Create: `Locales/enUS.lua`, `Locales/deDE.lua` (the two tables moved out of `Locales/Locales.lua`, unchanged)
- Modify: `Locales/Locales.lua` (resolver only), `Guildy.toc` (language files before `Locales\Locales.lua`), `tests/test_locales.lua`

**Interfaces:**
- Produces, per language file: `ns.LocaleTables = ns.LocaleTables or {}` then `ns.LocaleTables.<code> = { KEY = "text", ... }`.
- Produces in `Locales/Locales.lua`:
  - `ns.Locale.ORDER = { "enUS", "deDE", "frFR", "esES", "ruRU", "ptBR" }`
  - `ns.Locale.NAMES = { enUS = "English", deDE = "Deutsch", frFR = "Français", esES = "Español", ruRU = "Русский", ptBR = "Português (Brasil)" }`
  - `ns.Locale.Languages() -> { code, ... }`: the codes of `ORDER` that have a table.
  - `ns.Locale.Resolve(setting, clientLocale) -> code`: `setting` if it has a table; else `clientLocale` if it has a table; `esMX` gives `esES`; else `"enUS"`.
  - `ns.Locale.Apply(code)`: the language `ns.L` reads from now on; `ns.Locale.current` holds the code.
  - `ns.L`: an empty table whose `__index` returns the text of the current language, else English, else the key. At load the file applies `Resolve(nil, GetLocale())` (`"enUS"` without `GetLocale`).

- [ ] **Step 1: Rewrite `tests/test_locales.lua` for any number of languages.** Load every `Locales/*.lua` of `T.tocFiles()` into `ns`. Keep the existing checks that only look at English. Replace the German-only ones and add:

```lua
local EN = ns.LocaleTables.enUS
local function Directives(text)   -- "%d", "%s", "%.1f" ... in order; "%%" is not one
  local list = {}
  for d in text:gsub("%%%%", ""):gmatch("%%[%d%.%-]*%a") do list[#list + 1] = d end
  return list
end

T.it("has every language of the list that has a file, and no other", function()
  for code in pairs(ns.LocaleTables) do
    local listed
    for _, known in ipairs(ns.Locale.ORDER) do listed = listed or known == code end
    T.truthy(listed, code .. " is not in Locale.ORDER")
  end
end)
T.it("has the same keys in every language, none empty", function()
  for _, code in ipairs(ns.Locale.Languages()) do
    local table_ = ns.LocaleTables[code]
    for key in pairs(EN) do T.truthy(table_[key] and table_[key] ~= "", code .. " is missing " .. key) end
    for key in pairs(table_) do T.truthy(EN[key], code .. " has unknown " .. key) end
  end
end)
T.it("keeps the placeholders and their order in every language", function()
  for _, code in ipairs(ns.Locale.Languages()) do
    for key, text in pairs(EN) do T.eq(Directives(ns.LocaleTables[code][key]), Directives(text), code .. " " .. key) end
  end
end)
T.it("resolves the language", function()
  local R = ns.Locale.Resolve
  T.eq(R(nil, "deDE"), "deDE")
  T.eq(R("enUS", "deDE"), "enUS")
  T.eq(R(nil, "enGB"), "enUS")
  T.eq(R(nil, "koKR"), "enUS")
  T.eq(R("xxXX", "deDE"), "deDE")   -- Review Focus 1
  T.eq(R(42, "deDE"), "deDE")
  T.eq(R(nil, nil), "enUS")
end)
T.it("reads from the applied language, English for a gap, the key for an unknown one", function()
  ns.Locale.Apply("deDE")
  T.eq(ns.L.TAB_MEMBERS, "Mitglieder")
  ns.LocaleTables.deDE.TAB_MEMBERS = nil
  T.eq(ns.L.TAB_MEMBERS, "Members")
  T.eq(ns.L.NO_SUCH_KEY, "NO_SUCH_KEY")
  ns.Locale.Apply("enUS")
  T.eq(ns.L.TAB_OVERVIEW, "Overview")
end)
```

  An empty-string English text, if one exists, is exempt from "none empty" by comparing against English.

- [ ] **Step 2: Run `luajit tests/run.lua`.** Expected: FAIL (`ns.Locale` is nil).
- [ ] **Step 3: Move the tables and write the resolver** as in Interfaces. Search the addon for anything that iterates `ns.L` or reads `ns.LocaleTables` directly and adapt it.
- [ ] **Step 4: Run `luajit tests/run.lua` and `luacheck .`.** Expected: `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: one file per language, resolver for the language in force`.

---

### Task 2: The saved language applies; reading the game does not follow it

**Files:**
- Modify: `Core/Init.lua` (`ADDON_LOADED`), `Game/TradeSkill.lua` (`SkillByName`), `Core/Anon.lua` (`Anon.Lines`), `tests/wow.lua`, `tests/smoke.lua`

**Interfaces:**
- Consumes: `ns.Locale.Resolve`, `ns.Locale.Apply`, `ns.Locale.current`, `ns.Locale.Languages`, `ns.LocaleTables`.
- Produces: setting `GuildyDB.settings.language` (a code, or `nil` for automatic; not in `Store.DEFAULTS`). In `ADDON_LOADED`, right after `Store.Init`: `ns.Locale.Apply(ns.Locale.Resolve(GuildyDB.settings.language, GetLocale()))`.
- Produces in `tests/wow.lua`: `opts.afterFile(file, ns)`, called after each TOC file has run.

- [ ] **Step 1: Write the failing tests in `tests/smoke.lua`**, each with a world of its own (`dofile(T.testsDir .. "/wow.lua")(T, opts)`; the stub client is `deDE`):
  - "applies the saved language": `opts.setup` puts `GuildyDB = { settings = { language = "enUS" } }` into `env`; after `Fire("ADDON_LOADED", "Guildy")`: `ns.Locale.current == "enUS"` and `ns.L.TAB_MEMBERS == "Members"`.
  - "falls back to the client for an unknown saved language": `language = "xxXX"` gives `ns.Locale.current == "deDE"`.
  - "reads no text while the files load": in `opts.afterFile`, once `file == "Locales/Locales.lua"`, wrap the `__index` of `getmetatable(ns.L)` so every key read is noted; after the world is built (before any event) the list of noted keys is empty. The failure message lists the keys.
  - "knows the game's profession names under every Guildy language" (Review Focus 5): with `language = "enUS"` on the `deDE` stub client, for every language `code` of `ns.Locale.Languages()` and every `key` of `ns.Professions.SKILL_LINES`: `ns.TradeSkill.SkillByName(ns.LocaleTables[code]["PROF_" .. key])` is the skill line of that key.
  - "anonymous chat follows Guildy's language": with `language = "enUS"`, `ns.Anon.Enable(true)`, the text of `ns.Anon.Lines({ { sender = "A", text = "x" } })[1]` is a line of the English pool, not of the German one.
- [ ] **Step 2: Run the tests.** Expected: FAIL on `opts.afterFile` / `ns.Locale.current`.
- [ ] **Step 3: Implement.** `tests/wow.lua`: the callback. `Core/Init.lua`: the `Apply` line. Any text the third test names: move the read to where it is used. `SkillByName`: the third source loops over all languages' `PROF_*` instead of `ns.L`. `Anon.Lines`: pool by `ns.Locale.current`, English where a language has none.
- [ ] **Step 4: Check the sync wire.** Read `Core/Protocol.lua` and `Game/Sync.lua` payload building: only IDs, keys and player-written text may be sent, nothing from `ns.L`. If something translated is sent, stop and report it instead of changing the protocol.
- [ ] **Step 5: Run `luajit tests/run.lua` and `luacheck .`.** Expected: `0 failed`, clean.
- [ ] **Step 6: Commit** `feat: saved language applies at load; profession names matched in every language`.

---

### Task 3: Language choice in the options

**Files:**
- Modify: `UI/Options.lua` (general panel, next to the tooltip choice), `Locales/enUS.lua`, `Locales/deDE.lua`, `.luacheckrc`, `tests/wow.lua`, `tests/smoke.lua`

**Interfaces:**
- Consumes: `ns.Locale.ORDER`, `ns.Locale.NAMES`, `ns.Locale.Languages`, `ns.Settings().language`.
- Produces: `UI.SetLanguage(code)`: `code` nil for automatic. Saves the setting; if the language in force would change (`Resolve` before and after differ) it reloads the interface, else only refreshes the panel.
- New texts: `OPTIONS_LANGUAGE` ("Language" / "Sprache"), `OPTIONS_LANGUAGE_AUTO` ("Automatic (%s)" / "Automatisch (%s)", `%s` is the name of the client's language), `OPTIONS_LANGUAGE_TIP` ("Guildy's own texts. The game keeps its language. Changing it reloads the interface." / the German equivalent).

- [ ] **Step 1: Write the failing smoke tests.** The stub `ReloadUI` in `tests/wow.lua` counts its calls.
  - `ns.UI.SetLanguage("enUS")` on the `deDE` stub: `ns.Settings().language == "enUS"`, one reload.
  - then `ns.UI.SetLanguage(nil)`: setting is `nil`, a second reload.
  - `ns.UI.SetLanguage("deDE")` when the language in force is already `deDE`: setting saved, no reload.
  - the existing "opens the options" path still runs without error.
- [ ] **Step 2: Run the tests.** Expected: FAIL (`SetLanguage` is nil).
- [ ] **Step 3: Implement.** A label and a `W.MenuButton` under the tooltip choice, built like it. Items: the automatic entry first, then every language of `ns.Locale.Languages()` under its name from `NAMES`, the chosen one checked. The button shows the chosen entry. Language names are never translated (spec, anti-goal 1). `W.Tooltip` with `OPTIONS_LANGUAGE_TIP` on the button. The reload happens on the click, without a further question. "Reset all customizations" does not touch the language.
- [ ] **Step 4: Run `luajit tests/run.lua` and `luacheck .`.** Expected: `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: language choice in the options`.

---

### Tasks 4 to 7: The four translations

One task per language, in this order: **4** `frFR`, **5** `esES`, **6** `ruRU`, **7** `ptBR`. Same shape each.

**Files:**
- Create: `Locales/<code>.lua`
- Modify: `Guildy.toc` (the file after the previous language's; `## Notes-<code>:` line, for Spanish also `## Notes-esMX:` with the same text)

**Interfaces:**
- Consumes: the key set of `Locales/enUS.lua`; `Locales/deDE.lua` as a second reading of what each text means.
- Produces: `ns.LocaleTables.<code>` with every key of English.

- [ ] **Step 1: Run `luajit tests/run.lua` after adding an empty table file and its TOC line.** Expected: FAIL, "<code> is missing ..." for every key. This proves the tests see the new language.
- [ ] **Step 2: Translate every text**, keys in the order of `enUS.lua`, with these rules:
  - Game terms as the game's own client in that language has them: guild, guild master, officer, rank, member, note / officer note, message of the day, whisper, invite, promote / demote, community, professions and every `PROF_*` name, dungeon names (`FAME_DUNGEON_*`), reputation, honor, level, zone. Where unsure about the official term, take the one from the localized global strings or Wowhead in that language, not a literal translation.
  - Informal address where the language's client uses it (French: "vous" as the client does; Spanish and Portuguese: "tú" / "você"; Russian: "вы" lower case).
  - Placeholders in the English order. If the natural sentence would reorder them, reword it.
  - Text length near the English one for labels, column heads, buttons and tab names. A shorter synonym beats a precise long word there.
  - `"..."`, `…`, `·`, colour codes (`|cff......` / `|r`) and line breaks stay as in English; French keeps its spaces before `:` `?` `!`.
  - Russian: no count pairs that need three forms; word such texts as "label: number".
  - Guildy, Raidy, CurseForge and slash commands are never translated.
- [ ] **Step 3: Run `luajit tests/run.lua` and `luacheck .`.** Expected: `0 failed`, clean. The profession-name test of Task 2 now also covers this language.
- [ ] **Step 4: Read the finished file once top to bottom** for a term translated two ways, and make each one consistent.
- [ ] **Step 5: Commit** `feat: French` (or `Spanish`, `Russian`, `Brazilian Portuguese`).

---

### Task 8: The run's decisions (pure)

**Files:**
- Create: `Core/ShotRun.lua` (pure: no WoW API), `tests/test_shotrun.lua`
- Modify: `Guildy.toc` (after `Core\Anon.lua`), `tests/lib.lua` (`lib.PURE`), `tests/run.lua` (`FILES`)

**Interfaces:**
- Produces:
  - `ns.ShotRun.STALE = 180` (seconds without a step after which a saved run counts as cut off)
  - `ns.ShotRun.Start(settings, languages, now) -> run`: `run = { queue = <copy of languages>, language = settings.language or false, width = settings.width, height = settings.height, touched = now }`
  - `ns.ShotRun.Next(run, now) -> code | nil`: removes and returns the first language of `queue`, sets `touched = now`; `nil` when the queue is empty.
  - `ns.ShotRun.Stale(run, now) -> boolean`: not a table, no `queue` table, or `now - (touched or 0) > STALE`.
  - `ns.ShotRun.Restore(run, settings)`: writes `language` (`false` becomes `nil`), `width`, `height` back into `settings`.

- [ ] **Step 1: Write `tests/test_shotrun.lua`:**

```lua
local T = ...
local R = T.pureNs().ShotRun
T.describe("ShotRun", function()
  T.it("walks the languages in order and ends", function()
    local settings = { language = "deDE", width = 1300, height = 700 }
    local run = R.Start(settings, { "enUS", "deDE", "frFR" }, 100)
    T.eq(R.Next(run, 101), "enUS")
    T.eq(R.Next(run, 150), "deDE")
    T.eq(run.touched, 150)
    T.eq(R.Next(run, 200), "frFR")
    T.eq(R.Next(run, 250), nil)
  end)
  T.it("restores what was there, automatic language included", function()
    local settings = { width = 1300, height = 700 }
    local run = R.Start(settings, { "enUS" }, 100)
    settings.language, settings.width, settings.height = "enUS", 1130, 560
    R.Restore(run, settings)
    T.eq(settings, { width = 1300, height = 700 })
  end)
  T.it("knows a cut-off run", function()
    local run = R.Start({}, { "enUS" }, 100)
    T.eq(R.Stale(run, 100 + R.STALE), false)
    T.eq(R.Stale(run, 101 + R.STALE), true)
    T.eq(R.Stale("junk", 0), true)
    T.eq(R.Stale({ touched = 100 }, 100), true)
  end)
  T.it("does not share the language list with the caller", function()
    local languages = { "enUS", "deDE" }
    local run = R.Start({}, languages, 0)
    R.Next(run, 1)
    T.eq(#languages, 2)
  end)
end)
```

- [ ] **Step 2: Run `luajit tests/run.lua`.** Expected: FAIL (`ShotRun` is nil).
- [ ] **Step 3: Implement the four functions.**
- [ ] **Step 4: Run `luajit tests/run.lua` and `luacheck .`.** Expected: `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: decisions of the screenshot run over all languages`.

---

### Task 9: `/guildy shots all` and `/guildy shots stop`

**Files:**
- Modify: `UI/Shots.lua`, `Core/Init.lua` (slash commands, `PLAYER_LOGIN`), `tests/wow.lua`, `tests/smoke.lua`, `.luacheckrc`

**Interfaces:**
- Consumes: `ns.ShotRun.*`, `ns.Locale.Languages`, `ns.Locale.current`, `UI.MIN_W`, `UI.MIN_H`, `UI.Show`, `UI.IsShown`, `UI.frame`, `ns.Roster.Members`, `ns.Now`, `ns.DB()` (the run is `ns.DB().shotRun`).
- Changes: `UI.TakeShots(onDone)`: `onDone` optional, called after the last picture and the clean-up.
- Produces:
  - `UI.TakeAllShots()` for `/guildy shots all`: refuses while a run is on; `ShotRun.Start` with all languages, then the next step.
  - `UI.ResumeShots()`, called in `PLAYER_LOGIN`: no saved run, nothing. A stale one: restore, clear, one printed line, **no reload**. Else continue with the language in force.
  - `UI.StopShots()` for `/guildy shots stop`: restore, clear, reload if the language in force differs from the restored one.

  The steps of a run:
  1. **Next language:** `code = ShotRun.Next(run, now)`. With a code: `settings.language = code`, reload. Without: `ShotRun.Restore`, clear `shotRun`, reload once (language and saved size apply on the way up).
  2. **After the reload (`ResumeShots`):** every second, up to 20 times, look whether `#ns.Roster.Members() > 0`. Then `UI.Show()`, set the window to `UI.MIN_W` × `UI.MIN_H` without saving that size, two seconds later `UI.TakeShots(nextStep)`. Set `run.touched` when the pictures start.
  3. **Giving up** (Review Focus 3): roster not there after 20 seconds, or the window not shown after `UI.Show()`: print why, then as `StopShots`.
  4. **Reload refused:** if the reload does not happen (the code after it still runs two seconds later), print `shots: type /reload to go on` once and wait; `ResumeShots` picks up after the player's reload. Same for the last reload.

- [ ] **Step 1: Write the failing smoke tests**, each in a world of its own, with stub `ReloadUI` and `Screenshot` that count calls, and `ns.Now` steerable:
  - "starts with the first language": `UI.TakeAllShots()` sets `settings.language = "enUS"`, saves a run whose queue has five languages left, one reload.
  - "continues after a reload": world set up with a saved fresh run (queue `{ "ptBR" }`, `language = false`, `width = 1300`, `height = 700`) and `settings.language = "ruRU"`; after login events and timers: window at 1130 × 560, `#UI.SHOTS` screenshots, then `settings.language == "ptBR"` and a reload.
  - "ends and restores": the same with an empty queue: after the pictures `settings.language == nil`, `settings.width == 1300`, `settings.height == 700`, `ns.DB().shotRun == nil`, one reload.
  - "drops a cut-off run without reloading" (Review Focus 2): saved run with `touched` older than `ShotRun.STALE`: after login the settings are restored, `shotRun` is nil, **zero** reloads, zero screenshots.
  - "gives up without a roster" (Review Focus 3): stub roster empty: after the timers the settings are restored, `shotRun` is nil, zero screenshots.
  - "stops on request": `UI.StopShots()` during a run restores and clears.
  - `/guildy shots` alone still takes `#UI.SHOTS` pictures and changes neither language nor size.
- [ ] **Step 2: Run the tests.** Expected: FAIL (`TakeAllShots` is nil).
- [ ] **Step 3: Implement** as in Interfaces; the three slash commands in `Core/Init.lua` (`shots all` and `shots stop` before the plain `shots`). The size set for the run must not reach `settings.width` / `settings.height` (the window saves its size in `OnSizeChanged`, `UI/Main.lua`); if that cannot be kept apart cleanly, `ShotRun.Restore` at the end is what guarantees the old size, and the test above pins it.
- [ ] **Step 4: Run `luajit tests/run.lua` and `luacheck .`.** Expected: `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: /guildy shots all, every view in every language at the smallest size`.

---

### Task 10: Collecting the pictures, and the docs

**Files:**
- Create: `media/e2e/collect.py`
- Modify: `.gitignore` (`media/e2e/*/`), `media/gallery/README.md` (a section "Pictures in every language"), `README.md` (languages), `CHANGELOG.md` (entry under a new unreleased heading in the file's style)

**Interfaces:**
- Consumes: the picture names from `UI/Shots.lua` (as `media/gallery/collect.py` reads them), the language order from `ns.Locale.ORDER` in `Locales/Locales.lua` (same way, by regex), `window_box(img)` from `media/gallery/crop.py`.
- Produces: `python media/e2e/collect.py "<Screenshots folder>"` (or `GUILDY_SCREENSHOTS`): takes the newest run and writes `media/e2e/<code>/<NN-name>.png`, each cut to the window with `crop.py`'s box.

  The newest run: walking back from the newest picture, groups of pictures at most 6 seconds apart; groups at most 120 seconds apart belong to one run. It must be 6 groups of as many pictures as `UI/Shots.lua` lists; anything else is refused with the counts found, and nothing is written. An existing `media/e2e/<code>/` is emptied before it is filled.

- [ ] **Step 1: Write the script.**
- [ ] **Step 2: Try it on a made-up folder:** a small Python snippet writes 114 dark 400 × 300 JPGs with a lighter rectangle and modification times in six groups (2 seconds apart inside, 20 seconds between). Expected: six folders with 19 PNGs each, named as in `UI/Shots.lua`. Then remove one file. Expected: refusal naming `5 groups of 19 and one of 18`-style counts, nothing written. Delete the made-up folder.
- [ ] **Step 3: Write the docs.** README: the six languages and where to switch. Changelog: the new languages, the language option, and one sentence that the four new translations were not checked by native speakers and odd wording is welcome as an issue. Gallery README: the command, the five minutes, the folder.
- [ ] **Step 4: Commit** `feat: collect the pictures of a run over all languages; docs`.

---

### Task 11: Round two (with Sven, not for a subagent)

- [ ] **Step 1:** Sven installs the branch build, opens Guildy and types `/guildy shots all`. Notes whether the reloads happened by themselves and whether Guildy came back in his language and size.
- [ ] **Step 2:** `python media/e2e/collect.py "<Screenshots folder>"`.
- [ ] **Step 3:** Claude reads all 114 pictures and lists, per language and view: text cut off, text over other elements or outside its box, English left in a translated view, missing glyphs. Stand-in content of the anonymous mode and text supplied by the game do not count.
- [ ] **Step 4:** Fixes, each with the test run. A layout that holds for every language beats shortening one translation. Missing Cyrillic glyphs are reported, not fixed here.
- [ ] **Step 5:** A second run for the views that changed. Clean: the branch is ready for review and release.
