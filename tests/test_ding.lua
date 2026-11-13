local T = ...
local ns = T.pureNs()
local D = ns.Ding

local function names(found)
  local list = {}
  for i, m in ipairs(found) do list[i] = m.key end
  return list
end

T.describe("Ding", function()
  T.it("finds nobody on the first scan and remembers the levels", function()
    local found, levels = D.Find(nil, { { key = "a", level = 60 }, { key = "b", level = 59 } }, 60)
    T.eq(found, {})
    T.eq(levels, { a = 60, b = 59 })
  end)
  T.it("finds who went from the level before the top one to it", function()
    local members = { { key = "a", level = 60 }, { key = "c", level = 60 }, { key = "d", level = 59 } }
    local found, levels = D.Find({ a = 59, c = 60, d = 58 }, members, 60)
    T.eq(names(found), { "a" })
    T.eq(levels, { a = 60, c = 60, d = 59 })
  end)
  T.it("takes a jump over several levels for a roster that was wrong for a moment, not for a level 60", function()
    -- the roster gives level 1 for a member whose level the game did not send (Game/Roster.lua)
    local members = { { key = "a", level = 60 }, { key = "b", level = 60 }, { key = "c", level = 60 } }
    T.eq((D.Find({ a = 1, b = 0, c = 40 }, members, 60)), {})
  end)
  T.it("does not find a member who was not in the scan before", function()
    local found = D.Find({ a = 60 }, { { key = "a", level = 60 }, { key = "new", level = 60 } }, 60)
    T.eq(found, {})
  end)
  T.it("forgets a member who is gone, so a return at 60 is not found", function()
    local _, levels = D.Find({ a = 59, b = 30 }, { { key = "b", level = 30 } }, 60)
    T.eq(levels, { b = 30 })
    local found = D.Find(levels, { { key = "a", level = 60 }, { key = "b", level = 30 } }, 60)
    T.eq(found, {})
  end)
  T.it("lives with broken levels", function()
    local found, levels = D.Find({ a = "x", b = 59 }, { { key = "a", level = 60 }, { key = "b" }, { level = 60 } }, 60)
    T.eq(found, {})
    T.eq(levels, { a = 60 })
  end)
  T.it("builds the line for guild chat", function()
    T.eq(D.Line("%s has reached level %d!", "Au Tsch", 60), "[Guildy] Au Tsch has reached level 60!")
  end)
  T.it("knows a line that says it already", function()
    T.eq(D.Said("[Guildy] Au-Tsch has reached level 60!", "Au-Tsch"), true) -- "-" is no pattern here
    T.eq(D.Said("[Guildy] Au-Tsch hat Stufe 60 erreicht!", "Au-Tsch"), true) -- another language
    T.eq(D.Said("Au-Tsch has reached level 60!", "Au-Tsch"), false)
    T.eq(D.Said("gz [Guildy] Au-Tsch", "Au-Tsch"), false)
    T.eq(D.Said("[Guildy] Makira has reached level 60!", "Au-Tsch"), false)
    T.eq(D.Said(nil, "Au-Tsch"), false)
    T.eq(D.Said({}, "Au-Tsch"), false)
    T.eq(D.Said("[Guildy] x", ""), false)
  end)
end)
