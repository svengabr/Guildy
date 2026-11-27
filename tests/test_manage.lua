local T = ...
local ns = T.pureNs()
local Manage = ns.Manage

local ALL = { promote = true, demote = true, remove = true }

T.describe("Manage.Rights", function()
  T.it("lets an officer promote, demote and remove lower ranks", function()
    local r = Manage.Rights(4, 1, 7, ALL)
    T.truthy(r.promote and r.demote and r.remove)
  end)
  T.it("never promotes to the player's own rank", function()
    T.eq(Manage.Rights(2, 1, 7, ALL).promote, false)
    T.eq(Manage.Rights(3, 1, 7, ALL).promote, true)
  end)
  T.it("does not demote below the lowest rank", function()
    T.eq(Manage.Rights(6, 1, 7, ALL).demote, false)
    T.eq(Manage.Rights(5, 1, 7, ALL).demote, true)
  end)
  T.it("leaves equal and higher ranks alone", function()
    local r = Manage.Rights(1, 1, 7, ALL)
    T.eq(r.promote, false)
    T.eq(r.demote, false)
    T.eq(r.remove, false)
  end)
  T.it("follows the guild permissions", function()
    local r = Manage.Rights(4, 1, 7, { demote = true })
    T.eq(r.promote, false)
    T.eq(r.demote, true)
    T.eq(r.remove, false)
  end)
  T.it("gives nothing for the player or missing data", function()
    T.eq(Manage.Rights(4, 1, 7, ALL, true).remove, false)
    T.eq(Manage.Rights(nil, 1, 7, ALL).remove, false)
    T.eq(Manage.Rights(4, nil, 7, ALL).remove, false)
  end)
end)

T.describe("Manage.Command", function()
  T.it("builds slash commands with Forever's spaced name", function()
    T.eq(Manage.Command("demote", "Xii Lightspark"), "/gdemote Xii Lightspark")
    T.eq(Manage.Command("promote", "Ranfredo-Blanko"), "/gpromote Ranfredo Blanko")
    T.eq(Manage.Command("demote", "Dr Doomshot-Realm"), "/gdemote Dr Doomshot")
    T.eq(Manage.Command("remove", "Solo"), "/gremove Solo")
  end)
  T.it("refuses unknown kinds and empty names", function()
    T.eq(Manage.Command("invite", "Solo"), nil)
    T.eq(Manage.Command("remove", ""), nil)
    T.eq(Manage.Command("remove", nil), nil)
  end)
end)

T.describe("Manage batch", function()
  local function Roster()
    local byKey = {
      a = { key = "a", rankIndex = 4 }, b = { key = "b", rankIndex = 5 }, c = { key = "c", rankIndex = 3 },
    }
    local allowed = { a = true, b = true, c = true }
    return byKey, function(key) return byKey[key] end, function(m) return { demote = allowed[m.key], remove = allowed[m.key] } end, allowed
  end

  T.it("steps through the picks, locked until the roster shows the change", function()
    local byKey, find, rights = Roster()
    local b = Manage.NewBatch("demote", { "a", "b" })
    T.eq(Manage.BatchCurrent(b, find, rights).key, "a")
    Manage.BatchSent(b, byKey.a, 100)
    T.eq(Manage.BatchConfirm(b, find), false) -- no change yet: still a, still locked
    T.eq(Manage.BatchCurrent(b, find, rights).key, "a")
    T.truthy(b.waiting, "locked")
    byKey.a.rankIndex = 5
    T.eq(Manage.BatchConfirm(b, find), true)
    T.eq(b.waiting, nil)
    T.eq(Manage.BatchCurrent(b, find, rights).key, "b")
    Manage.BatchSent(b, byKey.b, 101)
    byKey.b.rankIndex = 6
    Manage.BatchConfirm(b, find)
    T.eq(Manage.BatchCurrent(b, find, rights), nil)
    T.eq({ b.done, b.skipped }, { 2, 0 })
  end)

  T.it("a promotion only counts when the rank goes up", function()
    local byKey, find, rights = Roster()
    rights = function() return { promote = true } end
    local b = Manage.NewBatch("promote", { "c" })
    Manage.BatchSent(b, Manage.BatchCurrent(b, find, rights), 1)
    byKey.c.rankIndex = 4 -- someone else demoted them meanwhile
    T.eq(Manage.BatchConfirm(b, find), false)
    byKey.c.rankIndex = 2
    T.eq(Manage.BatchConfirm(b, find), true)
  end)

  T.it("removal counts once the member is gone", function()
    local byKey, find, rights = Roster()
    local b = Manage.NewBatch("remove", { "a" })
    Manage.BatchSent(b, Manage.BatchCurrent(b, find, rights), 1)
    byKey.a = nil
    T.eq(Manage.BatchConfirm(b, find), true)
    T.eq(b.done, 1)
  end)

  T.it("skips members who left or may no longer be changed", function()
    local byKey, find, rights, allowed = Roster()
    byKey.a = nil
    allowed.b = false
    local b = Manage.NewBatch("demote", { "a", "b", "c" })
    T.eq(Manage.BatchCurrent(b, find, rights).key, "c")
    T.eq(b.skipped, 2)
  end)

  T.it("unlocks after the time limit and lets the player skip", function()
    local byKey, find, rights = Roster()
    local b = Manage.NewBatch("demote", { "a", "b" })
    Manage.BatchSent(b, byKey.a, 100)
    T.eq(Manage.BatchTimedOut(b, 104, 8), false)
    T.eq(Manage.BatchTimedOut(b, 108, 8), true)
    T.eq(Manage.BatchCurrent(b, find, rights).key, "a") -- the same member again
    Manage.BatchSkip(b)
    T.eq(Manage.BatchCurrent(b, find, rights).key, "b")
    T.eq(b.skipped, 1)
  end)
end)
