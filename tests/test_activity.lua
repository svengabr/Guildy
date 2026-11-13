local T = ...
local ns = T.pureNs()
local A, Stats = ns.Activity, ns.Stats
local DAY = 86400
local date = function(fmt, ts) return os.date("!" .. fmt, ts) end
local NOV = os.time({ year = 2026, month = 11, day = 2, hour = 12 })
local OCT, NOW = NOV - 30 * DAY, NOV + 12 * DAY -- whole days apart, whatever the time zone does
local TODAY = A.Day(NOW)

T.describe("Activity days", function()
  T.it("finds the last day seen", function()
    T.eq(A.LastSeenDay(10 * DAY + 5, true, nil), 10)
    T.eq(A.LastSeenDay(10 * DAY + 5, false, 2.5), 7)
    T.eq(A.LastSeenDay(10 * DAY + 5, false, nil), nil) -- unknown last online: no day
  end)
  T.it("marks days and forgets old ones", function()
    local m = {}
    T.eq(A.MarkSeen(m, 100), true)
    T.eq(A.MarkSeen(m, 100), false)
    A.MarkSeen(m, 100 + A.DAYS_KEPT)
    T.eq(m.seen[100], nil)
    T.eq(m.seen[100 + A.DAYS_KEPT], true)
  end)
  T.it("replaces a broken list of days", function()
    local m = { seen = "x" }
    T.eq(A.MarkSeen(m, 7), true)
    T.eq(m.seen, { [7] = true })
  end)
  T.it("counts a day once over several characters", function()
    T.eq(A.SeenCount({ { [5] = true, [6] = true }, { [6] = true, [9] = true } }, 5, 8), 2)
    T.eq(A.SeenCount({}, 5, 8), 0)
  end)
end)

local function rates(t)
  local r = { span = 30, kills = 0, honorKills = 0, quests = 0, raidBosses = 0, dungeonBosses = 0, dungeons = 0, battlegrounds = 0 }
  for k, v in pairs(t) do r[k] = v end
  return r
end

T.describe("Activity score", function()
  T.it("puts the daily raider, dungeon runner and PvP player above 75", function()
    T.truthy(A.Score(rates({ kills = 700, quests = 5, raidBosses = 4, dungeonBosses = 2, dungeons = 2 }), 7) >= 75)
    T.truthy(A.Score(rates({ kills = 960, quests = 2, dungeonBosses = 12, dungeons = 12 }), 7) >= 75)
    T.truthy(A.Score(rates({ kills = 50, honorKills = 150, battlegrounds = 16 }), 7) >= 75)
  end)
  T.it("lets a daily solo player who quests a lot reach Very active without any group play", function()
    local score, parts = A.Score(rates({ kills = 1300, quests = 100 }), 7)
    T.truthy(score >= 75, tostring(score))
    T.eq(parts.group, nil)
  end)
  T.it("scores the same play time about the same, solo or in dungeons", function()
    -- about ten hours a week: questing (ten quests and 120 kills an hour) or dungeon runs (one an hour)
    local solo = A.Score(rates({ kills = 1200, quests = 100 }), 7)
    local group = A.Score(rates({ kills = 1000, dungeons = 10, dungeonBosses = 10 }), 7)
    T.truthy(math.abs(solo - group) <= 5, solo .. " vs " .. group)
    T.truthy(group >= 75, tostring(group))
  end)
  T.it("counts every source in one pot of units, and says how much each brought", function()
    local total, by = A.Units(rates({ kills = 100, honorKills = 5, quests = 1, dungeons = 1, dungeonBosses = 1,
      raidBosses = 1, battlegrounds = 1 }))
    local U = A.UNITS
    T.eq(by.kills, 100 * U.kills)
    T.eq(by.quests, U.quests)
    T.eq(by.raidBosses, U.raidBosses)
    local sum = 0
    for _, units in pairs(by) do sum = sum + units end
    T.truthy(math.abs(total - sum) < 1e-9, total .. " vs " .. sum)
  end)
  T.it("fills the playing part on one curve up to its max", function()
    local _, parts = A.Score(rates({ quests = A.K }), 7)
    T.truthy(math.abs(parts.playing - A.MAX.playing * (1 - math.exp(-1))) < 1e-9, tostring(parts.playing))
    T.eq(A.MAX.presence + A.MAX.playing, 100)
  end)
  T.it("puts the twice-a-week solo quester between 25 and 49", function()
    local score = A.Score(rates({ kills = 300, quests = 15 }), 2)
    T.truthy(score >= 25 and score <= 49, tostring(score))
  end)
  T.it("gives a real zero to somebody who did nothing", function()
    local score, parts = A.Score(rates({}), 0)
    T.eq(score, 0)
    T.eq(parts, { presence = 0, playing = 0 })
  end)
  T.it("scales the playing part up to 100 while days are not counted yet", function()
    local score, parts = A.Score(rates({ quests = 60 }), nil)
    T.eq(score, math.floor(parts.playing * 100 / A.MAX.playing + 0.5))
    local with = A.Score(rates({ kills = 960, dungeonBosses = 12, dungeons = 12 }), nil)
    T.truthy(with >= 75 and with <= 100, tostring(with))
  end)
  T.it("never goes above 100", function()
    T.eq(A.Score(rates({ kills = 1e6, quests = 1e4, raidBosses = 500 }), 7), 100)
    T.eq(A.Score(rates({ kills = 1e6, quests = 1e4, raidBosses = 500 }), nil), 100)
  end)
end)

T.describe("Activity rates", function()
  T.it("measures from the first reading of the previous month, per week", function()
    local rec = { ts = NOW, v = { [107] = 4100, [1098] = 6 }, months = {
      ["2026-10"] = { ts = OCT, v = { [107] = 100, [1098] = 0 } }, ["2026-11"] = { ts = NOV, v = { [107] = 2000 } } } }
    local r = A.Rates(rec, NOW, date)
    T.eq(r.span, 42)
    T.eq(math.floor(r.kills + 0.5), 667) -- 4000 in 6 weeks
    T.eq(r.raidBosses, 1)
    T.eq(r.fromDay, A.Day(OCT))
  end)
  T.it("has no rates without a usable snapshot", function()
    T.eq(A.Rates({ ts = NOW, v = { [107] = 5 } }, NOW, date), nil) -- no months
    T.eq(A.Rates({ ts = NOW, v = {}, months = {} }, NOW, date), nil)
    T.eq(A.Rates({ ts = NOV + DAY, v = {}, months = { ["2026-11"] = { ts = NOV, v = {} } } }, NOW, date), nil) -- 1 day
    T.eq(A.Rates({ ts = NOV, v = {}, months = { ["2026-11"] = { ts = NOV + 5 * DAY, v = {} } } }, NOW, date), nil) -- snapshot newer
    T.eq(A.Rates({ ts = NOW, v = {}, months = { ["2026-11"] = "x" } }, NOW, date), nil)
    T.eq(A.Rates(nil, NOW, date), nil)
  end)
  T.it("counts a statistic that went down as zero", function()
    local rec = { ts = NOW, v = { [107] = 50, [98] = 40 }, months = { ["2026-11"] = { ts = NOV, v = { [107] = 900, [98] = 12 } } } }
    local r = A.Rates(rec, NOW, date)
    T.eq(r.kills, 0)
    T.truthy(r.quests > 0)
  end)
  T.it("stretches the window to a later end: nothing happened after the last logout", function()
    local rec = { ts = NOV + 6 * DAY, v = { [107] = 1200 }, months = { ["2026-11"] = { ts = NOV, v = { [107] = 0 } } } }
    T.eq(math.floor(A.Rates(rec, NOW, date).kills + 0.5), 1400)     -- 1200 in 6 days
    T.eq(math.floor(A.Rates(rec, NOW, date, NOW).kills + 0.5), 700) -- 1200 in 12 days
  end)
  T.it("reads the growth of the days counter", function()
    local rec = { ts = NOW, v = { [Stats.DAYS] = 20 }, months = { ["2026-11"] = { ts = NOV, v = { [Stats.DAYS] = 14 } } } }
    T.eq(A.Rates(rec, NOW, date).ownDays, 6)
    rec.months["2026-11"].v = {}
    T.eq(A.Rates(rec, NOW, date).ownDays, nil) -- the counter is younger than the window
  end)
  T.it("knows a current reading", function()
    T.eq(A.IsCurrent({ ts = NOW - 3 * DAY }, { online = true }, NOW), true)
    T.eq(A.IsCurrent({ ts = NOW - 20 * DAY }, { online = false, daysOffline = 21 }, NOW), true) -- read on the last evening
    T.eq(A.IsCurrent({ ts = NOW - 20 * DAY }, { online = false, daysOffline = 2 }, NOW), false)
    T.eq(A.IsCurrent({ ts = NOW - 20 * DAY }, { online = false }, NOW), false) -- unknown last online
    T.eq(A.IsCurrent(nil, { online = true }, NOW), false)
  end)
end)

T.describe("Activity players", function()
  local function runner(ts)
    return { ts = ts or NOW, v = { [107] = 2000, [932] = 20, [1095] = 20 }, months = { ["2026-11"] = { ts = NOV, v = { [107] = 1 } } } }
  end
  local function world()
    local members = { { key = "a", online = true, level = 60 }, { key = "b", online = false, daysOffline = 20 }, { key = "c", online = true } }
    local records = { a = { stats = runner() }, b = { stats = runner(NOW - 25 * DAY) } }
    return members, records, function(m) return records[m.key] end
  end

  T.it("makes one player of a main and its twinks", function()
    local members, records, recordOf = world()
    local players, byKey = A.Players(members, { a = "a", b = "a" }, recordOf, NOW, date, nil)
    T.eq(#players, 2)
    T.truthy(byKey.a == byKey.b)
    T.eq(#byKey.a.chars, 2)
    T.eq(byKey.a.score, (A.Score(A.Rates(records.a.stats, NOW, date), nil)))
    T.eq(byKey.c.score, nil) -- no record at all
  end)
  T.it("has no score when the character played last has no current reading", function()
    local members, _, recordOf = world()
    members[1].online, members[1].daysOffline = false, 5
    members[2].online, members[2].daysOffline = true, nil
    local _, byKey = A.Players(members, { a = "a", b = "a" }, recordOf, NOW, date, nil)
    T.eq(byKey.a.score, nil)
  end)
  T.it("adds the rates of the characters before the curves", function()
    local members, records, recordOf = world()
    members[2].daysOffline = 1
    records.b.stats = runner()
    local _, byKey = A.Players(members, { a = "a", b = "a" }, recordOf, NOW, date, nil)
    local sum = A.AddRates(A.Rates(records.a.stats, NOW, date), A.Rates(records.b.stats, NOW, date))
    T.eq(byKey.a.score, (A.Score(sum, nil)))
  end)
  T.it("rates presence over the days counted so far, a day once per player", function()
    local members, records, recordOf = world()
    records.a.seen = { [TODAY] = true, [TODAY - 1] = true, [TODAY - 2] = true }
    records.b.seen = { [TODAY - 2] = true, [TODAY - 5] = true }
    local _, byKey = A.Players(members, { a = "a", b = "a" }, recordOf, NOW, date, TODAY - 9)
    T.eq(byKey.a.score, (A.Score(A.Rates(records.a.stats, NOW, date), 4 / 10 * 7)))
  end)
  T.it("leaves presence out until a week of days is counted", function()
    local members, records, recordOf = world()
    records.a.seen = { [TODAY] = true }
    local _, byKey = A.Players(members, {}, recordOf, NOW, date, TODAY - 3)
    T.eq(byKey.a.score, (A.Score(A.Rates(records.a.stats, NOW, date), nil)))
  end)
  T.it("takes the own days counter of a member when it says more", function()
    local members, records, recordOf = world()
    records.a.stats.v[Stats.DAYS], records.a.stats.months["2026-11"].v[Stats.DAYS] = 20, 14
    local _, byKey = A.Players(members, {}, recordOf, NOW, date, nil)
    T.eq(byKey.a.score, (A.Score(A.Rates(records.a.stats, NOW, date), 6 / 12 * 7)))
  end)
  T.it("sorts scores into the five bars", function()
    local expect = { [100] = 1, [75] = 1, [74] = 2, [50] = 2, [49] = 3, [25] = 3, [24] = 4, [0] = 4 }
    for score, bucket in pairs(expect) do T.eq(A.Bucket(score), bucket, tostring(score)) end
    T.eq(A.Bucket(nil), 5)
  end)
  T.it("sums up a guild, also one without any score", function()
    T.eq(A.Summary({}), { buckets = { 0, 0, 0, 0, 0 }, scored = 0 })
    local s = A.Summary({ { score = 80 }, { score = 60 }, {} })
    T.eq(s.buckets, { 1, 1, 0, 0, 1 })
    T.eq(s.pulse, 70)
    T.eq(s.scored, 2)
    T.eq(s.median, 70)
  end)
  T.it("keeps the pulse of a few months and compares with the last", function()
    local guild = {}
    T.eq(A.PulseChange(guild, 74, "2026-11"), nil)
    for month = 7, 11 do A.StorePulse(guild, string.format("2026-%02d", month), 60 + month) end
    A.StorePulse(guild, "2026-12", nil)
    local kept = 0
    for _ in pairs(guild.pulse) do kept = kept + 1 end
    T.eq(kept, A.PULSES_KEPT)
    T.eq(guild.pulse["2026-07"], nil)
    T.eq(A.PulseChange(guild, 74, "2026-11"), 3)
  end)
end)

T.describe("Activity month", function()
  Stats.LAUNCH_MONTH = "2026-01" -- ordinary months here
  local TENTH = os.time({ year = 2026, month = 11, day = 10, hour = 12 })
  local FIRST, BEFORE = TENTH - 9 * DAY, TENTH - 35 * DAY
  local function row(rows, id)
    for _, r in ipairs(rows) do
      if r.id == id then return r end
    end
  end
  T.it("has the six rows in order", function()
    local rows = A.Month({}, {}, function() end, TENTH, date, nil)
    local ids = {}
    for i, r in ipairs(rows) do ids[i] = r.id end
    T.eq(ids, A.MONTH_ROWS)
    T.eq(row(rows, 98).value, 0)
    T.eq(row(rows, 98).compare, nil)
    T.eq(row(rows, "days").value, 0)
  end)
  T.it("compares with last month up to the same day", function()
    local full = { rec = { ts = TENTH, v = { [98] = 70 }, months = {
      ["2026-10"] = { ts = BEFORE, v = { [98] = 10 } }, ["2026-11"] = { ts = FIRST, v = { [98] = 40 } } } } }
    local fresh = { rec = { ts = TENTH, v = { [98] = 500 }, months = {} } } -- no start value: left out
    local r = row(A.Month({ full, fresh }, {}, function() end, TENTH, date, nil), 98)
    T.eq(r.value, 30)
    T.eq(r.last, 30)
    T.eq(r.compare, 10) -- day 10 of 30
  end)
  T.it("averages the days online per player", function()
    local today = A.Day(TENTH)
    local records = { a = { seen = { [today] = true, [today - 1] = true, [today - 20] = true } }, b = { seen = { [today - 1] = true } },
      c = { seen = { [today - 2] = true } } }
    local players = { { chars = { { key = "a" }, { key = "b" } } }, { chars = { { key = "c" } } }, { chars = { { key = "d" } } } }
    local recordOf = function(m) return records[m.key] end
    local r = row(A.Month({}, players, recordOf, TENTH, date, today - 5), "days")
    T.eq(r.value, 1.5)   -- 2 and 1 days; the player never seen is left out
    T.eq(r.last, nil)    -- counting began this month
    r = row(A.Month({}, players, recordOf, TENTH, date, today - 50), "days")
    T.eq(r.last, 0.5)    -- one day of one of two players
  end)
end)

T.describe("Activity after the review", function()
  local function record(ts)
    return { stats = { ts = ts, v = { [107] = 4000, [932] = 60, [1095] = 60 },
      months = { ["2026-10"] = { ts = math.min(NOW - 40 * DAY, ts - 20 * DAY), v = { [107] = 1 } } } } }
  end
  local function score(member, ts)
    local rec = record(ts)
    local _, byKey = A.Players({ member }, {}, function() return rec end, NOW, date, nil)
    return byKey[member.key].score
  end

  T.it("lets the score of a player who stopped fall off, down to zero at a month", function()
    local fresh = score({ key = "a", online = true }, NOW)
    T.truthy(fresh >= 60, tostring(fresh))
    T.truthy(score({ key = "a", online = false, daysOffline = 2 }, NOW - 2 * DAY) >= fresh - 5, "two days away change little")
    local two = score({ key = "a", online = false, daysOffline = 14 }, NOW - 14 * DAY)
    T.truthy(two <= fresh * 0.6, two .. " of " .. fresh)
    T.truthy(two > 0)
    T.truthy(score({ key = "a", online = false, daysOffline = 29.5 }, NOW - 29.5 * DAY) <= 3)
    T.eq(score({ key = "a", online = false, daysOffline = 45 }, NOW - 45 * DAY), 0)
  end)
  T.it("has no score for a member gone long of whom nothing was ever read", function()
    local _, byKey = A.Players({ { key = "z", online = false, daysOffline = 45 } }, {}, function() end, NOW, date, nil)
    T.eq(byKey.z.score, nil)
  end)
  T.it("falls back to an older snapshot when the last two months have none", function()
    local rec = { ts = NOW - 20 * DAY, v = { [107] = 900 }, months = { ["2026-08"] = { ts = NOW - 80 * DAY, v = { [107] = 300 } } } }
    local r = A.Rates(rec, NOW, date)
    T.truthy(r and r.kills > 0)
    T.eq(r.span, 60)
  end)
  T.it("counts the days of a player once, also from the own counters of two characters", function()
    local function own(days)
      return { stats = { ts = NOW, v = { [107] = 500, [Stats.DAYS] = 20 + days },
        months = { ["2026-11"] = { ts = NOV, v = { [107] = 1, [Stats.DAYS] = 20 } } } } }
    end
    local records = { a = own(6), b = own(5) }
    local members = { { key = "a", online = true }, { key = "b", online = false, daysOffline = 1 } }
    local _, byKey = A.Players(members, { a = "a", b = "a" }, function(m) return records[m.key] end, NOW, date, nil)
    local sum = A.AddRates(A.Rates(records.a.stats, NOW, date), A.Rates(records.b.stats, NOW, date))
    T.eq(byKey.a.score, (A.Score(sum, 6 / 12 * 7))) -- the larger of the two, not 11 days
  end)
  T.it("starts the day where the game layer says, not at midnight UTC", function()
    T.eq(A.Day(10 * DAY - 3600), 9)
    A.SetDayShift(2 * 3600)
    T.eq(A.Day(10 * DAY - 3600), 10)
    A.SetDayShift(0)
  end)
  T.it("marks no day from a last online too vague or too close to the change of day", function()
    T.eq(A.LastSeenDay(10 * DAY + 600, false, 0), 9)   -- whole hours: the logout was up to an hour before
    T.eq(A.LastSeenDay(40 * DAY, false, 27), 12)
    T.eq(A.LastSeenDay(40 * DAY, false, 28), nil)      -- months count as 30 days from here on
  end)
end)

T.describe("Activity and readings from the Battle.net sync", function()
  T.it("takes a reading stamped with the last login as the state at the last logout", function()
    -- tools/bnet-sync stamps a reading with the last login, hours before the logout the roster reports
    T.eq(A.IsCurrent({ ts = NOW - 20 * DAY - 5 * 3600 }, { online = false, daysOffline = 20 }, NOW), true)
    T.eq(A.IsCurrent({ ts = NOW - 22 * DAY }, { online = false, daysOffline = 20 }, NOW), false)
  end)
end)

T.describe("Activity score detail", function()
  local function runner(ts)
    return { ts = ts or NOW, v = { [107] = 2000, [932] = 20, [1095] = 20, [98] = 30 }, months = { ["2026-11"] = { ts = NOV, v = { [107] = 1 } } } }
  end
  local function world()
    local members = { { key = "a", online = true, level = 60 }, { key = "b", online = false, daysOffline = 1 } }
    local records = { a = { stats = runner() }, b = { stats = runner() } }
    return members, records, function(m) return records[m.key] end
  end

  T.it("keeps the characters, their summed rates and the lead's window", function()
    local members, records, recordOf = world()
    local _, byKey = A.Players(members, { a = "a", b = "a" }, recordOf, NOW, date, nil)
    local detail = byKey.a.detail
    T.eq(detail.chars, { "a", "b" })
    local ra, rb = A.Rates(records.a.stats, NOW, date), A.Rates(records.b.stats, NOW, date)
    T.eq(detail.rates.kills, ra.kills + rb.kills)
    T.eq(detail.rates.quests, ra.quests + rb.quests)
    T.eq(detail.fromDay, ra.fromDay)
    T.eq(detail.toDay, ra.toDay)
    T.eq(detail.fade, nil)
    T.eq(detail.away, nil)
  end)

  T.it("keeps the units each source brought, for each source's share", function()
    local members, _, recordOf = world()
    local _, byKey = A.Players(members, { a = "a", b = "a" }, recordOf, NOW, date, nil)
    local detail = byKey.a.detail
    local _, by = A.Units(detail.rates)
    T.eq(detail.units, by)
    T.truthy(detail.units.dungeonBosses > 0 and detail.units.raidBosses == 0, "dungeon bosses brought units")
  end)

  T.it("says when presence is not counted yet and how many days it counted", function()
    local members, records, recordOf = world()
    records.a.seen = { [TODAY] = true, [TODAY - 1] = true, [TODAY - 2] = true }
    local _, byKey = A.Players(members, {}, recordOf, NOW, date, TODAY - 3)
    T.eq(byKey.a.detail.presence, nil)
    T.eq(byKey.a.detail.scaled, true)
    _, byKey = A.Players(members, {}, recordOf, NOW, date, TODAY - 9)
    T.eq(byKey.a.detail.presence, 3 * 7 / 10)
    T.eq(byKey.a.detail.scaled, false)
  end)

  T.it("keeps the fade factor and the days away", function()
    local members, records, recordOf = world()
    members[1].online, members[1].daysOffline = false, 10
    members[2] = nil
    records.a.stats = runner(NOW - 10 * DAY)
    records.a.stats.months["2026-11"].ts = NOV - DAY -- a window of three days before the last logout
    local _, byKey = A.Players(members, {}, recordOf, NOW, date, nil)
    local detail = byKey.a.detail
    T.eq(detail.away, 10)
    T.truthy(math.abs(detail.fade - (1 - (10 - 3) / (30 - 3))) < 1e-9, tostring(detail.fade))
    local unfaded = A.Score(A.Rates(records.a.stats, NOW, date, NOW), nil)
    T.eq(byKey.a.score, math.floor(unfaded * detail.fade + 0.5))
  end)

  T.it("leaves out a twink without a current reading", function()
    local members, records, recordOf = world()
    members[2].daysOffline = 20
    records.b.stats = runner(NOW - 25 * DAY)
    local _, byKey = A.Players(members, { a = "a", b = "a" }, recordOf, NOW, date, nil)
    T.eq(byKey.a.detail.chars, { "a" })
  end)

  T.it("has no detail without a score", function()
    local members, records, recordOf = world()
    records.a.stats = nil
    local _, byKey = A.Players(members, {}, recordOf, NOW, date, nil)
    T.eq(byKey.a.score, nil)
    T.eq(byKey.a.detail, nil)
  end)

  T.it("gives a time on the day for a date", function()
    T.eq(A.Day(A.DayTime(A.Day(NOW))), A.Day(NOW))
  end)
end)
