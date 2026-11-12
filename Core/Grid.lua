-- The grid a tab's boxes stand on (UI/Board.lua), pure. A layout is a list of
--   { k = box, x, y, w, h, o = { option = value } or nil }
-- in cells: x and y from the top left corner counted from 0, Grid.COLS cells wide, as many rows down
-- as the boxes need. Boxes never overlap: a box put where others stand takes the place and they move
-- down, and every box moves up as far as there is room (Grid.Compact).
local _, ns = ...

local Grid = {}
ns.Grid = Grid

Grid.COLS = 12
Grid.PAGE = 12      -- the rows one page of a tab shows without scrolling
Grid.MAX_ROWS = 60

local floor, max, min = math.floor, math.max, math.min

local function Overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- True when item lies inside the grid and on no other box of the layout
function Grid.Fits(layout, item)
  if item.x < 0 or item.y < 0 or item.x + item.w > Grid.COLS or item.y + item.h > Grid.MAX_ROWS then return false end
  for _, other in ipairs(layout) do
    if other.k ~= item.k and Overlap(other, item) then return false end
  end
  return true
end

-- The rows the layout reaches down to
function Grid.Rows(layout)
  local rows = 0
  for _, item in ipairs(layout) do rows = max(rows, item.y + item.h) end
  return rows
end

-- A place for a new box: a free one among the boxes at its usual size, else one at its smallest size,
-- else below everything at its usual size. nil only when the grid is full down to its last row.
function Grid.Spot(layout, key, w, h, minW, minH)
  local rows = max(Grid.PAGE, Grid.Rows(layout))
  for _, try in ipairs({ { w, h, rows - h }, { minW, minH, rows - minH }, { w, h, rows } }) do
    for y = 0, try[3] do
      for x = 0, Grid.COLS - try[1] do
        local item = { k = key, x = x, y = y, w = try[1], h = try[2] }
        if Grid.Fits(layout, item) then return item end
      end
    end
  end
  return nil
end

-- The free rectangles among the boxes in the first `rows` rows that are at least minW x minH: found
-- row by row from the top left, each as wide as the free run it starts in and as tall as that stays free
function Grid.Gaps(layout, rows, minW, minH)
  local used = {}
  for _, item in ipairs(layout) do
    for y = item.y, min(rows, item.y + item.h) - 1 do
      for x = item.x, item.x + item.w - 1 do used[y * Grid.COLS + x] = true end
    end
  end
  local gaps = {}
  for y = 0, rows - 1 do
    for x = 0, Grid.COLS - 1 do
      if not used[y * Grid.COLS + x] then
        local w = 0
        while x + w < Grid.COLS and not used[y * Grid.COLS + x + w] do w = w + 1 end
        local h = 1
        while y + h < rows do
          local free = true
          for xx = x, x + w - 1 do
            if used[(y + h) * Grid.COLS + xx] then free = false break end
          end
          if not free then break end
          h = h + 1
        end
        for yy = y, y + h - 1 do
          for xx = x, x + w - 1 do used[yy * Grid.COLS + xx] = true end
        end
        if w >= minW and h >= minH then gaps[#gaps + 1] = { x = x, y = y, w = w, h = h } end
      end
    end
  end
  return gaps
end

local function Whole(value, low, high)
  if type(value) ~= "number" or value ~= value or value < low or value > high then return nil end
  return floor(value)
end

-- A box's options made safe: short names, values true / false / a number / a short text
function Grid.Options(o)
  if type(o) ~= "table" then return nil end
  local clean, count = {}, 0
  for key, value in pairs(o) do
    local kind = type(value)
    if type(key) == "string" and #key <= 24 and count < 24
      and (kind == "boolean" or kind == "number" or (kind == "string" and #value <= 60)) then
      clean[key] = value
      count = count + 1
    end
  end
  if count == 0 then return nil end
  return clean
end

-- A saved layout made safe: only known boxes (least(key, options) gives the smallest { w, h } a box
-- works at, nil for a box there is not), each once, at least that size, inside the grid and on no
-- other. nil for what is no layout at all.
function Grid.Clean(saved, least)
  if type(saved) ~= "table" then return nil end
  local layout, seen = {}, {}
  for index = 1, min(#saved, 60) do
    local it = saved[index]
    if type(it) == "table" and type(it.k) == "string" and not seen[it.k] then
      local o = Grid.Options(it.o)
      local size = least(it.k, o or {})
      if size then
        local item = { k = it.k, x = Whole(it.x, 0, Grid.COLS - 1), y = Whole(it.y, 0, Grid.MAX_ROWS - 1),
          w = Whole(it.w, size[1], Grid.COLS), h = Whole(it.h, size[2], Grid.MAX_ROWS), o = o }
        if item.x and item.y and item.w and item.h and Grid.Fits(layout, item) then
          layout[#layout + 1] = item
          seen[it.k] = true
        end
      end
    end
  end
  return layout
end

-- The layout with every box moved up as far as it goes, in their order from the top; a box standing
-- on another moves down below it. `first`: the box that was just placed, which keeps its place among
-- those in the same row (the others make room for it).
function Grid.Compact(layout, first)
  local order = Grid.Copy(layout)
  table.sort(order, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if (a.k == first) ~= (b.k == first) then return a.k == first end
    if a.x ~= b.x then return a.x < b.x end
    return a.k < b.k
  end)
  local out = {}
  local function Free(item, y)
    local at = { k = item.k, x = item.x, y = y, w = item.w, h = item.h }
    for _, other in ipairs(out) do
      if Overlap(other, at) then return false end
    end
    return true
  end
  for _, item in ipairs(order) do
    while item.y > 0 and Free(item, item.y - 1) do item.y = item.y - 1 end
    while not Free(item, item.y) and item.y + item.h < Grid.MAX_ROWS do item.y = item.y + 1 end
    out[#out + 1] = item
  end
  return out
end

function Grid.Copy(layout)
  local out = {}
  for i, item in ipairs(layout) do
    local o
    if item.o then
      o = {}
      for key, value in pairs(item.o) do o[key] = value end
    end
    out[i] = { k = item.k, x = item.x, y = item.y, w = item.w, h = item.h, o = o }
  end
  return out
end
