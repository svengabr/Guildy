-- Profession specializations, pure. Forever has them in three professions only (checked against its
-- own database 2026-11-13): engineering, blacksmithing and leatherworking. The Burning Crusade ones of
-- alchemy and tailoring do not exist there.
--   ProfRec.spec = { id = spell ID of the specialization (0 = has none), src, ts }
--   src: "known" = the game says so for the player's own character (IsSpellKnown)
--        "api"   = the profile API, written by tools/bnet-sync
--        "book"  = inferred from recipes in the member's book that only one specialization can learn
-- Only the game and the script may replace or revoke a specialization. A book only ever adds: that a
-- marker recipe is missing proves nothing.
local _, ns = ...

local Specs = {}
ns.Specs = Specs

-- The specializations per skill line, the most specific first: a weaponsmith who went on to swords
-- knows both spells, and the sword is what to show
Specs.ORDER = {
  [202] = { 20219, 20222 },                      -- Gnomish, Goblin engineer
  [164] = { 17039, 17040, 17041, 9787, 9788 },  -- Master Sword-, Hammer-, Axesmith, Weaponsmith, Armorsmith
  [165] = { 10656, 10658, 10660 },               -- Dragonscale, Elemental, Tribal leatherworking
}

Specs.SKILL_OF = {}
for skillLine, spells in pairs(Specs.ORDER) do
  for _, id in ipairs(spells) do Specs.SKILL_OF[id] = skillLine end
end

-- Recipes only one specialization can learn: recipe spell -> specialization spell. Engineering only:
-- Forever's database names the requirement on each of these. Every specialist learns several of them
-- at the trainer between skill 205 and 210, so one of them in a book is enough. Blacksmithing and
-- leatherworking wait: Forever dropped the requirement from some of their recipes (Lionheart Helm now
-- wants a Master Forge), and the guild has no specialist yet to check the rest against.
Specs.MARKERS = {}
for spec, recipes in pairs({
  [20219] = { 12759, 12906, 12897, 12902, 23489, 12905, 12907, 12895, 15633, 12899 },
  [20222] = { 8895, 12760, 13240, 12716, 12715, 23078, 23486, 12717, 12758, 15628 },
}) do
  for _, recipe in ipairs(recipes) do Specs.MARKERS[recipe] = spec end
end

local RANK = { known = 3, api = 2, book = 1 }
local AUTHORITY = { known = true, api = true }

-- The player's own specialization in a skill line: isKnown(spellID) -> boolean. 0 when they have
-- none, nil for a profession without specializations.
function Specs.Detect(skillLine, isKnown)
  local spells = Specs.ORDER[skillLine]
  if not spells then return nil end
  for _, id in ipairs(spells) do
    if isKnown(id) then return id end
  end
  return 0
end

-- The specialization a book shows, nil when it shows none or two rival ones
function Specs.FromBook(skillLine, recipes)
  if type(recipes) ~= "table" then return nil end
  local found
  for _, recipe in ipairs(recipes) do
    local spec = Specs.MARKERS[recipe]
    if spec and Specs.SKILL_OF[spec] == skillLine then
      if found and found ~= spec then return nil end
      found = spec
    end
  end
  return found
end

-- A clean copy of an incoming specialization, or nil when it can't be used
function Specs.Validate(skillLine, raw)
  if type(raw) ~= "table" or not RANK[raw.src] then return nil end
  if type(raw.ts) ~= "number" or raw.ts ~= raw.ts or raw.ts <= 0 then return nil end
  local id = raw.id
  if type(id) ~= "number" or id ~= math.floor(id) then return nil end
  if not Specs.ORDER[skillLine] then return nil end
  if id == 0 then
    if raw.src == "book" then return nil end
  elseif Specs.SKILL_OF[id] ~= skillLine then
    return nil
  end
  return { id = id, src = raw.src, ts = math.floor(raw.ts) }
end

-- Merges a validated specialization into a profession record. Returns true when it changed.
function Specs.Merge(rec, incoming)
  if type(rec) ~= "table" or type(incoming) ~= "table" then return false end
  local have = rec.spec
  local take
  if type(have) ~= "table" then
    take = true
  elseif have.id == incoming.id and have.src == incoming.src and have.ts == incoming.ts then
    take = false
  elseif not AUTHORITY[incoming.src] then
    take = not AUTHORITY[have.src] and incoming.ts > have.ts
  elseif not AUTHORITY[have.src] then
    take = true
  else
    take = incoming.ts > have.ts or (incoming.ts == have.ts and RANK[incoming.src] > RANK[have.src])
  end
  if take then rec.spec = { id = incoming.id, src = incoming.src, ts = incoming.ts } end
  return take
end
