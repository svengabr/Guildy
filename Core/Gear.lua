-- Gear of guild members item by item, pure: the record, its wire form, merge, the ready mark, the
-- enchant line of a tooltip and the layout of the gear list. The game side is Game/Gear.lua.
--   guild.gear[nameKey] = { ts = when read, src = "self"|"seen"|"relay"|"api", race = raceID|nil,
--     sex = 2|3|nil, items = { [slot] = { id, e, s, l, q } } }
--   slot 1..19 (shirt 4 and tabard 19 only for the model), e = enchantID or 0, s = suffixID or 0,
--   l = item level, q = quality 0..5
--   GuildyDB.enchantText = { locale, names = { [enchantID] = text } } (per account, reset on a new locale)
-- An incomplete read (a slot with an item ID but no link) is never stored.
local _, ns = ...

local Gear = {}
ns.Gear = Gear

Gear.SLOTS = {}
for slot = 1, 19 do Gear.SLOTS[slot] = slot end
Gear.LIST_SLOTS = ns.Stats.GEAR_SLOTS -- the 17 slots of the list (no shirt, no tabard)
Gear.MAX_AGE = 60 * 86400
-- slots flagged "no enchantment" when empty of one; the off hand only for a weapon or a shield
Gear.ENCHANTABLE = { [15] = true, [5] = true, [9] = true, [10] = true, [8] = true, [16] = true, [17] = "weapon" }
Gear.OFFHAND_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true }
Gear.MIN_READY = 5
Gear.SOURCES = { self = true, seen = true, relay = true, api = true }

local function IsInt(n)
  return type(n) == "number" and n == n and n == math.floor(n) and n > -2 ^ 31 and n < 2 ^ 31
end
local function IsId(n) return IsInt(n) and n > 0 end

-- id, enchant, suffix of an item link or item string; nil when it is none
function Gear.ParseLink(link)
  if type(link) ~= "string" then return nil end
  local body = link:match("item:([%-%d:]+)")
  if not body then return nil end
  local fields, i = {}, 0
  for field in (body .. ":"):gmatch("([^:]*):") do
    i = i + 1
    fields[i] = tonumber(field) or 0
  end
  local id = fields[1]
  if not IsId(id) then return nil end
  return id, fields[2] or 0, fields[7] or 0
end

function Gear.ItemString(item)
  return ("item:%d:%d:0:0:0:0:%d"):format(item.id, item.e or 0, item.s or 0)
end

-- items from the links of one read: links { [slot] = link }, ids { [slot] = itemID } (what the game says
-- is equipped), info(link) -> quality, item level. nil when a slot has an ID but no link, or info is missing.
function Gear.FromLinks(links, ids, info)
  local items = {}
  for slot = 1, 19 do
    local link = links[slot]
    if link == nil then
      if ids and ids[slot] then return nil end
    else
      local id, e, s = Gear.ParseLink(link)
      if not id then return nil end
      local quality, level = info(link)
      if type(quality) ~= "number" or type(level) ~= "number" then return nil end
      items[slot] = { id = id, e = e, s = s, l = math.max(0, math.floor(level)), q = math.max(0, math.min(5, math.floor(quality))) }
    end
  end
  return items
end

-- "slot:id:e:s:l:q" -> slot, item; nil when any field is wrong
local function ReadSlot(text)
  if type(text) ~= "string" then return nil end
  local parts = {}
  for field in (text .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = tonumber(field) end
  if #parts ~= 6 then return nil end
  local slot, id, e, s, l, q = parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
  if not (IsInt(slot) and slot >= 1 and slot <= 19) then return nil end
  if not (IsId(id) and IsInt(e) and e >= 0 and IsInt(s) and IsInt(l) and l >= 0 and IsInt(q) and q >= 0 and q <= 5) then
    return nil
  end
  return slot, { id = id, e = e, s = s, l = l, q = q }
end

-- A record from the guild (wire form) as stored, or nil; nil too without a single valid item (an empty
-- record would wipe good gear)
function Gear.Validate(raw, now)
  if type(raw) ~= "table" or not IsId(raw.ts) or raw.ts > now + 300 then return nil end
  local rec = { ts = raw.ts, src = Gear.SOURCES[raw.src] and raw.src or "relay", items = {} }
  if IsId(raw.r) then rec.race = raw.r end
  if raw.x == 2 or raw.x == 3 then rec.sex = raw.x end
  if type(raw.i) == "table" then
    for n = 1, math.min(#raw.i, 19) do
      local slot, item = ReadSlot(raw.i[n])
      if slot and not rec.items[slot] then rec.items[slot] = item end
    end
  end
  if not next(rec.items) then return nil end
  return rec
end

-- The wire form of a stored record
function Gear.Wire(rec)
  local slots, list = {}, {}
  for slot in pairs(rec.items or {}) do slots[#slots + 1] = slot end
  table.sort(slots)
  for _, slot in ipairs(slots) do
    local it = rec.items[slot]
    list[#list + 1] = ("%d:%d:%d:%d:%d:%d"):format(slot, it.id, it.e or 0, it.s or 0, it.l or 0, it.q or 0)
  end
  return { ts = rec.ts, src = rec.src, r = rec.race, x = rec.sex, i = list }
end

-- Newer wins; at the same time the member's own reading wins. A record without items is never taken.
-- True when rec was taken.
function Gear.Merge(book, key, rec)
  if type(rec) ~= "table" or type(rec.items) ~= "table" or not next(rec.items) then return false end
  local have = book[key]
  if type(have) == "table" and type(have.ts) == "number" then
    if have.ts > rec.ts then return false end
    if have.ts == rec.ts and (rec.src ~= "self" or have.src == "self") then return false end
  end
  book[key] = rec
  return true
end

-- { [nameKey] = ts } of the records younger than MAX_AGE
function Gear.Digest(book, now)
  local digest = {}
  for key, rec in pairs(type(book) == "table" and book or {}) do
    if type(rec) == "table" and type(rec.ts) == "number" and now - rec.ts <= Gear.MAX_AGE then digest[key] = rec.ts end
  end
  return digest
end

-- Removes the records of members not in keep. Returns how many were removed.
function Gear.Prune(book, keep)
  local removed = 0
  for key in pairs(book) do
    if not keep[key] then
      book[key] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- Average item level times ten over the listed slots with an item, nil without items
function Gear.Average(rec)
  local sum, count = 0, 0
  for _, slot in ipairs(Gear.LIST_SLOTS) do
    local item = rec and rec.items and rec.items[slot]
    if item then sum, count = sum + (item.l or 0), count + 1 end
  end
  if count == 0 then return nil end
  return math.floor(sum / count * 10 + 0.5)
end

-- { [slot] = true }, count: enchantable slots with an item but no enchantment. equipLocOf(itemID) ->
-- equip location or nil (unknown yet: the off hand is not counted then)
function Gear.Unenchanted(rec, equipLocOf)
  local set, count = {}, 0
  for slot, kind in pairs(Gear.ENCHANTABLE) do
    local item = rec and rec.items and rec.items[slot]
    if item and (item.e or 0) == 0 and (kind == true or Gear.OFFHAND_WEAPON[equipLocOf(item.id) or ""]) then
      set[slot] = true
      count = count + 1
    end
  end
  return set, count
end

-- The median average item level (tenths) of the members at level: list { {level, ilvl} }; nil with fewer
-- than MIN_READY of them. With an even count the lower of the two middle values.
function Gear.ReadyMark(list, level)
  local values = {}
  for _, entry in ipairs(list) do
    if entry[1] == level and type(entry[2]) == "number" then values[#values + 1] = entry[2] end
  end
  if #values < Gear.MIN_READY then return nil end
  table.sort(values)
  return values[math.ceil(#values / 2)]
end

local function Plain(text)
  return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
end

-- The first tooltip line of the enchanted item the plain one lacks (duplicates counted), nil when none
function Gear.EnchantLine(withLines, withoutLines)
  local count = {}
  for _, text in ipairs(withoutLines or {}) do
    local plain = Plain(text)
    count[plain] = (count[plain] or 0) + 1
  end
  for _, text in ipairs(withLines or {}) do
    local plain = Plain(text)
    if (count[plain] or 0) > 0 then
      count[plain] = count[plain] - 1
    elseif plain ~= "" then
      return plain
    end
  end
  return nil
end

-- The enchant texts of this account in locale (a new table when the locale changed)
function Gear.EnchantCache(db, locale)
  local cache = db.enchantText
  if type(cache) ~= "table" or cache.locale ~= locale or type(cache.names) ~= "table" then
    cache = { locale = locale, names = {} }
    db.enchantText = cache
  end
  return cache.names
end

-- Layout of the gear list: row height, width of the level bar and of the enchant text for a box of
-- height x width. 17 rows of at least 18 px; the bar narrows first (130 to 60), then the enchant text
-- (200 to 0); the item name keeps at least NAME_MIN.
Gear.ROWS = 17
Gear.HEAD = 52       -- header and the line under the list
Gear.FIXED = 170     -- slot name, icon, level number and the gaps
Gear.NAME_MIN = 140
function Gear.Fit(height, width)
  local rowH = math.max(18, math.floor((height - Gear.HEAD) / Gear.ROWS))
  local room = width - Gear.FIXED - Gear.NAME_MIN
  local barW = math.max(60, math.min(130, room - 200))
  local enchantW = math.max(0, math.min(200, room - barW))
  return rowH, barW, enchantW
end
