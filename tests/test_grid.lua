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
