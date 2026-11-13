# Member Since Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guildy remembers when each member joined the guild, shares it between Guildy users and shows it.

**Architecture:** A pure module `Core/Tenure.lua` holds the rules (merge, digest, wire, text). `Game/Roster.lua` feeds it from the guild event log on each scan, `Game/Sync.lua` shares it (`SUM.j`, `JOIN`), the members tab, tooltip and character page show it.

**Tech Stack:** Lua 5.1 (WoW Forever addon), tests with `luajit tests/run.lua`.

**Spec:** `docs/superpowers/specs/2026-11-13-member-since-design.md`

## Global Constraints

- Data: `guild.joined[nameKey] = { d = day number, x = true | nil }`.
- A rejoin is two log dates more than 2 days apart.
- `JOIN` carries at most 150 members a message.
- Every locale file gets the same new keys (tests/test_locales.lua checks it).
- Nothing is stored while names are made up for pictures (`ns.Anon.on`).

## Review Focus

- A sync message with rubbish in it (strings for days, a day in the future, a non-member): refused, nothing stored. Test in Task 1 (`Tenure.Apply`).
- First scan before the event log has arrived: member gets "first seen", the log's date replaces it on the next scan. Test in Task 1 (`Note`: exact beats seen).
- Two clients that hold slightly different log dates must end on the same date, or they offer each other dates forever. Test in Task 1 (merge both ways gives the same day).
- A member who left and came back: later log date wins. Test in Task 1.
- A saved column choice from before this release: `joined` stays hidden, all others as chosen. Checked by hand in Task 4 (smoke test loads the tab).

---

### Task 1: Core/Tenure.lua

**Files:** Create `Core/Tenure.lua`, `tests/test_tenure.lua`; modify `Guildy.toc` (after `Core\Ding.lua`), `tests/lib.lua` (`lib.PURE`), `tests/run.lua` (`FILES`).

**Produces:**
- `Tenure.REJOIN_DAYS = 2`, `Tenure.WIRE_MEMBERS = 150`
- `Tenure.Day(ts) -> day`
- `Tenure.Note(joined, key, day, exact, today) -> changed` (the merge rules of the spec)
- `Tenure.Prune(joined, keep) -> removed`
- `Tenure.Digest(joined) -> { n, x, s }`, `Tenure.Differs(mine, theirs) -> boolean`
- `Tenure.Wire(joined, names) -> { message, ... }`, each `{ { name, day, 1 | 0 }, ... }`
- `Tenure.Apply(joined, list, today, isMember) -> changed`
- `Tenure.Span(days) -> unit, count` (`"d"`, `"mo"`, `"y"`)

- [ ] Tests first (rules, digest, wire round trip, rubbish refused), run red, implement, run green.

### Task 2: Roster

**Files:** Modify `Game/Roster.lua`, `Core/Search.lua` (getter `joined`), `tests/smoke.lua` or `tests/test_search.lua`.

**Produces:** members carry `joinedDay`, `joinedExact`; `guild.joined` is filled and pruned; `Roster.TenureText(m, long) -> string | nil`.

- [ ] After `ReadEventLog()`: note log joins as exact, everyone else as seen today; prune with a complete roster; not while `ns.Anon.on`.
- [ ] `Search.SortMembers(list, "joined")`: by day, members without one last.

### Task 3: Sync

**Files:** Modify `Game/Sync.lua` (header comment, `SendSummary`, `OnSummary`, new `OnJoined`, `HANDLERS.JOIN`).

- [ ] `SUM.j = Tenure.Digest(guild.joined)`; on a summary with a differing `j`: offer after `5 + random * 8` s unless a `JOIN` arrived meanwhile or this state was already offered to this sender.
- [ ] `OnJoined`: `Tenure.Apply`, then refresh the members' fields and fire `ROSTER`.

### Task 4: UI and locales

**Files:** Modify `UI/TabMembers.lua`, `UI/Popups.lua`, `UI/CharacterPage.lua`, `Locales/*.lua`, `CHANGELOG.md`.

- [ ] Column `joined` (width 80), hidden unless `settings.memberColumns.joined == true`.
- [ ] Tooltip line and character page line.
- [ ] Locale keys: `COL_JOINED`, `MEMBER_SINCE`, `SINCE_AT_LEAST`, `SPAN_D`, `SPAN_MO`, `SPAN_Y`, `SPAN_TODAY`, `SPAN_MORE`, `JOINED_TIP`.
- [ ] `luajit tests/run.lua`: 0 failed.
