local T = ...
local ns = T.pureNs()
local Census = ns.Census

T.describe("Census", function()
  T.it("brackets levels", function()
    T.eq(Census.Bracket(1), 1)
    T.eq(Census.Bracket(9), 1)
    T.eq(Census.Bracket(10), 2)
    T.eq(Census.Bracket(59), 6)
    T.eq(Census.Bracket(60), 6)
    T.eq(Census.Bracket(nil), 1)
    T.eq(Census.BracketLabel(1), "1-9")
    T.eq(Census.BracketLabel(2), "10-19")
    T.eq(Census.BracketLabel(6), "50-60")
  end)

  T.it("converts last online", function()
    T.eq(Census.DaysOffline(nil, nil, nil, nil), nil)
    T.eq(Census.DaysOffline(0, 1, 2, 12), 32.5)
  end)

  T.it("decides activity", function()
    T.eq(Census.IsActive({ online = true }, 30), true)
    T.eq(Census.IsActive({ online = false }, 30), false)
    T.eq(Census.IsActive({ online = false }, false), true)
    T.eq(Census.IsActive({ online = false, daysOffline = 29.9 }, 30), true)
    T.eq(Census.IsActive({ online = false, daysOffline = 30.5 }, 30), false)
  end)

  T.it("handles an empty roster", function()
    local r = Census.Compute({}, 30)
    T.eq(r.total, 0)
    T.eq(r.active, 0)
    T.eq(r.avgLevel, 0)
    T.eq(r.brackets, { 0, 0, 0, 0, 0, 0 })
  end)

  T.it("counts only active members", function()
    local members = {
      { level = 16, classFile = "DRUID", online = true, joinedDaysAgo = 2 },
      { level = 22, classFile = "PALADIN", online = false, daysOffline = 3 },
      { level = 40, classFile = "PALADIN", online = false, daysOffline = 200 },
    }
    local profs = { [members[1]] = { [182] = true, [171] = true } }
    local r = Census.Compute(members, 30, function(m) return profs[m] end)
    T.eq(r.total, 3)
    T.eq(r.active, 2)
    T.eq(r.online, 1)
    T.eq(r.avgLevel, 19)
    T.eq(r.classes, { DRUID = 1, PALADIN = 1 })
    T.eq(r.brackets, { 0, 1, 1, 0, 0, 0 })
    T.eq(r.professions, { [182] = 1, [171] = 1 })
    T.eq(r.withProfessions, 1)
    T.eq(r.newCount, 1)
    T.eq(Census.Compute(members, false).active, 3)
  end)

  T.it("sorts counts", function()
    T.eq(Census.Sorted({ A = 1, B = 3, C = 1 }), { { key = "B", count = 3 }, { key = "A", count = 1 }, { key = "C", count = 1 } })
  end)
  T.it("buckets activity over all members", function()
    T.eq(Census.ActivityBucket({ online = true }), 1)
    T.eq(Census.ActivityBucket({ daysOffline = 0.5 }), 1)
    T.eq(Census.ActivityBucket({ daysOffline = 3 }), 2)
    T.eq(Census.ActivityBucket({ daysOffline = 20 }), 3)
    T.eq(Census.ActivityBucket({ daysOffline = 60 }), 4)
    T.eq(Census.ActivityBucket({ daysOffline = 400 }), 5)
    T.eq(Census.ActivityBucket({}), 5)
    local members = {
      { level = 16, classFile = "DRUID", online = true },
      { level = 12, classFile = "DRUID", daysOffline = 3 },
      { level = 40, classFile = "PALADIN", daysOffline = 200 },
    }
    local ranks = { [members[1]] = { [171] = 120 }, [members[2]] = { [171] = 225, [182] = 50 } }
    local r = Census.Compute(members, 30, nil, function(m) return ranks[m] end)
    T.eq(r.activity, { 1, 1, 0, 0, 1 })
    T.eq(r.matrix, { DRUID = { [2] = 2 } })
    T.eq(r.levels[16], { DRUID = 1 })
    T.eq(r.levelTotals[12], 1)
    T.eq(r.maxRank, { [171] = 225, [182] = 50 })
  end)

  T.it("lists joins, departures and removals of the last days", function()
    local changes = Census.Changes({
      { kind = "join", player1 = "A", daysAgo = 2 },
      { kind = "quit", player1 = "B", daysAgo = 1 },
      { kind = "remove", player1 = "Officer", player2 = "C", daysAgo = 5 },
      { kind = "promote", player1 = "Officer", player2 = "D", daysAgo = 1 },
      { kind = "join", player1 = "Old", daysAgo = 90 },
    }, 30)
    T.eq(#changes, 3)
    T.eq(changes[1].name, "B")
    T.eq(changes[3].by, "Officer")
  end)
end)

T.describe("Census endgame", function()
  local function m(t)
    local out = { level = 60, classFile = "MAGE", online = true }
    for k, v in pairs(t or {}) do out[k] = v end
    return out
  end
  T.it("picks the phase", function()
    local sixty, low = m(), m({ level = 40 })
    T.eq(Census.Phase({ sixty, low }, "level"), "level")
    T.eq(Census.Phase({ low }, "endgame"), "endgame")
    T.eq(Census.Phase({ sixty, sixty, sixty, low, low, low }), "endgame")
    T.eq(Census.Phase({ sixty, sixty, low, low, low, low }), "level")
    T.eq(Census.Phase({}), "level")
    T.eq(Census.Phase({ low, m({ online = false, daysOffline = 90 }) }), "level") -- an inactive 60 does not count
    T.eq(Census.Phase({ sixty }, "nonsense"), "endgame")
  end)
  T.it("stacks item levels of the level 60 members", function()
    local a, b, c, d = m(), m({ classFile = "DRUID" }), m({ level = 59 }), m()
    local ilvl = { [a] = 579, [b] = 571, [c] = 600 }
    local r = Census.ItemLevels({ a, b, c, d }, 30, function(x) return ilvl[x] end)
    T.eq(r.counts, { [57] = { MAGE = 1, DRUID = 1 } })
    T.eq(r.totals, { [57] = 2 })
    T.eq({ r.min, r.max, r.top }, { 57, 57, 2 })
    local empty = Census.ItemLevels({}, 30, function() end)
    T.eq(empty.min, nil)
    T.eq(empty.top, 0)
  end)
  T.it("knows who is raid ready", function()
    T.eq(Census.IsReady(m(), 560), true)
    T.eq(Census.IsReady(m(), 559), false)
    T.eq(Census.IsReady(m(), nil), false)
    T.eq(Census.IsReady(m({ level = 59 }), 600), false)
    T.eq(Census.IsReady(m({ online = false, daysOffline = 7 }), 600), true)
    T.eq(Census.IsReady(m({ online = false, daysOffline = 7.5 }), 600), false)
  end)
  T.it("sums up a raid", function()
    local old, new, open, away = m({ name = "old" }), m({ name = "new" }), m({ name = "open" }), m({ name = "away", level = 30 })
    local values = { [old] = { [1098] = 4 }, [new] = { [1098] = 1 }, [open] = { [107] = 9 }, [away] = { [1098] = 2 } }
    local start = { [old] = { [1098] = 3 }, [new] = {}, [open] = {} }
    local ilvl = { [old] = 600, [new] = 600, [open] = 580 }
    local raids = Census.Raids({ old, new, open, away }, 30, { { key = "onyxia", raid = true, stats = { 1098 } } },
      function(x) return values[x] end, function(x) return start[x] end, function(x) return ilvl[x] end)
    T.eq(#raids, 1)
    T.eq(raids[1].raid.key, "onyxia")
    T.eq(raids[1].readings, 3)
    T.eq(#raids[1].killers, 2)
    T.eq(raids[1].new, 1)
    T.eq(#raids[1].open, 1)
    T.eq(raids[1].open[1].name, "open")
  end)
end)
