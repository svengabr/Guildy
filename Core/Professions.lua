-- Profession records per guild member: validation of incoming data, merge rules (newer scan wins,
-- the member's own data beats relayed data of the same age), digests for sync and the parser for
-- profession links in chat. Pure functions.
--   ProfRec = { rank = n|nil, max = n|nil, recipes = {spellID,...}|nil, ts = epochSeconds, src = "scan"|"self"|"relay"|"link" }
local _, ns = ...

local Professions = {}
ns.Professions = Professions

Professions.SKILL_LINES = {
  [171] = "ALCHEMY", [164] = "BLACKSMITHING", [333] = "ENCHANTING", [202] = "ENGINEERING",
  [182] = "HERBALISM", [165] = "LEATHERWORKING", [186] = "MINING", [393] = "SKINNING", [197] = "TAILORING",
  [185] = "COOKING", [129] = "FIRST_AID", [356] = "FISHING",
}
Professions.PRIMARY = { [171] = true, [164] = true, [333] = true, [202] = true, [182] = true, [165] = true,
  [186] = true, [393] = true, [197] = true }
-- Display order: primary professions first, then the secondary ones
Professions.ORDER = { 171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356 }

Professions.ICONS = {
  [171] = "Interface\\Icons\\Trade_Alchemy", [164] = "Interface\\Icons\\Trade_BlackSmithing",
  [333] = "Interface\\Icons\\Trade_Engraving", [202] = "Interface\\Icons\\Trade_Engineering",
  [182] = "Interface\\Icons\\Trade_Herbalism", [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17",
  [186] = "Interface\\Icons\\Trade_Mining", [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  [197] = "Interface\\Icons\\Trade_Tailoring", [185] = "Interface\\Icons\\INV_Misc_Food_15",
  [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", [356] = "Interface\\Icons\\Trade_Fishing",
}

-- Profession spells (all ranks) -> skill line, for links and the spellbook
Professions.SPELL_TO_SKILL = {}
for skillLine, spells in pairs({
  [171] = { 2259, 3101, 3464, 11611 }, [164] = { 2018, 3100, 3538, 9785 }, [333] = { 7411, 7412, 7413, 13920 },
  [202] = { 4036, 4037, 4038, 12656 }, [165] = { 2108, 3104, 3811, 10662 }, [197] = { 3908, 3909, 3910, 12180 },
  [185] = { 2550, 3102, 3413, 18260 }, [129] = { 3273, 3274, 7924, 10846 }, [186] = { 2575, 2576, 3564, 10248, 2656 },
  [182] = { 2366, 2368, 3570, 11993 }, [393] = { 8613, 8617, 8618, 10768 }, [356] = { 7620, 7731, 7732, 18248 },
}) do
  for _, spell in ipairs(spells) do Professions.SPELL_TO_SKILL[spell] = skillLine end
end

Professions.MAX_RECIPES = 1000
Professions.MAX_SKILL = 450
-- "note" = guessed from a guild note (no skill, never synced, any real data wins)
local SOURCES = { scan = 2, self = 2, relay = 1, link = 1, note = 0 }
Professions.NOTE_TS = 1

local function Int(value, min, max)
  value = tonumber(value)
  if not value or value ~= value then return nil end
  value = math.floor(value)
  if value < min then return min end
  if value > max then return max end
  return value
end

-- Returns a clean copy of an incoming record, or nil when it can't be used
function Professions.ValidateRecord(r)
  if type(r) ~= "table" or type(r.ts) ~= "number" or r.ts <= 0 then return nil end
  local clean = {
    ts = math.floor(r.ts),
    src = SOURCES[r.src] and r.src or "relay",
    rank = Int(r.rank, 0, Professions.MAX_SKILL),
    max = Int(r.max, 0, Professions.MAX_SKILL),
  }
  if type(r.recipes) == "table" then
    clean.recipes = {}
    local seen = {}
    for _, id in ipairs(r.recipes) do
      if #clean.recipes >= Professions.MAX_RECIPES then break end
      if type(id) == "number" and id > 0 and id == math.floor(id) and not seen[id] then
        seen[id] = true
        clean.recipes[#clean.recipes + 1] = id
      end
    end
  end
  return clean
end

-- Merges a validated record into member.profs[skillLine]. ctx.isOwnChar: the member is one of the
-- player's own characters; then only own scans are accepted. Returns true when something changed.
function Professions.Merge(member, skillLine, incoming, ctx)
  if type(incoming) ~= "table" or not Professions.SKILL_LINES[skillLine] then return false end
  ctx = ctx or {}
  if ctx.isOwnChar and incoming.src ~= "scan" then return false end
  member.profs = member.profs or {}
  local existing = member.profs[skillLine]
  if existing then
    if incoming.ts < existing.ts then return false end
    if incoming.ts == existing.ts and (SOURCES[incoming.src] or 0) < (SOURCES[existing.src] or 0) then return false end
  end
  local merged = {
    ts = incoming.ts, src = incoming.src, rank = incoming.rank, max = incoming.max, recipes = incoming.recipes,
  }
  if existing then
    if merged.recipes == nil then merged.recipes = existing.recipes end
    if merged.rank == nil then merged.rank, merged.max = existing.rank, existing.max end
  end
  member.profs[skillLine] = merged
  return true
end

-- { [skillLineID] = true } of a member record (nil when none)
function Professions.SetOf(member)
  if not member or type(member.profs) ~= "table" or not next(member.profs) then return nil end
  local set = {}
  for skillLine in pairs(member.profs) do set[skillLine] = true end
  return set
end

-- Newest timestamp per member: { [nameKey] = ts }
function Professions.Digest(guild)
  local digest = {}
  for key, member in pairs(guild.members or {}) do
    local newest
    for _, rec in pairs(member.profs or {}) do
      if rec.src ~= "note" and (not newest or rec.ts > newest) then newest = rec.ts end
    end
    if newest then digest[key] = newest end
  end
  return digest
end

-- Members where my data is newer than theirs (or they have none), sorted
function Professions.Outdated(mine, theirs)
  local list = {}
  for key, ts in pairs(mine or {}) do
    local other = type(theirs) == "table" and theirs[key]
    if type(other) ~= "number" or ts > other then list[#list + 1] = key end
  end
  table.sort(list)
  return list
end

-- Guild notes ("Herb/ Alch", "Tank Schmied", "VZ 150") ------------------------------------------------

-- Word stems per profession (lowercase, German and English); a note word matches when it is a prefix of
-- a stem with at least 4 letters ("alch", "kürsch") or starts with a stem ("schneiderin")
local NOTE_STEMS = {
  [171] = { "alchemie", "alchimie", "alchemy", "alchemist" },
  [164] = { "schmiedekunst", "schmied", "blacksmithing", "blacksmith" },
  [333] = { "verzauberkunst", "verzauberer", "verzauberung", "enchanting", "enchanter" },
  [202] = { "ingenieurskunst", "ingenieur", "ingi", "engineering", "engineer", "engi" },
  [182] = { "kräuterkunde", "kräuter", "kraeuterkunde", "kraeuter", "herbalism", "herbalist", "herbs", "herb" },
  [165] = { "lederverarbeitung", "lederer", "leder", "leatherworking", "leatherworker" },
  [186] = { "bergbau", "bergmann", "mining", "miner" },
  [393] = { "kürschnerei", "kürschner", "kuerschnerei", "kuerschner", "skinning", "skinner" },
  [197] = { "schneiderei", "schneider", "tailoring", "tailor" },
  [185] = { "kochkunst", "kochen", "koch", "cooking", "cook" },
  [129] = { "erstehilfe", "firstaid" },
  [356] = { "angeln", "angler", "fishing", "fisher" },
}
-- Short forms that only count as a whole word
local NOTE_ABBREVIATIONS = {
  bs = 164, vz = 333, lw = 165, lwk = 165, bb = 186, eh = 129, fa = 129, ea = 129, alc = 171, ench = 333,
}

local function Words(lowered)
  local words = {}
  for word in lowered:gmatch("[^%s/,;:%.%+&|%-%(%)%[%]!%?%d]+") do words[#words + 1] = word end
  return words
end

local function NoteWordSkill(word)
  if NOTE_ABBREVIATIONS[word] then return NOTE_ABBREVIATIONS[word] end
  if #word < 4 then return nil end
  for skillLine, stems in pairs(NOTE_STEMS) do
    for _, stem in ipairs(stems) do
      if stem:sub(1, #word) == word or word:sub(1, #stem) == stem then return skillLine end
    end
  end
  return nil
end

-- { [skillLineID] = true } of the professions a note mentions (empty table when none)
function Professions.ParseNote(note)
  local found = {}
  if type(note) ~= "string" or note == "" then return found end
  local lowered = ns.Names.Lower(note)
  -- "Erste Hilfe" / "First Aid" are two words
  lowered = lowered:gsub("erste%s+hilfe", "erstehilfe"):gsub("first%s+aid", "firstaid")
  for _, word in ipairs(Words(lowered)) do
    local skillLine = NoteWordSkill(word)
    if skillLine then found[skillLine] = true end
  end
  return found
end

-- Applies the professions a member's notes mention: adds "note" records for professions without data,
-- removes "note" records the notes no longer mention. Returns true when something changed.
function Professions.ApplyNotes(member, mentioned)
  member.profs = member.profs or {}
  local changed = false
  for skillLine, rec in pairs(member.profs) do
    if rec.src == "note" and not mentioned[skillLine] then
      member.profs[skillLine] = nil
      changed = true
    end
  end
  for skillLine in pairs(mentioned) do
    if not member.profs[skillLine] then
      member.profs[skillLine] = { ts = Professions.NOTE_TS, src = "note" }
      changed = true
    end
  end
  return changed
end

-- Profession links in a chat message. Two formats exist:
--   |Htrade:Player-1-0ABC:2259:171|h  (guid, spellID, skillLineID)
--   |Htrade:2259:75:150:Player-1-0ABC:<data>|h  (spellID, rank, max, guid, recipe bitmap)
-- Returns { {guid, spellID, skillLine, rank, max} }.
function Professions.ParseTradeLinks(text)
  local found = {}
  if type(text) ~= "string" then return found end
  for body in text:gmatch("|Htrade:([^|]+)|h") do
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    local entry
    if fields[1] and fields[1]:match("^Player%-") then
      entry = { guid = fields[1], spellID = tonumber(fields[2]), skillLine = tonumber(fields[3]) }
    elseif tonumber(fields[1]) then
      entry = { spellID = tonumber(fields[1]), rank = tonumber(fields[2]), max = tonumber(fields[3]),
        guid = fields[4] and fields[4]:match("^Player%-") and fields[4] or nil }
    end
    if entry then
      if not (entry.skillLine and Professions.SKILL_LINES[entry.skillLine]) then
        entry.skillLine = entry.spellID and Professions.SPELL_TO_SKILL[entry.spellID] or nil
      end
      if entry.skillLine then found[#found + 1] = entry end
    end
  end
  return found
end

-- Icons the client shows instead of a real one: recipes that make an item often have no icon of their
-- own, and every profession has its own stand-in for them (a "W", a blue swirl, ...). An icon used by at
-- least 5 recipes and a quarter of all recipes of one profession counts as such a stand-in.
-- icons: one icon per distinct recipe of a profession; returns the set of stand-in icons
function Professions.PlaceholderIcons(icons)
  local counts, total = {}, 0
  for _, icon in ipairs(icons) do
    counts[icon] = (counts[icon] or 0) + 1
    total = total + 1
  end
  local found = {}
  for icon, count in pairs(counts) do
    if count >= 5 and count * 4 >= total then found[icon] = true end
  end
  return found
end
