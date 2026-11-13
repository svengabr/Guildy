-- Talent specs per member (Core/Talents.lua) and stat weights per class and spec (Core/StatWeights.lua)
local T = ...
local ns = T.pureNs()
local Tal, SW = ns.Talents, ns.StatWeights

local AGI, STR, STA, INT, SPI, AP, DEF = "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"

local function rec(a, b, c) return { ts = 100, src = "self", trees = { a, b, c } } end
local CAT_GEAR = { { [AGI] = 12, [STR] = 6, [STA] = 6 }, { [AGI] = 8, [AP] = 20, [STA] = 5 }, { [AGI] = 10, [STA] = 7 } }
local BEAR_GEAR = { { [STA] = 18, [AGI] = 6, [DEF] = 8 }, { [STA] = 15, [AGI] = 5 }, { [STA] = 14, [STR] = 4, [DEF] = 5 } }
local FAT_GEAR = { { [STA] = 20, [AGI] = 5 }, { [STA] = 18, [STR] = 4 }, { [STA] = 16, [AGI] = 6 } }

T.describe("Stat weights", function()
  T.it("has coarse weights between 0 and 1 in the client's ITEM_MOD keys for every spec", function()
    local count = 0
    for spec, weights in pairs(SW.WEIGHTS) do
      count = count + 1
      for key, w in pairs(weights) do
        -- armour (the tooltip's RESISTANCE0_NAME) only for the tanks, at a small weight: it comes in hundreds
        T.truthy(key:match("^ITEM_MOD_[A-Z0-9_]+_SHORT$") or (key == "RESISTANCE0_NAME" and SW.TANK[spec] and w <= 0.05),
          spec .. ": " .. key)
        T.truthy(type(w) == "number" and w >= 0 and w <= 1, spec .. ": " .. key .. " = " .. tostring(w))
      end
    end
    T.eq(count, 18)
  end)

  T.it("values stamina low for every spec but the tanks", function()
    for spec, weights in pairs(SW.WEIGHTS) do
      if SW.TANK[spec] then
        T.eq(weights[STA], 1, spec)
      else
        T.truthy((weights[STA] or 0) <= 0.2, spec .. " stamina " .. tostring(weights[STA]))
      end
    end
  end)

  T.it("gives cat agility and strength high, bear stamina, defense and agility high, healers intellect and spirit", function()
    local cat, bear, heal = SW.For("DRUID_CAT"), SW.For("DRUID_BEAR"), SW.For("PRIEST_HEAL")
    T.truthy(cat[AGI] >= 0.9 and cat[STR] >= 0.8 and cat[AP] > 0 and cat[AP] < cat[AGI] and (cat[INT] or 0) == 0)
    T.truthy(bear[STA] == 1 and bear[DEF] >= 0.8 and bear[AGI] >= 0.7)
    T.truthy(heal[INT] >= 0.8 and heal[SPI] > 0 and (heal[AGI] or 0) == 0)
    T.eq(SW.For("NOPE"), nil)
  end)

  T.it("maps every class's three trees to a spec", function()
    for classFile, trees in pairs(SW.TREES) do
      T.eq(#trees, 3, classFile)
      for _, spec in ipairs(trees) do T.truthy(spec == "DRUID_FERAL" or SW.WEIGHTS[spec], classFile .. ": " .. spec) end
    end
  end)
end)

T.describe("Talent specs", function()
  T.it("takes the tree with the most points as the main spec", function()
    T.eq({ Tal.Decide("MAGE", 60, rec(0, 31, 20)) }, { "MAGE", 2 })
    T.eq({ Tal.Decide("WARRIOR", 60, rec(31, 20, 0)) }, { "WARRIOR_DPS", 1 })
    T.eq({ Tal.Decide("WARRIOR", 60, rec(20, 31, 0)) }, { "WARRIOR_DPS", 2 })
    T.eq({ Tal.Decide("WARRIOR", 60, rec(5, 0, 46)) }, { "WARRIOR_TANK", 3 })
    T.eq({ Tal.Decide("PALADIN", 60, rec(31, 0, 20)) }, { "PALADIN_HOLY", 1 })
    T.eq({ Tal.Decide("PALADIN", 60, rec(0, 31, 20)) }, { "PALADIN_PROT", 2 })
    T.eq({ Tal.Decide("PALADIN", 60, rec(11, 5, 35)) }, { "PALADIN_RET", 3 })
    T.eq({ Tal.Decide("SHAMAN", 60, rec(0, 21, 30)) }, { "SHAMAN_RESTO", 3 })
    T.eq({ Tal.Decide("PRIEST", 60, rec(21, 30, 0)) }, { "PRIEST_HEAL", 2 })
    T.eq({ Tal.Decide("PRIEST", 60, rec(15, 5, 31)) }, { "PRIEST_SHADOW", 3 })
    T.eq({ Tal.Decide("DRUID", 60, rec(31, 0, 20)) }, { "DRUID_BALANCE", 1 })
    T.eq({ Tal.Decide("DRUID", 60, rec(0, 11, 40)) }, { "DRUID_RESTO", 3 })
  end)

  T.it("has no spec below level 10, with too few points, without a record or for an unknown class", function()
    T.eq(Tal.Decide("MAGE", 9, rec(0, 5, 0)), nil)
    T.eq(Tal.Decide("MAGE", 12, rec(0, 3, 0)), nil)
    T.eq(Tal.Decide("MAGE", 60, nil), nil)
    T.eq(Tal.Decide("MONK", 60, rec(0, 31, 0)), nil)
    T.eq(Tal.Decide(nil, 60, rec(0, 31, 0)), nil)
  end)

  T.it("decides a tie only when the tied trees share their weights", function()
    T.eq({ Tal.Decide("WARRIOR", 60, rec(25, 25, 1)) }, { "WARRIOR_DPS", 1 })
    T.eq(Tal.Decide("WARRIOR", 60, rec(25, 1, 25)), nil)
    T.eq({ Tal.Decide("PRIEST", 60, rec(25, 25, 1)) }, { "PRIEST_HEAL", 1 })
  end)

  T.it("tells a feral cat from a bear by the worn gear", function()
    T.eq({ Tal.Decide("DRUID", 60, rec(0, 31, 20), CAT_GEAR) }, { "DRUID_CAT", 2 })
    T.eq({ Tal.Decide("DRUID", 60, rec(0, 31, 20), BEAR_GEAR) }, { "DRUID_BEAR", 2 })
    T.eq({ Tal.Decide("DRUID", 60, rec(0, 31, 20), FAT_GEAR) }, { "DRUID_BEAR", 2 })
    T.eq({ Tal.Decide("DRUID", 60, rec(0, 31, 20), {}) }, { "DRUID_CAT", 2 }) -- nothing worn known: the cat
    T.eq({ Tal.Decide("DRUID", 60, rec(0, 31, 20)) }, { "DRUID_CAT", 2 })
  end)

  T.it("reads the points of the game's talent tabs, in either shape of GetTalentTabInfo", function()
    -- classic: name, icon, pointsSpent, fileName; later clients: id, name, description, icon, pointsSpent, ...
    T.eq(Tal.TabPoints("Wildheit", 132276, 31, "DruidFeralCombat"), { name = "Wildheit", points = 31 })
    T.eq(Tal.TabPoints(281, "Wildheit", "Text", 132276, 31, "DruidFeralCombat"), { name = "Wildheit", points = 31 })
    T.eq(Tal.TabPoints(nil), nil)
    T.eq(Tal.TabPoints("Wildheit", 132276, -1), nil)
  end)

  T.it("makes the trees of three tabs, nothing of fewer", function()
    T.eq(Tal.FromTabs({ { points = 0 }, { points = 31 }, { points = 20 } }), { 0, 31, 20 })
    T.eq(Tal.FromTabs({ { points = 0 }, { points = 31 } }), nil)
    T.eq(Tal.FromTabs(nil), nil)
  end)
end)

T.describe("Talent records", function()
  T.it("validates a record from the guild and drops a wrong one", function()
    local now = 1000
    T.eq(Tal.Validate({ ts = 900, src = "self", p = { 0, 31, 20 } }, now), { ts = 900, src = "self", trees = { 0, 31, 20 } })
    T.eq(Tal.Validate({ ts = 900, src = "weird", p = { 0, 31, 20 } }, now).src, "relay")
    T.eq(Tal.Validate({ ts = 900, p = { 0, 31 } }, now), nil)
    T.eq(Tal.Validate({ ts = 900, p = { 0, 31, 20, 1 } }, now), nil)
    T.eq(Tal.Validate({ ts = 900, p = { 0, -1, 20 } }, now), nil)
    T.eq(Tal.Validate({ ts = 900, p = { 0, 1.5, 20 } }, now), nil)
    T.eq(Tal.Validate({ ts = 900, p = { 0, 101, 20 } }, now), nil)
    T.eq(Tal.Validate({ ts = now + 301, p = { 0, 31, 20 } }, now), nil)
    T.eq(Tal.Validate({ ts = 900, p = "0:31:20" }, now), nil)
    T.eq(Tal.Validate("x", now), nil)
    T.eq(Tal.Validate(nil, now), nil)
  end)

  T.it("goes over the wire and back", function()
    local r = { ts = 900, src = "seen", trees = { 5, 0, 46 } }
    T.eq(Tal.Validate(Tal.Wire(r), 1000), r)
  end)

  T.it("keeps the newer record, the member's own at the same time", function()
    local book = {}
    T.eq(Tal.Merge(book, "a", { ts = 10, src = "relay", trees = { 0, 1, 0 } }), true)
    T.eq(Tal.Merge(book, "a", { ts = 9, src = "self", trees = { 0, 2, 0 } }), false)
    T.eq(Tal.Merge(book, "a", { ts = 10, src = "relay", trees = { 0, 3, 0 } }), false)
    T.eq(Tal.Merge(book, "a", { ts = 10, src = "self", trees = { 0, 4, 0 } }), true)
    T.eq(Tal.Merge(book, "a", { ts = 10, src = "self", trees = { 0, 5, 0 } }), false)
    T.eq(Tal.Merge(book, "a", { ts = 11, src = "relay", trees = { 0, 6, 0 } }), true)
    T.eq(book.a.trees, { 0, 6, 0 })
    T.eq(Tal.Merge(book, "a", nil), false)
  end)

  T.it("digests records younger than the gear's 60 days and prunes members who left", function()
    local now = 100 * 86400
    local book = { a = { ts = now - 10, trees = { 0, 1, 0 } }, b = { ts = now - 61 * 86400, trees = { 0, 1, 0 } } }
    T.eq(Tal.Digest(book, now), { a = now - 10 })
    T.eq(Tal.Prune(book, { a = true }), 1)
    T.eq(book.b, nil)
  end)
end)
