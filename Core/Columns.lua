-- The columns of a list the player arranges (the member list, UI/TabMembers.lua), pure. A list has its
-- columns in a default order, each with a default width; the player's choice is three small tables:
--   order  = { key, ... }        the columns from the left (those it does not name follow in their default order)
--   widths = { key = pixels }    only where a width differs from the default
--   off    = { key = false }     the hidden columns
local _, ns = ...

local Columns = {}
ns.Columns = Columns

Columns.MIN_WIDTH = 28
Columns.MAX_WIDTH = 480

local floor, max, min = math.floor, math.max, math.min

-- The width a column has: the player's, kept within what a column can be, else its default
function Columns.Width(def, widths)
  local chosen = type(widths) == "table" and widths[def.key] or nil
  if type(chosen) ~= "number" or chosen ~= chosen then return def.width end
  return max(Columns.MIN_WIDTH, min(Columns.MAX_WIDTH, floor(chosen + 0.5)))
end

-- The keys of every column from the left: the player's order as far as it names columns there are
-- (each once), then the others in their default order
function Columns.Order(defs, order)
  local known, keys, seen = {}, {}, {}
  for _, def in ipairs(defs) do known[def.key] = true end
  if type(order) == "table" then
    for i = 1, min(#order, 60) do
      local key = order[i]
      if known[key] and not seen[key] then
        seen[key] = true
        keys[#keys + 1] = key
      end
    end
  end
  for _, def in ipairs(defs) do
    if not seen[def.key] then keys[#keys + 1] = def.key end
  end
  return keys
end

-- Every column as the list shows it, from the left: { key, width, hidden, def }.
-- saved = { order, widths, off }; hide(key) = true for a column that is hidden whatever the player chose.
function Columns.Arrange(defs, saved, hide)
  saved = type(saved) == "table" and saved or {}
  local byKey = {}
  for _, def in ipairs(defs) do byKey[def.key] = def end
  local off = type(saved.off) == "table" and saved.off or {}
  local list = {}
  for i, key in ipairs(Columns.Order(defs, saved.order)) do
    local def = byKey[key]
    list[i] = { key = key, def = def, width = Columns.Width(def, saved.widths),
      hidden = (not def.fixed and off[key] == false) or (hide ~= nil and hide(key) == true) }
  end
  return list
end

-- The order with `key` moved before the column `before` (nil: to the end)
function Columns.Move(keys, key, before)
  local out = {}
  if before == key then before = false end -- before itself: where it is
  for _, other in ipairs(keys) do
    if other == before then out[#out + 1] = key end
    if other ~= key or before == false then out[#out + 1] = other end
  end
  if before == nil then out[#out + 1] = key end
  return out
end

-- A column dragged sideways: `shown` are the columns that show ({ key, x, width }, as they stood when
-- the drag began), `middle` is where the middle of the dragged one is now. Returns the key of the shown
-- column it lands before (nil: at the end): it has passed those whose middle lies left of its own.
function Columns.Before(shown, key, middle)
  for _, column in ipairs(shown) do
    if column.key ~= key and column.x + column.width / 2 > middle then return column.key end
  end
  return nil
end

-- nil when the keys are the default order (settings only store what differs)
function Columns.Differs(defs, keys)
  for i, def in ipairs(defs) do
    if keys[i] ~= def.key then return keys end
  end
  return nil
end
