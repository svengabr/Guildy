-- Families (main and twinks) of guild members. Pure: takes and returns tables.
-- Three sources, joined into groups:
--   * own characters: every character of the account that ran Guildy (GuildyDB.ownChars)
--   * shared lists: Guildy users send their characters in the guild (FAM, Game/Sync.lua), kept as
--     guild.families[ownerKey] = FamilyRec = { ts, chars = { "Name", ... } }
--   * notes: a public or officer note naming another member with a twink word ("Twink von Ran Fred",
--     "Main: Ran Fred", "alt of Ran Fred")
local _, ns = ...

local Family = {}
ns.Family = Family

Family.MAX_CHARS = 20
-- words that mark a note as pointing at the member's main (or twink); lowercase, matched as words
Family.NOTE_WORDS = { "twink", "twinks", "alt", "alts", "main", "zweitchar", "hauptchar" }

-- A FamilyRec from the wire or SavedVariables, or nil when malformed
function Family.Validate(raw)
  if type(raw) ~= "table" or type(raw.ts) ~= "number" or type(raw.c or raw.chars) ~= "table" then return nil end
  local chars, seen = {}, {}
  for _, name in ipairs(raw.c or raw.chars) do
    if type(name) == "string" and name ~= "" and #chars < Family.MAX_CHARS then
      local normal = ns.Names.Normalize(name)
      local key = ns.Names.Key(normal)
      if not seen[key] then
        seen[key] = true
        chars[#chars + 1] = normal
      end
    end
  end
  if #chars == 0 then return nil end
  return { ts = raw.ts, chars = chars }
end

function Family.Wire(rec)
  return { ts = rec.ts, c = rec.chars }
end

-- Keeps rec as the family of owner when newer than what the guild has. Returns true when it changed.
function Family.Merge(guild, owner, rec)
  if type(guild) ~= "table" or not rec then return false end
  guild.families = type(guild.families) == "table" and guild.families or {}
  local key = ns.Names.Key(owner)
  local known = guild.families[key]
  if type(known) == "table" and type(known.ts) == "number" and known.ts >= rec.ts then return false end
  guild.families[key] = rec
  return true
end

-- { ownerKey = ts } for SUM
function Family.Digest(guild)
  local digest = {}
  for key, rec in pairs(type(guild) == "table" and type(guild.families) == "table" and guild.families or {}) do
    if type(rec) == "table" and type(rec.ts) == "number" then digest[key] = rec.ts end
  end
  return digest
end

-- The own family record from the account's characters that are in the guild: kept as it is when
-- the characters did not change, else a new one stamped now. known = the stored record or nil.
function Family.Own(ownChars, memberKeys, nameOf, known, now)
  local chars = {}
  for key in pairs(type(ownChars) == "table" and ownChars or {}) do
    if memberKeys[key] then chars[#chars + 1] = nameOf[key] or key end
  end
  table.sort(chars)
  if #chars < 2 then return nil end
  if known and type(known.chars) == "table" and table.concat(known.chars, ",") == table.concat(chars, ",") then
    return known
  end
  return { ts = now, chars = chars }
end

local function HasWord(text)
  for word in text:gmatch("[%a\128-\255]+") do
    for _, w in ipairs(Family.NOTE_WORDS) do
      if word == w then return true end
    end
  end
  return false
end

-- Members a note names together with a twink word, as keys: "Twink von Ran Fred" on Fredwild,
-- "Twinks: Fredwild, Ranfredo" on Ran Fred. note: the note text, selfKey: the note owner, members:
-- { {key, name} }. Names count as whole words; a longer name wins over one inside it ("Ran Fred"
-- over "Ran"); never the owner.
-- Looking through every member for every note took most of the member list's refresh in a big guild
-- (tests/bench.lua): the names of a roster are indexed once by their first word, and a note only
-- looks at the members whose first word it contains.
local indexes = setmetatable({}, { __mode = "k" }) -- members list -> { byWord = { word -> {entry} }, other = {entry} }

local function NameIndex(members)
  local index = indexes[members]
  if index and index.count == #members then return index end
  index = { byWord = {}, other = {}, count = #members }
  for i, m in ipairs(members) do
    local name = m.name and m.name:lower()
    if name and #name >= 3 then
      local entry = { key = m.key, name = name, order = i }
      -- a whole-word match of the name starts with its first word as a whole word of the note
      local word = name:match("^[%a\128-\255]+")
      local list = index.other
      if word then
        list = index.byWord[word]
        if not list then
          list = {}
          index.byWord[word] = list
        end
      end
      list[#list + 1] = entry
    end
  end
  indexes[members] = index
  return index
end

function Family.NoteLinks(note, selfKey, members)
  local links = {}
  if type(note) ~= "string" or note == "" then return links end
  local text = note:lower()
  if not HasWord(text) then return links end
  local index = NameIndex(members)
  local found = {}
  local function Look(entry)
    local name = entry.name
    local from = 1
    while true do
      local start = text:find(name, from, true)
      if not start then break end
      local stop = start + #name - 1
      local before, after = text:sub(start - 1, start - 1), text:sub(stop + 1, stop + 1)
      if not before:match("[%a\128-\255]") and not after:match("[%a\128-\255]") then
        -- the owner's own name only blocks names inside it ("Ran" in "Ran Fred")
        found[#found + 1] = { key = entry.key, start = start, stop = stop, len = #name, own = entry.key == selfKey,
          order = entry.order }
        break
      end
      from = start + 1
    end
  end
  local looked = {}
  for word in text:gmatch("[%a\128-\255]+") do
    if not looked[word] then
      looked[word] = true
      for _, entry in ipairs(index.byWord[word] or {}) do Look(entry) end
    end
  end
  for _, entry in ipairs(index.other) do Look(entry) end
  -- the longest name first, names of one length in roster order
  table.sort(found, function(a, b)
    if a.len ~= b.len then return a.len > b.len end
    return a.order < b.order
  end)
  local taken = {}
  for _, f in ipairs(found) do
    local free = true
    for _, t in ipairs(taken) do
      if f.start <= t.stop and f.stop >= t.start then free = false break end
    end
    if free then
      taken[#taken + 1] = f
      if not f.own then links[#links + 1] = f.key end
    end
  end
  return links
end

-- Groups of member keys: { [key] = groupId }. members: { {key, name, note, officerNote} } (the
-- roster), families: guild.families, ownChars: GuildyDB.ownChars. Only members of the roster count.
function Family.Groups(members, families, ownChars)
  local parent, inRoster, byKey = {}, {}, {}
  for _, m in ipairs(members) do
    parent[m.key] = m.key
    inRoster[m.key] = true
    byKey[m.key] = m
  end
  local function Find(key)
    while parent[key] ~= key do
      parent[key] = parent[parent[key]]
      key = parent[key]
    end
    return key
  end
  local function Join(a, b)
    if not (inRoster[a] and inRoster[b]) then return end
    local ra, rb = Find(a), Find(b)
    if ra ~= rb then parent[rb] = ra end
  end
  local function JoinAll(keys)
    local first
    for _, key in ipairs(keys) do
      if inRoster[key] then
        if first then Join(first, key) else first = key end
      end
    end
  end
  for owner, rec in pairs(type(families) == "table" and families or {}) do
    if type(rec) == "table" and type(rec.chars) == "table" then
      local keys = { owner }
      for _, name in ipairs(rec.chars) do keys[#keys + 1] = ns.Names.Key(name) end
      JoinAll(keys)
    end
  end
  local own = {}
  for key in pairs(type(ownChars) == "table" and ownChars or {}) do own[#own + 1] = key end
  JoinAll(own)
  for _, m in ipairs(members) do
    for _, other in ipairs(Family.NoteLinks(m.note, m.key, members)) do Join(m.key, other) end
    for _, other in ipairs(Family.NoteLinks(m.officerNote, m.key, members)) do Join(m.key, other) end
  end
  local groups = {}
  for key in pairs(inRoster) do groups[key] = Find(key) end
  return groups, byKey
end

-- The other characters of member key, highest level first: { member, ... }
function Family.Of(key, members, families, ownChars)
  local groups, byKey = Family.Groups(members, families, ownChars)
  local group = groups[key]
  local list = {}
  if not group then return list end
  for other, id in pairs(groups) do
    if id == group and other ~= key then list[#list + 1] = byKey[other] end
  end
  table.sort(list, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return (a.name or "") < (b.name or "")
  end)
  return list
end

-- Guild notes in the form "Main, <group>" or "Alt, <main>": the kind ("main" or "alt") and the rest
-- (the guild's own group name like "Murloc Raid" or "Friends", or the main's name). Any group name
-- works; nothing is fixed to one guild. nil for other notes.
local KINDS = { main = "main", hauptchar = "main", alt = "alt", twink = "alt", zweitchar = "alt" }
function Family.ParseNote(note)
  if type(note) ~= "string" then return nil end
  local head, rest = note:match("^%s*([%a\128-\255]+)%s*[,:;%-]?%s*(.-)%s*$")
  local kind = head and KINDS[head:lower()]
  if not kind then return nil end
  return kind, rest ~= "" and rest or nil
end

-- Main of every member in a family: { [key] = mainKey } (members without family are left out).
-- The main is the one whose note says "Main", else the one an "Alt" note names, else the highest level.
function Family.Mains(members, families, ownChars)
  local groups, byKey = Family.Groups(members, families, ownChars)
  local byGroup = {}
  for key, id in pairs(groups) do
    byGroup[id] = byGroup[id] or {}
    table.insert(byGroup[id], byKey[key])
  end
  local named = {}
  for _, m in ipairs(members) do
    local kind = Family.ParseNote(m.note or "")
    if kind == "alt" then
      for _, other in ipairs(Family.NoteLinks(m.note, m.key, members)) do named[other] = true end
    end
  end
  local mains = {}
  for _, list in pairs(byGroup) do
    if #list > 1 then
      table.sort(list, function(a, b)
        local am, bm = Family.ParseNote(a.note or "") == "main", Family.ParseNote(b.note or "") == "main"
        if am ~= bm then return am end
        if (named[a.key] or false) ~= (named[b.key] or false) then return named[a.key] or false end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.name or "") < (b.name or "")
      end)
      for _, m in ipairs(list) do mains[m.key] = list[1].key end
    end
  end
  return mains
end

-- What the account remembers about one of its characters (GuildyDB.ownChars[key]; older versions
-- stored just true). info = {name, classFile, className, level, raceFile, raceName, female, guild,
-- guildKey}; keeps known fields.
function Family.OwnRecord(old, info, now)
  local record = type(old) == "table" and old or {}
  for _, field in ipairs({ "name", "classFile", "className", "level", "raceFile", "raceName", "guild", "guildKey" }) do
    if info[field] ~= nil then record[field] = info[field] end
  end
  if info.female ~= nil then record.female = info.female end
  if not info.guild then record.guild, record.guildKey = nil, nil end -- left the guild
  record.seen = now
  return record
end

-- The account's other characters that are not in the given set (shown: {key = true}): those in
-- other guilds or without one. Only characters remembered with details. Highest level first.
-- daysOffline counts from their last login (now).
function Family.OwnElsewhere(ownChars, shown, now)
  local list = {}
  for key, record in pairs(type(ownChars) == "table" and ownChars or {}) do
    if type(record) == "table" and record.name and not shown[key] then
      local name, guildName = record.name, record.guild
      if ns.Anon and ns.Anon.on then name, guildName = ns.Anon.Name(name), ns.Anon.Guild(guildName) end
      list[#list + 1] = { key = key, name = name, classFile = record.classFile, className = record.className,
        level = record.level, raceFile = record.raceFile, raceName = record.raceName, female = record.female,
        guildName = guildName, guildKey = record.guildKey, seen = record.seen, elsewhere = true,
        daysOffline = (now and record.seen) and math.max(0, now - record.seen) / 86400 or nil }
    end
  end
  table.sort(list, function(a, b)
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.name < b.name
  end)
  return list
end

