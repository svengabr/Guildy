# Overview Endgame View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The overview tab gets a second, endgame view (activity score, this month, item levels, last online, comings and goings, raids) and a switch between it and today's level-phase view.

**Architecture:** The numbers live in pure modules: a new `Core/Activity.lua` (days seen online, rates, score, players, pulse, month rows) and additions to `Core/Census.lua` (phase, item level histogram, raids) and `Core/Stats.lua` (the days counter, boss sums). `Game/Activity.lua` feeds them from roster and saved data and caches the result. `UI/TabOverview.lua` keeps the level-phase view and the toolbar; the six endgame boxes are a new `UI/OverviewEndgame.lua`.

**Tech Stack:** Lua 5.1 (WoW addon, Interface 16001), tests with `luajit tests/run.lua`, `luacheck`.

**Spec:** `docs/superpowers/specs/2026-11-11-overview-endgame-design.md` · Picture: `docs/mockups/overview-endgame.png`

## Global Constraints

- Logic in `Core/` is pure (no WoW API at load or call time, `now` and `date` are passed in) and has tests; game access in `Game/`; drawing in `UI/`.
- A member without a current reading has **no** score (`nil`), never a low one. Nothing divides by a count that can be zero.
- Nothing new is written to `GuildyDB` while `ns.Anon.on` (screenshot mode).
- The days counter's ID is `9800001`: above Blizzard's IDs, below `Stats.GEAR_BASE` (9900000). Never above it.
- No new message type on the addon channel.
- The level-phase view looks and behaves as today.
- Every text Guildy shows comes from `ns.L` and exists in all six locale files (`enUS`, `deDE`, `frFR`, `esES`, `ruRU`, `ptBR`), placeholders in the same order. English and German are given in "Texts" below; the other four are written in the tone of their file. Each task adds the keys it starts to use.
- The smallest window (1130 × 560) holds all six boxes without cut-off text.
- Code comments, commit messages and docs in English, in the style of the files around them. Commits: `feat:` / `test:` / `docs:` subject lines, no attribution lines.
- Before every commit: `luajit tests/run.lua` ends with `0 failed`, and `luacheck .` is clean. New WoW globals go into `.luacheckrc` and get a stub in `tests/wow.lua`.
- Work on branch `feat/overview-endgame`, cut from `main`. No release in this plan.

## Review Focus

1. A statistics record whose `months` is missing, empty or holds only a snapshot newer than `rec.ts` (old saves, relayed records): no score, no error. Pinned in Task 3.
2. A counter that went down between snapshot and reading (Blizzard reset, the Alliance boss merge): its growth counts as 0, the others still count. Pinned in Task 3.
3. A guild where nobody has a score: pulse is `nil`, the box shows "–" and five bars of zero width. Pinned in Task 4 (pure) and checked by eye in Task 8.
4. A roster member with unknown last online (`daysOffline == nil`, not online): no day is marked, and the reading is current only by the 7-day rule. Pinned in Tasks 2 and 3.
5. An older Guildy relays a member's record without the days counter after the new one stored it: the stored counter survives. Pinned in Task 1.

## Texts

| Key | enUS | deDE |
|---|---|---|
| `PHASE_LEVEL` | Levelling | Levelphase |
| `PHASE_ENDGAME` | Endgame | Endgame |
| `OPTIONS_PHASE` | Overview shows | Übersicht zeigt |
| `OPTIONS_PHASE_AUTO` | Automatic | Automatisch |
| `OPTIONS_PHASE_TIP` | Automatic switches to the endgame view once half of the active members are level 60. | Automatisch wechselt zur Endgame-Ansicht, sobald die Hälfte der aktiven Mitglieder Stufe 60 ist. |
| `SCORE` | Activity | Aktivität |
| `SCORE_HINT` | value 0-100 from the game's statistics | Wert 0-100 aus den Spielstatistiken |
| `SCORE_PULSE` | Guild pulse | Gildenpuls |
| `SCORE_PULSE_OF` | average of %d players with a current reading | Durchschnitt von %d Spielern mit aktuellem Stand |
| `SCORE_CHANGE` | %s since last month | %s zum Vormonat |
| `SCORE_1` … `SCORE_5` | Very active / Active / Occasional / Hardly / No current reading | Sehr aktiv / Aktiv / Gelegentlich / Kaum / Kein aktueller Stand |
| `SCORE_CLICK` | Click on a bar shows who | Klick auf einen Balken zeigt, wer |
| `COL_SCORE` | Act. | Akt. |
| `MONTH` | This month | Diesen Monat |
| `MONTH_HINT` | whole guild · mark: last month up to the same day | Gilde gesamt · Strich: Vormonat bis zum selben Tag |
| `MONTH_RAID` / `MONTH_BOSSES` / `MONTH_DUNGEONS` / `MONTH_QUESTS` / `MONTH_HONOR` / `MONTH_DAYS` | Raid bosses / Dungeon bosses / Dungeons entered / Quests completed / Honorable kills / Days online per player | Bosse in Schlachtzügen / Dungeon-Bosse / Dungeons betreten / Quests abgeschlossen / Ehrenhafte Siege / Tage online je Spieler |
| `ILVL` | Item level | Itemlevel |
| `ILVL_HINT` | level 60 | Stufe 60 |
| `ILVL_TIP` | Item level %d: %d members | Itemlevel %d: %d Mitglieder |
| `ILVL_READY` | Raid roster from %d | Raidkader ab %d |
| `RAIDS` | Raids | Schlachtzüge |
| `RAIDS_HINT` | members with a kill · click shows who | Mitglieder mit Sieg · Klick zeigt, wer |
| `RAIDS_NEW` | new this month: +%d | neu diesen Monat: +%d |
| `RAIDS_OPEN` | Raid ready without a kill: | Raidbereit ohne Sieg: |
| `RAIDS_OPEN_NONE` | nobody | niemand |
| `ACTIVITY_REPORT` | Activity: pulse %s · %d very active, %d active, %d occasional, %d hardly, %d without a reading · median %s | Aktivität: Puls %s · %d sehr aktiv, %d aktiv, %d gelegentlich, %d kaum, %d ohne Stand · Median %s |

`LEVEL_MAX` ("highest column: %d") and the `ACTIVITY*` / `CHANGES*` keys are reused as they are.

---

### Task 1: Statistics — days counter and boss sums

**Files:**
- Modify: `Core/Stats.lua`
- Test: `tests/test_stats.lua`

**Interfaces:**
- Produces: `Stats.DAYS = 9800001`; special IDs `"raidBosses"` and `"dungeonBosses"` accepted by `Stats.Value` and `Stats.Ranking` (sum of the end boss statistics of `Stats.DUNGEONS` entries with / without `raid`); `Stats.Update` and `Stats.Merge` never let `rec.v[Stats.DAYS]` go down.

- [ ] **Step 1: Write the failing tests** in `tests/test_stats.lua`:

```lua
T.it("sums raid and dungeon end bosses apart", function()
  local rec = { ts = 100, v = { [1098] = 3, [63580] = 2, [1095] = 5, [6145] = 1 }, months = {} }
  T.eq(Stats.Value(rec, "raidBosses", "all"), 5)
  T.eq(Stats.Value(rec, "dungeonBosses", "all"), 6)
  T.eq(Stats.Value(rec, "bosses", "all"), 11)
end)
T.it("keeps the days counter when a newer record lacks it", function()
  local member = {}
  Stats.Update(member, { [107] = 10, [Stats.DAYS] = 12 }, 1000, "self")
  Stats.Update(member, { [107] = 20 }, 2000, "seen")                       -- read nearby by an old client
  T.eq(member.stats.v[Stats.DAYS], 12)
  Stats.Merge(member, { ts = 3000, src = "relay", v = { [107] = 30, [Stats.DAYS] = 9 }, months = {} })
  T.eq(member.stats.v[Stats.DAYS], 12)                                     -- never down
  Stats.Merge(member, { ts = 4000, src = "relay", v = { [107] = 40, [Stats.DAYS] = 15 }, months = {} })
  T.eq(member.stats.v[Stats.DAYS], 15)
end)
T.it("does not take the days counter for equipment", function()
  T.eq(Stats.HasGear({ [Stats.DAYS] = 4 }), false)
end)
```

- [ ] **Step 2: Run** `luajit tests/run.lua` — expected: these three fail.
- [ ] **Step 3: Implement** in `Core/Stats.lua`: the constant with a comment on why it is below `GEAR_BASE`; the two special IDs in `StatValue`; in `Stats.Update` and `Stats.Merge`, after `rec.v` is replaced, `rec.v[Stats.DAYS] = max(old, new)` when either exists. `Stats.TileChoices` must not offer `Stats.DAYS` (it is not in the catalog, so nothing to do — assert it in a test if in doubt).
- [ ] **Step 4: Run** `luajit tests/run.lua` and `luacheck .` — expected: `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: days counter and raid/dungeon boss sums in the statistics`

### Task 2: Activity — days seen online

**Files:**
- Create: `Core/Activity.lua` (add to `Guildy.toc` after `Core\Family.lua`, to `lib.PURE` in `tests/lib.lua` after `Core/Family.lua`)
- Create: `tests/test_activity.lua` (add to `FILES` in `tests/run.lua`)

**Interfaces:**
- Produces:
  - `Activity.DAYS_KEPT = 60`
  - `Activity.Day(ts) -> integer` — `floor(ts / 86400)`
  - `Activity.LastSeenDay(now, online, daysOffline) -> day | nil` — today when online, `Day(now - daysOffline * 86400)` when `daysOffline` is a number, else nil
  - `Activity.MarkSeen(member, day) -> changed` — `member.seen = { [day] = true }`; drops days older than `day - DAYS_KEPT + 1`
  - `Activity.SeenCount(seenList, fromDay, toDay) -> n` — days in the range marked in **any** of the given `seen` tables (a list, so a player's characters count once per day)

- [ ] **Step 1: Write the failing tests**

```lua
local T = ...
local ns = T.pureNs()
local A = ns.Activity
local DAY = 86400

T.describe("Activity days", function()
  T.it("finds the last day seen", function()
    T.eq(A.LastSeenDay(10 * DAY + 5, true, nil), 10)
    T.eq(A.LastSeenDay(10 * DAY + 5, false, 2.5), 7)
    T.eq(A.LastSeenDay(10 * DAY + 5, false, nil), nil)      -- unknown last online: no day
  end)
  T.it("marks days and forgets old ones", function()
    local m = {}
    T.eq(A.MarkSeen(m, 100), true)
    T.eq(A.MarkSeen(m, 100), false)
    A.MarkSeen(m, 100 + A.DAYS_KEPT)
    T.eq(m.seen[100], nil)
    T.eq(m.seen[100 + A.DAYS_KEPT], true)
  end)
  T.it("counts a day once over several characters", function()
    T.eq(A.SeenCount({ { [5] = true, [6] = true }, { [6] = true, [9] = true } }, 5, 8), 2)
    T.eq(A.SeenCount({}, 5, 8), 0)
  end)
end)
```

- [ ] **Step 2: Run** — expected: fails loading `Core/Activity.lua`.
- [ ] **Step 3: Implement** the five items above. `member.seen` keys are numbers; a `seen` that is not a table is replaced.
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: days seen online per member`

### Task 3: Activity — rates, current reading, score

**Files:**
- Modify: `Core/Activity.lua`
- Test: `tests/test_activity.lua`

**Interfaces:**
- Consumes: `Stats.Value` special IDs and `Stats.DAYS` (Task 1), `Stats.MonthKey`, `Stats.PreviousMonth`.
- Produces:
  - `Activity.MAX = { presence = 30, playing = 25, group = 45 }`
  - `Activity.GROUP_POINTS = { raidBosses = 10, dungeonBosses = 3, dungeons = 1, battlegrounds = 3 }`, `Activity.K_GROUP = 30`
  - `Activity.K_PLAYING = 5`, playing input `x = (kills + 5 * honorKills) / 100 + quests / 2`
  - `Activity.FULL_PRESENCE = 5` (days a week for the full presence part), `Activity.MIN_SPAN = 3` (days), `Activity.CURRENT_DAYS = 7`, `Activity.MIN_COUNTED = 7`
  - `Activity.Rates(rec, now, date) -> rates | nil` — `{ span = days, fromDay, toDay, kills, honorKills, quests, raidBosses, dungeonBosses, dungeons, battlegrounds, ownDays }`, every count **per week**; `ownDays` is the growth of `Stats.DAYS` (not per week, nil when the record has no counter at the window start). Window start: `rec.months[previous month]`, else `rec.months[this month]`; its own `ts` and `v` (not zero in the launch month). nil when there is no such snapshot or `rec.ts - snap.ts < MIN_SPAN` days. A count that went down is 0.
  - `Activity.IsCurrent(rec, m, now) -> boolean` — `rec.ts >= now - 7 days`, or `m` is offline with a numeric `daysOffline` and `rec.ts >= now - daysOffline * 86400 - 3600`
  - `Activity.Score(rates, presence) -> score, parts` — `rates` may be a sum of several characters' rates; `presence` = days a week or nil. `parts = { presence, playing, group }` in points. With `presence == nil` the other two are scaled by `100 / 70`. Curves: `max * (1 - exp(-x / k))`, presence `30 * min(1, presence / 5)`. Score is `floor(sum + 0.5)`, at most 100.
  - `Activity.AddRates(a, b) -> a` — adds b's weekly counts into a; `span` becomes the larger

- [ ] **Step 1: Write the failing tests.** The three example players of the spec, as weekly rates:

```lua
T.describe("Activity score", function()
  local function rates(t)
    local r = { span = 30, kills = 0, honorKills = 0, quests = 0, raidBosses = 0, dungeonBosses = 0, dungeons = 0, battlegrounds = 0 }
    for k, v in pairs(t) do r[k] = v end
    return r
  end
  T.it("puts the daily raider, dungeon runner and PvP player above 75", function()
    T.truthy(A.Score(rates({ kills = 700, quests = 5, raidBosses = 4, dungeonBosses = 2, dungeons = 2 }), 7) >= 75)
    T.truthy(A.Score(rates({ kills = 960, quests = 2, dungeonBosses = 12, dungeons = 12 }), 7) >= 75)
    T.truthy(A.Score(rates({ kills = 50, honorKills = 150, battlegrounds = 16 }), 7) >= 75)
  end)
  T.it("puts the twice-a-week solo quester between 25 and 49", function()
    local score = A.Score(rates({ kills = 300, quests = 15 }), 2)
    T.truthy(score >= 25 and score <= 49, tostring(score))
  end)
  T.it("lets a daily solo player reach Active but not Very active", function()
    local score = A.Score(rates({ kills = 800, quests = 30 }), 7)
    T.truthy(score >= 50 and score < 75, tostring(score))
  end)
  T.it("gives a real zero to somebody who did nothing", function()
    local score, parts = A.Score(rates({}), 0)
    T.eq(score, 0)
    T.eq(parts, { presence = 0, playing = 0, group = 0 })
  end)
  T.it("scales the other parts while days are not counted yet", function()
    local with = A.Score(rates({ kills = 960, dungeonBosses = 12, dungeons = 12 }), nil)
    T.truthy(with >= 75 and with <= 100, tostring(with))
  end)
end)

T.describe("Activity rates", function()
  local date = function(fmt, ts) return os.date("!" .. fmt, ts) end
  local NOV = os.time({ year = 2026, month = 11, day = 2, hour = 12 })
  local OCT, NOW = NOV - 30 * DAY, NOV + 12 * DAY   -- whole days apart, whatever the time zone does
  T.it("measures from the previous month's first reading, per week", function()
    local rec = { ts = NOW, v = { [107] = 4100, [1098] = 6 }, months = {
      ["2026-10"] = { ts = OCT, v = { [107] = 100, [1098] = 0 } }, ["2026-11"] = { ts = NOV, v = { [107] = 2000 } } } }
    local r = A.Rates(rec, NOW, date)
    T.eq(r.span, 42)
    T.eq(math.floor(r.kills + 0.5), 667)     -- 4000 in 6 weeks
    T.eq(r.raidBosses, 1)
  end)
  T.it("has no rates without a usable snapshot", function()
    T.eq(A.Rates({ ts = NOW, v = { [107] = 5 } }, NOW, date), nil)                       -- no months
    T.eq(A.Rates({ ts = NOW, v = {}, months = {} }, NOW, date), nil)
    T.eq(A.Rates({ ts = NOV + DAY, v = {}, months = { ["2026-11"] = { ts = NOV, v = {} } } }, NOW, date), nil)   -- 1 day
    T.eq(A.Rates({ ts = NOV, v = {}, months = { ["2026-11"] = { ts = NOV + 5 * DAY, v = {} } } }, NOW, date), nil) -- snapshot newer
    T.eq(A.Rates(nil, NOW, date), nil)
  end)
  T.it("counts a statistic that went down as zero", function()
    local rec = { ts = NOW, v = { [107] = 50, [98] = 40 }, months = { ["2026-11"] = { ts = NOV, v = { [107] = 900, [98] = 12 } } } }
    local r = A.Rates(rec, NOW, date)
    T.eq(r.kills, 0)
    T.truthy(r.quests > 0)
  end)
  T.it("knows a current reading", function()
    T.eq(A.IsCurrent({ ts = NOW - 3 * DAY }, { online = true }, NOW), true)
    T.eq(A.IsCurrent({ ts = NOW - 20 * DAY }, { online = false, daysOffline = 21 }, NOW), true)   -- read on the last evening
    T.eq(A.IsCurrent({ ts = NOW - 20 * DAY }, { online = false, daysOffline = 2 }, NOW), false)
    T.eq(A.IsCurrent({ ts = NOW - 20 * DAY }, { online = false }, NOW), false)                    -- unknown last online
    T.eq(A.IsCurrent(nil, { online = true }, NOW), false)
  end)
end)
```

- [ ] **Step 2: Run** — expected: the new tests fail.
- [ ] **Step 3: Implement** the interface. Statistic IDs: kills 107, honorable kills 588, quests 98, dungeons entered 932, battlegrounds 839; boss sums through `Stats.Value(rec_like, "raidBosses", "all")` on the two value tables. If an example-player test misses its band, change `K_GROUP` / `K_PLAYING` / `GROUP_POINTS`, not the test.
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: activity score from weekly rates`

### Task 4: Activity — players, bars, pulse

**Files:**
- Modify: `Core/Activity.lua`
- Test: `tests/test_activity.lua`

**Interfaces:**
- Consumes: Tasks 2–3; `Family.Mains(members, families, ownChars) -> { [key] = mainKey }`.
- Produces:
  - `Activity.Players(members, mains, recordOf, now, date, since) -> players, byKey` — `recordOf(m)` returns the saved member record (`{ stats, seen }`) or nil; `since` = the day this client began counting days (`guild.seenSince`) or nil. One player per main (members without a family are their own). `players[i] = { key = mainKey, chars = { m, ... }, score = n | nil, parts = t | nil }`; `byKey[memberKey] = player`.
    - The player's lead character is the one online or with the smallest `daysOffline`; no score unless `IsCurrent(lead record, lead, now)` and the lead has rates.
    - Rates of all characters with a current reading and rates are added.
    - Presence = days a week over the counted span: `from = max(since, window start day)`, `to = today`; counted `= to - from + 1`; `days = max(SeenCount(chars' seen, from, to), sum of ownDays capped at counted)`; nil when `since` is nil or `counted < MIN_COUNTED`.
  - `Activity.Bucket(score) -> 1..5` — 75+, 50+, 25+, below, nil → 5
  - `Activity.Summary(players) -> { buckets = { n1..n5 }, pulse = n | nil, scored = n, median = n | nil }` — pulse = mean of the scores, one decimal
  - `Activity.PULSES_KEPT = 4`; `Activity.StorePulse(guild, monthKey, pulse)` — `guild.pulse[monthKey] = pulse`, older months pruned, nil pulse stores nothing; `Activity.PulseChange(guild, monthKey, pulse, previousKey) -> delta | nil`

- [ ] **Step 1: Write the failing tests** — one `T.it` each, with two members `a` (main, online, current reading, dungeon rates) and `b` (twink of `a`, offline 30 days, stale reading), and a loner `c` without a record:
  - `Players` returns two players; `byKey.a == byKey.b`; that player has a score and it equals `Score` of `a`'s rates alone; `c`'s player has `score == nil`.
  - with `b` as the most recently online character and a stale reading, the player has no score even though `a` has rates.
  - `since = nil` → the score equals `Score(rates, nil)`; `since` 10 days back with 5 marked days over `a` and `b` (2 of them on the same day) → presence `4 / 10 * 7`.
  - `Bucket`: 100→1, 75→1, 74→2, 50→2, 49→3, 25→3, 24→4, 0→4, nil→5.
  - `Summary({})` → `{ buckets = {0,0,0,0,0}, pulse = nil, scored = 0, median = nil }`; `Summary` of scores 80, 60, nil → buckets `{1,1,0,0,1}`, pulse 70, scored 2.
  - `StorePulse` keeps 4 months; `PulseChange` with no stored previous month → nil; with 65 stored and 74 now → 9.
- [ ] **Step 2: Run** — expected: fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: activity per player, bars and guild pulse`

### Task 5: This month, phase, item levels, raids

**Files:**
- Modify: `Core/Activity.lua`, `Core/Census.lua`
- Test: `tests/test_activity.lua`, `tests/test_census.lua`

**Interfaces:**
- Produces:
  - `Activity.MONTH_ROWS = { "raidBosses", "dungeonBosses", 932, 98, 588, "days" }`
  - `Activity.Month(entries, players, now, date, since) -> { { id, value, last, compare } }` — `entries` as `GameStats.Entries()` gives them (`{ rec, member }`). `value` = sum of `Stats.Value(rec, id, "month", now, date)` over records that have one; `last` the same for `"last"`; `compare = last * dayOfMonth / daysInMonth` (nil when `last` is nil for every record). The `"days"` row: mean days seen per player this month and last month from the characters' `seen`, one decimal; `last` nil while `since` is later than the first of last month.
  - `Census.READY_ILVL = 56`, `Census.READY_DAYS = 7`, `Census.ENDGAME_SHARE = 0.5`
  - `Census.Phase(members, setting) -> "level" | "endgame"` — `setting` `"level"` / `"endgame"` wins; else endgame when at least half of the members active in 30 days are level 60 (and there is at least one)
  - `Census.ItemLevels(members, windowDays, ilvlOf) -> { counts = { [ilvl] = { [classFile] = n } }, totals = { [ilvl] = n }, min, max, top }` — level 60 members active in the window whose `ilvlOf(m)` (tenths, as stored) is a number; column = `floor(tenths / 10)`; `min`/`max` nil when empty
  - `Census.IsReady(m, ilvlTenths) -> boolean` — level 60, online or `daysOffline <= READY_DAYS`, item level at least `READY_ILVL`
  - `Census.Raids(members, windowDays, raids, valuesOf, monthStartOf, ilvlOf) -> { { raid, readings, killers = { m }, new, open = { m } } }` — `raids` = the `raid = true` entries of `Stats.DUNGEONS`; `valuesOf(m)` current statistics table or nil; `monthStartOf(m)` this month's first values or nil. `readings` = level 60 members active in the window with values; `killers` those with a kill; `new` killers whose month start has none; `open` ready members with values and no kill, highest item level first.

- [ ] **Step 1: Write the failing tests** — `Phase` (settings win; 3 of 6 active at 60 → endgame; 2 of 6 → level; empty roster → level; inactive 60s do not count); `ItemLevels` (a level 59 member and a member without reading are left out; 57.9 → column 57; empty → `min == nil`, `top == 0`); `IsReady` at 55.9 / 56.0 and at 7 / 7.5 days; `Raids` with three members (killer since last month, killer new this month, ready without kill) → `readings 3, #killers 2, new 1, open = { third }`; `Month` with two records on day 10 of a 30-day month → `compare == last / 3`, and a record without this month's snapshot left out of `value`.
- [ ] **Step 2: Run** — expected: fail.
- [ ] **Step 3: Implement.** Days in the month from `date("%d", ...)` of the last day (day 0 of the next month via `os.time` is not available in WoW: step from the 28th forward a day at a time with the `date` passed in).
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: month rows, phase, item levels and raids for the endgame view`

### Task 6: Game side — counting days, the cache, `/guildy activity`

**Files:**
- Create: `Game/Activity.lua` (in `Guildy.toc` after `Game\Stats.lua`)
- Modify: `Game/Stats.lua` (`GameStats.ReadOwn`), `Core/Init.lua` (slash command), locale files (`ACTIVITY_REPORT`)
- Test: `tests/smoke.lua`

**Interfaces:**
- Consumes: Tasks 1–5; `ns.Roster.Members()`, `ns.GuildData()`, `ns.DB()`, `ns.GameStats.Entries()`, `ns.GameStats.Date`, `ns.Family.Mains`, `ns.Now()`, events `"ROSTER"`, `"STATS"`.
- Produces:
  - `ns.GameActivity.Get() -> { players, byKey, summary, change, month }` — computed on first use, dropped on `"ROSTER"`, `"STATS"` and `"PROFS"`-independent; `change` from `Activity.PulseChange`
  - `ns.GameActivity.ScoreOf(memberKey) -> score | nil, parts | nil`
  - `ns.GameActivity.Report() -> string` (the `ACTIVITY_REPORT` line)
  - Saved data: `member.seen`, `guild.seenSince`, `guild.pulse`, `GuildyDB.ownDays[charKey] = { day, n }`

- [ ] **Step 1: Write the failing smoke tests**: after a roster scan with one member online and one offline 2 days, the saved records carry `seen` for today and for two days ago, and `guild.seenSince` is today; the same scan with `ns.Anon.on` writes neither. After `GameStats.UpdateOwn()` on two different days (move the stubbed server time), the own record's `v[Stats.DAYS]` is 2, and a second read on the same day leaves it at 2. `/guildy activity` prints one line starting with the chat tag.
- [ ] **Step 2: Run** — expected: fail.
- [ ] **Step 3: Implement.** On `"ROSTER"`: mark `LastSeenDay` for every member (records created with `ns.Store.Member` only for members that get a day), set `seenSince` once; skip everything while `ns.Anon.on` or without `ns.GuildData()`. In `GameStats.ReadOwn`: bump `GuildyDB.ownDays[own key]` once per day and put `n` into `values[Stats.DAYS]`. In `Get()`: store the pulse for the current month (not while `Anon.on`). Slash command `activity` in `Core/Init.lua` next to `statmouse`, also listed in the help text there.
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: count days online, cache the activity, /guildy activity`

### Task 7: The switch and the option

**Files:**
- Modify: `UI/TabOverview.lua`, `UI/Options.lua`, locale files (`PHASE_*`, `OPTIONS_PHASE*`)
- Test: `tests/smoke.lua`

**Interfaces:**
- Consumes: `Census.Phase` (Task 5), `W.Segmented`, `W.MenuButton`.
- Produces: `settings.overviewPhase` = `"level"` | `"endgame"` | nil (automatic); `UI.OverviewPhase() -> "level" | "endgame"` (the phase in force); in `UI/TabOverview.lua` two frames filling `page.Body`, `view.Level` (today's boxes, moved under it unchanged) and `view.Endgame` (empty until Task 8), one shown at a time.

- [ ] **Step 1: Write the failing smoke tests**: with no setting and a stub roster of levelling members `UI.OverviewPhase()` is `"level"`; selecting "Endgame" on the switch stores `"endgame"`, and it is still `"endgame"` after the settings table is re-read; the options menu's "Automatic" item sets it back to nil.
- [ ] **Step 2: Run** — expected: fail.
- [ ] **Step 3: Implement.** The switch is the first control on `page.Bar`, before the `ACTIVE_IN` label, and always shows the phase in force (so on automatic it follows the guild). The options row goes on the general panel under the language row, same label and menu-button layout, with `OPTIONS_PHASE_TIP` as tooltip; choosing there refreshes the overview tab. "Reset all" also clears `overviewPhase`.
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: level phase / endgame switch on the overview, kept across reloads`

### Task 8: The six endgame boxes

**Files:**
- Create: `UI/OverviewEndgame.lua` (in `Guildy.toc` after `UI\TabOverview.lua`)
- Modify: `UI/TabOverview.lua` (build and refresh `view.Endgame` through it; share `GuildEvents` and the changes list instead of copying them), locale files (`SCORE*`, `MONTH*`, `ILVL*`, `RAIDS*`)
- Test: `tests/smoke.lua`

**Interfaces:**
- Consumes: `ns.GameActivity.Get()` (Task 6), `Census.ItemLevels` / `Census.Raids` / `Census.IsReady` (Task 5), `W.Box`, `W.BarRow`, `W.ScrollList`, `W.ClassColor`, `W.ClassName`, `UI.FilterMembers`.
- Produces: `UI.BuildOverviewEndgame(parent) -> view` with `view:Layout()` and `view:Refresh()`; filters handed to `UI.FilterMembers`: `{ scoreBucket = 1..5 }`, `{ ilvl = n, level = 60, activeDays = … }`, `{ raidKill = raid.key }` (Task 9 makes the members tab understand them).

Layout, from the picture: three columns of equal width, gaps as the level view (8); the top row takes 48 % of the height. Top: Activity, This month, Item level. Bottom: Last online, Comings and goings, Raids.

- [ ] **Step 1: Write the failing smoke test**: with the endgame phase set and the stub guild, opening the overview tab builds the view, `Refresh()` runs without error both with members that have scores and with an empty statistics store, and the activity box's big number reads "–" in the second case.
- [ ] **Step 2: Run** — expected: fail.
- [ ] **Step 3: Implement the boxes.**
  - **Activity:** pulse in `GameFontNormalHuge` ("–" when nil); beside it `SCORE_PULSE` and, when there is a change, `SCORE_CHANGE` with a signed number, green from 0 up and red below; under it `SCORE_PULSE_OF`. Five `W.BarRow`s `SCORE_1..5` with their ranges in grey after the label (75-100, 50-74, 25-49, 0-24, none for the fifth); colours as the Last online rows over four steps, the fifth grey; click → `scoreBucket`. `SCORE_CLICK` at the bottom, hidden when the box is too low for it. Not affected by the time window.
  - **This month:** six rows from `month`: label, value in gold, signed difference to `compare` (green / red; nothing when `compare` is nil), a bar of `value` and a 2 px white mark at `compare`, both on a scale of `max(value, compare) * 1.08`. Row pitch from the box height.
  - **Item level:** as the level columns in `UI/TabOverview.lua` (stacked class segments, tooltip `ILVL_TIP` with the classes, click → `ilvl`), one column per level from `min` to `max`, tick labels at multiples of five, `LEVEL_MAX` top right, and a 1 px gold line with `ILVL_READY` at `Census.READY_ILVL` when it lies inside the range. Empty: no columns, no line.
  - **Last online / Comings and goings:** the level view's two boxes, same data and clicks.
  - **Raids:** one block per raid: icon and name as `UI/TabFame.lua` draws a dungeon's, `RAIDS_NEW`, a bar with "n / readings", and one line `RAIDS_OPEN` + class-coloured names that fit + "+n" (or `RAIDS_OPEN_NONE`); click → `raidKill`.
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: endgame view of the overview tab`

### Task 9: Members tab — the three filters and the score column

**Files:**
- Modify: `UI/TabMembers.lua`, `UI/Options.lua` (the column in the members column choice), locale files (`COL_SCORE`)
- Test: `tests/smoke.lua`

**Interfaces:**
- Consumes: `ns.GameActivity.Get().byKey`, `ns.GameActivity.ScoreOf`, `Activity.Bucket`, `Stats.DungeonOf` / the raid's `stats`.
- Produces: filter keys `scoreBucket`, `ilvl`, `raidKill` in `view.filter`; column `score` in `COLUMNS` (`width = 40, desc = true`) and in `UI.MEMBER_COLUMNS` after `"ilvl"`.

- [ ] **Step 1: Write the failing smoke tests**: `SetFilter({ scoreBucket = 1 })` lists exactly the characters of the players in that bucket, sorted by score, highest first, and the summary line names the bar (`SCORE_1`); `scoreBucket = 5` lists the characters of players without a score; `SetFilter({ ilvl = 57, level = 60 })` lists the members whose item level floors to 57; `SetFilter({ raidKill = "onyxia" })` lists the members with that kill.
- [ ] **Step 2: Run** — expected: fail.
- [ ] **Step 3: Implement.** The score shows on the main's row (and on a character without family), empty on twinks. While `scoreBucket` is set the column is shown even when the user has not chosen it, and the list sorts by it. The three filters are cleared the way `level` and `bracket` are today.
- [ ] **Step 4: Run** tests and luacheck — `0 failed`, clean.
- [ ] **Step 5: Commit** `feat: members tab filters for activity, item level and raid kills`

### Task 10: Screenshot run, docs, final check

**Files:**
- Modify: `UI/Shots.lua`, `media/gallery/README.md`, `README.md`, `CHANGELOG.md`
- Test: `tests/smoke.lua`, `tests/test_shotsall.lua`

- [ ] **Step 1:** Add `{ "20-overview-endgame", … }` at the end of `UI.SHOTS`: selects the overview tab with the endgame view shown **without** storing `overviewPhase` (a session-only override the run clears when it ends), so a run leaves the setting as it was. Adjust the "19" in `media/gallery/README.md` and the smoke test's count to 20.
- [ ] **Step 2: Write the failing smoke test**: after a full `/guildy shots` run `settings.overviewPhase` is what it was before, for nil and for `"level"`.
- [ ] **Step 3: Implement**, run tests and luacheck — `0 failed`, clean.
- [ ] **Step 4:** `CHANGELOG.md` (unreleased): the endgame view, the activity score and what it counts, the days counter, `/guildy activity`. `README.md`: one row in the tab table, English and German part.
- [ ] **Step 5: Commit** `docs: endgame view in the screenshot run, changelog and README`
- [ ] **Step 6: Hand over to Sven for the in-game check** (the plan's executor cannot run the game): `/guildy shots all`, then look through `20-overview-endgame` in all six languages at 1130 × 560 for cut-off or overlapping text; `/guildy activity` for the real distribution; `Census.READY_ILVL = 56` confirmed or changed.
