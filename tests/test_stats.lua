local T = ...
local ns = T.pureNs()
local Stats = ns.Stats
Stats.LAUNCH_MONTH = "2026-01" -- these tests use ordinary months; the launch month has its own test

-- fixed calendar: ts in days since 2026-01-01, any day >= 304 is November, >= 273 October
local function date(fmt, ts)
  assert(fmt == "%Y-%m")
  local day = math.floor(ts / 86400)
  if day >= 304 then return "2026-11" end
  if day >= 273 then return "2026-10" end
  return "2026-09"
end
local OCT, NOV = 280 * 86400, 310 * 86400

T.describe("Stats.Parse", function()
  T.it("reads plain numbers and counts with text", function()
    T.eq(Stats.Parse("1298"), 1298)
    T.eq(Stats.Parse("672 (Humanoid)"), 672)
    T.eq(Stats.Parse("1.298"), 1298)
    T.eq(Stats.Parse(42), 42)
  end)
  T.it("treats -- and nil as zero", function()
    T.eq(Stats.Parse("--"), 0)
    T.eq(Stats.Parse(nil), 0)
  end)
  T.it("reads money in copper", function()
    local gold = "6|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 88|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t "
      .. "93|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
    T.eq(Stats.Parse(gold), 68893)
    T.eq(Stats.Parse("30|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"), 30)
  end)
end)

T.describe("Stats months", function()
  T.it("steps back a month", function()
    T.eq(Stats.PreviousMonth("2026-11"), "2026-10")
    T.eq(Stats.PreviousMonth("2026-01"), "2025-12")
  end)
  T.it("keeps the first values of each month and computes growth", function()
    local member = {}
    Stats.Update(member, { [107] = 100 }, OCT, "self", date)
    Stats.Update(member, { [107] = 150 }, OCT + 86400, "self", date)
    Stats.Update(member, { [107] = 300 }, NOV, "self", date)
    Stats.Update(member, { [107] = 340 }, NOV + 86400, "self", date)
    T.eq(member.stats.months["2026-10"].v[107], 100)
    T.eq(member.stats.months["2026-11"].v[107], 300)
    T.eq(Stats.Value(member.stats, 107, "all", NOV + 86400, date), 340)
    T.eq(Stats.Value(member.stats, 107, "month", NOV + 86400, date), 40)
    T.eq(Stats.Value(member.stats, 107, "last", NOV + 86400, date), 200)
  end)
  T.it("counts the launch month from zero, equipment from the first reading", function()
    Stats.LAUNCH_MONTH = "2026-10"
    local member = {}
    Stats.Update(member, { [107] = 100, [Stats.GEAR.ILVL] = 200, [Stats.GEAR.COUNT] = 15 }, OCT, "self", date)
    Stats.Update(member, { [107] = 150, [Stats.GEAR.ILVL] = 210, [Stats.GEAR.COUNT] = 15 }, OCT + 86400, "self", date)
    T.eq(Stats.Value(member.stats, 107, "month", OCT + 86400, date), 150)
    T.eq(Stats.Value(member.stats, Stats.GEAR.ILVL, "month", OCT + 86400, date), 10)
    Stats.Update(member, { [107] = 300 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, 107, "last", NOV, date), 300) -- all of October, from 0
    Stats.LAUNCH_MONTH = "2026-01"
  end)
  T.it("has no last month without both snapshots", function()
    local member = {}
    Stats.Update(member, { [107] = 300 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, 107, "last", NOV, date), nil)
  end)
  T.it("sums end boss kills", function()
    local member = {}
    Stats.Update(member, { [63570] = 2, [15027] = 1 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, "bosses", "all", NOV, date), 3)
  end)
end)

T.describe("Stats merge", function()
  T.it("validates and merges newer values and earlier month snapshots", function()
    local member = {}
    Stats.Update(member, { [107] = 300 }, NOV + 86400, "seen", date)
    local wire = Stats.Wire({ ts = NOV + 2 * 86400, src = "self", v = { [107] = 320, [999999] = 5 },
      months = { ["2026-11"] = { ts = NOV, v = { [107] = 290 } }, ["2026-10"] = { ts = OCT, v = { [107] = 100 } } } })
    local rec = Stats.Validate(wire)
    T.truthy(rec)
    T.eq(rec.v[999999], 5) -- statistics outside the catalog are kept for later
    T.truthy(Stats.Merge(member, rec))
    T.eq(member.stats.v[107], 320)
    T.eq(member.stats.months["2026-11"].v[107], 290)
    T.eq(member.stats.months["2026-10"].v[107], 100)
  end)
  T.it("keeps newer own data", function()
    local member = {}
    Stats.Update(member, { [107] = 500 }, NOV + 5 * 86400, "self", date)
    local rec = Stats.Validate({ ts = NOV, src = "relay", v = { ["107"] = 1 } })
    Stats.Merge(member, rec)
    T.eq(member.stats.v[107], 500)
  end)
  T.it("rejects broken records", function()
    T.eq(Stats.Validate(nil), nil)
    T.eq(Stats.Validate({ ts = "x", v = {} }), nil)
    T.eq(Stats.Validate({ ts = 1, v = { ["107"] = -5 } }).v[107], nil)
  end)
end)

T.describe("Stats ranking", function()
  T.it("sorts by value and skips members without statistics", function()
    local a, b, c = {}, {}, {}
    Stats.Update(a, { [98] = 10 }, NOV, "self", date)
    Stats.Update(b, { [98] = 30 }, NOV, "self", date)
    local ranking = Stats.Ranking({ { key = "a", name = "A", rec = a.stats }, { key = "b", name = "B", rec = b.stats },
      { key = "c", name = "C", rec = c.stats } }, 98, "all", NOV, date)
    T.eq(#ranking, 2)
    T.eq(ranking[1].name, "B")
    T.eq(Stats.Total(ranking), 40)
  end)
end)

T.describe("Stats pages and gear", function()
  local G = Stats.GEAR
  T.it("reads the equipment: average item level, qualities, waits for item info", function()
    local items = { [1] = "head", [5] = "chest", [16] = "sword" }
    local info = { head = { 2, 30 }, chest = { 3, 34 }, sword = { 4, 41 } }
    local function link(slot) return items[slot] end
    local function get(l) local i = info[l] return "n", l, i[1], i[2] end
    local gear = Stats.ReadGear(link, get)
    T.eq(gear[G.ILVL], 350)
    T.eq(gear[G.EPIC], 1)
    T.eq(gear[G.RARE], 1)
    T.eq(gear[G.UNCOMMON], 1)
    T.eq(gear[G.COUNT], 3)
    info.chest = {}
    T.eq(Stats.ReadGear(link, function(l) local i = info[l] return "n", l, i[1], i[2] end), nil)
    T.eq(next(Stats.ReadGear(function() end, get)), nil)
  end)
  T.it("counts white and grey items and empty slots, not the off hand next to a two-hander", function()
    local items = { [1] = "hat", [5] = "rag", [16] = "staff" }
    local info = { hat = { 1, 5 }, rag = { 0, 3 }, staff = { 2, 10, "INVTYPE_2HWEAPON" } }
    local function link(slot) return items[slot] end
    local function get(l) local i = info[l] return "n", l, i[1], i[2], nil, nil, nil, nil, i[3] end
    local gear = Stats.ReadGear(link, get)
    T.eq(gear[G.COMMON], 1)
    T.eq(gear[G.POOR], 1)
    T.eq(gear[G.UNCOMMON], 1)
    T.eq(gear[G.EMPTY], #Stats.GEAR_SLOTS - 4) -- 3 items, off hand taken by the staff
    info.hat = { 5, 60 }
    T.eq(Stats.ReadGear(link, get)[G.LEGENDARY], 1)
    T.eq(gear[Stats.GEAR_SLOT_BASE + 5], 1) -- grey chest
    T.eq(gear[Stats.GEAR_SLOT_BASE + 17], Stats.SLOT_TWO_HANDED)
    local groups = Stats.GearSlots(gear)
    T.eq(groups[1][1], 2) -- head first, white
    T.eq(groups[1][2], false) -- neck empty
    T.eq(groups[3][1], 3) -- main hand, green
    info.staff[3] = "INVTYPE_WEAPON"
    T.eq(Stats.ReadGear(link, get)[G.EMPTY], #Stats.GEAR_SLOTS - 3)
    T.eq(Stats.ReadGear(link, get)[Stats.GEAR_SLOT_BASE + 17], nil)
    T.eq(Stats.GearSlots({ [G.COUNT] = 3 }), nil) -- older reading
  end)
  T.it("keeps the last equipment when a reading has none", function()
    local member = {}
    Stats.Update(member, { [107] = 10, [G.ILVL] = 380, [G.COUNT] = 15 }, NOV, "self", date)
    Stats.Update(member, { [107] = 20 }, NOV + 60, "seen", date)
    T.eq(member.stats.v[107], 20)
    T.eq(member.stats.v[G.ILVL], 380)
    Stats.Merge(member, Stats.Validate({ ts = NOV + 120, src = "relay", v = { ["107"] = 30 } }))
    T.eq(member.stats.v[G.ILVL], 380)
    Stats.Update(member, { [107] = 40, [G.ILVL] = 400, [G.COUNT] = 15 }, NOV + 180, "self", date)
    T.eq(member.stats.v[G.ILVL], 400)
  end)
  T.it("drops equipment without an item count (incomplete reads of older versions)", function()
    local member = { stats = { ts = NOV, src = "seen", v = { [107] = 5, [G.ILVL] = 290, [G.RARE] = 1 },
      months = { ["2026-11"] = { ts = NOV, v = { [107] = 5, [G.ILVL] = 290 } } } } }
    Stats.CleanRecord(member.stats)
    T.eq(member.stats.v[G.ILVL], nil)
    T.eq(member.stats.v[G.RARE], nil)
    T.eq(member.stats.v[107], 5)
    T.eq(member.stats.months["2026-11"].v[G.ILVL], nil)
    local rec = Stats.Validate({ ts = NOV, src = "seen", v = { ["107"] = 5, [tostring(G.ILVL)] = 290 } })
    T.eq(rec.v[G.ILVL], nil)
    rec = Stats.Validate({ ts = NOV, src = "seen", v = { [tostring(G.ILVL)] = 290, [tostring(G.COUNT)] = 14 } })
    T.eq(rec.v[G.ILVL], 290)
    -- a member's own equipment was always complete: kept without a count
    rec = Stats.Validate({ ts = NOV, src = "self", v = { [tostring(G.ILVL)] = 290 } })
    T.eq(rec.v[G.ILVL], 290)
    local own = { ts = NOV, src = "relay", v = { [G.ILVL] = 310 }, months = {} }
    Stats.CleanRecord(own)
    T.eq(own.v[G.ILVL], 310)
  end)
  T.it("counts equipment growth from the first equipment seen in the month", function()
    local member = {}
    Stats.Update(member, { [107] = 10 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, G.ILVL, "month", NOV, date), nil)
    Stats.Update(member, { [107] = 11, [G.ILVL] = 228, [G.COUNT] = 15 }, NOV + 60, "self", date)
    T.eq(Stats.Value(member.stats, G.ILVL, "month", NOV + 60, date), 0)
    Stats.Update(member, { [107] = 12, [G.ILVL] = 240, [G.COUNT] = 15 }, NOV + 120, "self", date)
    T.eq(Stats.Value(member.stats, G.ILVL, "month", NOV + 120, date), 12)
    T.eq(member.stats.months["2026-11"].v[107], 10)
  end)
  T.it("never asks the game for equipment", function()
    T.eq(Stats.Wanted()[G.ILVL], nil)
    T.truthy(Stats.Wanted()[339])
  end)
  T.it("sums spending and counts cleared dungeons", function()
    local member = {}
    Stats.Update(member, { [1146] = 500, [1148] = 30, [63570] = 3, [15027] = 1 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, "spent", "all", NOV, date), 530)
    T.eq(Stats.Value(member.stats, "dungeons", "all", NOV, date), 2)
    T.eq(Stats.Value(member.stats, "bosses", "all", NOV, date), 4)
  end)
  T.it("counts a dungeon with two end bosses once", function()
    local member = {}
    Stats.Update(member, { [63572] = 1, [63589] = 2, [1093] = 1 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, "dungeons", "all", NOV, date), 2)
    T.eq(Stats.Value(member.stats, "bosses", "all", NOV, date), 4)
  end)
  T.it("orders the dungeons by level and covers every boss statistic", function()
    local covered, lastMin, raids = {}, 0, false
    for _, d in ipairs(Stats.DUNGEONS) do
      if d.raid then raids = true else
        T.eq(raids, false)
        T.truthy(d.min >= lastMin)
        lastMin = d.min
      end
      for _, id in ipairs(d.stats) do covered[id] = true end
    end
    for _, id in ipairs(Stats.Bosses()) do T.truthy(covered[id]) end
    T.eq(Stats.DungeonOf(63589).key, "dalaran")
    T.eq(Stats.DungeonOf(15027).key, "ragefire")
  end)
  T.it("counts the Alliance's Hall of Thanes from Blizzard's Ragefire statistic", function()
    Stats.SetFaction("Alliance")
    local keys = {}
    for _, d in ipairs(Stats.DUNGEONS) do keys[d.key] = d end
    T.eq(#keys.ragefire.stats, 0)
    T.eq(keys.ragefire.lost, true)
    T.eq(#Stats.DUNGEONS, #Stats.ALL_DUNGEONS)
    T.eq(keys.thanes.stats[1], 15027)
    T.eq(keys.thanes.nameStat, 63573)
    T.eq(Stats.DungeonOf(15027).key, "thanes")
    local member = {}
    Stats.Update(member, { [15027] = 2, [63573] = 1, [63570] = 1 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, "dungeons", "all", NOV, date), 2)
    Stats.SetFaction("Horde")
    T.eq(Stats.DungeonOf(15027).key, "ragefire")
    T.eq(#Stats.DUNGEONS, #Stats.ALL_DUNGEONS)
    Stats.SetFaction(nil)
  end)
  T.it("shortens kill counts to at most two digits", function()
    T.eq(Stats.ShortCount(1), "")
    T.eq(Stats.ShortCount(nil), "")
    T.eq(Stats.ShortCount(2), "2")
    T.eq(Stats.ShortCount(99), "99")
    T.eq(Stats.ShortCount(100), "99+")
    T.eq(Stats.ShortCount(412), "99+")
  end)
  T.it("splits the dungeons into level bands, raids last", function()
    local bands, count = Stats.DungeonBands(), 0
    T.eq(#bands, 4)
    T.eq(bands[1].min, 13)
    T.eq(bands[1].max, 33)
    T.eq(bands[1].dungeons[#bands[1].dungeons].key, "dalaran")
    T.eq(bands[2].dungeons[1].key, "gnomeregan")
    T.eq(bands[3].max, 60)
    T.eq(bands[4].raid, true)
    T.eq(#bands[4].dungeons, 3)
    for _, band in ipairs(bands) do count = count + #band.dungeons end
    T.eq(count, #Stats.DUNGEONS)
  end)
  T.it("splits the reputation statistics into standings", function()
    local t = Stats.RepTiers({ [931] = 10, [1466] = 6, [529] = 3, [378] = 1 })
    T.eq(t.exalted, 0)
    T.eq(t.revered, 1)
    T.eq(t.honored, 2)
    T.eq(t.friendly, 3)
  end)
  T.it("rates equipment against the level", function()
    T.eq(Stats.GearRating(42, 42), "good")
    T.eq(Stats.GearRating(38, 42), "ok")
    T.eq(Stats.GearRating(30, 42), "behind")
    T.eq(Stats.GearRating(3, 5), "ok")
  end)
end)

T.describe("Stats tiles", function()
  local general = Stats.PAGES[1]
  T.it("offers the headline first, then the title cards' statistics without states", function()
    local choices = Stats.TileChoices(general)
    for i, id in ipairs(general.headline) do T.eq(choices[i], id) end
    local seen = {}
    for _, id in ipairs(choices) do
      T.eq(seen[id], nil)
      seen[id] = true
    end
    T.truthy(seen[347], "food from the title cards")
    T.eq(seen[Stats.GEAR.ILVL], nil) -- a guild total of item levels says nothing
  end)
  T.it("keeps the default without a valid choice", function()
    T.eq(Stats.Headline(general), general.headline)
    T.eq(Stats.Headline(general, {}), general.headline)
    T.eq(Stats.Headline(general, { 999999 }), general.headline)
  end)
  T.it("offers the other pages' statistics after the page's own", function()
    local choices = Stats.TileChoices(general)
    local at = {}
    for i, id in ipairs(choices) do at[id] = i end
    T.truthy(at[328], "gold from the economy page")
    T.truthy(at[328] > at[347], "after the page's own")
  end)
  T.it("offers every tracked statistic, the end boss kills too, but no worn-item states", function()
    local at = {}
    for i, id in ipairs(Stats.TileChoices(general)) do at[id] = i end
    for _, category in ipairs(Stats.CATALOG) do
      for _, id in ipairs(category.stats) do
        if category.isLocal then T.eq(at[id], nil) else T.truthy(at[id], "statistic " .. tostring(id)) end
      end
    end
    T.truthy(at[108] > at[328], "a statistic of no page after the pages' own")
    T.eq(Stats.Headline(general, { 108, 94 }), { 108, 94 })
  end)
  T.it("shows the chosen title cards in the chosen order, also another page's, at most MAX_CARDS", function()
    T.eq(Stats.Titles(general), general.titles)
    T.eq(Stats.Titles(general, { "NOPE" }), general.titles)
    local list = Stats.Titles(general, { "GOLD", "SLAYER", "GOLD" })
    T.eq(#list, 2)
    T.eq(list[1].key, "GOLD")
    T.eq(list[2].stat, 107)
    local all = {}
    for i, fame in ipairs(Stats.TitleChoices(general)) do all[i] = fame.key end
    T.eq(#Stats.Titles(general, all), Stats.MAX_CARDS)
  end)
  T.it("shows the chosen statistics in the chosen order, each once, at most MAX_TILES", function()
    T.eq(Stats.Headline(general, { 347, 107, 347 }), { 347, 107 })
    T.eq(#Stats.Headline(general, Stats.TileChoices(general)), Stats.MAX_TILES)
  end)
end)
