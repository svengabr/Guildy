-- Talent specs of guild members, pure: the record of points per talent tree, its wire form, merge, and
-- the spec decided from it (weights in Core/StatWeights.lua). The game side is Game/Talents.lua.
-- (Talent specs, not the profession specializations of Core/Specs.lua.)
--   guild.talents[nameKey] = { ts = when read, src = "self"|"seen"|"relay"|"api", trees = { p1, p2, p3 } }
--   p1..p3: points spent in the class's three talent trees, in the game's tab order
-- On the wire it rides in the GEAR message as k = { ts, src, p = { p1, p2, p3 } } (Game/Sync.lua); older
-- Guildy versions ignore the field.
local _, ns = ...

local Talents = {}
ns.Talents = Talents

Talents.MIN_LEVEL = 10    -- the first talent point
Talents.MIN_POINTS = 5    -- points the main tree needs before it says anything
Talents.MAX_POINTS = 100  -- per tree (Classic has 51 at level 60)
Talents.MAX_AGE = 60 * 86400
Talents.SOURCES = { self = true, seen = true, relay = true, api = true }
-- feral cat or bear by the worn gear: bear with this much defense on it, or with stamina at least this
-- many times agility and strength together
Talents.BEAR_DEFENSE = 10
Talents.BEAR_STAMINA = 1.2

local STA, AGI, STR, DEF = "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT",
  "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"

local function IsInt(n) return type(n) == "number" and n == n and n == math.floor(n) end
local function IsPoints(n) return IsInt(n) and n >= 0 and n <= Talents.MAX_POINTS end

-- One talent tab of GetTalentTabInfo's results: { name, points }, nil when they make no sense. Classic
-- clients give name, icon, pointsSpent, fileName; later ones id, name, description, icon, pointsSpent, ...
function Talents.TabPoints(...)
  local a, b, c, _, e = ...
  local name, points
  if type(a) == "string" then
    name, points = a, c
  elseif type(b) == "string" then
    name, points = b, e
  end
  if not (name and IsPoints(points)) then return nil end
  return { name = name, points = points }
end

-- The trees { p1, p2, p3 } of three tabs (TabPoints), nil for anything else
function Talents.FromTabs(tabs)
  if type(tabs) ~= "table" or #tabs ~= 3 then return nil end
  local trees = {}
  for i = 1, 3 do
    local points = type(tabs[i]) == "table" and tabs[i].points
    if not IsPoints(points) then return nil end
    trees[i] = points
  end
  return trees
end

local function Trees(list)
  if type(list) ~= "table" or #list ~= 3 then return nil end
  for i = 1, 3 do
    if not IsPoints(list[i]) then return nil end
  end
  return { list[1], list[2], list[3] }
end

-- A record from the guild (wire form) as stored, or nil
function Talents.Validate(raw, now)
  if type(raw) ~= "table" or not IsInt(raw.ts) or raw.ts <= 0 or raw.ts > now + 300 then return nil end
  local trees = Trees(raw.p)
  if not trees then return nil end
  return { ts = raw.ts, src = Talents.SOURCES[raw.src] and raw.src or "relay", trees = trees }
end

-- The wire form of a stored record
function Talents.Wire(rec)
  return { ts = rec.ts, src = rec.src, p = { rec.trees[1], rec.trees[2], rec.trees[3] } }
end

-- Newer wins; at the same time the member's own reading wins. True when rec was taken.
function Talents.Merge(book, key, rec)
  if type(rec) ~= "table" or not Trees(rec.trees) or not IsInt(rec.ts) then return false end
  local have = book[key]
  if type(have) == "table" and type(have.ts) == "number" then
    if have.ts > rec.ts then return false end
    if have.ts == rec.ts and (rec.src ~= "self" or have.src == "self") then return false end
  end
  book[key] = rec
  return true
end

-- Whether two records hold the same points
function Talents.Same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or type(a.trees) ~= "table" or type(b.trees) ~= "table" then return false end
  for i = 1, 3 do
    if a.trees[i] ~= b.trees[i] then return false end
  end
  return true
end

-- { [nameKey] = ts } of the records younger than MAX_AGE
function Talents.Digest(book, now)
  local digest = {}
  for key, rec in pairs(type(book) == "table" and book or {}) do
    if type(rec) == "table" and type(rec.ts) == "number" and now - rec.ts <= Talents.MAX_AGE then digest[key] = rec.ts end
  end
  return digest
end

-- Removes the records of members not in keep. Returns how many were removed.
function Talents.Prune(book, keep)
  local removed = 0
  for key in pairs(book) do
    if not keep[key] then
      book[key] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- Cat or bear by the worn pieces' stats (a list of stat tables): bear with defense or a stamina-heavy set
local function Feral(worn)
  local sta, agiStr, def = 0, 0, 0
  for _, stats in ipairs(worn or {}) do
    local function N(key) local v = stats[key] return type(v) == "number" and v > 0 and v or 0 end
    sta, agiStr, def = sta + N(STA), agiStr + N(AGI) + N(STR), def + N(DEF)
  end
  if def >= Talents.BEAR_DEFENSE or (sta > 0 and sta >= Talents.BEAR_STAMINA * agiStr) then return "DRUID_BEAR" end
  return "DRUID_CAT"
end

-- The spec (a key of StatWeights.WEIGHTS) of a member of classFile at level with rec (a talent record),
-- and the main tree's number; nil below MIN_LEVEL, with fewer than MIN_POINTS in the main tree, for a tie
-- between trees of different specs, or without a record. worn: the worn pieces' stats (feral cat or bear).
function Talents.Decide(classFile, level, rec, worn)
  local specs = classFile and ns.StatWeights.TREES[classFile]
  local trees = specs and type(rec) == "table" and Trees(rec.trees)
  if not trees or (level or 0) < Talents.MIN_LEVEL then return nil end
  local top = math.max(trees[1], trees[2], trees[3])
  if top < Talents.MIN_POINTS then return nil end
  local spec, tree
  for i = 1, 3 do
    if trees[i] == top then
      if not spec then
        spec, tree = specs[i], i
      elseif specs[i] ~= spec then
        return nil
      end
    end
  end
  if spec == "DRUID_FERAL" then spec = Feral(worn) end
  return spec, tree
end
