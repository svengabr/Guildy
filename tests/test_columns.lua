local T = ...
local ns = T.pureNs()
local Columns = ns.Columns

local DEFS = { { key = "level", width = 34, fixed = true }, { key = "name", width = 175, fixed = true },
  { key = "rank", width = 100 }, { key = "zone", width = 120 }, { key = "note", width = 210 } }

local function Keys(list, shownOnly)
  local keys = {}
  for _, column in ipairs(list) do
    if not (shownOnly and column.hidden) then keys[#keys + 1] = column.key end
  end
  return table.concat(keys, " ")
end

T.describe("Columns", function()
  T.it("keeps the default order and widths while the player chose nothing", function()
    local list = Columns.Arrange(DEFS, nil)
    T.eq(Keys(list), "level name rank zone note")
    T.eq(list[2].width, 175)
    T.eq(list[2].hidden, false)
    T.eq(Keys(Columns.Arrange(DEFS, { order = "x", widths = 5, off = true })), "level name rank zone note")
  end)

  T.it("takes the player's order as far as it makes sense", function()
    T.eq(table.concat(Columns.Order(DEFS, { "note", "gone", "rank", "note", 7 }), " "), "note rank level name zone")
    T.eq(table.concat(Columns.Order(DEFS, {}), " "), "level name rank zone note")
    T.eq(Keys(Columns.Arrange(DEFS, { order = { "zone", "level" } })), "zone level name rank note")
  end)

  T.it("keeps a width within what a column can be", function()
    T.eq(Columns.Width(DEFS[3], { rank = 140.4 }), 140)
    T.eq(Columns.Width(DEFS[3], { rank = 3 }), Columns.MIN_WIDTH)
    T.eq(Columns.Width(DEFS[3], { rank = 9000 }), Columns.MAX_WIDTH)
    T.eq(Columns.Width(DEFS[3], { rank = "wide" }), 100)
    T.eq(Columns.Width(DEFS[3], { rank = 0 / 0 }), 100)
    T.eq(Columns.Width(DEFS[3], nil), 100)
  end)

  T.it("hides what the player switched off, but never a column that always stays", function()
    local list = Columns.Arrange(DEFS, { off = { rank = false, name = false, zone = true } })
    T.eq(Keys(list, true), "level name zone note")
    -- and what the list itself does not show to this player
    list = Columns.Arrange(DEFS, nil, function(key) return key == "note" end)
    T.eq(Keys(list, true), "level name rank zone")
  end)

  T.it("moves a column before another or to the end", function()
    local keys = Columns.Order(DEFS)
    T.eq(table.concat(Columns.Move(keys, "note", "name"), " "), "level note name rank zone")
    T.eq(table.concat(Columns.Move(keys, "level", nil), " "), "name rank zone note level")
    T.eq(table.concat(Columns.Move(keys, "rank", "zone"), " "), "level name rank zone note")
    T.eq(table.concat(Columns.Move(keys, "rank", "rank"), " "), "level name rank zone note")
    T.eq(table.concat(keys, " "), "level name rank zone note") -- the order given stays as it was
  end)

  T.it("lets a dragged column land where its middle is", function()
    -- as the list places them: 6 pixels between the columns
    local shown = { { key = "level", x = 8, width = 34 }, { key = "name", x = 48, width = 175 },
      { key = "rank", x = 229, width = 100 }, { key = "zone", x = 335, width = 120 } }
    -- rank (middle 279) where it stands: before zone, as it is
    T.eq(Columns.Before(shown, "rank", 279), "zone")
    -- a little to the left: nothing changes until its middle passes the name's (135)
    T.eq(Columns.Before(shown, "rank", 140), "zone")
    T.eq(Columns.Before(shown, "rank", 130), "name")
    T.eq(Columns.Before(shown, "rank", 0), "level")
    -- to the right past the zone's middle (395): at the end
    T.eq(Columns.Before(shown, "rank", 390), "zone")
    T.eq(Columns.Before(shown, "rank", 400), nil)
  end)

  T.it("stores an order only when it differs from Guildy's own", function()
    T.eq(Columns.Differs(DEFS, Columns.Order(DEFS)), nil)
    local moved = Columns.Move(Columns.Order(DEFS), "note", "rank")
    T.eq(Columns.Differs(DEFS, moved), moved)
  end)
end)
