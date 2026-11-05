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
end)
