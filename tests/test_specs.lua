local T = ...
local ns = T.pureNs()
local Specs = ns.Specs

local function Known(...)
  local set = {}
  for _, id in ipairs({ ... }) do set[id] = true end
  return function(id) return set[id] == true end
end

T.describe("Specs", function()
  T.it("reads the own specialization, the most specific one first", function()
    T.eq(Specs.Detect(202, Known(20222)), 20222)
    T.eq(Specs.Detect(202, Known(20219)), 20219)
    T.eq(Specs.Detect(202, Known()), 0) -- an engineer without one
    T.eq(Specs.Detect(164, Known(9787, 17039)), 17039) -- a weaponsmith who went on to swords
    T.eq(Specs.Detect(164, Known(9787)), 9787)
    T.eq(Specs.Detect(165, Known(10658)), 10658)
    T.eq(Specs.Detect(171, Known(20222)), nil) -- alchemy has none on Forever
  end)

  T.it("knows which profession a specialization belongs to", function()
    T.eq(Specs.SKILL_OF[20222], 202)
    T.eq(Specs.SKILL_OF[17041], 164)
    T.eq(Specs.SKILL_OF[10656], 165)
    T.eq(Specs.SKILL_OF[28672], nil) -- Transmutation Master does not exist here
  end)

  T.it("infers a specialization from a recipe book", function()
    T.eq(Specs.FromBook(202, { 1, 12760, 2 }), 20222) -- Goblin Sapper Charge
    T.eq(Specs.FromBook(202, { 12895 }), 20219) -- Inlaid Mithril Cylinder Plans
    T.eq(Specs.FromBook(202, { 1, 2, 3 }), nil)
    T.eq(Specs.FromBook(202, nil), nil)
    T.eq(Specs.FromBook(171, { 12760 }), nil) -- not an engineering book
  end)

  T.it("infers nothing from a book with recipes of two rival specializations", function()
    T.eq(Specs.FromBook(202, { 12760, 12895 }), nil)
  end)

  T.it("takes a clean specialization", function()
    T.eq(Specs.Validate(202, { id = 20222, src = "api", ts = 10.7 }), { id = 20222, src = "api", ts = 10 })
    T.eq(Specs.Validate(202, { id = 0, src = "known", ts = 10 }), { id = 0, src = "known", ts = 10 })
  end)

  T.it("refuses a specialization that does not fit", function()
    T.eq(Specs.Validate(164, { id = 20222, src = "api", ts = 10 }), nil) -- engineering spell on a blacksmith
    T.eq(Specs.Validate(202, { id = 0, src = "book", ts = 10 }), nil) -- a book never says "none"
    T.eq(Specs.Validate(202, { id = 20222, src = "guess", ts = 10 }), nil)
    T.eq(Specs.Validate(202, { id = 20222, src = "api" }), nil)
    T.eq(Specs.Validate(202, { id = 20222, src = "api", ts = 0 }), nil)
    T.eq(Specs.Validate(202, { id = 20222.5, src = "api", ts = 10 }), nil)
    T.eq(Specs.Validate(202, { id = "20222", src = "api", ts = 10 }), nil)
    T.eq(Specs.Validate(202, "x"), nil)
    T.eq(Specs.Validate(171, { id = 0, src = "known", ts = 10 }), nil) -- no specializations in alchemy
  end)

  T.it("takes a first specialization", function()
    local rec = { ts = 5 }
    T.eq(Specs.Merge(rec, { id = 20222, src = "book", ts = 5 }), true)
    T.eq(rec.spec, { id = 20222, src = "book", ts = 5 })
    T.eq(Specs.Merge(rec, { id = 20222, src = "book", ts = 5 }), false)
    T.eq(Specs.Merge(nil, { id = 20222, src = "book", ts = 5 }), false)
    T.eq(Specs.Merge(rec, nil), false)
  end)

  T.it("lets a book only add, never overrule the game or the script", function()
    local rec = { spec = { id = 20219, src = "known", ts = 5 } }
    T.eq(Specs.Merge(rec, { id = 20222, src = "book", ts = 99 }), false)
    rec = { spec = { id = 0, src = "api", ts = 5 } }
    T.eq(Specs.Merge(rec, { id = 20222, src = "book", ts = 99 }), false) -- nor revive a revoked one
    rec = { spec = { id = 20219, src = "book", ts = 5 } }
    T.eq(Specs.Merge(rec, { id = 20222, src = "book", ts = 4 }), false)
    T.eq(Specs.Merge(rec, { id = 20222, src = "book", ts = 6 }), true)
    T.eq(rec.spec.id, 20222)
  end)

  T.it("lets the game and the script replace and revoke", function()
    local rec = { spec = { id = 20219, src = "book", ts = 50 } }
    T.eq(Specs.Merge(rec, { id = 20222, src = "api", ts = 10 }), true) -- over a book, whatever its age
    T.eq(rec.spec, { id = 20222, src = "api", ts = 10 })
    T.eq(Specs.Merge(rec, { id = 0, src = "known", ts = 9 }), false) -- older
    T.eq(Specs.Merge(rec, { id = 0, src = "known", ts = 11 }), true) -- unlearned
    T.eq(rec.spec.id, 0)
    T.eq(Specs.Merge(rec, { id = 20219, src = "api", ts = 11 }), false) -- the same moment: the game wins
    rec = { spec = { id = 20219, src = "api", ts = 11 } }
    T.eq(Specs.Merge(rec, { id = 20222, src = "known", ts = 11 }), true)
  end)

  T.it("keeps the specialization when a newer skill reading comes in", function()
    local P = ns.Professions
    local member = { profs = { [202] = { ts = 5, src = "relay", rank = 200, spec = { id = 20222, src = "api", ts = 5 } } } }
    T.eq(P.Merge(member, 202, P.ValidateRecord({ ts = 6, src = "relay", rank = 210 })), true)
    T.eq(member.profs[202].rank, 210)
    T.eq(member.profs[202].spec, { id = 20222, src = "api", ts = 5 })
  end)
end)
