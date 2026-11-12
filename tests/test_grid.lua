local T = ...
local ns = T.pureNs()
local Grid = ns.Grid

local layout = { { k = "a", x = 0, y = 0, w = 3, h = 4 }, { k = "b", x = 3, y = 0, w = 9, h = 12 } }
local function Least(key, o)
  if key == "wide" then return { 5 + (o.extra ~= false and 3 or 0), 3 } end
  return ({ a = { 3, 3 }, b = { 4, 3 }, c = { 3, 3 } })[key]
end

T.describe("Grid", function()
  T.it("lets a box stand only inside the grid and on no other", function()
    T.eq(Grid.Fits(layout, { k = "c", x = 0, y = 4, w = 3, h = 8 }), true)
    T.eq(Grid.Fits(layout, { k = "c", x = 0, y = 3, w = 3, h = 3 }), false)
    T.eq(Grid.Fits(layout, { k = "c", x = 0, y = 4, w = 4, h = 3 }), false)
    T.eq(Grid.Fits(layout, { k = "c", x = -1, y = 4, w = 3, h = 3 }), false)
    T.eq(Grid.Fits(layout, { k = "c", x = 10, y = 20, w = 3, h = 3 }), false)
    T.eq(Grid.Fits(layout, { k = "c", x = 0, y = 20, w = 12, h = 3 }), true)  -- further down there is always room
    T.eq(Grid.Fits(layout, { k = "c", x = 0, y = Grid.MAX_ROWS - 2, w = 3, h = 3 }), false)
    T.eq(Grid.Fits(layout, { k = "a", x = 0, y = 1, w = 3, h = 4 }), true)   -- its own place is no obstacle
  end)

  T.it("finds a place for a new box: a free one, a smaller one, else below everything", function()
    T.eq(Grid.Rows(layout), 12)
    T.eq(Grid.Spot(layout, "c", 3, 5, 3, 3), { k = "c", x = 0, y = 4, w = 3, h = 5 })
    T.eq(Grid.Spot(layout, "c", 4, 5, 3, 3), { k = "c", x = 0, y = 4, w = 3, h = 3 })
    T.eq(Grid.Spot(layout, "c", 8, 4, 8, 4), { k = "c", x = 0, y = 12, w = 8, h = 4 })
    T.eq(Grid.Spot({}, "c", 3, 3, 3, 3), { k = "c", x = 0, y = 0, w = 3, h = 3 })
  end)

  T.it("names the free places among the boxes", function()
    T.eq(Grid.Gaps(layout, 12, 3, 3), { { x = 0, y = 4, w = 3, h = 8 } })
    T.eq(Grid.Gaps(layout, 12, 4, 3), {})
    T.eq(Grid.Gaps({}, 12, 3, 3), { { x = 0, y = 0, w = 12, h = 12 } })
    local two = Grid.Gaps({ { k = "a", x = 3, y = 0, w = 6, h = 12 } }, 12, 3, 3)
    T.eq(two, { { x = 0, y = 0, w = 3, h = 12 }, { x = 9, y = 0, w = 3, h = 12 } })
  end)

  T.it("makes room for a box put where others stand, and closes the room that got free", function()
    local function Places(list)
      local out = {}
      for _, item in ipairs(list) do out[item.k] = item.x .. "," .. item.y end
      return out
    end
    local board = { { k = "a", x = 0, y = 0, w = 3, h = 4 }, { k = "b", x = 3, y = 0, w = 9, h = 4 },
      { k = "c", x = 0, y = 4, w = 12, h = 6 }, { k = "t", x = 0, y = 10, w = 12, h = 2 } }
    T.eq(Places(Grid.Compact(board)), { a = "0,0", b = "3,0", c = "0,4", t = "0,10" }) -- nothing to do
    -- the row at the bottom dragged to the top: everything else moves down by its height
    board[4].y = 0
    T.eq(Places(Grid.Compact(board, "t")), { t = "0,0", a = "0,2", b = "3,2", c = "0,6" })
    -- dragged into the middle: what stands there and below moves down
    board[4].y = 4
    T.eq(Places(Grid.Compact(board, "t")), { a = "0,0", b = "3,0", t = "0,4", c = "0,6" })
    -- on its way up over the tall box it changes places only once its middle is above that one's
    board[4].y = 8
    T.eq(Places(Grid.Compact(board, "t")), { a = "0,0", b = "3,0", c = "0,4", t = "0,10" })
    board[4].y = 7
    T.eq(Places(Grid.Compact(board, "t")), { a = "0,0", b = "3,0", c = "0,4", t = "0,10" })
    board[4].y = 6
    T.eq(Places(Grid.Compact(board, "t")), { a = "0,0", b = "3,0", t = "0,4", c = "0,6" })
    -- and one dragged down from the top lets the others up only then: nothing jumps before
    local top = { { k = "t", x = 0, y = 0, w = 12, h = 2 }, { k = "c", x = 0, y = 2, w = 12, h = 6 } }
    top[1].y = 3
    T.eq(Places(Grid.Compact(top, "t")), { t = "0,0", c = "0,2" })
    top[1].y = 5
    T.eq(Places(Grid.Compact(top, "t")), { c = "0,0", t = "0,6" })
    board[4].y = 4
    -- a box taken away: what stood below it moves up; what has a box above it stays
    T.eq(Places(Grid.Compact({ board[2], board[3] })), { b = "3,0", c = "0,4" })
    T.eq(Places(Grid.Compact({ board[1], board[3] })), { a = "0,0", c = "0,4" })
    T.eq(Places(Grid.Compact({ board[3] })), { c = "0,0" })
    -- a box made wider takes the room: its neighbour moves below it
    T.eq(Places(Grid.Compact({ { k = "a", x = 0, y = 0, w = 6, h = 4 }, board[2] }, "a")), { a = "0,0", b = "3,4" })
    -- the options of a box come along, and the layout given stays as it was
    local kept = Grid.Compact({ { k = "a", x = 0, y = 5, w = 3, h = 3, o = { rank = false } } })
    T.eq(kept, { { k = "a", x = 0, y = 0, w = 3, h = 3, o = { rank = false } } })
    T.eq(board[1].y, 0)
  end)

  T.it("lets a box dragged sideways change places with its neighbours in the row", function()
    local row = { { k = "a", x = 0, y = 0, w = 4, h = 4 }, { k = "b", x = 4, y = 0, w = 3, h = 4 },
      { k = "c", x = 7, y = 0, w = 5, h = 4 }, { k = "d", x = 0, y = 4, w = 12, h = 4 } }
    local function Drag(key, x, y)
      local from
      for _, item in ipairs(row) do
        if item.k == key then from = item end
      end
      local trial, to = Grid.Shift(row, from, { k = key, x = x, y = y or from.y, w = from.w, h = from.h })
      local out = {}
      for _, item in ipairs(Grid.Compact(trial, key)) do out[item.k] = item.x .. "," .. item.y end
      return out, to.x
    end
    local same = { a = "0,0", b = "4,0", c = "7,0", d = "0,4" }
    -- a little to the right: the neighbour keeps it out, nothing moves
    T.eq({ Drag("a", 1) }, { same, 0 })
    -- its middle past the neighbour's: they change places
    T.eq({ Drag("a", 2) }, { same, 0 })
    T.eq({ Drag("a", 4) }, { { b = "0,0", a = "3,0", c = "7,0", d = "0,4" }, 3 })
    -- far to the right, past both: it stands at the end of the row
    T.eq({ Drag("a", 8) }, { { b = "0,0", c = "3,0", a = "8,0", d = "0,4" }, 8 })
    -- and the other way round
    T.eq({ Drag("c", 5) }, { same, 7 })
    T.eq({ Drag("c", 3) }, { { a = "0,0", c = "4,0", b = "9,0", d = "0,4" }, 4 })
    T.eq({ Drag("c", 0) }, { { c = "0,0", a = "5,0", b = "9,0", d = "0,4" }, 0 })
    T.eq({ Drag("b", 5) }, { same, 4 })
    -- dragged down as well: no changing of places, the box below makes room
    T.eq((Drag("a", 4, 6)), { b = "4,0", c = "7,0", d = "0,4", a = "4,8" })
    -- the layout given stays as it was
    T.eq(row[1].x, 0)
    T.eq(row[2].x, 4)
  end)

  T.it("takes a saved layout only as far as it makes sense", function()
    T.eq(Grid.Clean(nil, Least), nil)
    T.eq(Grid.Clean("x", Least), nil)
    T.eq(Grid.Clean({}, Least), {})
    T.eq(Grid.Clean(layout, Least), layout)
    T.eq(Grid.Clean({ layout[1], { k = "gone", x = 5, y = 0, w = 3, h = 3 }, { k = "a", x = 6, y = 6, w = 3, h = 3 },
      { k = "b", x = 2, y = 0, w = 9, h = 12 }, { k = "c", x = 0, y = 4, w = 2, h = 3 }, "junk",
      { k = "c", x = 0.5, y = 4, w = 3, h = 300 } }, Least), { layout[1] })
  end)

  T.it("keeps a box's options and sizes it by them", function()
    T.eq(Grid.Options({ extra = false, n = 3, s = "x", t = {}, [5] = true, long = ("x"):rep(80) }), { extra = false, n = 3, s = "x" })
    T.eq(Grid.Options({}), nil)
    T.eq(Grid.Options("x"), nil)
    -- 5 cells are enough only with the option off
    T.eq(Grid.Clean({ { k = "wide", x = 0, y = 0, w = 5, h = 3 } }, Least), {})
    T.eq(Grid.Clean({ { k = "wide", x = 0, y = 0, w = 5, h = 3, o = { extra = false } } }, Least),
      { { k = "wide", x = 0, y = 0, w = 5, h = 3, o = { extra = false } } })
    local copy = Grid.Copy({ { k = "wide", x = 0, y = 0, w = 5, h = 3, o = { extra = false } } })
    copy[1].o.extra = true
    T.eq(Grid.Copy({ { k = "a", x = 1, y = 2, w = 3, h = 4 } }), { { k = "a", x = 1, y = 2, w = 3, h = 4 } })
  end)
end)
