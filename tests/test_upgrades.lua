local T = ...
local ns = T.pureNs()
local U = ns.Upgrades

local AGI, STR, STA, INT, SPI, AP = "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT"
local ARMOR = "RESISTANCE0_NAME"

local function item(id, l) return { id = id, e = 0, s = 0, l = l, q = 2 } end

-- item infos: id -> { equipLoc, level, reqLevel, classID, subclassID, bind, quality }
local INFO = {
  [500] = { equipLoc = "INVTYPE_WAIST", level = 58, reqLevel = 50, classID = 4, subclassID = 1, bind = 2, quality = 3 },
  [501] = { equipLoc = "INVTYPE_WAIST", level = 50, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 },
  [502] = { equipLoc = "INVTYPE_WAIST", level = 49, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 },
}
local function info(id) return INFO[id] end

-- item stats by item ID, for offers and worn items alike
local STATS = {
  [500] = { [INT] = 12, [STA] = 6 },
  [501] = { [INT] = 8, [STA] = 4 },
  [502] = { [INT] = 3, [STA] = 2 },
}
-- the caster's worn pieces: four with intellect and stamina (a strong profile), a weak waist
for id = 101, 104 do STATS[id] = { [INT] = 10, [STA] = 5 } end
STATS[1] = { [INT] = 3, [STA] = 2 }

local REQ = {} -- itemID -> requirements; none known: {}
local GAME = {
  stats = function(x) return STATS[type(x) == "table" and x.id or x] end,
  requirements = function(id) return REQ[id] or {} end,
}

local function caster(extra)
  local items = { [1] = item(101, 45), [3] = item(102, 45), [5] = item(103, 45), [7] = item(104, 45), [6] = item(1, 47) }
  for slot, it in pairs(extra or {}) do items[slot] = it end
  return { items = items }
end

local function maker(key, recipes, online, offline)
  return { key = key, online = online or false, offline = offline or 0, profs = { [197] = { recipes = recipes } } }
end

local MEMBER = { key = "me", level = 52, classFile = "MAGE" }

local function For(member, gear, makers, craft) return U.For(member, gear, makers, craft, info, GAME) end

T.describe("Upgrades", function()
  T.it("offers a better piece from another member's book", function()
    local rows, missing = For(MEMBER, caster(), { maker("tailor", { 9001 }, true) }, { [9001] = 500 })
    T.eq(#rows, 1)
    T.eq(rows[1].slot, 6)
    T.eq(rows[1].have, 47)
    T.eq(rows[1].offer, 58)
    T.eq(rows[1].itemID, 500)
    T.eq(rows[1].quality, 3)
    T.eq(rows[1].makers, { { key = "tailor", skillLine = 197, online = true } })
    T.eq(missing, {})
  end)

  T.it("needs a clearly better score, not a higher item level", function()
    local makers = { maker("tailor", { 9002, 9003 }) }
    -- 502 has the worn waist's stats at a higher level: no gain, not offered
    T.eq(#For(MEMBER, caster(), makers, { [9003] = 502 }), 0)
    -- 501 beats it by far: offered, the better of the two
    local rows = For(MEMBER, caster(), makers, { [9002] = 501, [9003] = 502 })
    T.eq(rows[1].offer, 50)
    -- a few points more than the worn piece but under ten percent: not offered
    STATS[505] = { [INT] = 31, [STA] = 15 }
    STATS[506] = { [INT] = 32, [STA] = 16 }
    INFO[506] = { equipLoc = "INVTYPE_WAIST", level = 50, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    T.eq(#For(MEMBER, caster({ [6] = item(505, 49) }), makers, { [9002] = 506 }), 0)
  end)

  T.it("skips the member's own book, a too high required level and bind on pickup", function()
    local gear = caster()
    T.eq(#For(MEMBER, gear, { maker("me", { 9001 }) }, { [9001] = 500 }), 0)
    T.eq(#For({ key = "me", level = 49, classFile = "MAGE" }, gear, { maker("t", { 9001 }) }, { [9001] = 500 }), 0)
    INFO[503] = { equipLoc = "INVTYPE_WAIST", level = 58, reqLevel = 50, classID = 4, subclassID = 1, bind = 1, quality = 3 }
    STATS[503] = STATS[500]
    T.eq(#For(MEMBER, gear, { maker("t", { 9004 }) }, { [9004] = 503 }), 0)
    INFO[503].bind = 2
    T.eq(#For(MEMBER, gear, { maker("t", { 9004 }) }, { [9004] = 503 }), 1)
  end)

  T.it("offers only armour the class can wear", function()
    INFO[510] = { equipLoc = "INVTYPE_CHEST", level = 45, reqLevel = 35, classID = 4, subclassID = 4, bind = 2, quality = 2 }
    INFO[511] = { equipLoc = "INVTYPE_CHEST", level = 25, reqLevel = 18, classID = 4, subclassID = 3, bind = 2, quality = 2 }
    STATS[510] = { [STR] = 20, [STA] = 10 }
    STATS[511] = { [AGI] = 10, [STA] = 5 }
    for id = 111, 114 do STATS[id] = { [STR] = 5, [AGI] = 5, [STA] = 5 } end
    STATS[2] = { [STR] = 1 }
    local function fighter(extra)
      local items = { [1] = item(111, 20), [3] = item(112, 20), [7] = item(113, 20), [8] = item(114, 20), [5] = item(2, 15) }
      for slot, it in pairs(extra or {}) do items[slot] = it end
      return { items = items }
    end
    local makers = { maker("smith", { 9010, 9011 }) }
    T.eq(#For({ key = "w", level = 39, classFile = "WARRIOR" }, fighter(), makers, { [9010] = 510 }), 0)
    T.eq(#For({ key = "w", level = 40, classFile = "WARRIOR" }, fighter(), makers, { [9010] = 510 }), 1)
    -- a level 20 hunter who already wears mail gets mail
    INFO[3] = { equipLoc = "INVTYPE_HAND", level = 18, reqLevel = 15, classID = 4, subclassID = 3, bind = 2, quality = 2 }
    STATS[3] = { [AGI] = 2 }
    T.eq(#For({ key = "h", level = 20, classFile = "HUNTER" }, fighter(), makers, { [9011] = 511 }), 0)
    T.eq(#For({ key = "h", level = 20, classFile = "HUNTER" }, fighter({ [10] = item(3, 18) }), makers, { [9011] = 511 }), 1)
    T.eq(#For({ key = "m", level = 50, classFile = "MAGE" }, { items = {} }, makers, { [9010] = 510, [9011] = 511 }), 0)
  end)

  T.it("never offers weapons, off hands or ranged items", function()
    INFO[520] = { equipLoc = "INVTYPE_WEAPON", level = 60, reqLevel = 1, classID = 2, subclassID = 7, bind = 2, quality = 3 }
    INFO[521] = { equipLoc = "INVTYPE_HOLDABLE", level = 60, reqLevel = 1, classID = 4, subclassID = 0, bind = 2, quality = 3 }
    INFO[522] = { equipLoc = "INVTYPE_RANGED", level = 60, reqLevel = 1, classID = 2, subclassID = 2, bind = 2, quality = 3 }
    INFO[523] = { equipLoc = "INVTYPE_SHIELD", level = 60, reqLevel = 1, classID = 4, subclassID = 6, bind = 2, quality = 3 }
    for id = 520, 523 do STATS[id] = { [INT] = 50 } end
    local rows = For(MEMBER, caster(), { maker("t", { 1, 2, 3, 4 }) }, { [1] = 520, [2] = 521, [3] = 522, [4] = 523 })
    T.eq(#rows, 0)
  end)

  T.it("compares a ring with the weaker ring slot and an empty slot with nothing", function()
    INFO[530] = { equipLoc = "INVTYPE_FINGER", level = 40, reqLevel = 35, classID = 4, subclassID = 0, bind = 2, quality = 2 }
    STATS[530] = { [INT] = 8, [STA] = 4 }
    STATS[4], STATS[5] = { [INT] = 9, [STA] = 5 }, { [INT] = 2 }
    local makers = { maker("jc", { 9030 }) }
    local rows = For(MEMBER, caster({ [11] = item(4, 30), [12] = item(5, 45) }), makers, { [9030] = 530 })
    T.eq(rows[1].slot, 12) -- the weaker by its stats, though its item level is higher
    T.eq(rows[1].have, 45)
    rows = For(MEMBER, caster({ [11] = item(4, 45) }), makers, { [9030] = 530 })
    T.eq(rows[1].slot, 12)
    T.eq(rows[1].have, 0)
  end)

  T.it("shows five rows at most, the largest gain first", function()
    local slots = { INVTYPE_HEAD = 1, INVTYPE_FEET = 8, INVTYPE_HAND = 10, INVTYPE_WRIST = 9, INVTYPE_LEGS = 7, INVTYPE_WAIST = 6 }
    local ids, craft, n = {}, {}, 0
    for loc in pairs(slots) do
      n = n + 1
      local id = 539 + n
      INFO[id] = { equipLoc = loc, level = 50, reqLevel = 40, classID = 4, subclassID = 1, bind = 2, quality = 2 }
      STATS[id] = { [INT] = 20, [STA] = 10 }
      craft[n], ids[n] = id, n
    end
    -- worn: the better the piece, the smaller the gain (9 worst, then 6, 8, 7, 1, 10)
    local worn = { [9] = 1, [6] = 2, [8] = 3, [7] = 4, [1] = 5, [10] = 6 }
    local items = { [3] = item(102, 45), [5] = item(103, 45), [13] = item(101, 45), [14] = item(104, 45) }
    for slot, k in pairs(worn) do
      STATS[600 + slot] = { [INT] = k * 2, [STA] = k }
      items[slot] = item(600 + slot, 40)
    end
    local rows = For(MEMBER, { items = items }, { maker("t", ids) }, craft)
    T.eq(U.MAX_ROWS, 5)
    T.eq(#rows, 5)
    T.eq({ rows[1].slot, rows[2].slot, rows[3].slot, rows[4].slot, rows[5].slot }, { 9, 6, 8, 7, 1 })
  end)

  T.it("lists makers online first, then the ones seen last", function()
    local makers = { maker("a", { 9001 }, false, 30), maker("b", { 9001 }, false, 2), maker("c", { 9001 }, true) }
    local rows = For(MEMBER, caster(), makers, { [9001] = 500 })
    T.eq({ rows[1].makers[1].key, rows[1].makers[2].key, rows[1].makers[3].key }, { "c", "b", "a" })
  end)

  T.it("asks for item infos it does not have", function()
    local rows, missing = For(MEMBER, caster(), { maker("t", { 9099, 9098 }) }, { [9099] = 599, [9098] = 599 })
    T.eq(#rows, 0)
    T.eq(missing, { 599 })
  end)

  T.it("skips an offer whose stats are not loaded yet and asks for them", function()
    INFO[598] = { equipLoc = "INVTYPE_WAIST", level = 58, reqLevel = 50, classID = 4, subclassID = 1, bind = 2, quality = 3 }
    local rows, missing = For(MEMBER, caster(), { maker("t", { 9097 }) }, { [9097] = 598 })
    T.eq(#rows, 0)
    T.eq(missing, { 598 })
  end)

  T.it("learns what recipes make, up to the cap, and forgets what is not equippable", function()
    local map = {}
    T.eq(U.Learn(map, 1, 10), true)
    T.eq(U.Learn(map, 1, 10), false)
    T.eq(U.Learn(map, 1.5, 10), false)
    T.eq(U.Learn(map, 2, 0), false)
    for i = 2, U.MAX_CRAFTS do U.Learn(map, i, 10) end
    T.eq(U.Learn(map, U.MAX_CRAFTS + 1, 10), false)
    T.eq(map[U.MAX_CRAFTS + 1], nil)
    local small = { [1] = 10, [2] = 20, [3] = 30 }
    local known = { [10] = true, [20] = false }
    T.eq(U.Clean(small, function(id) return known[id] end), 1)
    T.eq(small, { [1] = 10, [3] = 30 })
  end)
end)

-- A feral druid: agility, strength, stamina and attack power on leather -----------------------------
local FERAL = { key = "sven", level = 46, classFile = "DRUID" }
local function feral(extra)
  local items = {}
  local worn = { [1] = 201, [3] = 202, [7] = 203, [8] = 204, [10] = 205, [5] = 206, [6] = 207 }
  for slot, id in pairs(worn) do
    INFO[id] = { equipLoc = "INVTYPE_HEAD", level = 40, reqLevel = 35, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[id] = { [AGI] = 6, [STR] = 4, [STA] = 6, [AP] = 10, [ARMOR] = 80 }
    items[slot] = item(id, 40)
  end
  STATS[206] = { [AGI] = 6, [STA] = 5, [ARMOR] = 90 } -- the chest
  for slot, it in pairs(extra or {}) do items[slot] = it end
  return { items = items }
end

T.describe("Upgrades for a feral druid", function()
  INFO[700] = { equipLoc = "INVTYPE_ROBE", level = 50, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 3 } -- Winterzwirntunika
  STATS[700] = { [INT] = 14, [SPI] = 10, [STA] = 4, [ARMOR] = 50 }
  INFO[701] = { equipLoc = "INVTYPE_NECK", level = 50, reqLevel = 45, classID = 4, subclassID = 0, bind = 2, quality = 3 }
  STATS[701] = { [INT] = 9, [SPI] = 8 }
  INFO[702] = { equipLoc = "INVTYPE_CHEST", level = 44, reqLevel = 40, classID = 4, subclassID = 2, bind = 2, quality = 2 }
  STATS[702] = { [AGI] = 14, [STA] = 8, [ARMOR] = 100 }
  INFO[703] = { equipLoc = "INVTYPE_TRINKET", level = 45, reqLevel = 40, classID = 4, subclassID = 0, bind = 2, quality = 2 } -- needs engineering 205
  STATS[703] = { [AGI] = 10, [AP] = 20 }
  REQ[703] = { skill = "Ingenieurskunst", rank = 205 }
  INFO[704] = { equipLoc = "INVTYPE_FINGER", level = 45, reqLevel = 40, classID = 4, subclassID = 0, bind = 2, quality = 2 }
  STATS[704] = { [AGI] = 10, [STR] = 10 }
  REQ[704] = { classes = { "Schurke" } }
  local makers = { maker("t", { 9700, 9701, 9702, 9703, 9704 }) }
  local craft = { [9700] = 700, [9701] = 701, [9702] = 702, [9703] = 703, [9704] = 704 }

  T.it("does not offer cloth caster pieces of a higher level", function()
    local rows = For(FERAL, feral(), makers, { [9700] = 700, [9701] = 701 })
    T.eq(#rows, 0)
  end)

  T.it("offers a leather agility chest that scores higher", function()
    local rows = For(FERAL, feral(), makers, { [9700] = 700, [9702] = 702 })
    T.eq(#rows, 1)
    T.eq(rows[1].itemID, 702)
    T.eq(rows[1].offer - rows[1].have, 4)
    T.eq(rows[1].diff, { { key = AGI, delta = 8 }, { key = STA, delta = 3 } })
  end)

  T.it("drops a trinket that needs engineering 205 unless the member has it", function()
    T.eq(#For(FERAL, feral(), makers, { [9703] = 703 }), 0)
    local engineer = { key = "sven", level = 46, classFile = "DRUID", profs = { ingenieurskunst = 210 } }
    T.eq(#For(engineer, feral(), makers, { [9703] = 703 }), 1)
    local learning = { key = "sven", level = 46, classFile = "DRUID", profs = { ingenieurskunst = 150 } }
    T.eq(#For(learning, feral(), makers, { [9703] = 703 }), 0)
  end)

  T.it("drops a piece only other classes may wear", function()
    local druid = { key = "sven", level = 46, classFile = "DRUID", classNames = { Druide = true } }
    T.eq(#For(druid, feral(), makers, { [9704] = 704 }), 0)
    local rogue = { key = "x", level = 46, classFile = "ROGUE", classNames = { Schurke = true } }
    T.eq(#For(rogue, feral(), makers, { [9704] = 704 }), 1)
  end)

  T.it("drops a piece that needs a reputation", function()
    REQ[702] = { reputation = true }
    T.eq(#For(FERAL, feral(), makers, { [9702] = 702 }), 0)
    REQ[702] = nil
  end)

  T.it("offers no lighter armour type than the one worn mostly, though the class may wear it", function()
    INFO[705] = { equipLoc = "INVTYPE_CHEST", level = 50, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 3 }
    STATS[705] = { [AGI] = 20, [STA] = 12, [ARMOR] = 40 }
    T.eq(#For(FERAL, feral(), makers, { [9705] = 705 }), 0)
    -- a druid in mixed cloth and leather may get cloth
    INFO[208] = { equipLoc = "INVTYPE_HEAD", level = 40, reqLevel = 35, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    STATS[208] = STATS[201]
    local mixed = feral({ [1] = item(208, 40), [3] = item(208, 40), [7] = item(208, 40) })
    T.eq(#For(FERAL, mixed, { maker("t", { 9705 }) }, { [9705] = 705 }), 1)
  end)

  -- Sven's chest: "Waldläufertunika des Tigers", +13 strength and agility from its random suffix; the base
  -- item alone has no stats. "Barbarischer Harnisch" (+7 strength, +8 agility, +8 stamina) is no upgrade.
  INFO[720] = { equipLoc = "INVTYPE_CHEST", level = 39, reqLevel = 34, classID = 4, subclassID = 2, bind = 2, quality = 2 }
  STATS[720] = {} -- the base item: its stats are all in the suffix
  INFO[721] = { equipLoc = "INVTYPE_CHEST", level = 40, reqLevel = 35, classID = 4, subclassID = 2, bind = 2, quality = 2 }
  STATS[721] = { [STR] = 7, [AGI] = 8, [STA] = 8, [ARMOR] = 120 }
  local harness = { [9721] = 721 }

  T.it("does not offer the harness over the tiger tunic whose stats come with the suffix", function()
    local game = { requirements = GAME.requirements, stats = function(x)
      if type(x) == "table" and x.id == 720 then
        return x.s == -17 and x.u == 2752512 and { [STR] = 13, [AGI] = 13, [ARMOR] = 110 } or {}
      end
      return GAME.stats(x)
    end }
    local gear = feral({ [5] = { id = 720, e = 0, s = -17, u = 2752512, l = 39, q = 2 } })
    T.eq(#U.For(FERAL, gear, { maker("t", { 9721 }) }, harness, info, game), 0)
  end)

  T.it("uses the stats stored with a worn item (bnet-sync) over the game's", function()
    local gear = feral({ [5] = { id = 720, e = 0, s = 0, l = 39, q = 2, st = { [STR] = 13, [AGI] = 13 } } })
    T.eq(#For(FERAL, gear, { maker("t", { 9721 }) }, harness), 0)
    -- stored stats that are weaker do let a better piece through
    local weak = feral({ [5] = { id = 720, e = 0, s = 0, l = 39, q = 2, st = { [AGI] = 2 } } })
    local rows = For(FERAL, weak, { maker("t", { 9721 }) }, harness)
    T.eq(#rows, 1)
    T.eq(rows[1].diff[1], { key = AGI, delta = 6 })
  end)

  -- A protection warrior's worn chest: 20 stamina, 400 armour; the crafted one 18 stamina, 300 armour
  INFO[740] = { equipLoc = "INVTYPE_CHEST", level = 40, reqLevel = 35, classID = 4, subclassID = 4, bind = 2, quality = 2 }
  INFO[741] = { equipLoc = "INVTYPE_CHEST", level = 42, reqLevel = 37, classID = 4, subclassID = 4, bind = 2, quality = 2 }
  STATS[741] = { [STA] = 18, [ARMOR] = 300 }
  local TANK = { key = "w", level = 45, classFile = "WARRIOR", weights = ns.StatWeights.For("WARRIOR_TANK") }
  local function tankRows(worn)
    return For(TANK, { items = { [5] = worn } }, { maker("bs", { 9741 }) }, { [9741] = 741 })
  end

  T.it("does not beat a tank's worn piece whose stored stats carry its armour", function()
    STATS[740] = { [STA] = 20, [ARMOR] = 400 }
    T.eq(#tankRows({ id = 740, e = 0, s = 0, l = 40, q = 2, st = { [STA] = 20, [ARMOR] = 400 } }), 0)
  end)

  T.it("takes the armour of a worn piece with stored stats from the game", function()
    STATS[740] = { [STA] = 20, [ARMOR] = 400 }
    local worn = { id = 740, e = 0, s = 0, l = 40, q = 2, st = { [STA] = 20 } }
    T.eq(U.WornStats(worn, GAME), { [STA] = 20, [ARMOR] = 400 })
    T.eq(#tankRows({ id = 740, e = 0, s = 0, l = 40, q = 2, st = { [STA] = 20 } }), 0)
  end)

  T.it("keeps the stored stats over the game's for every ITEM_MOD key, also one the game adds", function()
    STATS[742] = { [STA] = 5, [AGI] = 9, [ARMOR] = 80 }
    T.eq(U.WornStats({ id = 742, e = 0, s = 0, l = 40, q = 2, st = { [STA] = 7 } }, GAME), { [STA] = 7, [ARMOR] = 80 })
  end)

  T.it("uses the stored stats alone while the game's load, and names the piece missing", function()
    local game = { stats = function() return nil end }
    local worn = { id = 743, e = 0, s = 0, l = 40, q = 2, st = { [STA] = 7 } }
    local stats, gone, loading = U.WornStats(worn, game)
    T.eq({ stats, gone, loading }, { { [STA] = 7 }, nil, true })
    local _, missing = U.For(TANK, { items = { [5] = worn } }, {}, {}, info, game)
    T.eq(missing, { 743 })
    game.stats = function() return { [ARMOR] = 90 } end -- loaded now: not kept from before
    T.eq(U.WornStats(worn, game), { [STA] = 7, [ARMOR] = 90 })
    game.stats = function() return nil, true end
    T.eq(U.WornStats({ id = 743, e = 0, s = 0, l = 40, q = 2, st = { [STA] = 7 } }, game), { [STA] = 7 })
  end)

  T.it("offers nothing for a worn item whose stats cannot be known", function()
    -- a record without the suffix (bnet-sync before stored stats): the game gives the bare base item
    local bare = feral({ [5] = { id = 720, e = 0, s = 0, l = 39, q = 2 } })
    T.eq(#For(FERAL, bare, { maker("t", { 9721 }) }, harness), 0)
    -- a negative suffix without the unique ID that carries its factor
    local noFactor = feral({ [5] = { id = 720, e = 0, s = -17, l = 39, q = 2 } })
    T.eq(#For(FERAL, noFactor, { maker("t", { 9721 }) }, harness), 0)
    -- the other slots still get their offers
    INFO[722] = { equipLoc = "INVTYPE_HEAD", level = 44, reqLevel = 40, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[722] = { [AGI] = 12, [STR] = 8, [STA] = 6, [AP] = 16 }
    T.eq(#For(FERAL, bare, { maker("t", { 9722 }) }, { [9722] = 722 }), 1)
  end)

  T.it("never takes a piece that wins on stamina alone", function()
    -- the worn chest has 6 agility and 5 stamina; this one the same agility and far more stamina
    INFO[723] = { equipLoc = "INVTYPE_CHEST", level = 40, reqLevel = 35, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[723] = { [AGI] = 6, [STA] = 25 }
    T.eq(#For(FERAL, feral(), { maker("t", { 9723 }) }, { [9723] = 723 }), 0)
    -- nor one that loses agility while gaining stamina, even at a higher item level
    INFO[724] = { equipLoc = "INVTYPE_CHEST", level = 48, reqLevel = 40, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[724] = { [AGI] = 5, [STA] = 30 }
    T.eq(#For(FERAL, feral(), { maker("t", { 9724 }) }, { [9724] = 724 }), 0)
  end)
end)

T.describe("Upgrades stat profile", function()
  T.it("weighs the stats that matter by what is worn, armor left out", function()
    local p = U.Profile({ { [AGI] = 3, [STA] = 2, [ARMOR] = 100 }, { [AGI] = 1, [AP] = 4 } })
    T.eq(p.weights, { [AGI] = 0.4, [STA] = 0.2 * U.STAMINA_DAMP, [AP] = 0.4 }) -- stamina damped: nearly every piece has it
    T.eq(p.items, 2)
    T.eq(p.top, AGI)
    T.eq(U.Score(p, { [AGI] = 10, [INT] = 50, [ARMOR] = 500 }), 4)
  end)

  T.it("names the top primary stat, stamina not counted", function()
    T.eq(U.TopPrimary({ [STA] = 20, [INT] = 5, [SPI] = 4 }), INT)
    T.eq(U.TopPrimary({ [STA] = 20 }), nil)
  end)

  T.it("tells the armour type worn mostly from 70 percent on", function()
    T.eq(U.ArmorType({ 2, 2, 2, 2, 2, 2, 2, 1, 1, 1 }), 2)
    T.eq(U.ArmorType({ 2, 2, 2, 2, 2, 2, 1, 1, 1, 1 }), nil)
    T.eq(U.ArmorType({}), nil)
  end)

  T.it("lists the stat differences, the largest first", function()
    T.eq(U.Diff({ [AGI] = 8, [STA] = 5, [ARMOR] = 30 }, { [INT] = 6, [STA] = 5 }),
      { { key = AGI, delta = 8 }, { key = INT, delta = -6 } })
  end)

  T.it("orders the differences by their weight in the profile, the largest effect first", function()
    local weights = { [AGI] = 0.3, [STR] = 0.2, [STA] = 0.05 }
    local diff = U.Diff({ [STR] = 7, [AGI] = 8, [STA] = 8 }, { [STR] = 13, [AGI] = 13 }, weights)
    T.eq(diff, { { key = AGI, delta = -5 }, { key = STR, delta = -6 }, { key = STA, delta = 8 } })
    local names = { [AGI] = "Beweglichkeit", [STR] = "Stärke", [STA] = "Ausdauer" }
    T.eq(U.DiffText(diff, function(key) return names[key] end),
      "|cffff5a5a−5 Beweglichkeit|r, |cffff5a5a−6 Stärke|r, |cff4ce64c+8 Ausdauer|r")
  end)

  T.it("writes the differences as a line with the client's stat names", function()
    local names = { [AGI] = "Beweglichkeit", [INT] = "Intelligenz" }
    local text = U.DiffText({ { key = AGI, delta = 8 }, { key = INT, delta = -6 }, { key = "ITEM_MOD_X", delta = 1.5 } },
      function(key) return names[key] end)
    T.eq(text, "|cff4ce64c+8 Beweglichkeit|r, |cffff5a5a−6 Intelligenz|r, |cff4ce64c+1.5 ITEM_MOD_X|r")
    T.eq(U.DiffText({}, function() end), nil)
  end)

  T.it("falls back to the top primary stat with a weak profile", function()
    local few = { items = { [6] = item(1, 47), [1] = item(101, 45) } } -- two pieces with stats
    STATS[710], STATS[711] = { [INT] = 12 }, { [STR] = 12 }
    INFO[710] = { equipLoc = "INVTYPE_WAIST", level = 52, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    INFO[711] = { equipLoc = "INVTYPE_WAIST", level = 52, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    T.eq(#For(MEMBER, few, { maker("t", { 1 }) }, { [1] = 710 }), 1)
    T.eq(#For(MEMBER, few, { maker("t", { 1 }) }, { [1] = 711 }), 0)
    -- the item level still has to be higher by three
    INFO[712] = { equipLoc = "INVTYPE_WAIST", level = 49, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    STATS[712] = { [INT] = 12 }
    T.eq(#For(MEMBER, few, { maker("t", { 1 }) }, { [1] = 712 }), 0)
    -- nothing worn in the slot: the profile's top stat
    INFO[713] = { equipLoc = "INVTYPE_FEET", level = 30, reqLevel = 25, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    INFO[714] = { equipLoc = "INVTYPE_FEET", level = 30, reqLevel = 25, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    STATS[713], STATS[714] = { [INT] = 3 }, { [AGI] = 3 }
    T.eq(#For(MEMBER, few, { maker("t", { 1 }) }, { [1] = 713 }), 1)
    T.eq(#For(MEMBER, few, { maker("t", { 1 }) }, { [1] = 714 }), 0)
    -- nothing with stats at all: nothing to go by
    T.eq(#For(MEMBER, { items = {} }, { maker("t", { 1 }) }, { [1] = 713 }), 0)
  end)
end)

T.describe("Upgrades requirements", function()
  local DE = { minLevel = "Benötigt Stufe %d", minSkill = "Benötigt %s (%d)", reqSkill = "Benötigt %s",
    classes = "Klassen: %s", reputation = "Benötigt %s - %s" }

  T.it("reads profession, classes and reputation from the tooltip in the client's language", function()
    T.eq(U.ParseRequirements({ "Goblinmörser", "Schmuck", "Benötigt Stufe 40", "|cffff2020Benötigt Ingenieurskunst (205)|r" }, DE),
      { skill = "Ingenieurskunst", rank = 205 })
    T.eq(U.ParseRequirements({ "Klassen: Schurke, Krieger" }, DE), { classes = { "Schurke", "Krieger" } })
    T.eq(U.ParseRequirements({ "Benötigt Sturmwind - Wohlwollend" }, DE), { reputation = true })
    T.eq(U.ParseRequirements({ "Ausdauer +5", "Benötigt Stufe 12" }, DE), {})
  end)

  T.it("understands numbered format arguments", function()
    T.eq(U.ParseRequirements({ "205 Engineering needed" }, { minSkill = "%2$d %1$s needed" }),
      { skill = "Engineering", rank = 205 })
  end)

  T.it("checks them against the member", function()
    local who = { classNames = { Druide = true }, profs = { ingenieurskunst = 210 } }
    T.eq(U.Meets({}, who), true)
    T.eq(U.Meets({ skill = "Ingenieurskunst", rank = 205 }, who), true)
    T.eq(U.Meets({ skill = "Ingenieurskunst", rank = 225 }, who), false)
    T.eq(U.Meets({ skill = "Schneiderei", rank = 1 }, who), false)
    T.eq(U.Meets({ skill = "Ingenieurskunst" }, { profs = { ingenieurskunst = true } }), true)
    T.eq(U.Meets({ classes = { "Schurke" } }, who), false)
    T.eq(U.Meets({ classes = { "Schurke", "Druide" } }, who), true)
    T.eq(U.Meets({ reputation = true }, who), false)
  end)
end)

T.describe("Upgrades with talent spec weights", function()
  -- waists: a cloth caster piece, a leather agility piece, a leather stamina pile
  INFO[560] = { equipLoc = "INVTYPE_WAIST", level = 58, reqLevel = 50, classID = 4, subclassID = 1, bind = 2, quality = 3 }
  INFO[561] = { equipLoc = "INVTYPE_WAIST", level = 50, reqLevel = 45, classID = 4, subclassID = 2, bind = 2, quality = 2 }
  INFO[562] = { equipLoc = "INVTYPE_WAIST", level = 52, reqLevel = 45, classID = 4, subclassID = 2, bind = 2, quality = 2 }
  STATS[560] = { [INT] = 12, [SPI] = 6, [STA] = 6 }
  STATS[561] = { [AGI] = 10, [STR] = 4, [STA] = 3 }
  STATS[562] = { [STA] = 20, [AGI] = 1 }
  local makers = { maker("crafter", { 9060, 9061, 9062 }) }
  local craft = { [9060] = 560, [9061] = 561, [9062] = 562 }
  local function Offered(member, gear)
    local ids = {}
    for _, row in ipairs(For(member, gear or caster(), makers, craft)) do ids[#ids + 1] = row.itemID end
    return ids
  end
  local druid = function(weights) return { key = "d", level = 52, classFile = "DRUID", weights = weights } end

  T.it("scores a feral cat by cat weights: the cloth caster piece and the stamina pile lose", function()
    T.eq(Offered(druid(nil)), { 560 }) -- by the worn caster gear (the fallback)
    T.eq(Offered(druid(ns.StatWeights.For("DRUID_CAT"))), { 561 })
  end)

  T.it("scores a bear by bear weights: the stamina pile wins", function()
    T.eq(Offered(druid(ns.StatWeights.For("DRUID_BEAR"))), { 562 })
  end)

  T.it("orders the comparison by the spec weights", function()
    local rows = For(druid(ns.StatWeights.For("DRUID_CAT")), caster(), makers, craft)
    T.eq(rows[1].diff[1].key, AGI)
  end)

  T.it("offers a feral cat a better leather chest over worn uncommon leather (Sven's case)", function()
    -- worn: a leather chest of item level 30 with +7 agility +7 stamina; offered: one of 40 with +12 agility +8 strength
    INFO[580] = { equipLoc = "INVTYPE_CHEST", level = 40, reqLevel = 35, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[580] = { [AGI] = 12, [STR] = 8 }
    INFO[730] = { equipLoc = "INVTYPE_CHEST", level = 30, reqLevel = 25, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[730] = { [AGI] = 7, [STA] = 7 }
    local gear = { items = { [5] = item(730, 30) } }
    local member = { key = "d", level = 47, classFile = "DRUID", weights = ns.StatWeights.For("DRUID_CAT") }
    local rows = For(member, gear, { maker("leatherworker", { 9080 }) }, { [9080] = 580 })
    T.eq(#rows, 1)
    T.eq(rows[1].itemID, 580)
    T.eq(rows[1].slot, 5)
  end)

  T.it("tells for each slot why each crafted piece is offered or not (/guildy upgradeprobe)", function()
    local function chest(id, sub, stats, extra)
      INFO[id] = { equipLoc = "INVTYPE_CHEST", level = 40, reqLevel = 35, classID = 4, subclassID = sub, bind = 2, quality = 2 }
      for k, v in pairs(extra or {}) do INFO[id][k] = v end
      STATS[id] = stats
    end
    chest(580, 2, { [AGI] = 12, [STR] = 8 })               -- offered
    chest(581, 1, { [INT] = 30 })                          -- cloth under worn leather
    chest(582, 2, { [AGI] = 7, [STA] = 30 })               -- better on stamina alone
    chest(583, 2, { [AGI] = 7, [STR] = 1 })                -- under the 10 %
    chest(584, 2, { [AGI] = 20 }, { reqLevel = 50 })        -- too high a level
    chest(585, 2, { [AGI] = 20 }, { bind = 1 })             -- bind on pickup: never in the index
    chest(586, 2, { [AGI] = 15 })                          -- needs a profession
    REQ[586] = { skill = "Lederverarbeitung", rank = 250 }
    INFO[730] = { equipLoc = "INVTYPE_CHEST", level = 30, reqLevel = 25, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[730] = { [AGI] = 7, [STA] = 7 }
    local craft = {}
    for id = 580, 586 do craft[9000 + id] = id end
    craft[9999] = 599 -- an item the game has not loaded yet
    local recipes = {}
    for spell in pairs(craft) do recipes[#recipes + 1] = spell end
    table.sort(recipes)
    local index = U.Index({ maker("lw", recipes) }, craft, info)
    local member = { key = "d", level = 47, classFile = "DRUID", weights = ns.StatWeights.For("DRUID_CAT") }
    local trace = {}
    local rows = U.ForIndex(member, { items = { [5] = item(730, 30), [6] = { id = 731, e = 0, s = -17, l = 30, q = 2 } } },
      index, info, GAME, trace)
    REQ[586] = nil
    T.eq(#rows, 1)
    T.eq(rows[1].itemID, 580)
    local chestTrace = trace.slots[5]
    T.eq(chestTrace.worn.itemID, 730)
    T.eq(chestTrace.worn.source, "link")
    T.truthy(math.abs(chestTrace.worn.score - 7.7) < 1e-9, chestTrace.worn.score)
    T.eq(chestTrace.count, 6) -- in the index for the chest (the bind on pickup piece is not)
    local verdict = {}
    for _, c in ipairs(chestTrace.candidates) do verdict[c.itemID] = c.verdict end
    T.eq(verdict, { [580] = "offered", [581] = "armour type", [582] = "stamina-only", [583] = "threshold",
      [584] = "level 50", [586] = "requirement Lederverarbeitung 250" })
    T.eq(chestTrace.candidates[1].itemID, 584) -- by score: 20 agility first
    T.eq(chestTrace.candidates[1].level, 40)
    -- a worn piece whose stats cannot be known: the slot is skipped, and the probe says so
    T.eq(trace.slots[6].worn.source, "unknown")
    T.eq(trace.slots[6].skipped, "worn stats unknown")
    T.eq(trace.weights, ns.StatWeights.For("DRUID_CAT"))
    -- the index by state
    T.eq(#index.pending, 1)
    T.eq(index.left[585], "bind on pickup")
  end)

  T.it("trusts spec weights with few worn pieces known", function()
    -- one worn piece: too few for a profile, which goes by item level and the worn piece's top stat
    local gear = { items = { [6] = item(1, 51) } }
    T.eq(Offered(druid(nil), gear), { 560 })
    T.eq(Offered(druid(ns.StatWeights.For("DRUID_CAT")), gear), { 561 })
  end)
end)

T.describe("Worn pieces without stats", function()
  local function loc(id, equipLoc, quality)
    INFO[id] = { equipLoc = equipLoc, level = 40, reqLevel = 35, classID = 4, subclassID = 0, bind = 2, quality = quality or 3 }
    STATS[id] = {}
  end

  T.it("counts a trinket with only a use effect as known with score 0 (Sven's trinket 280766)", function()
    loc(280766, "INVTYPE_TRINKET")
    local worn = { id = 280766, e = 0, s = 0, l = 40, q = 3 }
    T.eq(U.WornStats(worn, GAME, INFO[280766]), {})
    local trace = {}
    U.ForIndex({ key = "d", level = 47, classFile = "DRUID", weights = ns.StatWeights.For("DRUID_CAT") },
      { items = { [13] = worn } }, U.Index({}, {}, info), info, GAME, trace)
    T.eq(trace.slots[13].worn.source, "link")
    T.eq(trace.slots[13].worn.score, 0)
    T.eq(trace.slots[13].skipped, nil)
  end)

  T.it("counts plain rings, necks, shirts and tabards without stats as known", function()
    for id, equipLoc in pairs({ [281] = "INVTYPE_FINGER", [282] = "INVTYPE_NECK", [283] = "INVTYPE_BODY", [284] = "INVTYPE_TABARD" }) do
      loc(id, equipLoc)
      T.eq(U.WornStats({ id = id, e = 0, s = 0, l = 40, q = 3 }, GAME, INFO[id]), {}, equipLoc)
    end
  end)

  T.it("keeps a ring with bonus IDs and a chest without stats unknown: their stats did not come through", function()
    loc(285, "INVTYPE_FINGER")
    local stats, gone = U.WornStats({ id = 285, e = 0, s = 0, l = 40, q = 2, b = { 6655 } }, GAME, INFO[285])
    T.eq({ stats, gone }, { nil, true })
    loc(286, "INVTYPE_CHEST", 2)
    stats, gone = U.WornStats({ id = 286, e = 0, s = 0, l = 40, q = 2 }, GAME, INFO[286])
    T.eq({ stats, gone }, { nil, true })
  end)
end)

T.describe("Armour type by the item's numeric subclass", function()
  -- Tough Scorpid (8203 ...) is mail in classic and on Forever (Wowhead: class 4, subclass 3), although its
  -- icon is a leather one and leatherworkers make it: a feral druid in leather is not offered it. The rule
  -- reads only GetItemInfo's subclassID, never the name or the localized subtype.
  local function scorpid(sub)
    INFO[8203] = { name = "Feste Skorpidbrustplatte", equipLoc = "INVTYPE_CHEST", level = 44, reqLevel = 39, classID = 4,
      subclassID = sub, bind = 2, quality = 2 }
    STATS[8203] = { [AGI] = 15, [SPI] = 7 }
    INFO[730] = { equipLoc = "INVTYPE_CHEST", level = 30, reqLevel = 25, classID = 4, subclassID = 2, bind = 2, quality = 2 }
    STATS[730] = { [AGI] = 7, [STA] = 7 }
    local member = { key = "d", level = 47, classFile = "DRUID", weights = ns.StatWeights.For("DRUID_CAT") }
    local trace = {}
    local craft = { [9203] = 8203 }
    local rows = U.ForIndex(member, { items = { [5] = item(730, 30) } }, U.Index({ maker("lw", { 9203 }) }, craft, info),
      info, GAME, trace)
    return rows, trace.slots[5].candidates[1].verdict
  end

  T.it("rejects the mail Tough Scorpid breastplate for a druid in leather", function()
    local rows, verdict = scorpid(3)
    T.eq(#rows, 0)
    T.eq(verdict, "armour type")
  end)

  T.it("offers the same piece were it leather by subclass", function()
    local rows, verdict = scorpid(2)
    T.eq(#rows, 1)
    T.eq(verdict, "offered")
  end)
end)
