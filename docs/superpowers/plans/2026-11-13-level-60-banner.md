# Level 60 Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Guildy user sees a banner when a guild member reaches level 60, and one of them says it once in guild chat.

**Architecture:** A pure module compares the levels of two roster scans. A game module listens to "ROSTER", asks for the roster every 30 seconds, shows the banner and posts to guild chat after a random wait unless a "[Guildy]" line with the name was seen first. A UI module draws the banner on UIParent.

**Tech Stack:** Lua 5.1 (WoW Forever, interface 16001), tests with `luajit tests/run.lua`.

**Spec:** `docs/superpowers/specs/2026-11-13-level-60-banner-design.md`

## Global Constraints

- Level 60 is `ns.Census.MAX_LEVEL`, never a literal in code.
- Settings: `ding60` (banner and sound), `ding60Post` (guild chat). Absent means on; off is `false` (the `Off(check)` convention of `UI/Options.lua`).
- The chat line is `"[Guildy] " .. L.DING_CHAT:format(name, 60)`; the wait before posting is up to 3 seconds; the roster is asked every 30 seconds.
- Nothing is saved to `GuildyDB` except the two settings.
- While `ns.Anon.on` (made-up names for pictures) nothing is posted.
- Every text exists in all six locale files with the same placeholders; no middle dot in ruRU.
- Every new WoW global goes through `rawget(_G, ...)` or into `.luacheckrc`.
- No commits: Sven commits himself.

## Review Focus

1. A member leaves and rejoins at 60, or is new at 60: no banner (Task 1 test).
2. The player changes guild: the first roster of the new guild announces nobody (Task 2 test).
3. Two level 60s in one scan: both banners, one after the other; two chat lines (Task 2 test).
4. A guild chat text that is a secret value: not inspected (Task 2: `OnGuildChat` is called from `Init.OnGuildChat`, which runs after the secret check; `Said` also rejects non-strings, Task 1 test).
5. A name with Lua pattern characters ("Au-Tsch"): found as plain text in the chat line (Task 1 test).

---

### Task 1: `Core/Ding.lua` (pure)

**Files:** Create `Core/Ding.lua`, `tests/test_ding.lua`. Modify `Guildy.toc` (after `Core\Activity.lua`), `tests/lib.lua` (`lib.PURE`), `tests/run.lua` (`FILES`).

**Produces:**
- `ns.Ding.TAG = "[Guildy]"`
- `ns.Ding.Find(before, members, max) -> found, levels` — `before` = `{ [key] = level }` or nil; `members` = roster list (`m.key`, `m.level`); `found` = list of members with `before[m.key]` a number below `max` and `m.level >= max`; `levels` = new table for the next call. `before == nil` finds nothing.
- `ns.Ding.Line(format, name, max) -> string` — `TAG .. " " .. format:format(name, max)`.
- `ns.Ding.Said(text, name) -> boolean` — `text` is a string that starts with `TAG` and holds `name` as plain text.

- [ ] Write `tests/test_ding.lua`: first scan finds nobody and returns levels; 59→60 found; 40→60 found; 60→60 not; absent before and 60 now not; member gone drops from levels; non-number level treated as not found and kept out of trouble; `Said("[Guildy] Au-Tsch has reached level 60!", "Au-Tsch")` true, without tag false, other name false, `Said(nil, "x")` and `Said({}, "x")` false; `Line("%s has reached level %d!", "Au Tsch", 60)`.
- [ ] Run `luajit tests/run.lua`: fails (no `ns.Ding`).
- [ ] Implement; run: passes.

### Task 2: `Game/Ding.lua`, texts, events

**Files:** Create `Game/Ding.lua`, `tests/test_dingflow.lua`. Modify `Guildy.toc` (after `Game\Activity.lua`), `Core/Init.lua`, `Locales/*.lua`, `tests/run.lua`.

**Consumes:** Task 1; `ns.Roster.Members()`, `ns.Roster.Request(true)`, `ns.Chat.Send("guild", text)`, `ns.GuildKey()`, `ns.UI.ShowDing(m)` (Task 3, called at run time and only if present).

**Produces:**
- `ns.GameDing.Start()` — the 30-second ticker (`PLAYER_LOGIN`).
- `ns.GameDing.OnGuildChat(text)` — marks as said every level-60 roster member whose name the line holds (`Init.OnGuildChat`, kind "guild" only).
- `ns.GameDing.OnLevelUp(level)` — at max level asks for the roster after 1 second (`PLAYER_LEVEL_UP`).
- `ns.GameDing.Test()` — banner for the own character (`/guildy ding`), posts nothing.
- Locale keys: `DING_TITLE` ("Level %d"), `DING_TEXT`, `DING_CHAT` ("%s has reached level %d!"), `OPTIONS_DING`, `OPTIONS_DING_POST`, `OPTIONS_DING_POST_TIP`.

- [ ] Write `tests/test_dingflow.lua` on a world with its own roster table and a recording `C_ChatInfo.SendChatMessage`: after login nothing sent; member row to level 60 + `GUILD_ROSTER_UPDATE` + timers → exactly one line `"[Guildy] ..."` holding the name on "GUILD"; a second scan sends nothing more; a `CHAT_MSG_GUILD` "[Guildy] <name> ..." before the timers run → nothing sent; `ding60Post = false` → nothing sent; two members at once → two lines; `GetGuildInfo` changed to another guild → nothing; no errors.
- [ ] Run: fails. Implement, add the six texts, wire `Init.lua` (`PLAYER_LOGIN`, `PLAYER_LEVEL_UP`, `OnGuildChat`, `/guildy ding`). Run: passes, locale tests included.

### Task 3: `UI/Ding.lua` and options

**Files:** Create `UI/Ding.lua`. Modify `Guildy.toc` (after `UI\Widgets.lua`), `UI/Options.lua` (General panel: two check boxes under the size slider; "Reset all"), `tests/test_dingflow.lua`, `.luacheckrc` if needed, `CHANGELOG.md`.

**Produces:** `ns.UI.ShowDing(m)` — queues `m` (`name`, `classFile`); frame `GuildyDing` on `UIParent` (TOP, 0, -170; strata HIGH; no mouse) with `.Title`, `.Name`, `.Text`; fade in 0.4 s, hold 5 s, fade out 1 s by `OnUpdate`; the game's level-up sound per banner; next in the queue when one ends.

- [ ] Extend `tests/test_dingflow.lua`: after the level 60 `GuildyDing` is shown and `.Name` holds the name; with `ding60 = false` it is not shown and the chat line still goes out; running the frame's `OnUpdate` past the end hides it and shows the second of two.
- [ ] Run: fails. Implement banner and options. Run: passes.
- [ ] `luacheck .` if installed; changelog entry under a new top heading.

### In game (Sven)

`/guildy ding` for the look and the sound; a real level 60 for the guild chat line (does Forever let a timer send it?); `/guildy perf` for the cost of a roster every 30 seconds with the window closed.
