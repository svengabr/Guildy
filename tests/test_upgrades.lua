local T = ...
local ns = T.pureNs()
local U = ns.Upgrades

local function item(id, l) return { id = id, e = 0, s = 0, l = l, q = 2 } end

-- item infos: id -> { equipLoc, level, reqLevel, classID, subclassID, bind, quality }
local INFO = {
  [500] = { equipLoc = "INVTYPE_WAIST", level = 58, reqLevel = 50, classID = 4, subclassID = 1, bind = 2, quality = 3 },
  [501] = { equipLoc = "INVTYPE_WAIST", level = 50, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 },
  [502] = { equipLoc = "INVTYPE_WAIST", level = 49, reqLevel = 45, classID = 4, subclassID = 1, bind = 2, quality = 2 },
}
local function info(id) return INFO[id] end

local function maker(key, recipes, online, offline)
  return { key = key, online = online or false, offline = offline or 0, profs = { [197] = { recipes = recipes } } }
end

local MEMBER = { key = "me", level = 52, classFile = "MAGE" }

T.describe("Upgrades", function()
  T.it("offers a better piece from another member's book", function()
    local rows, missing = U.For(MEMBER, { items = { [6] = item(1, 47) } }, { maker("tailor", { 9001 }, true) }, { [9001] = 500 }, info)
    T.eq(#rows, 1)
    T.eq(rows[1].slot, 6)
    T.eq(rows[1].have, 47)
    T.eq(rows[1].offer, 58)
    T.eq(rows[1].itemID, 500)
    T.eq(rows[1].quality, 3)
    T.eq(rows[1].makers, { { key = "tailor", skillLine = 197, online = true } })
    T.eq(missing, {})
  end)

  T.it("needs a gain of at least three levels", function()
    local makers = { maker("tailor", { 9002, 9003 }) }
    local craft = { [9002] = 501, [9003] = 502 }
    T.eq(#U.For(MEMBER, { items = { [6] = item(1, 48) } }, makers, { [9003] = 502 }, info), 0) -- 49 - 48
    T.eq(#U.For(MEMBER, { items = { [6] = item(1, 47) } }, makers, { [9003] = 502 }, info), 0) -- 49 - 47 = 2
    local rows = U.For(MEMBER, { items = { [6] = item(1, 47) } }, makers, craft, info)
    T.eq(rows[1].offer, 50) -- 3 levels: shown, the better of the two
  end)

  T.it("skips the member's own book, a too high required level and bind on pickup", function()
    local gear = { items = { [6] = item(1, 47) } }
    T.eq(#U.For(MEMBER, gear, { maker("me", { 9001 }) }, { [9001] = 500 }, info), 0)
    T.eq(#U.For({ key = "me", level = 49, classFile = "MAGE" }, gear, { maker("t", { 9001 }) }, { [9001] = 500 }, info), 0)
    INFO[503] = { equipLoc = "INVTYPE_WAIST", level = 58, reqLevel = 50, classID = 4, subclassID = 1, bind = 1, quality = 3 }
    T.eq(#U.For(MEMBER, gear, { maker("t", { 9004 }) }, { [9004] = 503 }, info), 0)
    INFO[503].bind = 2
    T.eq(#U.For(MEMBER, gear, { maker("t", { 9004 }) }, { [9004] = 503 }, info), 1)
  end)

  T.it("offers only armour the class can wear", function()
    INFO[510] = { equipLoc = "INVTYPE_CHEST", level = 45, reqLevel = 35, classID = 4, subclassID = 4, bind = 2, quality = 2 }
    INFO[511] = { equipLoc = "INVTYPE_CHEST", level = 25, reqLevel = 18, classID = 4, subclassID = 3, bind = 2, quality = 2 }
    local makers = { maker("smith", { 9010, 9011 }) }
    local craft = { [9010] = 510, [9011] = 511 }
    T.eq(#U.For({ key = "w", level = 39, classFile = "WARRIOR" }, { items = { [5] = item(2, 30) } }, makers, { [9010] = 510 }, info), 0)
    T.eq(#U.For({ key = "w", level = 40, classFile = "WARRIOR" }, { items = { [5] = item(2, 30) } }, makers, { [9010] = 510 }, info), 1)
    -- a level 20 hunter who already wears mail gets mail
    INFO[3] = { equipLoc = "INVTYPE_HAND", level = 18, reqLevel = 15, classID = 4, subclassID = 3, bind = 2, quality = 2 }
    T.eq(#U.For({ key = "h", level = 20, classFile = "HUNTER" }, { items = { [5] = item(2, 15) } }, makers, { [9011] = 511 }, info), 0)
    T.eq(#U.For({ key = "h", level = 20, classFile = "HUNTER" }, { items = { [5] = item(2, 15), [10] = item(3, 18) } },
      makers, { [9011] = 511 }, info), 1)
    T.eq(#U.For({ key = "m", level = 50, classFile = "MAGE" }, { items = {} }, makers, craft, info), 0)
  end)

  T.it("never offers weapons, off hands or ranged items", function()
    INFO[520] = { equipLoc = "INVTYPE_WEAPON", level = 60, reqLevel = 1, classID = 2, subclassID = 7, bind = 2, quality = 3 }
    INFO[521] = { equipLoc = "INVTYPE_HOLDABLE", level = 60, reqLevel = 1, classID = 4, subclassID = 0, bind = 2, quality = 3 }
    INFO[522] = { equipLoc = "INVTYPE_RANGED", level = 60, reqLevel = 1, classID = 2, subclassID = 2, bind = 2, quality = 3 }
    INFO[523] = { equipLoc = "INVTYPE_SHIELD", level = 60, reqLevel = 1, classID = 4, subclassID = 6, bind = 2, quality = 3 }
    local rows = U.For(MEMBER, { items = {} }, { maker("t", { 1, 2, 3, 4 }) }, { [1] = 520, [2] = 521, [3] = 522, [4] = 523 }, info)
    T.eq(#rows, 0)
  end)

  T.it("compares a ring with the weaker ring slot and an empty slot with level 0", function()
    INFO[530] = { equipLoc = "INVTYPE_FINGER", level = 40, reqLevel = 35, classID = 4, subclassID = 0, bind = 2, quality = 2 }
    local makers = { maker("jc", { 9030 }) }
    local rows = U.For(MEMBER, { items = { [11] = item(4, 45), [12] = item(5, 30) } }, makers, { [9030] = 530 }, info)
    T.eq(rows[1].slot, 12)
    T.eq(rows[1].have, 30)
    rows = U.For(MEMBER, { items = { [11] = item(4, 45) } }, makers, { [9030] = 530 }, info)
    T.eq(rows[1].slot, 12)
    T.eq(rows[1].have, 0)
  end)

  T.it("shows five rows at most, the largest gain first", function()
    INFO[540] = { equipLoc = "INVTYPE_HEAD", level = 50, reqLevel = 40, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    INFO[541] = { equipLoc = "INVTYPE_FEET", level = 50, reqLevel = 40, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    INFO[542] = { equipLoc = "INVTYPE_HAND", level = 50, reqLevel = 40, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    INFO[543] = { equipLoc = "INVTYPE_WRIST", level = 50, reqLevel = 40, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    INFO[544] = { equipLoc = "INVTYPE_LEGS", level = 50, reqLevel = 40, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    INFO[545] = { equipLoc = "INVTYPE_WAIST", level = 50, reqLevel = 40, classID = 4, subclassID = 1, bind = 2, quality = 2 }
    local gear = { items = { [1] = item(1, 40), [8] = item(1, 30), [10] = item(1, 45), [9] = item(1, 20), [7] = item(1, 35),
      [6] = item(1, 25) } }
    local rows = U.For(MEMBER, gear, { maker("t", { 1, 2, 3, 4, 5, 6 }) },
      { [1] = 540, [2] = 541, [3] = 542, [4] = 543, [5] = 544, [6] = 545 }, info)
    T.eq(U.MAX_ROWS, 5)
    T.eq(#rows, 5)
    T.eq({ rows[1].slot, rows[2].slot, rows[3].slot, rows[4].slot, rows[5].slot }, { 9, 6, 8, 7, 1 })
  end)

  T.it("lists makers online first, then the ones seen last", function()
    local makers = { maker("a", { 9001 }, false, 30), maker("b", { 9001 }, false, 2), maker("c", { 9001 }, true) }
    local rows = U.For(MEMBER, { items = { [6] = item(1, 47) } }, makers, { [9001] = 500 }, info)
    T.eq({ rows[1].makers[1].key, rows[1].makers[2].key, rows[1].makers[3].key }, { "c", "b", "a" })
  end)

  T.it("asks for item infos it does not have", function()
    local rows, missing = U.For(MEMBER, { items = { [6] = item(1, 47) } }, { maker("t", { 9099, 9098 }) }, { [9099] = 599, [9098] = 599 }, info)
    T.eq(#rows, 0)
    T.eq(missing, { 599 })
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
